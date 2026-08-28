from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


class SceneXRayDedicatedFamilyRetirementTests(unittest.TestCase):
    def test_product_has_no_xray_dedicated_execution_family(self) -> None:
        retired = [
            SCENE / "Effects/SceneXRayPipeline.swift",
            SCENE / "Effects/SceneXRayRuntimePlan.swift",
            SCENE / "RenderGraph/SceneAuthoredXRayPlanner.swift",
            SCENE
            / "RenderGraph/EffectCompilation/SceneEffectStageXRayScalarOwnerAdmission.swift",
            SCENE
            / "RenderGraph/EffectExecution/SceneEffectStageRenderer+XRay.swift",
            SCENE / "Resources/SceneXRayEffectTextureLoader.swift",
        ]
        self.assertTrue(all(not path.exists() for path in retired))

        product = "\n".join(
            path.read_text(encoding="utf-8")
            for path in SCENE.rglob("*.swift")
        )
        for symbol in (
            "SceneXRayExecutionPlan",
            "SceneXRayRuntimePlan",
            "SceneXRayRuntimePlanner",
            "SceneXRayPipeline",
            "SceneXRayEffectTextures",
            "SceneXRayEffectTextureLoader",
            "case xRay(",
            "case .xRay",
            "func xRay()",
        ):
            self.assertNotIn(symbol, product)

    def test_shared_program_and_provider_contract_remain(self) -> None:
        compiler = (
            SCENE
            / "RenderGraph/EffectCompilation/SceneEffectProgramCompiler+DedicatedStages.swift"
        ).read_text(encoding="utf-8")
        backend = (
            SCENE / "RenderGraph/EffectCompilation/SceneEffectStageCompileModel.swift"
        ).read_text(encoding="utf-8")
        launch = (
            SCENE / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
        ).read_text(encoding="utf-8")
        identity = (
            SCENE / "RenderGraph/SceneAuthoredXRayPlanner+StockIdentity.swift"
        ).read_text(encoding="utf-8")

        self.assertNotIn("(.xRay,", compiler)
        self.assertNotIn('case xRay = "x-ray"', backend)
        self.assertIn("SceneResolvedMaterialExecutionCapabilityAdmission.compile(", launch)
        self.assertIn("SceneXRayStockIdentityVerifier.verifiedStockIdentityEffectKeys(", launch)
        self.assertIn("nonisolated enum SceneXRayStockIdentityVerifier", identity)
        self.assertNotIn("func plan(", identity)

    def test_user_textures_are_requested_by_typed_material_identity(self) -> None:
        view = (SCENE / "Rendering/SceneMetalView.swift").read_text(encoding="utf-8")
        loader = (
            SCENE / "Properties/SceneUserPropertyTextureLoader.swift"
        ).read_text(encoding="utf-8")
        layer_loader = (
            SCENE / "Resources/SceneLayerEffectTextureLoader.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("resolvedMaterialRuntime.userPropertyDemands", view)
        self.assertNotIn("SceneXRayRuntimePlanner", view)
        self.assertIn("requestedIdentities.compactMap", loader)
        self.assertNotIn("straightAlbedoPropertyKeys:", loader)
        self.assertNotIn("SceneXRayEffectTextureLoader", layer_loader)


if __name__ == "__main__":
    unittest.main()
