#!/usr/bin/env python3

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


class SceneDirectDrawContractTests(unittest.TestCase):
    def test_shared_direct_draw_entry_has_no_retired_owner_parameters(self) -> None:
        source = (
            SCENE_ROOT / "Rendering/SceneMetalRenderer+DirectDraw.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("guard let resolvedFramePlan else { return true }", source)
        self.assertIn("drawResolvedDirectDrawQuad(", source)
        self.assertIn("directDrawModelMatrix(", source)
        self.assertNotIn("SceneLightShaftsPipeline", source)
        self.assertNotIn("SceneLayerEffectTextureStore", source)
        self.assertNotIn("makeLightShaftsPipeline", source)

    def test_renderer_routes_quad_only_through_resolved_frame_plan(self) -> None:
        source = (
            SCENE_ROOT / "Rendering/SceneMetalRenderer.swift"
        ).read_text(encoding="utf-8")
        call = source[source.index("if !drawQuadLayer(") :]
        self.assertIn("resolvedFramePlan: resolvedMaterialFrameTargetPlans[layer.id]", call)
        self.assertNotIn("makeLightShaftsPipeline", call)

    def test_geometry_is_neutral_direct_draw_owner(self) -> None:
        geometry = (
            SCENE_ROOT / "Rendering/SceneDirectDrawQuadGeometry.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("enum SceneDirectDrawQuadGeometry", geometry)
        self.assertNotIn("SceneLightShaftsQuadGeometry", geometry)


if __name__ == "__main__":
    unittest.main()
