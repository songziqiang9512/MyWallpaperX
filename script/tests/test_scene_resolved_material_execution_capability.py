from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
EXECUTION = SCENE / "RenderGraph/EffectExecution"


class SceneResolvedMaterialExecutionCapabilityTests(unittest.TestCase):
    def test_capability_catalog_has_one_program_first_execution_route(self) -> None:
        capability = (
            EXECUTION / "SceneResolvedMaterialExecutionCapability.swift"
        ).read_text(encoding="utf-8")
        stages = (
            EXECUTION
            / "SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
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
            EXECUTION
            / "SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
        ).read_text(encoding="utf-8")
        executor = (
            EXECUTION
            / "SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
        ).read_text(encoding="utf-8")

        failure = stages.index("case let .failure(programFailure):")
        tail = stages[failure:failure + 2500]
        self.assertIn("visualFailurePassthrough", tail)
        self.assertIn("return .failure(programFailure)", tail)
        self.assertIn("prepareVisualFailurePassthrough", executor)
        self.assertIn("snapshot", executor)

    def test_unknown_execution_family_cannot_create_dedicated_owner(self) -> None:
        admission = (
            SCENE
            / "RenderGraph/EffectCompilation/SceneEffectStageAdmission.swift"
        ).read_text(encoding="utf-8")
        disposition = (
            SCENE / "Runtime/SceneEffectRuntimeDispositionCatalog.swift"
        ).read_text(encoding="utf-8")
        reporting = (
            SCENE
            / "RenderGraph/EffectCompilation/SceneEffectAdmissionCatalog+Reporting.swift"
        ).read_text(encoding="utf-8")

        self.assertNotIn("admissionKind = .admittedDedicated", admission)
        self.assertIn("unrecognized-unified-execution-family", admission)
        self.assertNotIn("kind: .dedicated", disposition)
        self.assertNotIn(
            "case .admittedDedicated, .admittedFallback",
            reporting,
        )


if __name__ == "__main__":
    unittest.main()
