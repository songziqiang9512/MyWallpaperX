#!/usr/bin/env python3

"""Keep diagnostic and static graph work out of normal Scene frames."""

from __future__ import annotations

from script.tests.source_family import read_source_family
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


class SceneRealtimePathPolicyTests(unittest.TestCase):
    def test_static_graph_work_is_reused_for_stable_generations(self) -> None:
        state = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphExecutionState.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("let reusesStaticPlan = !reparsed && !allocationChanged", state)
        self.assertIn("operations = cachedOperations", state)
        self.assertIn("historyClosure = previous.historyClosureIdentities", state)

    # Preparation-order behavior is exercised by test_scene_dependency_render_plan;
    # the removed helper-count assertion only pinned the former two-walk preflight.

    def test_full_graph_observations_are_explicitly_opt_in(self) -> None:
        completion = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+Completion.swift"
        ).read_text(encoding="utf-8")
        guard = completion.index("guard capturesExecutionObservations else")
        builder = completion.index("SceneResolvedMaterialGraphObservationBuilder.make")
        self.assertLess(guard, builder)

    def test_product_launch_only_enables_observations_for_debug_evidence(self) -> None:
        launch = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text(encoding="utf-8")
        self.assertGreaterEqual(
            launch.count(
                "capturesExecutionObservations: Self.usesExecutionObservationCapture"
            ),
            2,
        )
        host = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
        ).read_text(encoding="utf-8")
        # Observations stay strictly opt-in for the debug evidence window; the
        # performance-only opt-out may only narrow that, never widen it, and
        # non-DEBUG builds must still resolve to false.
        definition = host.index(
            "static var usesExecutionObservationCapture: Bool"
        )
        body = host[definition : host.index("\n    }", definition)]
        self.assertIn("usesDebugEvidenceWindow", body)
        self.assertIn("--mwx-debug-scene-no-execution-observations", body)
        self.assertIn("false", body)

    def test_dynamic_frame_schema_is_prepared_at_launch(self) -> None:
        launch = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text(encoding="utf-8")
        frame_driver = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
        ).read_text(encoding="utf-8")
        frame_schema = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperLaunchFrameSchema.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "self.launchDefinitions = SceneDynamicDefinitionMerger.merge(",
            frame_schema,
        )
        self.assertIn(
            "self.sceneScriptStatefulTargets = Set(",
            frame_schema,
        )
        self.assertIn("SceneDesktopWallpaperLaunchFrameSchema(", launch)
        self.assertIn(
            "let definitionIndex = launchContext.dynamicDefinitionIndex",
            frame_driver,
        )
        self.assertIn(
            "index: definitionIndex",
            frame_driver,
        )
        self.assertIn("frameSchema.dynamicDefinitions", launch)
        self.assertIn("authoredDefinitionRevision", frame_schema)
        self.assertIn("cachedDefinitionIndexRevision", frame_schema)
        self.assertIn(
            "SceneDynamicSnapshotResolver.prepare(",
            frame_schema,
        )
        self.assertIn(
            "let sceneScriptStatefulTargets = launchContext.sceneScriptStatefulTargets",
            frame_driver,
        )
        self.assertNotIn(
            "SceneDynamicDefinitionMerger.merge(",
            frame_driver,
        )

    def test_dynamic_layer_projection_is_revisioned(self) -> None:
        renderer = read_source_family(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift")
        projection = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+FrameWorldProjection.swift"
        ).read_text(encoding="utf-8")
        topology = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicLayerRuntime.swift"
        ).read_text(encoding="utf-8")
        cache = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneDynamicLayerRenderTopologyCache.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("let dynamicLayerTopologyCache", renderer)
        self.assertIn("dynamicLayerTopologyCache.resolve(", projection)
        self.assertNotIn(
            "frameDescriptor = renderDescriptor.applying(layerTopology)",
            renderer + projection,
        )
        self.assertIn("private(set) var topologyRevision: UInt64", topology)
        self.assertIn("dynamicTopologyChanged", topology)
        self.assertIn("cachedSnapshotTopologyRevision", topology)
        self.assertIn(
            "if cachedSnapshotTopologyRevision != topologyRevision",
            topology,
        )
        self.assertIn("revision == topology.topologyRevision", cache)
        self.assertIn("func applyingFrameValues(", cache)
        self.assertIn("let layerIndicesByID: [Int: Int]", cache)
        self.assertIn("guard let index = layerIndicesByID[layer.id]", cache)
        self.assertNotIn("descriptor.layers.firstIndex(where:", cache)
        self.assertIn("let dynamicLayerIDs: Set<Int>", cache)
        self.assertIn("let lightLayerIDs: [Int]", cache)
        self.assertIn("let orderedLayers: [SceneRenderDescriptor.Layer]", cache)
        self.assertIn("let orderedLayerPositionsByID: [Int: Int]", cache)
        self.assertIn("orderedLayers[orderedIndex] = layer", cache)
        self.assertIn("let orderedLayers: [SceneRenderDescriptor.Layer]", projection)
        self.assertIn("orderedLayers = projection.orderedLayers", projection)
        self.assertIn("orderedLayers = authoredLayers", projection)
        self.assertNotIn(
            "let orderedLayers = authoredLayerIDs.compactMap",
            renderer + projection,
        )

    def test_system_provider_demand_order_is_prepared(self) -> None:
        bindings = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneBaseMaterialProviderBindingProgram.swift"
        ).read_text(encoding="utf-8")
        texture_frame = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+TextureFrame.swift"
        ).read_text(encoding="utf-8")
        bridge = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("let orderedSystemProviderDemands:", bindings)
        self.assertIn(
            "baseMaterialProviderBindings.orderedSystemProviderDemands",
            texture_frame,
        )
        self.assertIn("private let orderedSystemProviderDemands:", bridge)
        self.assertIn(
            "for identity in orderedSystemProviderDemands",
            bridge,
        )
        self.assertEqual(
            bridge.count("catalog.systemProviderDemands.sorted(by:"),
            1,
        )

    def test_scene_script_inputs_use_program_owned_typed_lanes(self) -> None:
        frame_driver = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift"
        ).read_text(encoding="utf-8")
        snapshot = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift"
        ).read_text(encoding="utf-8")
        self.assertEqual(frame_driver.count(".typedValues("), 3)
        self.assertIn("propertyVectorScriptProgram.inputTargets", frame_driver)
        self.assertIn("sceneScriptStringProgram.inputTargets", frame_driver)
        self.assertIn("sceneScriptScalarProgram.inputTargets", frame_driver)
        self.assertIn("nonisolated func typedValues", snapshot)
        self.assertNotIn(
            "propertyVectorScriptProgram.bindings.reduce",
            frame_driver,
        )
        self.assertNotIn("sceneScriptStringProgram.bindings\n            .reduce", frame_driver)
        self.assertNotIn("sceneScriptScalarProgram.bindings.reduce", frame_driver)

    def test_frame_visibility_reuses_prepared_layer_index(self) -> None:
        visibility = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerVisibility.swift"
        ).read_text(encoding="utf-8")
        renderer = read_source_family(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift")
        preflight = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "layersByID: [Int: SceneRenderDescriptor.Layer]",
            visibility,
        )
        self.assertIn("layersByID: frameLayersByID", renderer)
        # The preflight consumes the renderer's resolved visibility set; the
        # duplicate per-frame walk must not reappear here (E1-②).
        self.assertIn("frameVisibleLayerIDs: Set<Int>,", preflight)
        self.assertNotIn("SceneLayerVisibility.visibleLayerIDs", preflight)
        self.assertIn(
            "frameProjection.dynamicLayerIDs.contains(layer.id)",
            renderer,
        )
        self.assertIn("frameProjection.lightLayerIDs", renderer)

    def test_normal_product_frames_skip_execution_diagnostics(self) -> None:
        coordinator = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator.swift"
        ).read_text(encoding="utf-8")
        lifecycle = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialSubmissionCoordinator+Lifecycle.swift"
        ).read_text(encoding="utf-8")
        executor = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor.swift"
        ).read_text(encoding="utf-8")
        preparation = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+Preparation.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "capturesExecutionDiagnostics: capturesExecutionObservations",
            coordinator,
        )
        self.assertIn("guard capturesExecutionObservations else { return }", lifecycle)
        self.assertIn("if capturesExecutionObservations {", lifecycle)
        self.assertIn("if capturesExecutionDiagnostics {", executor)
        self.assertIn("if capturesExecutionDiagnostics {", preparation)
        self.assertGreaterEqual(
            executor.count("guard capturesExecutionDiagnostics else { return }"),
            2,
        )

    def test_unique_output_owner_has_no_unowned_clear_present_bypass(self) -> None:
        renderer_files = list((SCENE / "Rendering/Frame").glob("SceneMetalRenderer*.swift"))
        source = "\n".join(path.read_text(encoding="utf-8") for path in renderer_files)
        self.assertNotIn("renderClearPass", source)
        self.assertEqual(source.count("commandBuffer.present(drawable)"), 1)


    def test_scene_clear_enabled_controls_only_initial_main_pass_load(self) -> None:
        renderer = read_source_family(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift")
        encoder = (ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneMainPassEncoder.swift").read_text(
            encoding="utf-8"
        )
        main_pass = renderer.index("let (mainPass, groups) = makeScenePass(")
        self.assertIn(
            "clearEnabled: frameDescriptor.camera.clearEnabled",
            renderer[main_pass:],
        )
        self.assertIn("private let clearEnabled: Bool", encoder)
        self.assertIn(
            "self.nextLoadAction = clearEnabled ? .clear : .load",
            encoder,
        )
        self.assertIn("nextLoadAction = .load", encoder)

    def test_runtime_model_has_no_parallel_placeholder_framework(self) -> None:
        source = (ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeModel.swift").read_text(
            encoding="utf-8"
        )
        for placeholder in (
            "ScenePlaybackController",
            "SceneRenderer",
            "SceneInputModel",
            "SceneTimelineModel",
            "SceneShaderModel",
        ):
            self.assertNotIn(placeholder, source)


if __name__ == "__main__":
    unittest.main()
