from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


class SceneStandardBlurDedicatedFamilyRetirementTests(unittest.TestCase):
    def test_product_has_no_standard_blur_or_generic_dedicated_runtime(self) -> None:
        retired = [
            SCENE / "Effects/SceneStandardBlurPipeline.swift",
            SCENE / "Effects/SceneStandardBlurRenderer.swift",
            SCENE / "RenderGraph/SceneAuthoredStandardBlurPlanner.swift",
            SCENE / "Resources/SceneStandardBlurEffectTextureLoader.swift",
            SCENE / "Resources/SceneLayerEffectTextureStore.swift",
            SCENE / "RenderGraph/EffectCompilation/SceneEffectStageCompiler.swift",
            SCENE / "RenderGraph/EffectCompilation/SceneEffectStageProgram.swift",
            SCENE / "RenderGraph/EffectExecution/SceneEffectStageRenderer.swift",
            SCENE
            / "RenderGraph/EffectExecution/SceneAuthoredEffectPipelineSet.swift",
        ]
        self.assertTrue(all(not path.exists() for path in retired))

        product = "\n".join(
            path.read_text(encoding="utf-8")
            for path in SCENE.rglob("*.swift")
        )
        for symbol in (
            "SceneStandardBlurPlan",
            "SceneStandardBlurPipeline",
            "SceneStandardBlurRenderer",
            "SceneStandardBlurEffectTextures",
            "SceneStandardBlurEffectTextureLoader",
            "SceneEffectStageExecutionPlan",
            "SceneEffectStageProgram",
            "SceneEffectStageRenderer",
            "DedicatedFrameInputs",
            "dedicatedStagePrograms",
            "case standardBlur(",
            "case .standardBlur",
            "func standardBlur()",
            "standardBlurEffects",
        ):
            self.assertNotIn(symbol, product)

    def test_shared_program_executor_and_mask_safety_remain(self) -> None:
        route = (
            SCENE
            / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift"
        ).read_text(encoding="utf-8")
        executor = (
            SCENE
            / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor.swift"
        ).read_text(encoding="utf-8")
        bridge = (
            SCENE
            / "Runtime/ResolvedMaterialExecution/SceneResolvedMaterialRuntimeBridge.swift"
        ).read_text(encoding="utf-8")
        masks = (
            SCENE / "Rendering/SceneImageLayerDrawRequest.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("source-proven-unit-previous-blurred-composite", route)
        self.assertIn("SceneResolvedMaterialPassEncoder", executor)
        self.assertIn("struct FrameInputs", bridge)
        self.assertNotIn("DedicatedFrameInputs", bridge)
        self.assertIn("standardBlurHasAuthoredMask", masks)
        self.assertNotIn("SceneStandardBlurEffectTextures", masks)


if __name__ == "__main__":
    unittest.main()
