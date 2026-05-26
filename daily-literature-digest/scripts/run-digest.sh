#!/bin/bash
# Unattended daily literature digest runner (e.g. invoked by launchd/cron).
#
#   1. Fetches new papers deterministically (no LLM).
#   2. Calls Claude Code headlessly to write the digest + follow-up list.
#   3. Renders HTML, emails the digest via SMTP, and records state (all deterministic).
#
# Configuration is read from the config JSON and a few optional environment
# variables -- no personal values are hard-coded, so this script is shareable.
#
# Environment overrides (all optional):
#   DIGEST_CONFIG       Path to the config JSON (default: $DIGEST_WORKSPACE/daily-literature-digest.config.json)
#   DIGEST_WORKSPACE    Working dir that the config + relative output_dir resolve against (default: script's repo dir)
#   DIGEST_SMTP_CONFIG  Path to SMTP secrets JSON (default: ~/.config/literature-digest/smtp.json)
#   DIGEST_MODEL        Model for the headless summarization (default: sonnet)
#   CLAUDE_BIN          Path to the claude binary (default: autodetected)
#   PYTHON_BIN          Path to python3 (default: autodetected)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

WORKSPACE="${DIGEST_WORKSPACE:-$SKILL_DIR}"
CONFIG="${DIGEST_CONFIG:-$WORKSPACE/daily-literature-digest.config.json}"
SMTP_CONFIG="${DIGEST_SMTP_CONFIG:-$HOME/.config/literature-digest/smtp.json}"
MODEL="${DIGEST_MODEL:-sonnet}"

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || true)}"
PYTHON="${PYTHON_BIN:-$(command -v python3 || true)}"

if [ -z "$PYTHON" ]; then echo "ERROR: python3 not found on PATH." >&2; exit 1; fi
if [ -z "$CLAUDE_BIN" ]; then echo "ERROR: claude CLI not found on PATH (set CLAUDE_BIN)." >&2; exit 1; fi
if [ ! -f "$CONFIG" ]; then echo "ERROR: config not found: $CONFIG" >&2; exit 1; fi

cd "$WORKSPACE" || exit 1

# Pull output_dir + recipient straight from the config so there is a single source of truth.
OUTPUT_DIR="$("$PYTHON" -c "import json,sys;print(json.load(open(sys.argv[1])).get('output_dir','daily-literature-digests'))" "$CONFIG")"
RECIPIENT="$("$PYTHON" -c "import json,sys;print(json.load(open(sys.argv[1])).get('recipient_email',''))" "$CONFIG")"
case "$OUTPUT_DIR" in
  /*) DIGEST_DIR="$OUTPUT_DIR" ;;       # absolute
  *)  DIGEST_DIR="$WORKSPACE/$OUTPUT_DIR" ;;  # relative to workspace
esac

LOGDIR="$DIGEST_DIR/logs"
mkdir -p "$LOGDIR"
DATE="$(date +%Y-%m-%d)"
LOG="$LOGDIR/$DATE.log"
DIGEST="$DIGEST_DIR/$DATE.md"
INBOX="$DIGEST_DIR/fulltext-inbox/to-download-$DATE.md"

{
  echo "=== Literature digest run: $(date) ==="
  echo "workspace=$WORKSPACE | output=$DIGEST_DIR | recipient=${RECIPIENT:-<none>}"

  # 1. Fetch only unseen papers (deterministic; no LLM).
  JSON="$("$PYTHON" "$SKILL_DIR/scripts/daily_literature_digest.py" --config "$CONFIG" fetch)"
  echo "Fetch JSON payload: $JSON"
  if [ -z "$JSON" ] || [ ! -f "$JSON" ]; then
    echo "ERROR: fetch produced no JSON payload; aborting."
    exit 1
  fi

  # 2. Claude writes the digest + follow-up list (summarization only).
  "$CLAUDE_BIN" -p "Run today's literature digest non-interactively. The fetch already ran; read the JSON payload at $JSON. Then do BOTH of the following and nothing else (do NOT send email, do NOT run mark-success):
1. Write a Markdown digest to $DIGEST in the language given by the JSON 'language' field. For each paper include title, source/publisher, journal or preprint source, date, authors, DOI/URL, matched keywords, priority, and -- ONLY when an abstract is present -- research goal, method, main result, relevance, next action. Mark arXiv items as preprints. Summarize strictly from the titles, abstracts, keywords, and metadata in the JSON. For papers with no abstract, list them as title-level candidates and say so explicitly; do NOT infer goal/method/result for them. Surface any entries in the JSON 'errors' array. If there are no papers, still write a short no-results digest.
2. Write the no-abstract / title-level papers to $INBOX with their DOI/URL." \
    --allowedTools "Bash Read Write Edit" \
    --permission-mode acceptEdits \
    --model "$MODEL"

  if [ ! -f "$DIGEST" ]; then
    echo "ERROR: digest file was not written; aborting before email."
    exit 1
  fi

  # 3. Render an HTML version so the email shows formatted headings/tables/links.
  DIGEST_HTML="$DIGEST_DIR/.${DATE}.html"
  "$PYTHON" "$SKILL_DIR/scripts/md_to_html.py" "$DIGEST" "$DIGEST_HTML" || DIGEST_HTML=""

  # 4. Email the digest via SMTP, then record success with the real status.
  EMAIL_STATUS="not-configured"
  if [ -n "$RECIPIENT" ] && [ -f "$SMTP_CONFIG" ] && ! grep -q "PASTE_16_CHAR_APP_PASSWORD_HERE" "$SMTP_CONFIG"; then
    HTML_ARGS=()
    [ -n "$DIGEST_HTML" ] && [ -f "$DIGEST_HTML" ] && HTML_ARGS=(--html-file "$DIGEST_HTML")
    if "$PYTHON" "$SKILL_DIR/scripts/send_email.py" \
        --config "$SMTP_CONFIG" \
        --to "$RECIPIENT" \
        --subject "Daily Literature Digest — $DATE" \
        --body-file "$DIGEST" \
        ${HTML_ARGS[@]+"${HTML_ARGS[@]}"}; then
      EMAIL_STATUS="sent"
    else
      EMAIL_STATUS="failed"
    fi
  else
    echo "SMTP not configured or no recipient; skipping email (digest saved locally)."
  fi
  echo "Email status: $EMAIL_STATUS"

  # 5. Record success (updates seen-paper state).
  "$PYTHON" "$SKILL_DIR/scripts/daily_literature_digest.py" --config "$CONFIG" \
    mark-success --data-file "$JSON" --digest-file "$DIGEST" --email-status "$EMAIL_STATUS"

  echo "=== Done: $(date) ==="
} >>"$LOG" 2>&1
