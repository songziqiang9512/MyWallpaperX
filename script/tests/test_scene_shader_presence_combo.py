#!/usr/bin/env python3

"""Admission contract: authored presence-combo textures cannot select the
unmasked program.

Stock Water Waves / Flow compile `mask = 1.0` when MASK/TIMEOFFSET is off.
If the author bound a slot-1 mask, that combo is required on; unreadiness
fails the effect locally instead of warping the whole image.
"""

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
WATERWAVES_FRAG = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects"
    / "waterwaves/shaders/effects/waterwaves.frag"
)
EFFECTS_REFERENCE = (
    REPOSITORY_ROOT / "docs/scene/semantics/effects-reference.md"
)


class AuthoredPresenceComboAdmissionTests(unittest.TestCase):
    def test_unmasked_water_waves_is_full_image(self) -> None:
        source = WATERWAVES_FRAG.read_text(encoding="utf-8")
        self.assertIn("#if MASK", source)
        self.assertIn("float mask = texSample2D(g_Texture1, v_TexCoord.zw).r;", source)
        self.assertIn("#else", source)
        self.assertIn("float mask = 1.0;", source)

    def test_effects_reference_requires_author_mask(self) -> None:
        text = EFFECTS_REFERENCE.read_text(encoding="utf-8")
        self.assertIn("仅在作者 mask 内变形", text)
        self.assertIn("作者绑定 mask 后不得再编译整图变形", text)

    def test_reachability_requires_authored_presence_combo(self) -> None:
        reachability = (
            SCENE_ROOT
            / "RenderGraph/MaterialProgram"
            / "SceneResolvedMaterialShaderSchema+Reachability.swift"
        ).read_text(encoding="utf-8")
        launch = (
            SCENE_ROOT
            / "RenderGraph/MaterialProgram"
            / "SceneResolvedMaterialTextureResolver+Launch.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("nonisolated static func readinessComboSlotMask(", reachability)
        self.assertIn("if required & bit == 0, hasOptionalSource { optional |= bit }", reachability)
        self.assertIn("case .selected:", launch)
        self.assertIn("sampler?.readinessCombo != nil", launch)
        self.assertIn("both combo-off and combo-on", launch)


if __name__ == "__main__":
    unittest.main()
