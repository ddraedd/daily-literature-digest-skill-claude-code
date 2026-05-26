#!/bin/bash
# Installer for the Daily Literature Digest Claude Code skill.
# Non-destructive: never overwrites existing files without asking.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SKILL_SRC="$REPO_DIR/daily-literature-digest"
SKILL_DEST="$HOME/.claude/skills/daily-literature-digest"
WORKSPACE_DEFAULT="$HOME/literature-digest"
SMTP_DIR="$HOME/.config/literature-digest"
SMTP_FILE="$SMTP_DIR/smtp.json"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!  \033[0m %s\n' "$1"; }
ask()  { local p="$1" d="${2:-}" r; read -r -p "$p " r || true; printf '%s' "${r:-$d}"; }

# --- Prerequisites -----------------------------------------------------------
command -v python3 >/dev/null 2>&1 || { warn "python3 not found on PATH."; exit 1; }
command -v claude  >/dev/null 2>&1 || warn "claude CLI not found on PATH — install Claude Code before running the digest."

# --- 1. Install the skill ----------------------------------------------------
if [ -d "$SKILL_DEST" ]; then
  if [ "$(ask "Skill already exists at $SKILL_DEST. Overwrite? [y/N]" N)" = "y" ]; then
    rm -rf "$SKILL_DEST"; mkdir -p "$SKILL_DEST"; cp -R "$SKILL_SRC/." "$SKILL_DEST/"
    say "Skill reinstalled."
  else
    say "Keeping existing skill."
  fi
else
  mkdir -p "$(dirname "$SKILL_DEST")"; cp -R "$SKILL_SRC" "$SKILL_DEST"
  say "Skill installed to $SKILL_DEST"
fi
chmod +x "$SKILL_DEST/scripts/run-digest.sh" 2>/dev/null || true

# --- 2. Workspace + config ---------------------------------------------------
WORKSPACE="$(ask "Workspace directory for your config [$WORKSPACE_DEFAULT]:" "$WORKSPACE_DEFAULT")"
mkdir -p "$WORKSPACE"
CONFIG="$WORKSPACE/daily-literature-digest.config.json"
if [ -f "$CONFIG" ]; then
  say "Config already exists: $CONFIG (left untouched)."
else
  cp "$REPO_DIR/examples/config.example.json" "$CONFIG"
  say "Starter config created: $CONFIG"
  warn "Edit it: set recipient_email, keyword_groups, and output_dir."
fi

# --- 3. SMTP secrets ---------------------------------------------------------
mkdir -p "$SMTP_DIR"
if [ -f "$SMTP_FILE" ]; then
  say "SMTP secrets already exist: $SMTP_FILE (left untouched)."
else
  cp "$REPO_DIR/examples/smtp.example.json" "$SMTP_FILE"
  chmod 600 "$SMTP_FILE"
  say "SMTP secrets scaffolded: $SMTP_FILE (chmod 600)"
  warn "Add a Gmail App Password (https://myaccount.google.com/apppasswords) to enable email."
fi

# --- 4. Optional: macOS launchd schedule ------------------------------------
if [ "$(uname)" = "Darwin" ]; then
  if [ "$(ask "Set up a daily launchd schedule now? [y/N]" N)" = "y" ]; then
    HOUR="$(ask "Hour to run (0-23, MACHINE-LOCAL time) [9]:" 9)"
    MIN="$(ask "Minute [0]:" 0)"
    PLIST="$HOME/Library/LaunchAgents/com.$USER.literature-digest.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    sed -e "s|__USERNAME__|$USER|g" \
        -e "s|__HOUR__|$HOUR|g" \
        -e "s|__MINUTE__|$MIN|g" \
        -e "s|com.example.literature-digest|com.$USER.literature-digest|g" \
        "$REPO_DIR/examples/com.example.literature-digest.plist" > "$PLIST"
    # If the config lives outside the default, point the job at it explicitly.
    if [ "$WORKSPACE" != "$WORKSPACE_DEFAULT" ]; then
      warn "Non-default workspace — add DIGEST_CONFIG=$CONFIG to the plist's EnvironmentVariables, or move your config."
    fi
    launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" && say "Scheduled: $PLIST (runs $HOUR:$(printf '%02d' "$MIN") local)"
    warn "launchd uses machine-local time and only runs while you're logged in and the Mac is awake."
  fi
fi

say "Done. Edit your config + SMTP secrets, then ask Claude Code: \"Use the daily-literature-digest skill to generate today's digest.\""
