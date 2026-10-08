#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneBaseMaterialProviderBindingProgram.swift"
COMPILER_SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneBaseMaterialProviderBindingCompiler.swift"
)
LIGHTING_PROFILE_SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneBaseMaterialLightingProfile.swift"
)
VISIBILITY_SOURCE = (
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneInitialMediaEffectVisibilityProjection.swift"
)

HARNESS = (ROOT / "script/tests/fixtures/SceneBaseMaterialProviderBindingHarness.swift").read_text(
    encoding="utf-8"
)


class SceneBaseMaterialProviderBindingTests(unittest.TestCase):
    def test_current_and_previous_binding_compiler_is_shared_and_fail_closed(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        from script.tests import test_scene_static_model_material_properties as material
        with tempfile.TemporaryDirectory(prefix="mwx-media-binding-") as directory:
            root = Path(directory)
            harness = root / "main.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "binding"
            subprocess.run(
                [
                    "swiftc", *map(str, material.SOURCES), str(SOURCE), str(COMPILER_SOURCE),
                    str(LIGHTING_PROFILE_SOURCE),
                    str(VISIBILITY_SOURCE),
                    str(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyLiveUpdateState.swift"),
                    str(ROOT / "script/tests/fixtures/SceneBaseMaterialAlphaChecks.swift"),
                    str(ROOT / "script/tests/fixtures/SceneBaseMaterialUserColorChecks.swift"),
                    str(harness), "-module-cache-path", str(root / "cache"), "-o", str(binary),
                ],
                check=True,
                cwd=ROOT,
            )
            result = json.loads(subprocess.check_output([str(binary)], text=True))
        for name, passed in result["customAlpha"].items():
            with self.subTest(alpha=name):
                self.assertTrue(passed)
        for name, passed in result["instanceFallback"].items():
            with self.subTest(instance_fallback=name):
                self.assertTrue(passed)
        for name, passed in result["customUserColor"].items():
            with self.subTest(user_color=name):
                self.assertTrue(passed)
        expected = [[.5,.5],[0,.7],[],[0,1],[.8,.2],[0,.7],[.5,.5],[1,0]]
        for actual, wanted in zip(result["scalarProfiles"], expected):
            self.assertEqual(len(actual),len(wanted))
            for a,b in zip(actual,wanted): self.assertAlmostEqual(a,b,places=6)
        self.assertEqual(result["accepted"], [10, 20, 100, 110])
        self.assertEqual(result["previousAccepted"], [30])
        self.assertEqual(result["propertyAccepted"], [170, 180])
        self.assertEqual(
            result["providers"],
            {
                "10": "current",
                "20": "current",
                "30": "previous",
                "100": "current",
                "110": "current",
                "170": "user-property:customCover",
                "180": "user-property:customCover",
            },
        )
        self.assertTrue(result["hasConsumers"])
        self.assertEqual(
            result["demands"],
            ["$mediaPreviousThumbnail", "$mediaThumbnail"],
        )
        self.assertEqual(result["propertyDemands"], ["customCover"])
        self.assertEqual(
            result["rejected"],
            {
                "40": "base-material-current-slot-shape-unsupported",
                "50": "base-material-current-multi-pass-unsupported",
                "80": "base-material-current-instance-fallback-mismatch",
                "90": "base-material-current-slot-shape-unsupported",
                "120": "base-material-current-instance-fallback-mismatch",
                "130": "base-material-current-instance-fallback-mismatch",
                "140": "base-material-current-instance-fallback-mismatch",
                "150": "base-material-previous-slot-shape-unsupported",
                "160": "base-material-previous-multi-pass-unsupported",
                "190": "base-material-user-property-slot-shape-unsupported",
                "210": "base-material-user-property-slot-shape-unsupported",
                "220": "base-material-provider-identity-conflict",
            },
        )
        self.assertEqual(
            result["report"],
            [
                "authoredMaterialColorCount: 0",
                "sourceMaterialAlphaBindingCount: 0",
                "sourceMaterialAlphaPropertyBindingCount: 0",
                "mediaThumbnailCurrentBindingCount: 4",
                "mediaThumbnailCurrentBindingLayerIDs: 10,20,100,110",
                "mediaThumbnailCurrentBaseMaterialBindingCount: 4",
                "mediaThumbnailPreviousBindingCount: 1",
                "mediaThumbnailPreviousBindingLayerIDs: 30",
                "mediaThumbnailPreviousBaseMaterialBindingCount: 1",
                "mediaThumbnailCurrentBaseMaterialRejectedCount: 7",
                "mediaThumbnailPreviousBaseMaterialRejectedCount: 2",
                "baseMaterialUserPropertyBindingCount: 2",
                "baseMaterialUserPropertyBindingLayerIDs: 170,180",
                "baseMaterialUserPropertyRejectedCount: 2",
                "baseMaterialProviderOtherRejectedCount: 1",
                "mediaThumbnailBaseMaterialRejectedCount: 9",
                "baseMaterialProviderRejectedCount: 12",
                "baseMaterialUserPropertyBinding: layer=170 "
                "identity=customCover source=material-pass slot=0",
                "baseMaterialUserPropertyBinding: layer=180 "
                "identity=customCover source=layer-instance slot=0",
            ],
        )
        self.assertFalse(result["projected"]["20"])
        self.assertFalse(result["projected"]["30"])
        self.assertFalse(result["projected"]["40"])
        self.assertTrue(result["projected"]["50"])

        # D3 first slice: authored material lighting profile gate. The same
        # compiled harness payload carries the lighting profile keys.
        self.assertEqual(result["authoredMaterialLighting"], [True, True, False, False, True])
        self.assertEqual(result["authoredNormals"], ["maps/authored.png", "absent",
            "maps/authored.png", "maps/override.png", "absent", "absent",
            "maps/authored.png", "absent", "absent", "absent"])
        self.assertEqual(result["normalAdmission"], [True] * 4)
        profiles = result["lightingProfiles"]
        # Authored LIGHTING combo == 1 with no authored shader pass enables
        # the built-in lit base capture.
        self.assertEqual(profiles["300"], [1, 0])
        # Missing combo never enables lighting.
        self.assertEqual(profiles["301"], [0, 0])
        # An authored shader pass keeps the material on the existing shader
        # frontend; the built-in lighting is never stacked on top.
        self.assertEqual(profiles["302"], [0, 0])
        # A registry-matched normal slot alone does not enable lighting.
        self.assertEqual(profiles["303"], [0, 0])
        # A tiered combo value (> 1) is deliberately rejected: unlike the
        # static-model `!= 0` precedent, the profile compiler fails closed.
        self.assertEqual(profiles["304"], [0, 0])
        # Enabled + normal slot keeps both facts on one profile.
        self.assertEqual(profiles["305"], [1, 1])
        # Non image-renderable layers never receive a profile.
        self.assertNotIn("306", profiles)
        self.assertEqual(
            result["lightingProfileNormalSlotPaths"]["303"],
            "",
        )
        self.assertTrue(result["lightingProfilesMatchDirectCompiler"])



if __name__ == "__main__":
    unittest.main()
