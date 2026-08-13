#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path
from urllib.parse import unquote, urlsplit


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOCUMENTATION_ROOT = REPOSITORY_ROOT / "docs"
ROLE_INDEX_PATH = DOCUMENTATION_ROOT / "document-role-index.json"
DATED_MARKDOWN_PATTERN = re.compile(r"\d{4}-\d{2}-\d{2}")
MARKDOWN_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")
REPOSITORY_SOURCE_LINK_PATTERN = re.compile(
    r"`(?:MyWallpaperX|WallpaperDaemonSources)/[^`]+(?:\.swift|/)`"
)
VALID_ROLES = {"active-plan", "stable-contract", "historical-evidence"}


def load_role_index() -> dict[str, object]:
    return json.loads(ROLE_INDEX_PATH.read_text(encoding="utf-8"))


def local_markdown_targets(source: Path) -> set[Path]:
    targets: set[Path] = set()
    text = source.read_text(encoding="utf-8")
    for raw_target in MARKDOWN_LINK_PATTERN.findall(text):
        target = raw_target.strip()
        if target.startswith("<") and ">" in target:
            target = target[1 : target.index(">")]
        else:
            target = target.split(maxsplit=1)[0]
        parsed = urlsplit(target)
        if parsed.scheme or parsed.netloc or not parsed.path:
            continue
        targets.add((source.parent / unquote(parsed.path)).resolve())
    return targets


class DocumentRoleIndexTests(unittest.TestCase):
    def setUp(self) -> None:
        self.index = load_role_index()
        documents = self.index.get("documents")
        self.assertIsInstance(documents, list)
        self.documents = documents

    def test_schema_and_role_definitions_are_explicit(self) -> None:
        self.assertEqual(self.index.get("schemaVersion"), 1)
        definitions = self.index.get("roleDefinitions")
        self.assertIsInstance(definitions, dict)
        self.assertEqual(set(definitions), VALID_ROLES)
        self.assertEqual(
            definitions["active-plan"].get("requiredMetadata"),
            ["retirementCondition"],
        )
        self.assertEqual(
            definitions["stable-contract"].get("requiredMetadata"),
            ["currentStateAuthority"],
        )
        self.assertEqual(
            definitions["historical-evidence"].get("requiredMetadata"),
            ["commandPolicy", "currentAuthorities"],
        )
        self.assertEqual(
            definitions["historical-evidence"].get("commandPolicy"),
            "historical-only",
        )

    def test_index_exactly_covers_automatically_discovered_documents(self) -> None:
        discovery = self.index.get("discovery")
        self.assertIsInstance(discovery, dict)
        self.assertEqual(
            discovery.get("datedMarkdownFilenamePattern"),
            r"\d{4}-\d{2}-\d{2}",
        )
        additional_paths = discovery.get("additionalPaths")
        self.assertIsInstance(additional_paths, list)

        discovered = {
            path.relative_to(REPOSITORY_ROOT).as_posix()
            for path in DOCUMENTATION_ROOT.rglob("*.md")
            if DATED_MARKDOWN_PATTERN.search(path.name)
        }
        discovered.update(str(path) for path in additional_paths)
        indexed = {str(document["path"]) for document in self.documents}
        self.assertEqual(
            indexed,
            discovered,
            "document role index must match dated Markdown discovery plus explicit legacy paths",
        )

    def test_documents_are_unique_sorted_and_exist(self) -> None:
        paths = [str(document["path"]) for document in self.documents]
        self.assertEqual(paths, sorted(paths))
        self.assertEqual(len(paths), len(set(paths)))
        for relative_path in paths:
            with self.subTest(path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())

    def test_role_specific_metadata_points_to_current_authorities(self) -> None:
        for document in self.documents:
            relative_path = str(document["path"])
            role = document.get("role")
            with self.subTest(path=relative_path, role=role):
                self.assertIn(role, VALID_ROLES)
                if role == "active-plan":
                    condition = document.get("retirementCondition")
                    self.assertIsInstance(condition, str)
                    self.assertTrue(condition.strip())
                elif role == "stable-contract":
                    authority = document.get("currentStateAuthority")
                    self.assertIsInstance(authority, str)
                    authority_path = REPOSITORY_ROOT / authority
                    self.assertTrue(authority_path.is_file())
                    document_path = REPOSITORY_ROOT / relative_path
                    self.assertIn(
                        authority_path.resolve(),
                        local_markdown_targets(document_path),
                        "stable contracts must link their current-state authority",
                    )
                    self.assertNotRegex(
                        document_path.read_text(encoding="utf-8"),
                        REPOSITORY_SOURCE_LINK_PATTERN,
                        "stable contracts must not freeze current source-file locations",
                    )
                else:
                    self.assertEqual(document.get("commandPolicy"), "historical-only")
                    authorities = document.get("currentAuthorities")
                    self.assertIsInstance(authorities, list)
                    self.assertTrue(authorities)
                    for authority in authorities:
                        self.assertIsInstance(authority, str)
                        self.assertTrue((REPOSITORY_ROOT / authority).is_file())

    def test_each_entrypoint_actually_links_its_document(self) -> None:
        for document in self.documents:
            relative_path = str(document["path"])
            entrypoint = document.get("entrypoint")
            with self.subTest(path=relative_path, entrypoint=entrypoint):
                self.assertIsInstance(entrypoint, str)
                entrypoint_path = REPOSITORY_ROOT / entrypoint
                self.assertTrue(entrypoint_path.is_file())
                self.assertIn(
                    (REPOSITORY_ROOT / relative_path).resolve(),
                    local_markdown_targets(entrypoint_path),
                    "entrypoint must contain a Markdown link to the indexed document",
                )


if __name__ == "__main__":
    unittest.main()
