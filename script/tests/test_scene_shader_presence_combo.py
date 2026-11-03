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
WATERWAVES_FRAG = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/effects"
    / "waterwaves/shaders/effects/waterwaves.frag"
)


class AuthoredPresenceComboAdmissionTests(unittest.TestCase):
    def test_unmasked_water_waves_is_full_image(self) -> None:
        source = WATERWAVES_FRAG.read_text(encoding="utf-8")
        self.assertIn("#if MASK", source)
        self.assertIn("float mask = texSample2D(g_Texture1, v_TexCoord.zw).r;", source)
        self.assertIn("#else", source)
        self.assertIn("float mask = 1.0;", source)



if __name__ == "__main__":
    unittest.main()
