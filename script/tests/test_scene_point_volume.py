"""GPU readback of the production point-volume draw against real depth writes."""

import unittest

from script.tests import test_scene_directional_shadow as gpu
from script.tests import test_scene_spot_model_shadow as model
from script.tests.scene import test_scene_static_model_pipeline as lighting


class ScenePointVolumeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture = gpu.REPO / "script/tests/fixtures/ScenePointVolumeChecks.swift"
        scene = gpu.SCENE
        cls.pixels = gpu.run_swift(
            [
                fixture,
                *model.sources(),
                scene / "Rendering/Geometry/SceneMatrix.swift",
                scene / "Rendering/Composition/SceneMainPassEncoder.swift",
                scene / "Rendering/Lighting/ScenePointVolumePipeline.swift",
            ],
            lighting.LIGHTING_STUB,
            label="point-volume",
            metal_sources=[lighting.METAL_SOURCE, scene / "Rendering/Lighting/ScenePointVolume.metal"],
        )

    def test_near_depth_blocks_only_covered_pixels(self):
        pixels = self.pixels
        baseline = pixels["background"]["covered"]
        red = pixels["red"]["covered"][0]
        clipped = pixels["throughVolume"]["covered"][0]
        # The front plane sits entirely before the sphere. The middle plane
        # crosses it and the far plane sits behind it, over the same pixels.
        self.assertGreater(red, baseline[0] + 0.03)
        self.assertEqual(pixels["nearPlane"]["covered"], baseline)
        self.assertEqual(pixels["nearPlane"]["uncovered"], pixels["red"]["uncovered"])
        self.assertGreater(clipped, baseline[0] + 0.01)
        self.assertLess(clipped, red - 0.01)
        self.assertAlmostEqual(pixels["farPlane"]["covered"][0], red, delta=1 / 255)

    def test_model_depth_respects_nearest_surface_and_winding(self):
        pixels = self.pixels
        blocked = pixels["nearPlane"]["covered"]
        clear = pixels["red"]["covered"]
        self.assertNotEqual(blocked, clear)
        self.assertEqual(pixels["nearThenFar"]["covered"], blocked)
        self.assertEqual(pixels["farThenNear"]["covered"], blocked)
        self.assertEqual(pixels["nearThenFarNoTest"]["covered"], pixels["farPlane"]["covered"])
        self.assertEqual(pixels["farThenNearNoTest"]["covered"], blocked)
        # Toggling which winding is front-facing makes the same plane eligible
        # in exactly one of these otherwise identical back-face-culling draws.
        self.assertCountEqual(
            [pixels["counterClockwise"]["covered"], pixels["clockwise"]["covered"]],
            [blocked, clear],
        )

    def test_radius_and_clip_segment_allow_camera_inside(self):
        pixels = self.pixels
        baseline = pixels["background"]
        self.assertTrue(pixels["red"]["encoded"])
        self.assertGreater(pixels["red"]["center"][0], pixels["red"]["shoulder"][0] + 0.02)
        self.assertGreater(pixels["red"]["shoulder"][0], baseline["shoulder"][0])
        self.assertEqual(pixels["red"]["outside"], baseline["outside"])
        self.assertTrue(pixels["cameraInside"]["encoded"])
        self.assertGreater(pixels["cameraInside"]["center"][0], baseline["center"][0] + 0.03)
        self.assertEqual(pixels["pastFarPlane"]["center"], baseline["center"])

    def test_clear_depth_remains_visible_with_large_far_near_ratio(self):
        pixels = self.pixels
        far = pixels["highFarNearRatio"]
        self.assertTrue(far["encoded"])
        self.assertGreater(far["center"][0], pixels["background"]["center"][0] + 0.03)
        # Both clip ranges enclose the whole sphere. Changing only the clear
        # depth's world distance cannot change its on-axis contribution.
        self.assertAlmostEqual(far["center"][0], pixels["red"]["center"][0], delta=1 / 255)

    def test_high_exponent_center_crossing_matches_analytic_integral(self):
        uniform = self.pixels["hdrUniformDensity"]
        peaked = self.pixels["hdrHighExponent"]
        self.assertTrue(uniform["encoded"])
        self.assertTrue(peaked["encoded"])
        self.assertEqual(uniform["center"][1:], [0.125, 0.1875, 0.375])
        self.assertEqual(peaked["center"][1:], uniform["center"][1:])
        full = uniform["center"][0] - 0.0625
        high = peaked["center"][0] - 0.0625
        self.assertGreater(full, 0.1)
        # At the center pixel, normalized radius varies linearly on each half
        # of the diameter. The mean of (1 - r)^10 from r=0 to r=1 is 1/11.
        self.assertAlmostEqual(high / full, 1 / 11, delta=0.002)

    def test_additive_color_preserves_alpha_and_ignores_inactive_volume(self):
        pixels = self.pixels
        background = pixels["background"]["center"]
        single = pixels["red"]["center"]
        both = pixels["twoLights"]["center"]
        self.assertEqual(single[1:], background[1:])
        self.assertEqual(both[0], single[0])
        self.assertGreater(both[1], single[1] + 0.03)
        self.assertEqual(both[2:], background[2:])
        self.assertGreater(pixels["lowerExponent"]["center"][0], single[0] + 0.03)
        for label in ("surfaceOnly", "zeroDensity", "zeroIntensity"):
            with self.subTest(label=label):
                for pixel in ("center", "covered", "uncovered", "shoulder", "outside"):
                    self.assertEqual(pixels[label][pixel], pixels["background"][pixel])
