#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SERVICE_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Modules/SteamWorkshop/Scene/"
    "SteamWorkshopSceneService+SceneProperties.swift"
)
TEXTURE_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Modules/SteamWorkshop/Scene/"
    "SteamWorkshopSceneService+SceneTextureProperties.swift"
)
EDITOR_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Modules/SteamWorkshop/Scene/"
    "SteamWorkshopScenePropertyEditorView.swift"
)


def method_body(source: str, signature: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    raise AssertionError(f"unterminated method: {signature}")


class ScenePropertyLiveRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.service = SERVICE_SOURCE.read_text(encoding="utf-8")
        cls.texture = TEXTURE_SOURCE.read_text(encoding="utf-8")
        cls.editor = EDITOR_SOURCE.read_text(encoding="utf-8")

    def test_single_update_persists_before_live_attempt_and_rebuilds_on_rejection(self) -> None:
        update = method_body(self.service, "func updateScenePropertyValue(")
        save = update.index("saveScenePropertyOverrides")
        notify = update.index("objectWillChange.send()")
        live = update.index("applyUserPropertyValue(")
        fallback = update.index("scheduleActiveScenePropertyRender")
        self.assertLess(save, notify)
        self.assertLess(notify, live)
        self.assertLess(live, fallback)
        self.assertIn("if !SceneDesktopWallpaperHost.shared.applyUserPropertyValue(", update)

    def test_live_success_does_not_cancel_an_existing_fallback(self) -> None:
        update = method_body(self.service, "func updateScenePropertyValue(")
        schedule = method_body(self.service, "private func scheduleActiveScenePropertyRender(")
        self.assertNotIn("scenePropertyRenderTask?.cancel()", update)
        self.assertLess(
            schedule.index("guard SceneDesktopWallpaperHost.shared.activeRecordID"),
            schedule.index("scenePropertyRenderTask?.cancel()"),
        )
        self.assertEqual(
            schedule.count("SceneDesktopWallpaperHost.shared.activeRecordID == record.id"),
            2,
        )
        self.assertLess(
            schedule.index("Task.sleep"),
            schedule.rindex("SceneDesktopWallpaperHost.shared.activeRecordID"),
        )

    def test_reset_uses_only_old_override_keys_and_texture_changes_force_rebuild(self) -> None:
        reset = method_body(self.service, "func resetScenePropertyValues(")
        self.assertIn("defaultValues: [String: SceneUserPropertyValue]", reset)
        self.assertLess(
            reset.index("let overrides = scenePropertyOverrides"),
            reset.index("clearSceneTexturePropertyBookmarks"),
        )
        self.assertIn("let changedPropertyKeys = Set(overrides.keys)", reset)
        self.assertIn("if !removedTextureBookmarks,", reset)
        self.assertIn("applyUserPropertyValues(", reset)
        self.assertIn("changedPropertyKeys: changedPropertyKeys", reset)
        self.assertLess(
            reset.index("applyUserPropertyValues("),
            reset.index("scheduleActiveScenePropertyRender"),
        )

    def test_texture_bookmark_clear_reports_whether_runtime_resources_changed(self) -> None:
        clear = method_body(self.texture, "func clearSceneTexturePropertyBookmarks(")
        self.assertIn("-> Bool", clear)
        self.assertIn("var removedBookmark = false", clear)
        self.assertIn("removedBookmark = true", clear)
        self.assertIn("return removedBookmark", clear)

    def test_editor_passes_defaults_and_commits_slider_during_drag(self) -> None:
        self.assertIn("defaultValues: context.catalog.defaultValues", self.editor)
        slider = method_body(self.editor, "private func sliderBinding(")
        self.assertIn("set: { commit(.number($0), definition: definition) }", slider)
        row = method_body(self.editor, "private func sliderRow(")
        self.assertNotIn("isEditing", row)
        self.assertNotIn("updateScenePropertyValue", row)

    def test_layer_color_is_actionable_only_for_solid_layers(self) -> None:
        context = method_body(self.service, "func scenePropertyContext(")
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn(
            "supportsScenePropertyTarget(\n                    binding.target,\n"
            "                    in: renderDescriptor,\n"
            "                    authoredEffectCatalog: authoredEffectCatalog\n                )",
            context,
        )
        self.assertIn("case let .layerColor(layerID):", support)
        self.assertIn('$0.id == layerID && $0.contentKind == "solid"', support)
        self.assertNotIn('$0.contentKind == "image"', support)
        self.assertNotIn('$0.contentKind == "text"', support)
        self.assertNotIn('$0.contentKind == "particle"', support)

    def test_local_contrast_controls_require_the_strict_execution_catalog(self) -> None:
        context = method_body(self.service, "func scenePropertyContext(")
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn("SceneAuthoredEffectExecutionCatalog(", context)
        self.assertIn("shaderContracts: report.assetCatalog?.shaderContracts ?? []", context)
        self.assertIn("case let .effectVisibility(_, _, effectPath):", support)
        self.assertIn("case let .shaderValue(layerID, effectIndex, passIndex, name, effectPath):", support)
        self.assertEqual(support.count("Self.isStrictLocalContrastPath(effectPath)"), 2)
        self.assertIn(
            "if Self.isStrictLocalContrastPath(effectPath) {\n                return true",
            support,
        )
        self.assertIn("authoredEffectCatalog.liveConsumerTargets.contains(.effectConstant(", support)
        self.assertNotIn('(\"localcontrast\", [\"strength\"])', self.service)


if __name__ == "__main__":
    unittest.main()
