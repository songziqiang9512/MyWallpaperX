#!/usr/bin/env python3

from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RESOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources"
LAYER_LOADER = RESOURCE_ROOT / "SceneLayerEffectTextureLoader.swift"
TEXTURE_LOADING = (
    RESOURCE_ROOT / "SceneLayerEffectTextureLoader+TextureLoading.swift"
)
XRAY_LOADER = RESOURCE_ROOT / "SceneXRayEffectTextureLoader.swift"
METAL_VIEW = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift"
)
LOADER_SOURCES = [
    LAYER_LOADER,
    RESOURCE_ROOT / "SceneBlendEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneCursorRippleEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneFilmGrainEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneFoliageSwayEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneGodraysEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneLightShaftsEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneOpacityEffectTextureLoader.swift",
    RESOURCE_ROOT / "ScenePulseEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneShineEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneTintEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneWaterFlowEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneWaterRippleEffectTextureLoader.swift",
    RESOURCE_ROOT / "SceneWaterWavesEffectTextureLoader.swift",
    XRAY_LOADER,
]
EXPECTED_PURPOSES = {
    "iris mask": "preservedChannels",
    "opacity mask": "preservedChannels",
    "water mask": "preservedChannels",
    "foliage mask": "preservedChannels",
    "waterripple normal": "preservedChannels",
    "shake flow": "preservedChannels",
    "shake phase": "preservedChannels",
    "shake mask": "preservedChannels",
    "blend effect texture": "premultipliedColor",
    "cursor ripple collision mask": "preservedChannels",
    "film grain noise": "preservedChannels",
    "foliagesway effect mask": "preservedChannels",
    "foliagesway noise": "preservedChannels",
    "godrays noise": "preservedChannels",
    "godrays effect mask": "preservedChannels",
    "light shafts noise": "preservedChannels",
    "light shafts gradient": "preservedChannels",
    "opacity effect mask": "preservedChannels",
    "pulse noise": "preservedChannels",
    "pulse effect mask": "preservedChannels",
    "shine noise": "preservedChannels",
    "shine effect mask": "preservedChannels",
    "tint effect mask": "preservedChannels",
    "waterflow flow": "preservedChannels",
    "waterflow phase": "preservedChannels",
    "waterripple effect mask": "preservedChannels",
    "waterripple effect normal": "preservedChannels",
    "waterwaves mask": "preservedChannels",
    "xray blend": "preservedChannels",
    "xray halo": "preservedChannels",
    "xray opacity": "preservedChannels",
}
CALL_PATTERN = re.compile(
    r"(?:SceneLayerEffectTextureLoader\.)?loadTexture\("
    r"\s*url:.*?"
    r"\s*label:\s*\"([^\"]+)\".*?"
    r"\s*purpose:\s*\.(\w+),",
    re.DOTALL,
)


class SceneEffectTexturePurposeTests(unittest.TestCase):
    def test_every_effect_auxiliary_declares_its_channel_purpose(self) -> None:
        calls: list[tuple[str, str]] = []
        for path in LOADER_SOURCES:
            calls.extend(CALL_PATTERN.findall(path.read_text(encoding="utf-8")))
        self.assertEqual(len(calls), len(EXPECTED_PURPOSES))
        self.assertEqual(dict(calls), EXPECTED_PURPOSES)

    def test_effect_helper_has_no_default_purpose(self) -> None:
        source = TEXTURE_LOADING.read_text(encoding="utf-8")
        signature = source.split("static func loadTexture(", maxsplit=1)[1]
        signature = signature.split(") ->", maxsplit=1)[0]
        self.assertIn("purpose: SceneTextureLoadPurpose", signature)
        self.assertNotIn("purpose: SceneTextureLoadPurpose =", signature)

    def test_xray_property_inputs_use_the_preserved_texture_map(self) -> None:
        xray = XRAY_LOADER.read_text(encoding="utf-8")
        view = METAL_VIEW.read_text(encoding="utf-8")
        self.assertEqual(xray.count("preservedUserPropertyTextures[$0]"), 2)
        self.assertNotIn("userPropertyTextures[$0]", xray)
        self.assertIn("declaration.blendPropertyKey", view)
        self.assertIn("declaration.haloPropertyKey", view)
        self.assertIn(
            "preservedUserPropertyTextures: userPropertyTextureLoad.preservedTextures",
            view,
        )


if __name__ == "__main__":
    unittest.main()
