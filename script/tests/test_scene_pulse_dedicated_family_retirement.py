from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


class ScenePulseDedicatedFamilyRetirementTests(unittest.TestCase):
    def test_product_has_no_pulse_dedicated_execution_family(self) -> None:
        retired = [
            SCENE / "Effects/ScenePulsePipeline.swift",
            SCENE / "RenderGraph/SceneAuthoredPulsePlanner.swift",
            SCENE / "RenderGraph/SceneAuthoredPulsePlanner+Constants.swift",
            SCENE / "RenderGraph/ScenePulseExecutionPlan.swift",
            SCENE / "RenderGraph/ScenePulseShaderProfile.swift",
            SCENE
            / "RenderGraph/EffectCompilation/SceneEffectStagePulseDirectPropertyOwnerAdmission.swift",
            SCENE
            / "RenderGraph/EffectExecution/SceneEffectStageRenderer+Pulse.swift",
            SCENE / "Resources/ScenePulseEffectTextureLoader.swift",
        ]
        self.assertTrue(all(not path.exists() for path in retired))

        product = "\n".join(
            path.read_text(encoding="utf-8")
            for path in SCENE.rglob("*.swift")
        )
        for symbol in (
            "ScenePulseExecutionPlan",
            "ScenePulseShaderProfile",
            "ScenePulsePipeline",
            "ScenePulseEffectTextures",
            "ScenePulseEffectTextureLoader",
            "case pulse(",
            "case .pulse",
            "func pulse()",
            "pulseEffects",
        ):
            self.assertNotIn(symbol, product)

    def test_shared_program_and_fail_soft_contract_remain(self) -> None:
        capability = (
            SCENE
            / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability.swift"
        ).read_text(encoding="utf-8")
        masks = (
            SCENE / "Rendering/SceneImageLayerDrawRequest.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("$0.variants.hasAudioSpectrumConsumer", capability)
        self.assertIn('"effects/pulse/effect.json"', masks)
        self.assertIn("pulsePreservesSourceCoverage", masks)
        self.assertNotIn("ScenePulseEffectTextures", masks)


if __name__ == "__main__":
    unittest.main()
