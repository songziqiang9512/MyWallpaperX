#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DETAIL_PATH = (
    ROOT
    / "MyWallpaperX"
    / "Modules"
    / "SteamWorkshop"
    / "UI"
    / "SteamWorkshopItemDetailSheet.swift"
)
CONTROLLER_PATH = (
    ROOT
    / "MyWallpaperX"
    / "Modules"
    / "SteamWorkshop"
    / "UI"
    / "SteamWorkshopSceneInspectionController.swift"
)
LEGACY_SERVICE_PATH = (
    ROOT
    / "MyWallpaperX"
    / "Modules"
    / "SteamWorkshop"
    / "Scene"
    / "SteamWorkshopSceneService+SceneDiagnostics.swift"
)


def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening : index + 1]
    raise AssertionError(f"unterminated function: {signature}")


class SceneDetailDiagnosticsOnDemandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.detail = DETAIL_PATH.read_text(encoding="utf-8")
        cls.controller = CONTROLLER_PATH.read_text(encoding="utf-8")

    def test_detail_rebuild_only_delegates_scene_section(self) -> None:
        body = function_body(
            self.detail,
            "private func buildSceneDiagnosticsSection()",
        )
        self.assertIn("sceneInspectionController.makeSection(for: record)", body)
        self.assertNotIn("SceneDiagnosticsBuilder", body)
        self.assertNotIn("sceneDiagnosticsReport", body)

    def test_ordinary_content_does_not_build_scene_diagnostics_summary(self) -> None:
        body = function_body(self.detail, "private func buildContentSection()")
        self.assertNotIn("sceneDiagnosticsSummary", body)
        self.assertNotIn("sceneDiagnosticsReport", body)
        self.assertNotIn("SceneDiagnosticsBuilder", body)

    def test_default_expansion_is_explanatory_only(self) -> None:
        body = function_body(self.controller, "private func appendExpandedContent(")
        self.assertIn("诊断默认关闭", body)
        self.assertNotIn("startInspection", body)
        self.assertNotIn("SceneDiagnosticsBuilder", body)

    def test_explicit_actions_are_the_only_inspection_entrypoints(self) -> None:
        diagnostics = function_body(
            self.controller,
            "private func requestDiagnostics(for record:",
        )
        properties = function_body(
            self.controller,
            "private func requestPropertyEditor(for record:",
        )
        self.assertIn("startInspection(for: record, purpose: .diagnostics)", diagnostics)
        self.assertIn("startInspection(for: record, purpose: .properties)", properties)
        self.assertEqual(self.controller.count("SceneDiagnosticsBuilder().build("), 1)
        start = function_body(self.controller, "private func startInspection(")
        diagnostics_branch = start[
            start.index("case .diagnostics:") : start.index("case .properties:")
        ]
        properties_branch = start[start.index("case .properties:") :]
        self.assertIn("SceneDiagnosticsBuilder().build(", diagnostics_branch)
        self.assertNotIn("SceneDiagnosticsBuilder", properties_branch)
        self.assertIn("SceneRuntimeSourceFactsBuilder().build(", properties_branch)

    def test_inspection_runs_off_main_and_rejects_stale_completion(self) -> None:
        start = function_body(self.controller, "private func startInspection(")
        finish = function_body(self.controller, "private func finishInspection(")
        self.assertIn("queue.async(execute: workItem)", start)
        self.assertIn("DispatchQueue.main.async", start)
        self.assertIn("guard request?.id == requestID", finish)
        self.assertIn("guard presentedIdentity == identity", finish)

    def test_legacy_synchronous_service_entrypoint_is_removed(self) -> None:
        self.assertFalse(LEGACY_SERVICE_PATH.exists())


if __name__ == "__main__":
    unittest.main()
