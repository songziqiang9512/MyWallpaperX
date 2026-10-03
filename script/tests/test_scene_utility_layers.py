#!/usr/bin/env python3

from __future__ import annotations

from script.tests.source_family import read_source_family
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayer.swift"
RUNTIME_PLAN_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerRuntimePlan.swift"
SOURCE_ROUTE_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerSourceRoute.swift"
UTILITY_RENDERER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayerRenderer.swift"
METAL_RENDERER_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
METAL_RENDERER_INITIALIZATION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Initialization.swift"
)
UTILITY_FRAME_RENDERER_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityPlanFrameRenderer.swift"
)
DEPENDENCY_RUNTIME_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyFrameRuntime.swift"
)
DEPENDENCY_GEOMETRY_SOURCE = DEPENDENCY_RUNTIME_SOURCE.with_name(
    "SceneDependencyFrameRuntime+Geometry.swift"
)
AUTHORED_CATALOG_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectAdmissionCatalog.swift"
)
METAL_VIEW_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
IMAGE_COMPOSITOR_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor.swift"
)
FRAME_PREFLIGHT_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
)
SUBMISSION_COORDINATOR_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift"
)
EFFECT_EXECUTION_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+EffectExecution.swift"
)
COMPOSITION_SOURCE_FALLBACK = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+CompositionSourceFallback.swift"
)
CAPABILITY_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift"
)
CAPABILITY_PROGRAM_FIRST_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
)
CAPTURED_MAIN_SOURCE_CONSERVATION = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityVariant+CapturedMainSourceConservation.swift"
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
            ("models/util/composelayer.json", ["copybackground": false]),
            ("models/util/composelayer.json", ["copybackground": ["value": true]]),
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
            ["composition", "project", "fullscreen", "none", "none", "composition", "composition"],
        )

    def test_composition_background_default_and_explicit_flags(self) -> None:
        self.assertEqual(self.result["copyBackground"], [True, True, False, False, False, False, True])
        self.assertEqual(self.result["passthrough"], [True, False, False, False, False, False, False])

    def test_document_and_descriptor_preserve_generic_dependencies(self) -> None:
        document = (SOURCE_ROOT / "Format/SceneDocument.swift").read_text(encoding="utf-8")
        descriptor = (REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor.swift").read_text(encoding="utf-8")
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
        metal_renderer = read_source_family(METAL_RENDERER_SOURCE) \
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
        metal_renderer = (
            read_source_family(METAL_RENDERER_SOURCE)
            + METAL_RENDERER_INITIALIZATION_SOURCE.read_text(encoding="utf-8")
            + UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        )
        self.assertIn("audioSpectrum: SceneAudioSpectrumSnapshot", utility_renderer)
        self.assertIn("audioSpectrum: audioSpectrum", utility_renderer)
        self.assertIn("audioSpectrum: frameContext.audioSpectrum", metal_renderer)

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
            "letfinalDependencyTexture=dependencyConsumed?nil:"
            "dependencyEffect?.texture",
            compact_compositor,
        )
        self.assertIn(
            "dependencyTexture:finalDependencyTexture",
            compact_compositor,
        )
        self.assertIn(
            "($0.slotIndex==3&&$0.blendMode==0)",
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
        metal_renderer = (
            read_source_family(METAL_RENDERER_SOURCE)
            + METAL_RENDERER_INITIALIZATION_SOURCE.read_text(encoding="utf-8")
            + UTILITY_FRAME_RENDERER_SOURCE.read_text(encoding="utf-8")
        )
        dependency_runtime = (
            DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
            + "\n"
            + DEPENDENCY_GEOMETRY_SOURCE.read_text(encoding="utf-8")
        )
        # Capture admission and prepared-input consumption are exercised by
        # test_scene_dependency_render_plan's production Swift harness.
        self.assertIn(
            "executableUtilityConsumerLayerIDs: Set<Int>",
            dependency_runtime,
        )
        self.assertIn(
            "executableUtilityConsumerLayerIDs: executableUtilityConsumerLayerIDs",
            dependency_runtime,
        )
        self.assertIn(
            "dependencyEffects: [SceneDependencyEffectInput] = []",
            utility_renderer,
        )
        self.assertIn("dependencyEffects: dependencyEffects,", utility_renderer)
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
        dependency_runtime = (
            DEPENDENCY_RUNTIME_SOURCE.read_text(encoding="utf-8")
            + "\n"
            + DEPENDENCY_GEOMETRY_SOURCE.read_text(encoding="utf-8")
        )
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
        image_renderer = read_source_family(METAL_RENDERER_SOURCE)
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

        self.assertIn(
            "let dependencyEffect = request.dependencyEffects.first",
            compositor,
        )
        self.assertIn("dependencyTexture: dependencyEffect?.texture", compositor)


if __name__ == "__main__":
    unittest.main()
