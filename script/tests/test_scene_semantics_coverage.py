#!/usr/bin/env python3

from __future__ import annotations

import re
import unittest
from pathlib import Path
from urllib.parse import unquote, urlsplit


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SEMANTICS_ROOT = REPOSITORY_ROOT / "docs/scene/semantics"
SCENE_SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
EXPECTED_SCENE_SOURCE_DIRECTORIES = {
    "Effects",
    "Format",
    "Particles",
    "Properties",
    "RenderGraph",
    "Rendering",
    "Resources",
    "Runtime",
    "Text",
}
INLINE_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")


def markdown_without_fenced_code(text: str) -> str:
    visible_lines: list[str] = []
    fence: str | None = None
    for line in text.splitlines():
        match = re.match(r"^\s*(```|~~~)", line)
        if match:
            marker = match.group(1)
            if fence is None:
                fence = marker
            elif marker == fence:
                fence = None
            continue
        if fence is None:
            visible_lines.append(line)
    return "\n".join(visible_lines)


def markdown_link_targets(text: str) -> list[str]:
    targets: list[str] = []
    for raw_target in INLINE_LINK_PATTERN.findall(markdown_without_fenced_code(text)):
        target = raw_target.strip()
        if target.startswith("<") and ">" in target:
            target = target[1 : target.index(">")]
        else:
            target = target.split(maxsplit=1)[0]
        targets.append(target)
    return targets


class SceneSemanticsCoverageTests(unittest.TestCase):
    def test_scene_sources_follow_the_documented_directory_layout(self) -> None:
        self.assertEqual(
            sorted(path.name for path in SCENE_SOURCE_ROOT.glob("*.swift")),
            [],
            "SteamWorkshopScene is a classification root and must not contain Swift files",
        )
        actual_directories = {
            path.parent.name
            for path in SCENE_SOURCE_ROOT.glob("*/*.swift")
            if path.is_file()
        }
        self.assertEqual(actual_directories, EXPECTED_SCENE_SOURCE_DIRECTORIES)
        nested_sources = [
            path.relative_to(SCENE_SOURCE_ROOT).as_posix()
            for path in SCENE_SOURCE_ROOT.glob("*/*/*.swift")
        ]
        self.assertEqual(
            nested_sources,
            [],
            "Scene source categories stay one level deep unless the layout contract changes",
        )

    def test_relative_markdown_links_in_semantics_directory_exist(self) -> None:
        missing: list[str] = []
        for document in sorted(SEMANTICS_ROOT.glob("*.md")):
            text = document.read_text(encoding="utf-8")
            for target in markdown_link_targets(text):
                parsed = urlsplit(target)
                if parsed.scheme or target.startswith(("#", "/", "//")):
                    continue
                relative_path = unquote(parsed.path)
                if not relative_path:
                    continue
                resolved = (document.parent / relative_path).resolve()
                if not resolved.exists():
                    missing.append(
                        f"{document.relative_to(REPOSITORY_ROOT)} -> {target}"
                    )

        self.assertEqual(missing, [], "Missing relative Markdown links:\n" + "\n".join(missing))


if __name__ == "__main__":
    unittest.main()
