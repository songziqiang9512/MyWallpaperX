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
LOADER_SOURCES = sorted(RESOURCE_ROOT.glob("*EffectTextureLoader*.swift"))
EXPECTED_PURPOSES = {
    "iris mask": "mask",
    "opacity mask": "mask",
    "water mask": "mask",
    "foliage mask": "mask",
    "waterripple normal": "normal",
    "shake flow": "flow",
    "shake phase": "phase",
    "shake mask": "mask",
    "blend effect texture": "premultipliedColor",
    "cursor ripple collision mask": "mask",
    "film grain noise": "noise",
    "foliagesway effect mask": "mask",
    "foliagesway noise": "noise",
    "godrays noise": "noise",
    "godrays effect mask": "mask",
    "light shafts noise": "noise",
    "light shafts gradient": "preservedChannels",
    "opacity effect mask": "mask",
    "pulse noise": "noise",
    "pulse effect mask": "mask",
    "shine noise": "noise",
    "shine effect mask": "mask",
    "standard blur mask": "mask",
    "tint effect mask": "mask",
    "waterflow flow": "flow",
    "waterflow phase": "phase",
    "waterripple effect mask": "mask",
    "waterripple effect normal": "normal",
    "waterwaves mask": "mask",
    "xray blend": "preservedChannels",
    "xray halo": "preservedChannels",
    "xray opacity": "mask",
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
