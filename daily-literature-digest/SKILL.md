---
name: daily-literature-digest
description: Set up, run, modify, or troubleshoot a personal AI literature digest that monitors Crossref, OpenAlex, and arXiv for new papers by user-provided research keywords, summarizes open metadata/abstracts, saves local Markdown (optionally DOCX) archives, and emails a daily digest (SMTP or the Gmail connector). Use when the user asks for daily or weekly paper monitoring, publisher/arXiv alerts, research keyword digests, AI paper summary emails, literature update emails, or a recurring scheduled literature automation.
---

# Daily Literature Digest

## Overview

Use this skill to create a user's own daily literature digest. A bundled fetch script gathers open metadata and abstracts; Claude writes the AI interpretation, saves the archive, emails the digest, and (optionally) creates the recurring automation.

Do not read paywalled full text or auto-login to university/publisher sites during the unattended daily run. Full-text follow-up is a separate explicit task after the user logs in themselves or provides PDFs.

The scripts live in this skill folder and are referenced by absolute path; the user's config and digest archives live in their workspace / chosen output folder. The fetch script uses only the Python standard library. DOCX output additionally requires `python-docx` (`pip install python-docx`).

## Bundled scripts

- `scripts/daily_literature_digest.py` — fetch candidates (`fetch`) and record state (`mark-success`). Stdlib only.
- `scripts/md_to_html.py` — convert a digest Markdown file to styled, email-friendly HTML. Stdlib only.
- `scripts/send_email.py` — send the digest over SMTP using a Gmail App Password (credentials in a separate secrets JSON). Stdlib only.
- `scripts/markdown_to_docx.py` — optional DOCX export (needs `python-docx`).
- `scripts/run-digest.sh` — config-driven wrapper for unattended runs (fetch → Claude writes digest → HTML → SMTP send → mark-success).

## Setup Workflow

1. Confirm or infer the user's settings:
   - Recipient email for the digest.
   - Research keywords, grouped by theme when useful.
   - Language: ask if unclear; default to `en`.
   - Timezone: ask if unclear; otherwise use the user's local timezone.
   - Schedule time: default to `09:00`.
   - Sources: default to Elsevier, Springer Nature, Wiley, Taylor & Francis/Routledge, and arXiv.
2. Create `daily-literature-digest.config.json` in the user's workspace (see `examples/config.example.json`). `output_dir` may be relative (to the workspace) or absolute (e.g. a Desktop folder).
3. Run a dry fetch from the workspace:
   ```bash
   python3 ~/.claude/skills/daily-literature-digest/scripts/daily_literature_digest.py \
     --config daily-literature-digest.config.json fetch --include-seen
   ```
   The script prints the absolute path of the JSON payload it wrote.
4. Read the printed JSON file and write the digest:
   - Save full Markdown to `<output_dir>/YYYY-MM-DD.md`.
   - Summarize using only title, abstract, keywords, subject tags, DOI, journal, authors, publisher, and source metadata.
   - Mark arXiv items as preprints.
   - If there are no matches, still write a short no-results digest.
5. For no-abstract/title-only papers, write `<output_dir>/fulltext-inbox/to-download-YYYY-MM-DD.md` with DOI/URL and a note that no abstract/full text was read.
6. Optional DOCX: when the user wants Word output, run `scripts/markdown_to_docx.py <md> <docx>`.
7. Deliver by email (pick one):
   - **SMTP (recommended for automation):** generate the HTML with `scripts/md_to_html.py`, then `scripts/send_email.py --config <smtp.json> --to <addr> --subject ... --body-file <md> --html-file <html>`. The SMTP secrets file holds a Gmail App Password and must never be committed (chmod 600). See `examples/smtp.example.json`.
   - **Gmail connector:** if the Gmail MCP connector tools are available, send a concise email with the digest. Note this connector only creates **drafts** (no send) and cannot run in an unattended job — prefer SMTP for automation.
   - If neither is configured, record email status as `not-configured` and keep the local Markdown.
8. Mark success only after the Markdown archive exists:
   ```bash
   python3 ~/.claude/skills/daily-literature-digest/scripts/daily_literature_digest.py \
     --config daily-literature-digest.config.json mark-success \
     --data-file <JSON_PATH> --digest-file <DIGEST_PATH> \
     --email-status <sent|failed|not-configured>
   ```
   `mark-success` records seen DOIs/items so the next run only surfaces new papers. It resolves `state.json` from the config's `output_dir`, matching `fetch`.
9. Schedule the recurring automation:
   - **macOS launchd (recommended for a true local automation):** a launchd agent runs `scripts/run-digest.sh` daily at the user's time. The wrapper does fetch → Claude writes digest → HTML → SMTP send → mark-success. See `examples/com.example.literature-digest.plist` and the repo README. launchd uses **machine-local** time and runs on the next wake if the Mac was asleep.
   - **CronCreate (Claude Code tool):** can schedule a prompt, but in many environments it only creates session-only jobs (lost when Claude exits) — not a reliable daily automation.

## Summary Rules

- Treat matching as inclusive: one keyword term is enough to include a paper.
- Use priority for ranking, not for exclusion.
- For each paper include title, source/publisher, journal/preprint source, date, authors, DOI/URL, matched keywords, priority, research goal, method, main result, relevance to the user, and next action.
- If the abstract is missing, include the paper only as a title-level candidate and state clearly: `No abstract/full text was available; this is a title-level judgment only.`
- Do not infer research goal, method, or result for no-abstract papers.
- Watch for query-only matches: Crossref's bibliographic search can return loosely related papers where the keyword does not actually appear (the JSON marks these `metadata_match_confidence: query-only`). Flag them as such rather than over-summarizing.
- Mention Crossref, OpenAlex, or arXiv API errors (from the JSON `errors` array) in the digest and summarize the results that were successfully fetched.

## Timezone note

Local schedulers (launchd, cron) fire in the **machine's local timezone**. If the user states a time in a different zone (e.g. "10am ET" on a Pacific machine), convert it before scheduling.

## Full-Text Follow-Up

When the user says they have logged in to a publisher / university library:

- Do not ask for passwords.
- Use only the current active session or PDFs the user downloaded into `<output_dir>/fulltext-inbox`.
- Process only the explicit batch the user asked about.
- Summarize each full-text paper with topic, method, data/case, main results, limitations, and relevance.
- Save summaries to `<output_dir>/fulltext-summaries/YYYY-MM-DD-fulltext.md`.
- Do not create unattended daily publisher-download automation.

## References

- Read `references/default-config.md` for default sources and a starter configuration.
