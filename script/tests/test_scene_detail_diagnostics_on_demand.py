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

    def test_detail_keeps_only_the_real_property_entry(self) -> None:
        body = function_body(self.detail, "@objc func openProperties()")
        self.assertIn("SteamWorkshopSceneInspectionController.requestPropertyEditor(for: record)", body)
        self.assertNotIn("openDiagnostics", self.detail)
        self.assertNotIn("diagnosticsPanel", self.detail)
        self.assertFalse(DETAIL_PATH.with_name("SteamWorkshopItemDetailSheet+Diagnostics.swift").exists())

    def test_ordinary_content_does_not_build_scene_diagnostics_summary(self) -> None:
        body = function_body(self.detail, "private func buildContentSection()")
        self.assertNotIn("sceneDiagnosticsSummary", body)
        self.assertNotIn("sceneDiagnosticsReport", body)
        self.assertNotIn("SceneDiagnosticsBuilder", body)

    def test_properties_retain_the_independent_preparation_owner(self) -> None:
        properties = function_body(self.controller, "private func preparePropertyEditor(for record:")
        self.assertIn("startInspection(for: record)", properties)
        self.assertIn("retaining: self", properties)
        entry = function_body(self.controller, "static func requestPropertyEditor(for record:")
        self.assertIn("propertyPreparation.preparePropertyEditor(for: current)", entry)
        self.assertNotIn("SceneDiagnosticsBuilder", self.controller)
        self.assertNotIn("makeSection", self.controller)
        build = function_body(self.controller, "private nonisolated static func buildPropertyInspection(")
        self.assertIn("SceneRuntimeSourceFactsBuilder().build(", build)

    def test_inspection_runs_off_main_and_rejects_stale_completion(self) -> None:
        start = function_body(self.controller, "private func startInspection(")
        finish = function_body(self.controller, "private func finishInspection(")
        self.assertIn("queue.async {", start)
        self.assertIn("withCheckedContinuation", start)
        self.assertNotIn("workItem.cancel()", start)
        self.assertIn("DispatchQueue.main.async", start)
        # Delivery, cancellation and replacement are exercised by the native
        # request-owner fixture rather than by a particular guard spelling.
        self.assertIn("guard presentedIdentity == identity", finish)


if __name__ == "__main__":
    unittest.main()
