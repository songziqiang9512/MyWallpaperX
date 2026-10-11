#!/usr/bin/env python3

from __future__ import annotations

import unittest

from script.tests.scene_particle_render_test_support import run_particle_harness
from script.tests.test_scene_particle_rendering import HARNESS_SOURCE, SWIFT_SOURCES


class SceneParticleCameraRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.result = run_particle_harness(tuple(SWIFT_SOURCES), HARNESS_SOURCE)

    def test_metal_right_handed_perspective_matches_scene_camera(self) -> None:
        self.assertAlmostEqual(self.result["nearNDC"][2], 0, places=5)
        self.assertAlmostEqual(self.result["farNDC"][2], 1, places=5)
        for actual, expected in zip(self.result["sceneCenterNDC"], [0, 0, 0.99992]):
            self.assertAlmostEqual(actual, expected, places=4)
        for actual, expected in zip(self.result["sceneTopRightNDC"][:2], [1, 1]):
            self.assertAlmostEqual(actual, expected, places=5)
        self.assertTrue(self.result["invalidPerspectiveIsIdentity"])


    def test_depth_state_rejects_far_fragment_and_overbright_scales_rgb_only(self) -> None:
        pixel = self.result["depthAndOverbrightPixel"]
        if not pixel:
            self.skipTest("Metal depth draw is unavailable")
        self.assertEqual(pixel[0], 0)
        self.assertEqual(pixel[1], 0)
        self.assertAlmostEqual(pixel[2], 128, delta=2)
        self.assertEqual(pixel[3], 255)
        self.assertEqual(
            self.result["depthTargetLease"],
            {
                "rejectsFourth": True,
                "reusesReleased": True,
                "completionReleased": True,
            },
        )


    def test_normal_cull_maps_to_back_faces_and_nocull_remains_two_sided(self) -> None:
        contract = self.result["cullContract"]
        if not contract.get("frontBackCull"):
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertGreater(contract["frontBackCull"][3], 240)
        self.assertEqual(contract["reversedBackCull"], [0, 0, 0, 0])
        self.assertGreater(contract["reversedNoCull"][3], 240)


    def test_projected_screen_sprites_keep_depth_test_and_write_independent(self) -> None:
        rows = self.result["projectedSpriteProfiles"].get("rows", [])
        self.assertEqual(len(rows), 8, "Real Metal readback for three cameras and native flag-off is required")
        expected = {
            "testWrite": [0, 0, 255, 255],
            "writeDisabled": [0, 255, 0, 255],
            "testDisabled": [0, 255, 0, 255],
            "bothDisabled": [0, 255, 0, 255],
            "writeWithoutTest": [0, 0, 255, 255],
            "farFirst": [0, 0, 255, 255],
        }
        for row in rows:
            with self.subTest(camera=row["camera"], space=row["space"]):
                self.assertGreater(row["nearDepth"], 0)
                self.assertLess(row["farDepth"], 1)
                self.assertLess(row["nearDepth"], row["farDepth"])
            for case, pixel in expected.items():
                with self.subTest(camera=row["camera"], space=row["space"], case=case):
                    self.assertEqual(row[case], pixel)


    def test_projected_screen_sprites_preserve_front_and_back_winding(self) -> None:
        rows = self.result["projectedSpriteProfiles"].get("rows", [])
        self.assertEqual(len(rows), 8, "Real Metal readback for three cameras and native flag-off is required")
        for row in rows:
            for case in ["frontBackCull", "reversedBackCull", "reversedNoCull"]:
                with self.subTest(camera=row["camera"], space=row["space"], case=case):
                    self.assertEqual(len(row[case]), 4)
                    if case == "reversedBackCull":
                        self.assertEqual(row[case], [0, 0, 0, 0])
                    else:
                        self.assertEqual(row[case][3], 255)


    def test_projected_screen_sprites_keep_texture_top_above_bottom(self) -> None:
        rows = self.result["projectedSpriteProfiles"].get("rows", [])
        self.assertEqual(len(rows), 8, "Real Metal readback for three cameras and native flag-off is required")
        for row in rows:
            for case, color_channel, opposite in [("topMarker", 2, 0), ("bottomMarker", 0, 2)]:
                with self.subTest(camera=row["camera"], space=row["space"], marker=case):
                    pixel = row[case]
                    self.assertEqual(len(pixel), 4)
                    self.assertEqual(pixel[3], 255)
                    self.assertGreater(pixel[color_channel], 200)
                    self.assertLess(pixel[opposite], 55)



if __name__ == "__main__":
    unittest.main()
