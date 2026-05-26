#!/usr/bin/env python3
"""Send an email via SMTP (e.g. Gmail with an App Password).

Credentials are read from a JSON secrets file (never hard-coded), e.g.:
  {
    "smtp_host": "smtp.gmail.com",
    "smtp_port": 465,
    "username": "you@gmail.com",
    "app_password": "abcd efgh ijkl mnop",
    "from": "you@gmail.com"
  }
Spaces in the app password are ignored. Uses SMTP_SSL for port 465, STARTTLS otherwise.
"""

from __future__ import annotations

import argparse
import json
import smtplib
import ssl
import sys
from email.message import EmailMessage
from pathlib import Path


def load_secrets(path: str) -> dict:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    for key in ("username", "app_password"):
        if not str(data.get(key, "")).strip():
            raise SystemExit(f"SMTP secrets file is missing '{key}'.")
    return data


def main() -> int:
    ap = argparse.ArgumentParser(description="Send an email via SMTP.")
    ap.add_argument("--config", required=True, help="Path to the SMTP secrets JSON file.")
    ap.add_argument("--to", required=True, action="append", help="Recipient address (repeatable).")
    ap.add_argument("--subject", required=True)
    ap.add_argument("--body-file", required=True, help="Plain-text (or Markdown) body file.")
    ap.add_argument("--html-file", help="Optional HTML body file (sent as a rich alternative).")
    args = ap.parse_args()

    s = load_secrets(args.config)
    host = s.get("smtp_host", "smtp.gmail.com")
    port = int(s.get("smtp_port", 465))
    username = s["username"].strip()
    password = s["app_password"].replace(" ", "")
    sender = s.get("from", username).strip()

    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = ", ".join(args.to)
    msg["Subject"] = args.subject
    msg.set_content(Path(args.body_file).read_text(encoding="utf-8"))
    if args.html_file:
        msg.add_alternative(Path(args.html_file).read_text(encoding="utf-8"), subtype="html")

    context = ssl.create_default_context()
    try:
        if port == 465:
            with smtplib.SMTP_SSL(host, port, context=context, timeout=60) as server:
                server.login(username, password)
                server.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=60) as server:
                server.starttls(context=context)
                server.login(username, password)
                server.send_message(msg)
    except Exception as exc:  # noqa: BLE001 - surface a clean failure for the caller.
        print(f"send failed: {exc}", file=sys.stderr)
        return 1
    print(f"sent to {msg['To']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
