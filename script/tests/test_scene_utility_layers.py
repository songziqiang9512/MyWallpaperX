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
SOURCE_ROUTE_SOURCE = SOURCE_ROOT / "Rendering/SceneUtilityLayerSourceRoute.swift"
SOURCE_COVERAGE_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneUtilityLayerSourceCoverage.swift"
)
UTILITY_RENDERER_SOURCE = SOURCE_ROOT / "Rendering/SceneUtilityLayerRenderer.swift"
METAL_RENDERER_SOURCE = SOURCE_ROOT / "Rendering/SceneMetalRenderer.swift"
UTILITY_FRAME_RENDERER_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneUtilityPlanFrameRenderer.swift"
)
DEPENDENCY_RUNTIME_SOURCE = (
    SOURCE_ROOT / "RenderGraph/LayerDependencies/SceneDependencyFrameRuntime.swift"
)
AUTHORED_CATALOG_SOURCE = (
    SOURCE_ROOT / "RenderGraph/EffectCompilation/SceneEffectAdmissionCatalog.swift"
)
METAL_VIEW_SOURCE = SOURCE_ROOT / "Rendering/SceneMetalView.swift"
IMAGE_COMPOSITOR_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneImageLayerCompositor.swift"
)
FRAME_PREFLIGHT_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneResolvedMaterialFramePreflight.swift"
)
SUBMISSION_COORDINATOR_SOURCE = (
    SOURCE_ROOT
    / "Runtime/ResolvedMaterialExecution/SceneResolvedMaterialSubmissionCoordinator.swift"
)
EFFECT_EXECUTION_SOURCE = (
    SOURCE_ROOT / "Rendering/SceneMetalRenderer+EffectExecution.swift"
)
COMPOSITION_SOURCE_FALLBACK = (
    SOURCE_ROOT / "Rendering/SceneMetalRenderer+CompositionSourceFallback.swift"
)
CAPABILITY_SOURCE = (
    SOURCE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift"
)
CAPABILITY_PROGRAM_FIRST_SOURCE = (
    SOURCE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
)
CAPTURED_MAIN_SOURCE_CONSERVATION = (
    SOURCE_ROOT
    / "RenderGraph/MaterialProgram"
    / "SceneResolvedMaterialExecutionCapabilityVariant+CapturedMainSourceConservation.swift"
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

    def test_utility_report_preserves_typed_dependency_issues(self) -> None:
        runtime_plan = RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            '"utilityDependencyIssueCount: \\(dependencyPlan.issues.count)"',
            runtime_plan,
        )
        self.assertIn(
            '"utilityDependencyIssue: kind=\\(issue.kind.rawValue) "',
            runtime_plan,
        )
        self.assertIn('"layer=\\(issue.layerID) provider=\\(provider)"', runtime_plan)

    def test_utility_capture_requires_unified_layer_ownership(self) -> None:
        runtime_plan = RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        self.assertIn("resolvedMaterialLayerIDs.contains(layer.id)", runtime_plan)
        self.assertIn("disposition = .capture", runtime_plan)
        self.assertNotIn("supportsCompleteAuthoredCapture", runtime_plan)
        self.assertNotIn("partialEffects", runtime_plan)
        capability = CAPABILITY_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("case dedicated", capability)
        self.assertNotIn("SceneEffectStageExecutionPlan", capability)

    def test_planned_utility_chain_loads_and_receives_effect_resources(self) -> None:
        metal_view = METAL_VIEW_SOURCE.read_text(encoding="utf-8")
        metal_renderer = METAL_RENDERER_SOURCE.read_text(encoding="utf-8") \
            + UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "resolvedMaterialRuntime.userPropertyDemands",
            metal_view,
            "shared MaterialProgram demands must drive resource loading",
        )
        self.assertIn(
            "masks: .empty",
            metal_renderer,
            "utility capture must use the shared Program texture bindings",
        )

    def test_utility_capture_receives_the_frame_audio_snapshot(self) -> None:
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")
        metal_renderer = METAL_RENDERER_SOURCE.read_text(encoding="utf-8") \
            + UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("audioSpectrum: SceneAudioSpectrumSnapshot", utility_renderer)
        self.assertIn("audioSpectrum: audioSpectrum", utility_renderer)
        self.assertIn("audioSpectrum: frameContext.audioSpectrum", metal_renderer)

    def test_resolved_utility_uses_the_current_main_target_and_frame_plan(self) -> None:
        runtime_plan = RUNTIME_PLAN_SOURCE.read_text(encoding="utf-8")
        source_route = SOURCE_ROUTE_SOURCE.read_text(encoding="utf-8")
        source_coverage = SOURCE_COVERAGE_SOURCE.read_text(encoding="utf-8")
        preflight = FRAME_PREFLIGHT_SOURCE.read_text(encoding="utf-8")
        coordinator = SUBMISSION_COORDINATOR_SOURCE.read_text(encoding="utf-8")
        effect_execution = EFFECT_EXECUTION_SOURCE.read_text(encoding="utf-8")
        frame_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")

        self.assertIn("resolvedMaterialLayerIDs.contains(layer.id)", runtime_plan)
        self.assertIn(
            "SceneUtilityLayerSourceRoute.resolve(",
            runtime_plan,
        )
        self.assertIn("triggerLayerID: sourceRoute?.triggerLayerID", runtime_plan)
        self.assertIn("order.first == layer.id", source_route)
        self.assertIn("Set(orderedSubtree) == subtreeIDs", source_route)
        self.assertIn("hasImplicitOpaqueCompositionAlpha(layer)", source_route)
        self.assertIn("layer.alpha == nil", source_route)
        self.assertIn("$0.host == .alpha", source_route)
        self.assertIn('$0.host == "alpha"', source_route)
        self.assertIn(".color(.resolved(.opaque))", source_coverage)
        self.assertIn(
            "isAxisAlignedFullViewportCoverage(",
            source_coverage,
        )
        self.assertIn(
            "utility-composition-subtree-source-coverage-unavailable",
            preflight,
        )
        self.assertIn(
            "utility-composition-subtree-source-coverage-unavailable",
            coordinator,
        )
        self.assertIn(
            "resolvedMaterialFrameTargetPlans[$0.layerID] != nil",
            effect_execution,
        )
        self.assertIn(
            r"by: \.triggerLayerID",
            METAL_RENDERER_SOURCE.read_text(encoding="utf-8"),
        )
        self.assertIn("case .capturedMainTargetTexture:", preflight)
        self.assertEqual(
            preflight.count("SceneUtilityLayerSourceRoute.resolve("),
            2,
        )
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
        self.assertNotIn("SceneEffectStageExecutionPlan", compact_program)
        self.assertNotIn("supportsUtilityCapture", compact_program)
        self.assertIn("compileStages(", compact_program)

        compact_compositor = "".join(compositor.split())
        self.assertIn(
            "letdependencyConsumed=graphExecutionTicket?."
            "consumesExternalPrimaryDependency==true",
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
        self.assertIn(
            "($0.slotIndex==3&&$0.blendMode==0)",
            compact_compositor,
        )

    def test_captured_main_accepts_exact_authored_filter_programs(self) -> None:
        conservation = CAPTURED_MAIN_SOURCE_CONSERVATION.read_text(
            encoding="utf-8"
        )
        self.assertIn("exactGraphReferences(", conservation)
        self.assertIn("variant.graphInputSourceSlotFacts", conservation)
        self.assertIn("activeSourceBinding.texture == effect.input", conservation)
        self.assertIn("return .sourceConsumer(slot: sourceSlot)", conservation)
        self.assertNotIn("capturedMainColorSourceSlot", conservation)

    def test_utility_has_no_legacy_authored_route_or_telemetry(self) -> None:
        utility_renderer = UTILITY_RENDERER_SOURCE.read_text(encoding="utf-8")
        frame_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")

        combined = utility_renderer + frame_renderer
        self.assertNotIn("onLegacyAuthoredRouteSelected", combined)
        self.assertNotIn("selectedLegacyAuthoredRoute", combined)
        self.assertNotIn("authoredEffectTelemetry", combined)
        self.assertNotIn("legacyAuthoredFrameTables", combined)
        self.assertIn("utilityCaptureTelemetry.record(", frame_renderer)

    def test_composition_source_fallback_is_neutral_and_structure_bounded(
        self,
    ) -> None:
        fallback = COMPOSITION_SOURCE_FALLBACK.read_text(encoding="utf-8")
        compact = "".join(fallback.split())
        self.assertIn(
            "SceneImageLayerBlendDependencyContract.declaration(",
            compact,
        )
        self.assertIn("declaration.blendMode==0", compact)
        self.assertIn("!declaration.requiresResolvedMaterialProgram", compact)
        self.assertIn("provider.visible==false", compact)
        self.assertIn(
            "SceneBaseImageTextureCandidateResolver.sample(", compact
        )
        self.assertIn("SceneImageLayerMainPassRenderer.draw(", compact)
        self.assertNotIn("2959875782", fallback)
        self.assertNotIn("ranger_wed", fallback)

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

    def test_hidden_solid_provider_uses_source_texture_capture(self) -> None:
        dependency_runtime = DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn(
            "case .resolvedMaterial, .solidLayer:",
            dependency_runtime,
        )
        self.assertGreaterEqual(
            dependency_runtime.count("case .solidLayer:"),
            2,
        )
        solid_branch = dependency_runtime[
            dependency_runtime.index("case .solidLayer:"):]
        self.assertIn("guard let sourceTexture else", solid_branch)
        self.assertIn("uniforms.tint = SIMD4", solid_branch)
        self.assertIn("providerTexture.width", solid_branch)
        self.assertIn(
            'failureReason = "solid-provider-texture-missing"',
            solid_branch,
        )
        self.assertIn('failureReason = "reservation-mismatch"', dependency_runtime)
        self.assertIn('failureReason = "frame-epoch-invalid"', dependency_runtime)

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

        self.assertNotIn("FallbackSuppressedLayerIDs", catalog)
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
        self.assertNotIn("suppressesUnclaimedEffectFallback", image_renderer)
        self.assertNotIn("authoredEffectCatalog", utility_renderer)

        self.assertIn("let dependencyEffect = request.dependencyEffect", compositor)
        self.assertIn("dependencyTexture: dependencyEffect?.texture", compositor)


if __name__ == "__main__":
    unittest.main()
