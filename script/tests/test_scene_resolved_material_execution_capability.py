from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
EXECUTION = SCENE / "RenderGraph/EffectExecution"
MATERIAL = SCENE / "RenderGraph/MaterialProgram"
RUNTIME = SCENE / "Runtime/ResolvedMaterialExecution"
RENDERING = SCENE / "Rendering"


class SceneResolvedMaterialExecutionCapabilityTests(unittest.TestCase):
    def test_capability_catalog_has_one_program_first_execution_route(self) -> None:
        capability = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift"
        ).read_text(encoding="utf-8")
        stages = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("Self.compileProgramFirstStages(", capability)
        self.assertIn("let programResult = compileStages(", stages)
        self.assertIn("case let .failure(programFailure):", stages)
        self.assertNotIn("StageCapability.dedicated", capability)
        self.assertNotIn("case dedicated", capability)
        for retired in (
            "dedicatedStagePrograms",
            "dedicatedStageFamilies",
            "dedicatedLeafKeys",
            "dedicatedGraphStageKeys",
            "SceneEffectStageProgram",
            "SceneEffectStageExecutionPlan",
        ):
            self.assertNotIn(retired, capability)
            self.assertNotIn(retired, stages)

    def test_program_failure_is_bounded_to_safe_previous_current(self) -> None:
        stages = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
        ).read_text(encoding="utf-8")
        executor = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
        ).read_text(encoding="utf-8")

        failure = stages.index("case let .failure(programFailure):")
        tail = stages[failure:failure + 2500]
        self.assertIn("visualFailurePassthrough", tail)
        self.assertIn("return .failure(programFailure)", tail)
        self.assertIn("prepareVisualFailurePassthrough", executor)
        self.assertIn("snapshot", executor)

    def test_aggregate_catalog_reuse_exports_each_authored_reference_slot(self) -> None:
        source = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift"
        ).read_text(encoding="utf-8")
        start = source.index(
            "var admittedResolvedMaterialReferences:"
        )
        end = source.index("\n    var sceneBackgroundLayerIDs", start)
        export = source[start:end]

        # A later generation receives this set before dependency-plan
        # compilation. Aggregate ownership therefore has to retain the full
        # consumer/provider/slot vector; reducing it to provider IDs would
        # silently lose multi-pass slots and make aggregate reuse impossible.
        self.assertIn("case let .externalAggregate(aggregate):", export)
        self.assertIn("for binding in aggregate.orderedBindings", export)
        self.assertIn("consumerLayerID: binding.consumerLayerID", export)
        self.assertIn("providerLayerID: binding.providerLayerID", export)
        self.assertIn("slot: binding.slot", export)
        self.assertIn("variant: .primary", export)
        self.assertNotIn("aggregate.providerLayerIDs", export)

    def test_unknown_execution_family_cannot_create_dedicated_owner(self) -> None:
        admission = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectStageAdmission.swift"
        ).read_text(encoding="utf-8")
        disposition = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectRuntimeDispositionCatalog.swift"
        ).read_text(encoding="utf-8")
        reporting = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectAdmissionCatalog+Reporting.swift"
        ).read_text(encoding="utf-8")

        self.assertNotIn("admissionKind = .admittedDedicated", admission)
        self.assertIn("unrecognized-unified-execution-family", admission)
        self.assertNotIn("kind: .dedicated", disposition)
        self.assertNotIn(
            "case .admittedDedicated, .admittedFallback",
            reporting,
        )

    def test_uniform_and_geometry_sources_are_prepared_before_frames(self) -> None:
        capability = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability.swift"
        ).read_text(encoding="utf-8")
        stages = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+Stages.swift"
        ).read_text(encoding="utf-8")
        compiled = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialCompiledVariant.swift"
        ).read_text(encoding="utf-8")
        compilation = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift"
        ).read_text(encoding="utf-8")
        finalizer = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialProgramFinalizer.swift"
        ).read_text(encoding="utf-8")
        bridge = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialRuntimeBridge.swift"
        ).read_text(encoding="utf-8")
        preflight = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneResolvedMaterialFramePreflight.swift"
        ).read_text(encoding="utf-8")
        composition = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneResolvedMaterialGraphComposition.swift"
        ).read_text(encoding="utf-8")
        direct_draw = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneDirectDrawLayerRenderer.swift"
        ).read_text(encoding="utf-8")
        geometry_compiler = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialDirectDrawGeometryCompiler.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("struct FrameInputContract: Equatable", capability)
        self.assertIn("case emittedOutputGeometry", capability)
        for geometry_source in (
            "case layerCard",
            "case captureGeometry",
            "case authoredCanvasDirectDraw",
        ):
            self.assertIn(geometry_source, capability)
        self.assertIn("let frameInputContract: FrameInputContract", capability)
        self.assertIn("stages.contains(", capability)
        self.assertIn(
            "SceneResolvedMaterialDirectDrawGeometryCompiler.compile(",
            capability,
        )
        self.assertIn("schema=prepared-direct-draw-geometry-v1", capability)
        self.assertIn("declarations.count == 1", geometry_compiler)
        self.assertIn("case let .staticExact(value)", geometry_compiler)
        self.assertIn(
            "let resolvedIntegerCombos: [String: Int]",
            compiled,
        )
        self.assertIn(
            "resolvedIntegerCombos: resolvedIntegerCombos",
            compilation,
        )
        for forbidden_dispatch in (
            "layerID ==",
            "sampleID",
            "shaderPath ==",
            "canonicalSHA256 ==",
        ):
            self.assertNotIn(forbidden_dispatch, geometry_compiler)
        self.assertNotIn(
            "extension SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability",
            stages,
        )
        self.assertIn(
            "struct SceneResolvedMaterialPreparedUniformBinding: Hashable",
            compiled,
        )
        for route in (
            "case host(Program.HostUniform)",
            "case staticValue(Data)",
            "case dynamic(Dynamic)",
            "case neutralMissingTextureResolution(",
            "case selfCompositeTextureResolution(",
        ):
            self.assertIn(route, compiled)
        self.assertIn(".prepareUniformBindings(", compilation)
        resolved_start = finalizer.index("private static func resolvedUniforms(")
        resolved_end = finalizer.index(
            "/// A same-layer composite slot may exist", resolved_start
        )
        resolved = finalizer[resolved_start:resolved_end]
        self.assertIn("variant.preparedUniformBindings.map", resolved)
        self.assertIn("switch binding.source", resolved)
        self.assertNotIn("template.uniformDeclarations.filter", resolved)
        self.assertNotIn("hostUniform(\n                field", resolved)
        self.assertIn("frameInputContract: capability.frameInputContract", bridge)
        self.assertIn(
            "claim.frameInputContract.effectTextureProjectionSource",
            preflight,
        )
        self.assertEqual(preflight.count("directDrawOutputModelMatrix("), 1)
        self.assertIn(
            "plan.directDrawOutputModelViewProjection",
            preflight,
        )
        self.assertIn(
            "framePlan.directDrawOutputModelViewProjection",
            composition,
        )
        self.assertNotIn("directDrawOutputModelMatrix(", direct_draw)
        self.assertNotIn("lightShafts", preflight)
        self.assertNotIn("lightShafts", composition)


if __name__ == "__main__":
    unittest.main()
