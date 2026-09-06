#!/usr/bin/env python3

"""Keep diagnostic and static graph work out of normal Scene frames."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


class SceneRealtimePathPolicyTests(unittest.TestCase):
    def test_static_graph_work_is_reused_for_stable_generations(self) -> None:
        state = (
            SCENE
            / "RenderGraph/GraphTargets/SceneGraphExecutionState.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("let reusesStaticPlan = !reparsed && !allocationChanged", state)
        self.assertIn("operations = cachedOperations", state)
        self.assertIn("historyClosure = previous.historyClosureIdentities", state)

    def test_resolved_material_preflight_reuses_launch_topology(self) -> None:
        renderer = (SCENE / "Rendering/SceneMetalRenderer.swift").read_text(
            encoding="utf-8"
        )
        initialization = (
            SCENE / "Rendering/SceneMetalRenderer+Initialization.swift"
        ).read_text(encoding="utf-8")
        preflight = (
            SCENE / "Rendering/SceneResolvedMaterialFramePreflight.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("resolvedMaterialPreparationLayerIDs: [Int]?", renderer)
        self.assertIn("resolvedMaterialPreparationLayers:", renderer)
        self.assertIn(".resolvedMaterialPreparationOrder(", initialization)
        self.assertIn("authoredLayerIDs: renderDescriptor.renderOrderLayerIDs", initialization)
        self.assertIn(
            "if let layerTopology,\n           !layerTopology.dynamicLayers.isEmpty",
            renderer,
        )
        self.assertIn(
            "layerTopology.renderOrderLayerIDs\n                    != renderDescriptor.renderOrderLayerIDs",
            renderer,
        )
        self.assertIn(
            "var baseMaterialSelections: [Int: SceneBaseMaterialTextureSelection] = [:]",
            preflight,
        )
        self.assertGreaterEqual(
            preflight.count("cachedBaseMaterialTextureSelection("), 3
        )
        self.assertIn(
            "cache: &baseMaterialSelections",
            preflight,
        )
        self.assertEqual(
            preflight.count("resolvedMaterialPreparationLayerIDs else"), 1
        )
        self.assertIn("resolvedMaterialPreparationLayers else", preflight)
        self.assertGreaterEqual(
            preflight.count("materialFunctionMutationsByLayerID"), 2
        )
        # The cache is intentionally topology-only. Per-frame visibility,
        # provider/source readiness, and logical extent remain in preflight.
        self.assertIn("frameVisibleRootLayerIDs", preflight)
        self.assertIn("baseMaterialTextureSelection(", preflight)
        self.assertIn("SceneLayerEffectSourceExtent.resolve(", preflight)

    def test_full_graph_observations_are_explicitly_opt_in(self) -> None:
        completion = (
            SCENE
            / "Runtime/ResolvedMaterialExecution/"
            "SceneResolvedMaterialSubmissionCoordinator+Completion.swift"
        ).read_text(encoding="utf-8")
        guard = completion.index("guard capturesExecutionObservations else")
        builder = completion.index("SceneResolvedMaterialGraphObservationBuilder.make")
        self.assertLess(guard, builder)

    def test_product_launch_only_enables_observations_for_debug_evidence(self) -> None:
        launch = (
            SCENE / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text(encoding="utf-8")
        self.assertGreaterEqual(
            launch.count(
                "capturesExecutionObservations: Self.usesDebugEvidenceWindow"
            ),
            2,
        )

    def test_dynamic_frame_schema_is_prepared_at_launch(self) -> None:
        launch = (
            SCENE / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text(encoding="utf-8")
        frame_driver = (
            SCENE / "Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
        ).read_text(encoding="utf-8")
        frame_schema = (
            SCENE / "Runtime/SceneDesktopWallpaperLaunchFrameSchema.swift"
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
        renderer = (
            SCENE / "Rendering/SceneMetalRenderer.swift"
        ).read_text(encoding="utf-8")
        topology = (
            SCENE
            / "Runtime/SceneScript/SceneScriptDynamicLayerRuntime.swift"
        ).read_text(encoding="utf-8")
        cache = (
            SCENE / "Rendering/SceneDynamicLayerRenderTopologyCache.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("let dynamicLayerTopologyCache", renderer)
        self.assertIn("dynamicLayerTopologyCache.resolve(", renderer)
        self.assertNotIn(
            "frameDescriptor = renderDescriptor.applying(layerTopology)",
            renderer,
        )
        self.assertIn("let topologyRevision: UInt64", topology)
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
        self.assertIn("let frameOrderedLayers: [SceneRenderDescriptor.Layer]", renderer)
        self.assertIn("frameOrderedLayers = projection.orderedLayers", renderer)
        self.assertIn("frameOrderedLayers = authoredLayers", renderer)
        self.assertNotIn(
            "let orderedLayers = authoredLayerIDs.compactMap",
            renderer,
        )

    def test_system_provider_demand_order_is_prepared(self) -> None:
        bindings = (
            SCENE / "Runtime/SceneBaseMaterialProviderBindingProgram.swift"
        ).read_text(encoding="utf-8")
        texture_frame = (
            SCENE / "Rendering/SceneMetalRenderer+TextureFrame.swift"
        ).read_text(encoding="utf-8")
        bridge = (
            SCENE / "Runtime/ResolvedMaterialExecution/"
            "SceneResolvedMaterialRuntimeBridge.swift"
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

    def test_frame_visibility_reuses_prepared_layer_index(self) -> None:
        visibility = (
            SCENE / "Rendering/SceneLayerVisibility.swift"
        ).read_text(encoding="utf-8")
        renderer = (
            SCENE / "Rendering/SceneMetalRenderer.swift"
        ).read_text(encoding="utf-8")
        preflight = (
            SCENE / "Rendering/SceneResolvedMaterialFramePreflight.swift"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "layersByID: [Int: SceneRenderDescriptor.Layer]",
            visibility,
        )
        self.assertIn("layersByID: frameLayersByID", renderer)
        self.assertIn("layersByID: layersByID", preflight)
        self.assertIn("frameDynamicLayerIDs = projection.dynamicLayerIDs", renderer)
        self.assertIn("frameLightLayerIDs = projection.lightLayerIDs", renderer)

    def test_normal_product_frames_skip_execution_diagnostics(self) -> None:
        coordinator = (
            SCENE
            / "Runtime/ResolvedMaterialExecution/"
            "SceneResolvedMaterialSubmissionCoordinator.swift"
        ).read_text(encoding="utf-8")
        lifecycle = (
            SCENE
            / "Runtime/ResolvedMaterialExecution/"
            "SceneResolvedMaterialSubmissionCoordinator+Lifecycle.swift"
        ).read_text(encoding="utf-8")
        executor = (
            SCENE
            / "RenderGraph/EffectExecution/"
            "SceneResolvedMaterialGraphExecutor.swift"
        ).read_text(encoding="utf-8")
        preparation = (
            SCENE
            / "RenderGraph/EffectExecution/"
            "SceneResolvedMaterialGraphExecutor+Preparation.swift"
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

    def test_top_level_contract_forbids_diagnostic_hot_path_work(self) -> None:
        agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        architecture = (
            ROOT / "docs/scene/runtime-architecture.md"
        ).read_text(encoding="utf-8")
        self.assertIn("目标主链只有一条", agents)
        self.assertIn("普通帧不得重新解析、编译、建图", agents)
        self.assertIn("任何逐帧 JSON 编码", architecture)

    def test_unique_output_owner_has_no_unowned_clear_present_bypass(self) -> None:
        renderer_files = list((SCENE / "Rendering").glob("SceneMetalRenderer*.swift"))
        source = "\n".join(path.read_text(encoding="utf-8") for path in renderer_files)
        self.assertNotIn("renderClearPass", source)
        self.assertEqual(source.count("commandBuffer.present(drawable)"), 1)

    def test_frame_submission_outcome_controls_dynamic_plan_commit(self) -> None:
        renderer = (SCENE / "Rendering/SceneMetalRenderer.swift").read_text(
            encoding="utf-8"
        )
        outcome = (
            SCENE / "Rendering/SceneMetalRenderer+FrameOutcome.swift"
        ).read_text(encoding="utf-8")
        view = (SCENE / "Rendering/SceneMetalView.swift").read_text(
            encoding="utf-8"
        )
        preflight = (
            SCENE / "Rendering/SceneResolvedMaterialFramePreflight.swift"
        ).read_text(encoding="utf-8")
        driver = (
            SCENE
            / "Runtime/SceneDesktopWallpaperHost+FrameDriver.swift"
        ).read_text(encoding="utf-8")
        lifecycle = (
            SCENE
            / "Runtime/SceneDesktopWallpaperHost+FrameDriverLifecycle.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("enum FrameOutcome: Equatable", outcome)
        self.assertIn("case submitted", outcome)
        self.assertIn("case deferred(reasonCode: String)", outcome)
        self.assertIn("case dropped(reasonCode: String)", outcome)
        self.assertIn(") -> FrameOutcome", renderer)
        self.assertEqual(renderer.count("commandBuffer.commit()"), 1)
        self.assertNotIn("finishUnsubmittedCommandBuffer", renderer)
        self.assertIn("return .submitted", renderer)
        self.assertIn(") -> SceneMetalRenderer.FrameOutcome", view)
        self.assertIn("let outcome = renderer.renderFrame(", view)
        self.assertIn("if outcome.isSubmitted {", view)
        self.assertIn("$0.commitPreparedFrame()", view)
        self.assertIn("$0.discardPreparedFrame()", view)
        self.assertIn("return outcome", view)
        self.assertIn(
            ") -> SceneMetalRenderer.ResolvedMaterialFrameAdmission",
            preflight,
        )
        self.assertIn("var frameOutcomes: [SceneMetalRenderer.FrameOutcome]", driver)
        self.assertIn("frameOutcomes.allSatisfy(\\.isSubmitted)", driver)
        self.assertIn("case .dropped:", driver)
        submission_guard = driver.index("let allSurfacesSubmitted")
        commit_call = driver.index("commitSubmittedSceneFrame(", submission_guard)
        helper_start = lifecycle.index("func commitSceneScriptLayerPlan(")
        plan_commit = lifecycle.index(
            "context.sceneScriptDynamicLayerRuntime.commit(plan)", helper_start
        )
        self.assertGreater(commit_call, submission_guard)
        self.assertGreater(plan_commit, helper_start)

    def test_scene_clear_enabled_controls_only_initial_main_pass_load(self) -> None:
        renderer = (SCENE / "Rendering/SceneMetalRenderer.swift").read_text(
            encoding="utf-8"
        )
        encoder = (SCENE / "Rendering/SceneMainPassEncoder.swift").read_text(
            encoding="utf-8"
        )
        main_pass = renderer.index("let mainPass = SceneMainPassEncoder(")
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
        source = (SCENE / "Runtime/SceneRuntimeModel.swift").read_text(
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
