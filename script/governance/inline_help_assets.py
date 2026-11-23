#!/usr/bin/env python3
"""Write the help book's shared style and script into every language page.

WebKit refuses parent-directory assets under file://, so the pages carry the
style and script inline. This keeps one editable source in script/help-assets/
and stamps it into all five pages, so a palette or behaviour change never has
to be repeated by hand.

    python3 script/build/inline_help_assets.py           # write
    python3 script/build/inline_help_assets.py --check   # report drift only
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELP = ROOT / "MyWallpaperXHelp"
ASSETS = ROOT / "script" / "help-assets"
LANGS = ("en", "zh-Hans", "ru", "de", "fr")

STYLE = re.compile(r"<style>\n.*?\n</style>", re.S)
SCRIPT = re.compile(r"<script defer>\n.*?\n</script>", re.S)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report drift without writing")
    args = parser.parse_args()

    style = (ASSETS / "styles.css").read_text(encoding="utf-8").rstrip("\n")
    script = (ASSETS / "help.js").read_text(encoding="utf-8").rstrip("\n")
    style_block = f"<style>\n{style}\n</style>"
    script_block = f"<script defer>\n{script}\n</script>"

    drifted: list[str] = []
    for lang in LANGS:
        page = HELP / f"{lang}.lproj" / "index.html"
        text = page.read_text(encoding="utf-8")
        updated = STYLE.sub(lambda _: style_block, text, count=1)
        updated = SCRIPT.sub(lambda _: script_block, updated, count=1)
        if updated == text:
            continue
        drifted.append(lang)
        if not args.check:
            page.write_text(updated, encoding="utf-8")

    if args.check:
        if drifted:
            print("inline-help-assets: out of date in " + ", ".join(drifted))
            return 1
        print(f"inline-help-assets: {len(LANGS)} pages match script/help-assets")
        return 0

    print(f"inline-help-assets: updated {len(drifted)} page(s)" if drifted else "inline-help-assets: already current")
    return 0


if __name__ == "__main__":
    sys.exit(main())
