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
LIVE_CONSUMERS_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Core/SteamWorkshopScene/Runtime/"
    "SceneDesktopWallpaperHost+LiveConsumers.swift"
)
LAYER_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Core/SteamWorkshopScene/Runtime/"
    "SceneRenderDescriptor+Layer.swift"
)
RUNTIME_MODEL_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneRuntimeModel.swift"
)
HOST_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift"
)
METAL_VIEW_SOURCE = REPOSITORY_ROOT / (
    "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift"
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
        cls.live_consumers = LIVE_CONSUMERS_SOURCE.read_text(encoding="utf-8")
        cls.layer = LAYER_SOURCE.read_text(encoding="utf-8")
        cls.runtime_model = RUNTIME_MODEL_SOURCE.read_text(encoding="utf-8")
        cls.host = HOST_SOURCE.read_text(encoding="utf-8")
        cls.metal_view = METAL_VIEW_SOURCE.read_text(encoding="utf-8")

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

    def test_unready_deferred_selection_preserves_previous_current(self) -> None:
        selection = method_body(
            self.live_consumers,
            "func deferredLayerVisibilitySelection(",
        )
        promote = method_body(
            self.live_consumers,
            "func promotePendingDeferredLayerVisibilityIfReady()",
        )
        apply = method_body(self.host, "func applyUserPropertyValues(")
        adoption = method_body(
            self.metal_view,
            "func adoptPreparedDeferredBaseImage(",
        )

        self.assertIn("propertyBindingProgram.evaluate(", selection)
        self.assertIn("case .bool(true)? = selectedValues", selection)
        self.assertIn("deferredLayerIDs.contains(layerID)", selection)
        self.assertLess(
            apply.index("candidateLiveState.apply("),
            apply.index("deferredLayerVisibilitySelection("),
        )
        self.assertIn("requestDeferredBaseImage(", apply)
        self.assertIn("pendingDeferredLayerVisibilityUpdate = .init(", apply)
        self.assertIn("return true", apply)
        self.assertIn("statuses.allSatisfy({ $0 == .ready })", promote)
        self.assertLess(
            promote.index("adoptPreparedDeferredBaseImage"),
            promote.index("context.liveState = candidateLiveState"),
        )
        self.assertLess(
            promote.index("case let .failed(code)"),
            promote.index("context.liveState = candidateLiveState"),
        )
        self.assertIn("preparedBaseImages.outcome(", adoption)
        self.assertIn("imageTextures.set(", adoption)

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

    def test_layer_color_is_live_for_solid_and_effectless_image_layers(self) -> None:
        context = method_body(self.service, "func scenePropertyContext(")
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn(
            "supportsScenePropertyTarget(\n                    binding.target,\n"
            "                    in: renderDescriptor\n                )",
            context,
        )
        self.assertIn("case let .layerColor(layerID):", support)
        layer_color = support[
            support.index("case let .layerColor(layerID):") : support.index(
                "case let .camera(field):"
            )
        ]
        self.assertIn(
            "$0.id == layerID && $0.supportsDirectLayerColorConsumer",
            layer_color,
        )

        eligibility = method_body(
            self.layer,
            "nonisolated var supportsDirectLayerColorConsumer: Bool",
        )
        self.assertIn('contentKind == "solid"', eligibility)
        self.assertIn('contentKind == "image" && effects.isEmpty', eligibility)
        self.assertNotIn('contentKind == "text"', eligibility)
        self.assertNotIn('contentKind == "particle"', eligibility)

        consumers = method_body(
            self.live_consumers, "static func activeLiveConsumerTargets("
        )
        image_case = consumers[
            consumers.index('case "image":') : consumers.index('case "text":')
        ]
        self.assertIn("if layer.supportsDirectLayerColorConsumer", image_case)
        self.assertIn("visibleLayerIDs.contains(layer.id)", image_case)
        self.assertIn(
            ".layer(layerID: layer.id, field: .color)", image_case
        )

        model = self.runtime_model
        self.assertIn(
            "let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(",
            model,
        )
        self.assertIn("let hasConsumer = layer.supportsDirectLayerColorConsumer", model)
        self.assertIn('layer.contentKind == "text"', model)
        self.assertIn("layer.supportsDirectLayerColorConsumer", model)
        self.assertIn("visibleLayerIDs.contains(layer.id)", model)
        self.assertIn(
            "admittedLayerColorConsumerIDs: sceneScriptColorConsumerLayerIDs",
            model,
        )

    def test_uniform_layer_scale_is_live_for_the_shared_world_frame(self) -> None:
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn("case let .layerScale(layerID):", support)
        self.assertIn(
            "renderDescriptor.layers.contains { $0.id == layerID }",
            support,
        )
        consumers = method_body(
            self.live_consumers, "static func activeLiveConsumerTargets("
        )
        self.assertIn(
            "targets.insert(.layer(layerID: layer.id, field: .scale))",
            consumers,
        )
        self.assertNotIn("SceneScriptedLayerTransformProjection.apply", self.runtime_model)

    def test_particle_properties_are_actionable_only_for_particle_layers(self) -> None:
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn("case let .particle(layerID, _):", support)
        self.assertIn('$0.id == layerID && $0.contentKind == "particle"', support)
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        self.assertIn('case "particle":', consumers)
        for field in (
            ".alpha", ".size", ".lifetime", ".rate", ".speed", ".count",
            ".brightness", ".normalizedColor",
        ):
            self.assertIn(field, consumers)
        self.assertIn(".particle(layerID: layer.id, field: $0)", consumers)

    def test_camera_shake_properties_require_supported_scene_projection(self) -> None:
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        for field in (
            "camerashake",
            "camerashakeamplitude",
            "camerashakeroughness",
            "camerashakespeed",
        ):
            self.assertIn(f'"{field}"', support)
        camera_case = support[
            support.index("case let .camera(field):") : support.index(
                "case let .effectVisibility"
            )
        ]
        self.assertIn("let orthoWidth = renderDescriptor.camera.orthoWidth", camera_case)
        self.assertIn("let orthoHeight = renderDescriptor.camera.orthoHeight", camera_case)
        self.assertIn("orthoWidth.isFinite", camera_case)
        self.assertIn("orthoHeight.isFinite", camera_case)
        self.assertIn("orthoWidth > 0", camera_case)
        self.assertIn("orthoHeight > 0", camera_case)
        self.assertIn("return false", camera_case)
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        self.assertNotIn("cameraShake", consumers)

    def test_puppet_animation_visibility_is_live_only_for_bound_layers(self) -> None:
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertIn(
            "case let .puppetAnimationVisibility(layerID, animationLayerID):",
            support,
        )
        self.assertIn("$0.id == animationLayerID && $0.visibilityBinding != nil", support)
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        self.assertIn("where animationLayer.visibilityBinding != nil", consumers)
        self.assertIn("ScenePuppetAnimationPropertyTarget.visibility(", consumers)

    def test_effect_properties_validate_descriptor_identity_without_path_allowlists(self) -> None:
        context = method_body(self.service, "func scenePropertyContext(")
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        self.assertNotIn("SceneAuthoredEffectExecutionCatalog", context)
        self.assertIn("case let .effectVisibility(layerID, effectIndex, effectPath)", support)
        self.assertIn("let .shaderValue(layerID, effectIndex, _, _, effectPath)", support)
        self.assertIn("Self.hasAuthoredEffect(", support)
        identity = method_body(self.service, "private static func hasAuthoredEffect(")
        self.assertIn("layer.effects.indices.contains(effectIndex)", identity)
        self.assertIn("layer.effects[effectIndex].file", identity)
        self.assertNotIn("supportedNamesByPath", self.service)
        self.assertNotIn("isStrictLocalContrastPath", self.service)

    def test_actionable_properties_come_from_typed_binding_targets(self) -> None:
        context = method_body(self.service, "func scenePropertyContext(")
        self.assertIn(
            "document.userPropertyResolution.bindingReport.bindings", context
        )
        self.assertIn("+ materialBindings", context)
        self.assertNotIn("authoredEffectCatalog", context)
        self.assertNotIn("blendPlan", context)
        self.assertNotIn("SceneImageBlendRenderPlan", self.service)

    def test_resolved_material_property_targets_remain_live_after_owner_transfer(self) -> None:
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        self.assertIn(
            "resolvedMaterialExecutionCapabilities:\n"
            "            SceneResolvedMaterialExecutionCapabilityCatalog",
            consumers,
        )
        self.assertIn(
            "resolvedMaterialExecutionCapabilities.liveConsumerTargets",
            consumers,
        )

    def test_static_model_material_properties_share_editor_and_live_targets(self) -> None:
        context = method_body(self.service, "func scenePropertyContext(")
        support = method_body(self.service, "private func supportsScenePropertyTarget(")
        consumers = method_body(
            self.live_consumers, "static func activeLiveConsumerTargets("
        )
        self.assertIn(
            "SceneStaticModelMaterialPropertyBindingCompiler.compile(", context
        )
        self.assertIn("+ materialBindings", context)
        self.assertIn("case .materialShaderValue:", support)
        self.assertIn(
            "SceneStaticModelMaterialPropertyBindingCompiler.compile(", support
        )
        self.assertIn("preparedStaticModelLayerIDs", consumers)
        self.assertIn("case let .materialConstant(layerID, _, _)", consumers)
        self.assertIn(".union(modelMaterialTargets)", consumers)

    def test_generic_string_property_inputs_remain_live_without_scene_relaunch(self) -> None:
        consumers = method_body(self.live_consumers, "static func activeLiveConsumerTargets(")
        unavailable = method_body(
            self.live_consumers, "static func unavailableLiveScriptPropertyTargets("
        )
        for source in (consumers, unavailable):
            self.assertIn("sceneScriptStringProgram.livePropertyInputTargets", source)
        self.assertIn(
            "sceneScriptStringProgram.activeLivePropertyInputTargets",
            unavailable,
        )


if __name__ == "__main__":
    unittest.main()
