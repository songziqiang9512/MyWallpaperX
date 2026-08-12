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
DEPENDENCY_RUNTIME_SOURCE = SOURCE_ROOT / "RenderGraph/SceneDependencyFrameRuntime.swift"
AUTHORED_CATALOG_SOURCE = (
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan.swift"
)
METAL_RENDERER_MASKS_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneMetalRenderer+EffectMasks.swift"
)
METAL_VIEW_SOURCE = SOURCE_ROOT / "Rendering/SceneMetalView.swift"
IMAGE_COMPOSITOR_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneImageLayerCompositor.swift"
)
FRAME_PREFLIGHT_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneResolvedMaterialFramePreflight.swift"
)
EFFECT_EXECUTION_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneMetalRenderer+EffectExecution.swift"
)
BACKEND_SOURCE = SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan+Backend.swift"
CAPABILITY_PROGRAM_FIRST_SOURCE = (
    SOURCE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
)
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
        self.assertNotIn("implementedEffectPlan", runtime_plan)
        self.assertNotIn("SceneEffectRuntimePlanner", runtime_plan)
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
        self.assertIn("case .proceduralNoise(let plan):", backend)
        for contract in (
            "plan.variant == .legacyWorleyColor",
            "plan.dependencyProviderLayerID != nil",
            "plan.dependencySlotIndex == 3",
        ):
            self.assertIn(contract, backend)
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
        compact_plan = "".join(runtime_plan.split())
        complete_capture = compact_plan.index(
            "elseifsupportsCompleteAuthoredCapture("
        )
        capture = compact_plan.index("disposition=.capture", complete_capture)
        partial = compact_plan.index("disposition=.partialEffects", capture)
        self.assertLess(complete_capture, capture)
        self.assertLess(capture, partial)
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

    def test_resolved_utility_dependency_keeps_full_frame_closed_and_consumes_once(
        self,
    ) -> None:
        program_first = CAPABILITY_PROGRAM_FIRST_SOURCE.read_text(
            encoding="utf-8"
        )
        compositor = IMAGE_COMPOSITOR_SOURCE.read_text(encoding="utf-8")

        compact_program = "".join(program_first.split())
        start = compact_program.index(
            "guardpairLeaf||logicalTargetStage||fullFrameComposeStage,"
        )
        end = compact_program.index("stages.append(.dedicated", start)
        captured_main_gate = compact_program[start:end]
        self.assertIn(
            "admitted.sourceRoute!=.capturedMainTargetTexture||"
            "((pairLeaf||logicalTargetStage)&&"
            "program.executionPlan.supportsUtilityCapture)",
            captured_main_gate,
        )
        self.assertNotIn(
            "fullFrameComposeStage)&&"
            "program.executionPlan.supportsUtilityCapture",
            captured_main_gate,
        )

        compact_compositor = "".join(compositor.split())
        self.assertIn(
            "letdependencyConsumed=authoredChainConsumesDependency||"
            "graphExecutionTicket?.consumesExternalPrimaryDependency==true",
            compact_compositor,
        )
        self.assertIn(
            "dependencyBlendMode:dependencyConsumed?nil:"
            "dependencyEffect?.blendMode",
            compact_compositor,
        )
        self.assertIn(
            "dependencyTexture:dependencyConsumed?nil:"
            "dependencyEffect?.texture",
            compact_compositor,
        )

    def test_utility_has_no_legacy_authored_route_or_telemetry(self) -> None:
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")
        frame_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")

        combined = utility_renderer + frame_renderer
        self.assertNotIn("onLegacyAuthoredRouteSelected", combined)
        self.assertNotIn("selectedLegacyAuthoredRoute", combined)
        self.assertNotIn("authoredEffectTelemetry", combined)
        self.assertNotIn("legacyAuthoredFrameTables", combined)
        self.assertIn("utilityCaptureTelemetry.record(", frame_renderer)

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

    def test_rejected_graph_suppression_does_not_retire_typed_dependencies(
        self,
    ) -> None:
        catalog = AUTHORED_CATALOG_SOURCE.read_text(encoding="utf-8")
        dependency_runtime = DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
        image_renderer = METAL_RENDERER_SOURCE.read_text(encoding="utf-8")
        utility_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(
            encoding="utf-8"
        )
        compositor = IMAGE_COMPOSITOR_SOURCE.read_text(encoding="utf-8")

        self.assertIn(
            "let legacyEffectFallbackSuppressedLayerIDs: Set<Int>",
            catalog,
        )
        self.assertNotIn("suppressedConsumerLayerIDs", dependency_runtime)
        self.assertNotIn("suppressedConsumerLayerIDs", image_renderer)
        self.assertIn(
            "descriptor.layers.flatMap(\\.dependencyLayerIDs)",
            RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8"),
        )
        self.assertNotIn(
            "descriptor.layers.filter {",
            RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8"),
        )
        self.assertIn(
            "request.suppressesLegacyEffectFallback =\n"
            "                    suppressesLegacyEffectFallback",
            image_renderer,
        )

        self.assertIn(
            "let suppressesLegacyEffectFallback = renderer.authoredEffectCatalog",
            utility_renderer,
        )

        self.assertIn("let dependencyEffect = request.dependencyEffect", compositor)
        self.assertIn("dependencyTexture: dependencyEffect?.texture", compositor)


if __name__ == "__main__":
    unittest.main()
