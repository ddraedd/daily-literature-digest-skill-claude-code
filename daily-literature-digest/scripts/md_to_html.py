#!/usr/bin/env python3
"""Convert a literature-digest Markdown file to styled, email-friendly HTML.

Stdlib only. Handles the Markdown subset the digest uses: headings (#, ##, ###),
GFM pipe tables, bullet lists, **bold**, `code`, [text](url) links, and bare URLs.
Block elements carry inline styles so they survive email clients like Gmail.
"""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path

ACCENT = "#1F4E5F"
ACCENT_DARK = "#173E4F"
BORDER = "#B8CDD2"
MUTED = "#5f6973"

LINK_RE = re.compile(r"\[([^\]]+)\]\((https?://[^)\s]+)\)")
BARE_URL_RE = re.compile(r"(https?://[^\s<>()]+)")
BOLD_RE = re.compile(r"\*\*([^*]+)\*\*")
CODE_RE = re.compile(r"`([^`]+)`")
SEP_RE = re.compile(r":?-{2,}:?")


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    stash: list[str] = []

    def keep(fragment: str) -> str:
        stash.append(fragment)
        return f"\x00{len(stash) - 1}\x00"

    text = LINK_RE.sub(lambda m: keep(f'<a href="{m.group(2)}" style="color:{ACCENT}">{m.group(1)}</a>'), text)
    text = BARE_URL_RE.sub(lambda m: keep(f'<a href="{m.group(1)}" style="color:{ACCENT}">{m.group(1)}</a>'), text)
    text = BOLD_RE.sub(r"<strong>\1</strong>", text)
    text = CODE_RE.sub(
        r'<code style="background:#f3f3f3;padding:1px 4px;border-radius:3px;font-size:90%">\1</code>', text
    )
    for index, fragment in enumerate(stash):
        text = text.replace(f"\x00{index}\x00", fragment)
    return text


def render_table(rows: list[str]) -> str:
    grid = [[cell.strip() for cell in row.strip().strip("|").split("|")] for row in rows]
    if len(grid) >= 2 and all(SEP_RE.fullmatch(cell.replace(" ", "")) for cell in grid[1] if cell != ""):
        header, body = grid[0], grid[2:]
    else:
        header, body = grid[0], grid[1:]
    th = "".join(
        f'<th style="border:1px solid {BORDER};padding:6px 9px;background:{ACCENT};'
        f'color:#fff;text-align:left;font-size:13px">{inline(cell)}</th>'
        for cell in header
    )
    body_rows = []
    for n, row in enumerate(body):
        bg = "#ffffff" if n % 2 == 0 else "#f4f8f9"
        tds = "".join(
            f'<td style="border:1px solid {BORDER};padding:6px 9px;font-size:13px;'
            f'vertical-align:top;background:{bg}">{inline(cell)}</td>'
            for cell in row
        )
        body_rows.append(f"<tr>{tds}</tr>")
    return (
        '<table style="border-collapse:collapse;width:100%;margin:10px 0 16px">'
        f"<thead><tr>{th}</tr></thead><tbody>{''.join(body_rows)}</tbody></table>"
    )


def convert(md: str) -> str:
    lines = md.splitlines()
    out: list[str] = []
    i, n = 0, len(lines)
    while i < n:
        stripped = lines[i].strip()
        if not stripped:
            i += 1
            continue
        if stripped.startswith("|"):
            table_lines = []
            while i < n and lines[i].strip().startswith("|"):
                table_lines.append(lines[i].strip())
                i += 1
            out.append(render_table(table_lines))
            continue
        if stripped.startswith("### "):
            out.append(f'<h3 style="color:{ACCENT_DARK};font-size:15px;margin:16px 0 4px">{inline(stripped[4:])}</h3>')
        elif stripped.startswith("## "):
            out.append(
                f'<h2 style="color:{ACCENT};font-size:18px;margin:20px 0 6px;'
                f'border-bottom:2px solid {BORDER};padding-bottom:3px">{inline(stripped[3:])}</h2>'
            )
        elif stripped.startswith("# "):
            out.append(f'<h1 style="color:{ACCENT_DARK};font-size:23px;margin:0 0 8px">{inline(stripped[2:])}</h1>')
        elif stripped.startswith("- "):
            items = []
            while i < n and lines[i].strip().startswith("- "):
                items.append(f'<li style="margin:3px 0">{inline(lines[i].strip()[2:])}</li>')
                i += 1
            out.append(f'<ul style="margin:6px 0 12px;padding-left:22px">{"".join(items)}</ul>')
            continue
        else:
            out.append(f'<p style="margin:8px 0">{inline(stripped)}</p>')
        i += 1

    body = "\n".join(out)
    return (
        '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1"></head>'
        '<body style="margin:0;padding:0;background:#f1f3f4">'
        '<div style="max-width:760px;margin:0 auto;padding:24px;background:#ffffff;'
        'font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;'
        f'font-size:14px;line-height:1.55;color:#23282d">{body}</div></body></html>'
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="Convert a digest Markdown file to styled HTML.")
    ap.add_argument("markdown_path")
    ap.add_argument("html_path")
    args = ap.parse_args()
    md = Path(args.markdown_path).read_text(encoding="utf-8")
    Path(args.html_path).write_text(convert(md), encoding="utf-8")
    print(str(Path(args.html_path).resolve()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
