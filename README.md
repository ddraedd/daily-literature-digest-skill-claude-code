# Daily Literature Digest — a Claude Code skill

A [Claude Code](https://claude.com/claude-code) skill that builds you a personal **daily literature digest**. Each day it searches Crossref, OpenAlex, and arXiv for new papers matching your research keywords, has Claude write structured summaries from the open metadata and abstracts, saves a local Markdown (optionally DOCX) archive, and emails you a formatted digest.

It does **not** store passwords, log in to publisher sites, or bypass paywalls. Papers without an open abstract are listed as title-level candidates in a follow-up file you can process later (after you log in yourself or drop the PDFs in).

> Adapted for Claude Code from the original Codex skill by **xuezheng627** ([daily-literature-digest-skill](https://github.com/xuezheng627/daily-literature-digest-skill)).

## How it works

```
fetch (Python, deterministic)  →  Claude writes the digest  →  HTML render  →  email (SMTP)  →  record state
```

- **`daily_literature_digest.py`** queries Crossref per publisher + keyword, pulls arXiv preprints, enriches with OpenAlex, dedupes, and writes a JSON payload. It does **not** call an LLM — it only gathers open metadata.
- **Claude** reads that JSON and writes the digest Markdown (summaries strictly from titles/abstracts/metadata; no fabrication for abstract-less papers).
- **`md_to_html.py`** turns the Markdown into a styled, email-friendly HTML body.
- **`send_email.py`** sends it via SMTP (Gmail App Password).
- **`mark-success`** records seen papers so tomorrow only shows new ones.

## Requirements

- macOS or Linux with **Python 3.9+** (the fetch/email/HTML scripts are standard-library only).
- **Claude Code** CLI installed and authenticated (`claude --version`).
- Optional: `python-docx` for DOCX output (`pip install python-docx`).
- Optional: a Gmail account with an **App Password** for automatic email delivery.

## Install

**Option A — installer:**
```bash
git clone https://github.com/ddraedd/daily-literature-digest-skill.git
cd daily-literature-digest-skill
./install.sh
```
The installer copies the skill into `~/.claude/skills/`, creates a workspace + starter config, scaffolds the SMTP secrets file, and (on macOS) optionally generates and loads the launchd schedule.

**Option B — manual:**
```bash
cp -R daily-literature-digest ~/.claude/skills/
cp examples/config.example.json ~/literature-digest/daily-literature-digest.config.json   # edit this
```

## Configure

Edit your `daily-literature-digest.config.json` (see [`examples/config.example.json`](examples/config.example.json)):

- `recipient_email` / `crossref_mailto` — your email (the mailto routes you to the API "polite pool").
- `keyword_groups` — your topics. Matching is **inclusive** and **substring-based**, so list exact phrases and spelling variants. Very specific multi-word phrases may rarely appear verbatim in a given week.
- `language` — digest language (`en`, `zh-CN`, …).
- `output_dir` — where archives are written; relative (to the workspace) or an absolute path like `/Users/you/Desktop/literature digest`.
- `timezone`, `schedule_time` — recorded in the digest; scheduling itself is set up separately (see below).

Defaults and source details are documented in [`daily-literature-digest/references/default-config.md`](daily-literature-digest/references/default-config.md).

## Run it once

Just ask Claude Code, in a directory holding your config:

> Use the daily-literature-digest skill to generate today's digest.

Or run the pieces manually:
```bash
python3 ~/.claude/skills/daily-literature-digest/scripts/daily_literature_digest.py \
  --config daily-literature-digest.config.json fetch --include-seen
# (Claude writes the Markdown from the printed JSON, then:)
python3 ~/.claude/skills/daily-literature-digest/scripts/daily_literature_digest.py \
  --config daily-literature-digest.config.json mark-success \
  --data-file <JSON> --digest-file <MD> --email-status not-configured
```

## Email setup (SMTP)

The Gmail **MCP connector only creates drafts** and can't run unattended, so automatic delivery uses SMTP with an App Password:

1. Enable 2-Step Verification on your Google account.
2. Create an App Password at <https://myaccount.google.com/apppasswords>.
3. Put it in the secrets file (kept out of git, `chmod 600`):
   ```bash
   mkdir -p ~/.config/literature-digest
   cp examples/smtp.example.json ~/.config/literature-digest/smtp.json
   chmod 600 ~/.config/literature-digest/smtp.json
   # edit username/app_password
   ```
4. Send a digest: `send_email.py --config ~/.config/literature-digest/smtp.json --to you@example.com --subject "..." --body-file <md> --html-file <html>`

## Schedule it (macOS launchd)

For a true hands-off daily run, use a launchd agent that runs [`run-digest.sh`](daily-literature-digest/scripts/run-digest.sh). The installer can generate it; or copy [`examples/com.example.literature-digest.plist`](examples/com.example.literature-digest.plist), fill in your username/time, then:
```bash
cp examples/com.example.literature-digest.plist ~/Library/LaunchAgents/com.ddraedd.literature-digest.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ddraedd.literature-digest.plist
# stop it later:
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.ddraedd.literature-digest.plist
```

**Timezone:** launchd fires in your **machine-local** time. If you want "10am Eastern" on a Pacific machine, schedule 7am. It also runs on the next wake if the Mac was asleep at the scheduled time, and requires you to be logged in (for keychain/Claude auth).

> Claude Code's built-in `CronCreate` tool often creates only *session-only* jobs (lost when Claude exits), so it isn't a reliable daily scheduler — launchd/cron is.

## Output layout

```
<output_dir>/
├── YYYY-MM-DD.md                         # the digest
├── fulltext-inbox/to-download-*.md       # title-level papers to pull behind a login
├── fulltext-summaries/                   # your later full-text summaries
├── data/*.json                           # raw fetch payloads
├── logs/                                 # run logs
└── state.json                            # seen-paper tracking
```

## Customization

- **Sources/publishers:** override the `publishers` key in the config (Crossref member IDs); see the reference doc.
- **DOCX:** `pip install python-docx`, then `markdown_to_docx.py <md> <docx>`.
- **Volume:** tune `rows`, `arxiv_rows`, `max_papers`, `lookback_days`.

## Limitations

- Summaries come only from open metadata/abstracts — not full text.
- Crossref's bibliographic search can return loosely-related "query-only" matches; the digest flags these.
- Local automations only run while your computer is awake and you're logged in.

## License

MIT — see [LICENSE](LICENSE).
