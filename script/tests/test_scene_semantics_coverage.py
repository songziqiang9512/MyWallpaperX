#!/usr/bin/env python3

from __future__ import annotations

import fnmatch
import json
import re
import unittest
from collections import defaultdict
from pathlib import Path
from urllib.parse import unquote, urlsplit


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SEMANTICS_ROOT = REPOSITORY_ROOT / "docs/scene/semantics"
SCENE_SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SCENE_LAYOUT_PATH = REPOSITORY_ROOT / "script/scene_source_layout.json"
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
        layout = json.loads(SCENE_LAYOUT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(layout["schema_version"], 1)
        self.assertEqual(
            REPOSITORY_ROOT / layout["source_root"],
            SCENE_SOURCE_ROOT,
        )
        self.assertEqual(
            sorted(path.name for path in SCENE_SOURCE_ROOT.glob("*.swift")),
            [],
            "SteamWorkshopScene is a classification root and must not contain Swift files",
        )
        actual_directories = {
            path.relative_to(SCENE_SOURCE_ROOT).parts[0]
            for path in SCENE_SOURCE_ROOT.rglob("*.swift")
        }
        self.assertEqual(
            actual_directories,
            set(layout["top_level_directories"]),
        )

        declared_nested = layout["declared_second_level_directories"]
        misplaced: list[str] = []
        sources_by_name: defaultdict[str, list[Path]] = defaultdict(list)
        for source in sorted(SCENE_SOURCE_ROOT.rglob("*.swift")):
            relative = source.relative_to(SCENE_SOURCE_ROOT)
            sources_by_name[source.name].append(relative)
            if len(relative.parts) == 2:
                continue
            if len(relative.parts) != 3:
                misplaced.append(
                    f"{relative.as_posix()}: Scene Swift depth must be one or two"
                )
                continue
            top_level, second_level, filename = relative.parts
            contract = declared_nested.get(top_level, {}).get(second_level)
            if contract is None:
                misplaced.append(
                    f"{relative.as_posix()}: second-level directory is not declared"
                )
                continue
            if not any(
                fnmatch.fnmatchcase(filename, pattern)
                for pattern in contract["file_globs"]
            ):
                misplaced.append(
                    f"{relative.as_posix()}: filename is outside its directory contract"
                )

        for top_level, second_levels in declared_nested.items():
            for second_level, contract in second_levels.items():
                expected_parent = Path(top_level) / second_level
                for pattern in contract["file_globs"]:
                    matches = [
                        source
                        for source in SCENE_SOURCE_ROOT.rglob(pattern)
                        if source.is_file()
                    ]
                    if not matches:
                        misplaced.append(
                            f"{expected_parent}/{pattern}: layout glob matched no files"
                        )
                    for source in matches:
                        relative = source.relative_to(SCENE_SOURCE_ROOT)
                        if relative.parent != expected_parent:
                            misplaced.append(
                                f"{relative.as_posix()}: belongs in {expected_parent}"
                            )

        duplicate_names = {
            name: paths
            for name, paths in sources_by_name.items()
            if len(paths) > 1
        }
        self.assertEqual(
            duplicate_names,
            {},
            "Scene Swift basenames must stay unique for reliable navigation",
        )
        forbidden_names = set(layout["forbidden_directory_names"])
        forbidden_directories = sorted(
            path.relative_to(SCENE_SOURCE_ROOT).as_posix()
            for path in SCENE_SOURCE_ROOT.rglob("*")
            if path.is_dir() and path.name in forbidden_names
        )
        self.assertEqual(forbidden_directories, [])
        self.assertEqual(
            misplaced,
            [],
            "Scene source layout violations:\n" + "\n".join(misplaced),
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
