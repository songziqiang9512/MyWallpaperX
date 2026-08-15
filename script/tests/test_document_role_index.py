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
HISTORY_README_PATH = DOCUMENTATION_ROOT / "history" / "README.md"
AGENT_RULES_PATH = REPOSITORY_ROOT / "AGENTS.md"
OFFICIAL_CLIENT_WORKFLOW_PATH = (
    DOCUMENTATION_ROOT
    / "scene"
    / "semantics"
    / "official-client-behavior-research-workflow.md"
)
DATED_MARKDOWN_PATTERN = re.compile(r"\d{4}-\d{2}-\d{2}")
MARKDOWN_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")
REPOSITORY_SOURCE_LINK_PATTERN = re.compile(
    r"`(?:MyWallpaperX|WallpaperDaemonSources)/[^`]+(?:\.swift|/)`"
)
HISTORICAL_BANNER = "> **历史证据 — 非现役入口**"
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

        discovery = self.index.get("discovery")
        self.assertIsInstance(discovery, dict)
        self.discovery = discovery
        history_root = discovery.get("historyRoot")
        self.assertIsInstance(history_root, str)
        self.history_root = REPOSITORY_ROOT / history_root

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

    def test_discovery_uses_history_root_plus_undated_additional_paths(self) -> None:
        self.assertEqual(set(self.discovery), {"historyRoot", "additionalPaths"})
        self.assertEqual(
            self.history_root.resolve(),
            (DOCUMENTATION_ROOT / "history").resolve(),
        )
        self.assertTrue(HISTORY_README_PATH.is_file())

        additional_paths = self.discovery.get("additionalPaths")
        self.assertIsInstance(additional_paths, list)
        self.assertEqual(additional_paths, sorted(additional_paths))
        for relative_path in additional_paths:
            with self.subTest(additionalPath=relative_path):
                self.assertIsInstance(relative_path, str)
                path = REPOSITORY_ROOT / relative_path
                self.assertTrue(path.is_file())
                self.assertEqual(path.suffix, ".md")
                self.assertFalse(path.resolve().is_relative_to(self.history_root.resolve()))
                self.assertNotRegex(path.name, DATED_MARKDOWN_PATTERN)

        discovered = {
            path.relative_to(REPOSITORY_ROOT).as_posix()
            for path in self.history_root.rglob("*.md")
            if path.resolve() != HISTORY_README_PATH.resolve()
        }
        discovered.update(str(path) for path in additional_paths)
        indexed = {str(document["path"]) for document in self.documents}
        self.assertEqual(
            indexed,
            discovered,
            "document role index must cover every history document plus explicit current documents",
        )

    def test_all_history_documents_are_explicit_historical_evidence(self) -> None:
        history_documents = {
            path.relative_to(REPOSITORY_ROOT).as_posix()
            for path in self.history_root.rglob("*.md")
            if path.resolve() != HISTORY_README_PATH.resolve()
        }
        indexed_history = {
            str(document["path"]): document
            for document in self.documents
            if (REPOSITORY_ROOT / str(document["path"]))
            .resolve()
            .is_relative_to(self.history_root.resolve())
        }
        self.assertEqual(set(indexed_history), history_documents)
        for relative_path, document in indexed_history.items():
            with self.subTest(path=relative_path):
                self.assertEqual(document.get("role"), "historical-evidence")
                self.assertEqual(document.get("entrypoint"), "docs/history/README.md")
                text = (REPOSITORY_ROOT / relative_path).read_text(encoding="utf-8")
                self.assertIn(HISTORICAL_BANNER, "\n".join(text.splitlines()[:12]))

    def test_dated_markdown_cannot_exist_outside_history(self) -> None:
        dated_outside_history = [
            path.relative_to(REPOSITORY_ROOT).as_posix()
            for path in DOCUMENTATION_ROOT.rglob("*.md")
            if DATED_MARKDOWN_PATTERN.search(path.name)
            and not path.resolve().is_relative_to(self.history_root.resolve())
        ]
        self.assertEqual(dated_outside_history, [])

    def test_documents_are_unique_sorted_and_exist(self) -> None:
        paths = [str(document["path"]) for document in self.documents]
        self.assertEqual(paths, sorted(paths))
        self.assertEqual(len(paths), len(set(paths)))
        for relative_path in paths:
            with self.subTest(path=relative_path):
                self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())

    def test_exactly_one_scene_active_roadmap_exists(self) -> None:
        scene_active_plans = [
            str(document["path"])
            for document in self.documents
            if document.get("role") == "active-plan"
            and str(document["path"]).startswith("docs/scene/")
        ]
        self.assertEqual(
            scene_active_plans,
            ["docs/scene/scene-compatibility-roadmap.md"],
        )

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

    def test_official_client_research_workflow_is_actionable(self) -> None:
        rules = AGENT_RULES_PATH.read_text(encoding="utf-8")
        workflow = OFFICIAL_CLIENT_WORKFLOW_PATH.read_text(encoding="utf-8")

        self.assertIn(
            "docs/scene/semantics/official-client-behavior-research-workflow.md",
            rules,
        )
        for heading in (
            "## 2. 何时启动，何时不得启动",
            "## 5. AI 研究卡",
            "## 7. 从研究到独立实现",
            "## 8. 官方结果一致性门",
            "## 9. 停止条件与文档回写",
        ):
            with self.subTest(heading=heading):
                self.assertIn(heading, workflow)

        for required_contract in (
            "不得把“每做一项功能都先反编译”设成前置仪式",
            "反编译输出不能进入产品实现",
            "固定控制变量",
            "预先声明比较方法",
            "官方客户端对照未运行",
            "不得保存或转述",
        ):
            with self.subTest(requiredContract=required_contract):
                self.assertIn(required_contract, workflow)


if __name__ == "__main__":
    unittest.main()
