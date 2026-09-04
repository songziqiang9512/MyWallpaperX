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
        preflight = (
            SCENE / "Rendering/SceneResolvedMaterialFramePreflight.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("resolvedMaterialPreparationLayerIDs: [Int]?", renderer)
        self.assertIn(
            "resolvedMaterialPreparationOrder(\n                authoredLayerIDs:",
            renderer,
        )
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
        self.assertGreaterEqual(
            preflight.count("resolvedMaterialPreparationLayerIDs else"), 2
        )
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
        self.assertIn("private let dynamicLayerTopologyCache", renderer)
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
        self.assertIn("一条最短产品播放链", agents)
        self.assertIn("正常帧不得重新解析、编译、建图", agents)
        self.assertIn("任何逐帧 JSON 编码", architecture)

    def test_unique_output_owner_has_no_unowned_clear_present_bypass(self) -> None:
        renderer_files = list((SCENE / "Rendering").glob("SceneMetalRenderer*.swift"))
        source = "\n".join(path.read_text(encoding="utf-8") for path in renderer_files)
        self.assertNotIn("renderClearPass", source)
        self.assertEqual(source.count("commandBuffer.present(drawable)"), 1)

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
