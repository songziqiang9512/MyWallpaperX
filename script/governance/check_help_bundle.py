#!/usr/bin/env python3
"""Keep the five help pages honest: same inlined style and script, same links.

WebKit refuses parent-directory assets under file://, so each language page carries
its own <style>, <script> and icon. This check makes sure they never drift apart.
"""
from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELP = ROOT / "MyWallpaperXHelp"
LANGS = ("en", "zh-Hans", "ru", "de", "fr")

STYLE = re.compile(r"<style>\n(.*?)\n</style>", re.S)
SCRIPT = re.compile(r"<script defer>\n(.*?)\n</script>", re.S)


def main() -> int:
    problems: list[str] = []
    assets = ROOT / "script/help-assets"
    reference = tuple((assets / name).read_text(encoding="utf-8").rstrip("\n")
                      for name in ("styles.css", "help.js"))
    app = ROOT / "MyWallpaperX"
    app_info = plistlib.loads((app / "Info.plist").read_bytes())
    help_info = plistlib.loads((HELP / "Info.plist").read_bytes())
    book_id = help_info["CFBundleIdentifier"]
    if app_info.get("CFBundleHelpBookName") != book_id or app_info.get("CFBundleHelpBookFolder") != HELP.name:
        problems.append("app Info.plist must identify the help bundle")
    if "CFBundleHelpBookName" in (app / "Resources/InfoPlist.xcstrings").read_text(encoding="utf-8"):
        problems.append("help book identifier must be language independent")

    for lang in LANGS:
        folder = HELP / f"{lang}.lproj"
        text = (folder / "index.html").read_text(encoding="utf-8")
        style, script = STYLE.search(text), SCRIPT.search(text)
        if not style or not script:
            problems.append(f"{lang}: missing inlined <style> or <script>")
            continue
        if (style.group(1), script.group(1)) != reference:
            problems.append(f"{lang}: inlined style/script differs from script/help-assets")
        if f'<meta name="AppleTitle" content="{book_id}">' not in text:
            problems.append(f"{lang}: help access page does not use the registered book identifier")
        title = folder / "InfoPlist.strings"
        if not title.is_file() or not re.search(r'"HPDBookTitle"\s*=\s*"[^"]+";', title.read_text(encoding="utf-8")):
            problems.append(f"{lang}: missing localized HPDBookTitle")
        if not (folder / "icon.png").exists():
            problems.append(f"{lang}: icon.png missing")

        # anchors must resolve inside the page
        ids = set(re.findall(r'id="([^"]+)"', text))
        for href in re.findall(r'href="#([^"]+)"', text):
            if href not in ids:
                problems.append(f"{lang}: dangling anchor #{href}")

        # language switcher reaches the other four pages
        links = set(re.findall(r'href="\.\./([a-zA-Z-]+)\.lproj/index\.html"', text))
        expected = set(LANGS) - {lang}
        if links != expected:
            problems.append(f"{lang}: language links {sorted(links)} != {sorted(expected)}")

    if problems:
        for problem in problems:
            print("help-bundle:", problem)
        return 1
    print(f"help bundle: {len(LANGS)} languages, identical style and script, anchors and links intact")
    return 0


if __name__ == "__main__":
    sys.exit(main())
