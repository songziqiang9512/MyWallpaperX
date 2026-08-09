#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCE = SOURCE_ROOT / "Rendering/SceneUtilityLayer.swift"
RUNTIME_PLAN_SOURCE = SOURCE_ROOT / "Rendering/SceneUtilityLayerRuntimePlan.swift"
UTILITY_RENDERER_SOURCE = SOURCE_ROOT / "Rendering/SceneUtilityLayerRenderer.swift"
METAL_RENDERER_SOURCE = SOURCE_ROOT / "Rendering/SceneMetalRenderer.swift"
UTILITY_FRAME_RENDERER_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneUtilityPlanFrameRenderer.swift"
)
LEGACY_BATCH_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneMetalRenderer+LegacyAuthoredBatch.swift"
)
DEPENDENCY_RUNTIME_SOURCE = SOURCE_ROOT / "RenderGraph/SceneDependencyFrameRuntime.swift"
METAL_RENDERER_MASKS_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneMetalRenderer+EffectMasks.swift"
)
METAL_VIEW_SOURCE = SOURCE_ROOT / "Rendering/SceneMetalView.swift"
FRAME_PREFLIGHT_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneResolvedMaterialFramePreflight.swift"
)
EFFECT_EXECUTION_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneMetalRenderer+EffectExecution.swift"
)
BACKEND_SOURCE = SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan+Backend.swift"
FOLIAGE_PLANNER_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredFoliageSwayPlanner.swift"
)

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let fixtures: [(String?, [String: Any])] = [
            ("models/util/composelayer.json", ["config": ["passthrough": true]]),
            (" MODELS\\UTIL\\PROJECTLAYER.JSON ", ["copybackground": true]),
            ("models/util/fullscreenlayer.json", [:]),
            ("models/user/composelayer.json", [:]),
            (nil, [:]),
        ]
        let parsed = fixtures.map { SceneUtilityLayer.parse(imagePath: $0.0, object: $0.1) }
        let result: [String: Any] = [
            "kinds": parsed.map { $0?.kind.rawValue ?? "none" },
            "copyBackground": parsed.map { $0?.copyBackground ?? false },
            "passthrough": parsed.map { $0?.passthrough ?? false },
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneUtilityLayerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-utility-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-utility-layers"
        subprocess.run(
            ["xcrun", "--sdk", "macosx", "swiftc", str(SOURCE), str(harness), "-o", str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_canonical_paths_are_typed_without_matching_user_models(self) -> None:
        self.assertEqual(
            self.result["kinds"],
            ["composition", "project", "fullscreen", "none", "none"],
        )

    def test_utility_flags_are_authored_opt_in(self) -> None:
        self.assertEqual(self.result["copyBackground"], [False, True, False, False, False])
        self.assertEqual(self.result["passthrough"], [True, False, False, False, False])

    def test_document_and_descriptor_preserve_generic_dependencies(self) -> None:
        document = (SOURCE_ROOT / "Format/SceneDocument.swift").read_text(encoding="utf-8")
        descriptor = (SOURCE_ROOT / "Runtime/SceneRenderDescriptor.swift").read_text(encoding="utf-8")
        self.assertIn('SceneObjectDependencies(rawValue: root["dependencies"])', document)
        self.assertIn("dependencyLayerIDs: object.dependencyLayerIDs", descriptor)
        self.assertIn("authoredDependencies: object.authoredDependencies", descriptor)
        self.assertIn("if let utilityLayer = object.utilityLayer", descriptor)

    def test_complete_authored_capture_requires_every_visible_stage(self) -> None:
        runtime_plan = RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        self.assertIn("supportsCompleteAuthoredCapture", runtime_plan)
        self.assertIn(
            "chain.executionStages.count == visible.count",
            runtime_plan,
            "utility capture must not silently truncate a visible effect suffix",
        )
        self.assertIn(
            "chain.executionStages.count == chain.renderGraph.effects.count",
            runtime_plan,
            "utility capture must represent the complete authored graph",
        )
        self.assertIn(
            "chain.executionStages.allSatisfy(\\.supportsUtilityCapture)",
            runtime_plan,
            "every stage must explicitly admit utility capture",
        )
        backend = BACKEND_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "case .foliageSway:",
            backend,
            "the exact Foliage backend must explicitly admit utility capture",
        )
        self.assertIn(
            "case .clippingMask, .opacity:",
            backend,
            "exact named clipping and static/direct opacity must admit utility capture",
        )
        self.assertNotIn(
            "case .simple = plan.profile",
            backend,
            "migrated Simple Audio Bars must not keep a dedicated utility owner",
        )
        self.assertIn("default:", backend)
        self.assertIn("return false", backend)

    def test_foliage_utility_source_requires_a_typed_kind_pair(self) -> None:
        planner = FOLIAGE_PLANNER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("supportsLayerSource(layer)", planner)
        self.assertIn('if layer.contentKind == "image"', planner)
        self.assertIn("switch layer.utilityLayer", planner)
        self.assertIn("case nil:", planner)
        self.assertIn("case .some:", planner)
        for pair in (
            '("composition", .composition)',
            '("project", .project)',
            '("fullscreen", .fullscreen)',
        ):
            self.assertIn(pair, planner)
        self.assertIn("default:", planner)
        self.assertIn("return false", planner)

    def test_planned_utility_chain_loads_and_receives_effect_resources(self) -> None:
        metal_view = METAL_VIEW_SOURCE.read_text(encoding="utf-8")
        metal_renderer = METAL_RENDERER_SOURCE.read_text(encoding="utf-8") \
            + UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        metal_renderer_masks = METAL_RENDERER_MASKS_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "renderer.utilityCaptureLayerIDs.contains(layer.id)",
            metal_view,
            "a unified utility owner must still load its effect resources",
        )
        self.assertIn(
            ").authoredEffectResourcesOnly",
            metal_renderer,
            "utility capture must receive the same planned effect-instance resources",
        )
        self.assertIn(
            "foliageSwayEffects: store.foliageSwayEffects",
            metal_renderer_masks,
        )
        self.assertIn("xRay: store.xRayEffects[layerID]", metal_renderer_masks)

    def test_utility_capture_receives_the_frame_audio_snapshot(self) -> None:
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")
        metal_renderer = METAL_RENDERER_SOURCE.read_text(encoding="utf-8") \
            + UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("audioSpectrum: SceneAudioSpectrumSnapshot", utility_renderer)
        self.assertIn("audioSpectrum: audioSpectrum", utility_renderer)
        self.assertIn("audioSpectrum: frameContext.audioSpectrum", metal_renderer)

    def test_resolved_utility_uses_the_current_main_target_and_frame_plan(self) -> None:
        runtime_plan = RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        preflight = FRAME_PREFLIGHT_SOURCE.read_text(encoding="utf-8")
        effect_execution = EFFECT_EXECUTION_SOURCE.read_text(encoding="utf-8")
        frame_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")

        self.assertIn("resolvedMaterialLayerIDs.contains(layer.id)", runtime_plan)
        self.assertIn("case .capturedMainTargetTexture:", preflight)
        self.assertIn("sourceTexture = mainTarget", preflight)
        self.assertIn("textureFrame = geometry.sourceUV", preflight)
        self.assertIn("outputMVP = geometry.outputMVP", preflight)
        self.assertIn(
            "resolvedMaterialFrameTargetPlans: [",
            effect_execution + frame_renderer,
        )
        self.assertIn(
            "resolvedMaterialFrameTargetPlans[layer.id]",
            frame_renderer,
        )
        self.assertIn(
            "resolvedMaterialFrameTargetPlan:",
            utility_renderer,
        )

    def test_utility_authored_telemetry_follows_compositor_route_selection(self) -> None:
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")
        frame_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            "onLegacyAuthoredRouteSelected: (() -> Void)? = nil",
            utility_renderer,
        )
        self.assertIn(
            "onLegacyAuthoredRouteSelected: onLegacyAuthoredRouteSelected",
            utility_renderer,
        )
        route_flag = frame_renderer.index(
            "var selectedLegacyAuthoredRoute = false"
        )
        callback = frame_renderer.index(
            "onLegacyAuthoredRouteSelected:",
            route_flag,
        )
        guard = frame_renderer.index(
            "if selectedLegacyAuthoredRoute {",
            callback,
        )
        record = frame_renderer.index(
            "authoredEffectTelemetry.record(",
            guard,
        )
        self.assertLess(route_flag, callback)
        self.assertLess(callback, guard)
        self.assertLess(guard, record)
        self.assertNotIn("if authoredEffectChain != nil", frame_renderer)

    def test_legacy_batch_utility_extent_matches_dispatch_geometry_inputs(self) -> None:
        batch = LEGACY_BATCH_SOURCE.read_text(encoding="utf-8")
        utility_extent = batch.split(
            "private func utilityOffscreenSize(", maxsplit=1
        )[1]
        self.assertIn("let model = imageModelMatrix(", utility_extent)
        self.assertIn("worldFramesByLayerID: worldFramesByLayerID", utility_extent)
        self.assertIn("parallaxMouseNormalized: parallaxMouse", utility_extent)
        self.assertIn("configuration: parallaxConfiguration", utility_extent)
        self.assertIn("visibleHalfExtents: cameraFrame.coverHalfExtents", utility_extent)
        self.assertIn("SceneCaptureGeometryResolver.resolve(", utility_extent)
        self.assertNotIn(
            "worldFramesByLayerID[layer.id] ?? matrix_identity_float4x4",
            utility_extent,
        )

    def test_composition_capture_receives_named_dependency_atomically(self) -> None:
        runtime_plan = RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")
        metal_renderer = METAL_RENDERER_SOURCE.read_text(encoding="utf-8") \
            + UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        dependency_runtime = DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "dependencyPlan.bindingsByConsumerLayerID[layer.id] != nil",
            runtime_plan,
        )
        self.assertIn(
            "executableUtilityConsumerLayerIDs.contains(layer.id)",
            runtime_plan,
        )
        self.assertIn(
            "executableUtilityConsumerLayerIDs: Set<Int>",
            dependency_runtime,
        )
        self.assertIn(
            "executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs",
            dependency_runtime,
        )
        self.assertIn(
            "dependencyEffect: SceneDependencyEffectInput?",
            utility_renderer,
        )
        self.assertIn("dependencyEffect: dependencyEffect", utility_renderer)
        self.assertIn("dependencyRuntime.effectInput(", metal_renderer)
        self.assertIn(
            "resolvedMaterialLayerIDs: resolvedMaterialLayerIDs",
            metal_renderer,
        )
        self.assertIn(
            "dependencyRuntime.recordBindingIfRequired(",
            metal_renderer,
        )


if __name__ == "__main__":
    unittest.main()
