from script.tests.source_family import read_source_family
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
        self.assertIn("snapshot", executor)

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
        ).read_text(encoding="utf-8") + (
            SCENE / "Runtime/Frame/SceneResolvedMaterialExecutionCapabilityCatalog.swift"
        ).read_text(encoding="utf-8")
        stages = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapability+Stages.swift"
        ).read_text(encoding="utf-8")
        compiled = (
            ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialCompiledVariant.swift"
        ).read_text(encoding="utf-8")
        compilation = read_source_family(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift")
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

        frame_contract = (
            SCENE / "Runtime/Frame/SceneResolvedMaterialPreparedFrameInput.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("SceneResolvedMaterialFrameInputContract", capability)
        self.assertIn("case emittedOutputGeometry", frame_contract)
        for geometry_source in (
            "case layerCard",
            "case captureGeometry",
            "case authoredCanvasDirectDraw",
        ):
            self.assertIn(geometry_source, frame_contract)
        self.assertIn("let frameInputContract: FrameInputContract", capability)
        self.assertIn(
            "let resolvedIntegerCombos: [String: Int]",
            compiled,
        )
        self.assertIn(
            "resolvedIntegerCombos: resolvedIntegerCombos",
            compilation,
        )
        self.assertNotIn(
            "extension SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability",
            stages,
        )
        self.assertIn("frameInputContract: capability.frameInputContract", bridge)
        self.assertIn(
            "claim.frameInputContract.effectTextureProjectionSource",
            preflight,
        )
        self.assertEqual(preflight.count("directDrawOutputModelMatrix("), 1)
        # The direct-draw output MVP flows straight from the sizing pass into
        # the preparation request; the plan round-trip read is gone.
        self.assertIn(
            "guard let directDrawOutputMVP =",
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
