#!/usr/bin/env python3

from __future__ import annotations

import unittest

from script.tests.scene_particle_render_test_support import run_particle_harness
from script.tests.test_scene_particle_rendering import HARNESS_SOURCE, SWIFT_SOURCES


# Reuse the maintained DTO preamble and source set, running only camera probes.
CAMERA_HARNESS_SOURCE = HARNESS_SOURCE.split("@main", 1)[0] + r'''
@main enum CameraHarness {
    static func main() throws {
        let result = SceneParticleCameraRenderingHarness.run()
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneParticleCameraRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.result = run_particle_harness(tuple(SWIFT_SOURCES), CAMERA_HARNESS_SOURCE)

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

    def test_native_rope_history_keeps_3d_endpoints_joins_and_texture_sides(self) -> None:
        rows = self.result["nativeRopeProfiles"]
        self.assertEqual(len(rows), 3, rows)
        for row in rows:
            with self.subTest(case=row.get("name")):
                self.assertTrue(row["completed"], row)
                self.assertEqual(row["instanceCount"], 2)
                self.assertTrue(row["preservesWorldModel"])
                self.assertGreater(row["visiblePixels"], 70)
                self.assertLessEqual(row["maximumAlpha"], 129)
                self.assertTrue(all(alpha >= 100 for alpha in row["pathAlpha"]), row)
                self.assertGreater(row["redPixels"], 15)
                self.assertGreater(row["bluePixels"], 15)
                for actual, expected in zip(row["bounds"], row["expectedBounds"], strict=True):
                    self.assertAlmostEqual(actual, expected, delta=8)
        self.assertEqual(rows[0]["pixelSHA256"], rows[1]["pixelSHA256"])
        self.assertGreater(rows[0]["bounds"][2] - rows[0]["bounds"][0],
                           (rows[2]["bounds"][2] - rows[2]["bounds"][0]) * 1.4)

    def test_native_rope_screen_width_stays_local_near_basis_projection_singularity(self) -> None:
        rows = self.result["ropeProjectionConditioning"]
        self.assertEqual(len(rows), 8, "Real production camera/shader/Metal readback is required")
        for row in rows:
            with self.subTest(case=row.get("name")):
                self.assertTrue(row["completed"], row)
                self.assertEqual(row["instanceCount"], 1)
                self.assertTrue(row["inputFinite"], row)
                self.assertTrue(row["preservesWorldModel"], row)
                for anchor_w in row["anchorW"]:
                    self.assertAlmostEqual(anchor_w, 10, places=4)
                # A singular width solution may decline this unsafe quad;
                # it must not paint unrelated pixels across the viewport.
                self.assertEqual(row["outsidePixels"], 0, row)
                if row["name"].startswith("safe-"):
                    self.assertGreater(row["visiblePixels"], 5, row)
                    self.assertAlmostEqual(row["maximumAlpha"], 128, delta=1)



if __name__ == "__main__":
    unittest.main()
