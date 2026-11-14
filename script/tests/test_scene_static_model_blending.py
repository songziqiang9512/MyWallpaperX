"""Prepared static-model blending through the real frame and Metal owners."""

import json
import os
from pathlib import Path
import tempfile
import unittest

from script.tests import test_scene_static_model_parts as parts


REPO = Path(__file__).resolve().parents[2]
HARNESS = REPO / "script/tests/fixtures/SceneStaticModelBlendChecks.swift"
SOURCES = parts.NATIVE_SOURCES


def cases():
    def case(name, blend="normal", alpha=1, texture_alpha=255, layer_alpha=1,
             far=True, near=True, renamed=False, near_writes_depth=True,
             far_first=False, far_blend="normal", far_layer_alpha=1,
             far_depth_test=None, far_writes_depth=True, volume=False):
        return dict(name=name, blend=blend, alpha=alpha, textureAlpha=texture_alpha,
                    layerAlpha=layer_alpha, far=far, near=near, renamed=renamed,
                    nearWritesDepth=near_writes_depth, farFirst=far_first,
                    farBlend=far_blend, farLayerAlpha=far_layer_alpha,
                    farDepthTest=far_depth_test, farWritesDepth=far_writes_depth, volume=volume)

    return [
        case("near-only", far=False), case("far-only", near=False),
        case("clear-only", near=False, far=False), case("normal-one"),
        case("normal-material-zero", alpha=0),
        case("normal-texture-zero", texture_alpha=0),
        case("normal-both-zero", alpha=0, texture_alpha=0),
        case("normal-layer-zero", alpha=0, texture_alpha=0, layer_alpha=0),
        case("normal-layer-half", alpha=0, texture_alpha=0, layer_alpha=.5, far=False),
        case("normal-renamed", blend=" Normal ", alpha=0, texture_alpha=0, renamed=True),
        case("translucent-zero", blend="translucent", alpha=0),
        case("translucent-layer-zero", blend="translucent", layer_alpha=0),
        case("translucent-texture-zero", blend="translucent", texture_alpha=0),
        case("translucent-half", blend="translucent", alpha=.5, far=False),
        case("legacy-nil-zero", blend=None, alpha=0),
        case("legacy-unknown-zero", blend="not-a-mode", alpha=0),
        case("normal-write-disabled-alone", far=False, near_writes_depth=False),
        case("normal-write-disabled-far", near_writes_depth=False),
        case("additive-full", blend="additive", far_first=True),
        case("additive-half", blend="additive", alpha=.5, far_first=True),
        case("additive-layer-half", blend="additive", layer_alpha=.5, far_first=True),
        case("additive-texture-half", blend="additive", texture_alpha=128, far_first=True),
        case("additive-zero", blend="additive", alpha=0, far_first=True),
        case("additive-texture-zero", blend="additive", texture_alpha=0, far_first=True),
        case("additive-alone-half", blend="additive", alpha=.5, far=False),
        case("additive-over-half-background", blend="additive", alpha=.5,
             far_first=True, far_layer_alpha=.5),
        case("additive-no-write-after-background", blend="additive", alpha=.5,
             far_first=True, near_writes_depth=False),
        case("additive-no-write-before-background", blend="additive", alpha=.5,
             near_writes_depth=False),
        case("near-opaque-far-additive", far_blend="additive"),
        case("near-no-write-far-additive", far_blend="additive", near_writes_depth=False),
        case("normal-after-background", far_first=True),
        case("translucent-after-background", blend="translucent", alpha=.5, far_first=True),
        case("additive-renamed", blend=" Additive ", alpha=.5, far_first=True, renamed=True),
        case("depth-read-write", far_depth_test="enabled"),
        case("depth-read-only", far_depth_test="enabled", far_writes_depth=False),
        case("depth-write-only", far_depth_test="disabled"),
        case("depth-neither", far_depth_test="disabled", far_writes_depth=False),
        case("depth-empty", far_depth_test=" \t "),
        case("depth-unknown", far_depth_test="not-a-depth-mode"),
        case("depth-false", far_depth_test="false"),
        case("depth-off", far_depth_test="off"), case("depth-zero", far_depth_test="0"),
        case("depth-disabled-renamed", far_depth_test=" Disabled ", renamed=True),
        case("depth-disabled-zero-coverage", far_depth_test="disabled", far_layer_alpha=0),
        case("volume-near", far=False, volume=True),
        case("volume-far", near=False, volume=True),
        case("volume-near-then-far", far_depth_test="disabled", volume=True),
        case("volume-readonly-far", far_depth_test="disabled", far_writes_depth=False, volume=True),
    ]


def prepare_fixture(root, rows):
    for row in rows:
        directory = root / row["name"]
        (directory / "models").mkdir(parents=True)
        (directory / "materials").mkdir()
        names = ["red", "blue"] if not row["renamed"] else ["ember_surface", "sky_surface"]
        for stem, z, rgba, blend, alpha, writes_depth, depth_test in [
            (names[0], 10, [255, 0, 0, row["textureAlpha"]], row["blend"], row["alpha"], row["nearWritesDepth"], None),
            (names[1], -10, [0, 0, 255, 255], row["farBlend"], 1, row["farWritesDepth"], row["farDepthTest"]),
        ]:
            material = f"materials/{stem}.json"
            (directory / f"models/{stem}.mdl").write_bytes(parts.quad(8, 56, 8, 56, z, material))
            (directory / f"materials/{stem}.rgba").write_bytes(bytes(rgba))
            (directory / f"materials/{stem}.png").write_bytes(parts.png(rgba))
            render_pass = dict(shader="generic4", textures=[f"materials/{stem}.png"],
                               combos={"LIGHTING": 0}, cullmode="nocull",
                               depthwrite="enabled" if writes_depth else "disabled",
                               constantshadervalues={"alpha": alpha})
            if blend is not None:
                render_pass["blending"] = blend
            if depth_test is not None:
                render_pass["depthtest"] = depth_test
            (directory / material).write_text(json.dumps({"passes": [render_pass]}))


class SceneStaticModelBlendingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("MWX_MODEL_BLEND_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-blending-input-", dir=parent))
        vectors = cases()
        prepare_fixture(cls.root, vectors)
        snapshot = os.environ.get("MWX_DIRECTIONAL_SHADOW_PRODUCT_SNAPSHOT")
        if snapshot:
            required = [*SOURCES, parts.MODEL_METAL,
                        parts.MODEL_METAL.with_name("SceneDistanceFog.metalh"),
                        parts.MODEL_METAL.with_name("SceneSurfaceResponse.metalh")]
            missing = [str(p) for p in required if not (Path(snapshot) / p.relative_to(REPO)).is_file()]
            if missing:
                raise AssertionError(f"Incomplete frozen production closure: {missing}")
        cls.report = parts.native.run_swift(
            SOURCES, parts.resource_support() + HARNESS.read_text(), label="model-blending",
            metal_sources=[parts.MODEL_METAL], input_value={"root": str(cls.root), "cases": vectors})
        cls.rows = {row["name"]: row for row in cls.report["rows"]}

    def assert_pixel(self, row, expected):
        self.assertEqual(len(row["rgba"]), 4)
        for actual, wanted in zip(row["rgba"], expected):
            self.assertLessEqual(abs(actual - wanted), 1, row)

    def test_typed_normal_ignores_material_and_texture_alpha_but_keeps_depth(self):
        near = self.rows["near-only"]["depth"]
        far = self.rows["far-only"]["depth"]
        self.assertGreater(near, far)
        self.assertGreater(far, 0)
        for name in ["normal-one", "normal-material-zero", "normal-texture-zero",
                     "normal-both-zero", "normal-renamed"]:
            with self.subTest(name=name):
                row = self.rows[name]
                self.assertEqual(row["preparedBlend"], "normal")
                self.assertEqual(row["opacity"], 0 if name in ["normal-material-zero", "normal-both-zero", "normal-renamed"] else 1)
                self.assert_pixel(row, [255, 0, 0, 255])
                self.assertAlmostEqual(row["depth"], near, delta=.000001)

    def test_layer_coverage_and_translucent_neighbors_keep_pma_and_no_hidden_occlusion(self):
        far = self.rows["far-only"]["depth"]
        for name in ["normal-layer-zero", "translucent-zero", "translucent-layer-zero",
                     "translucent-texture-zero", "legacy-nil-zero", "legacy-unknown-zero"]:
            with self.subTest(name=name):
                self.assert_pixel(self.rows[name], [0, 0, 255, 255])
                self.assertAlmostEqual(self.rows[name]["depth"], far, delta=.000001)
        for name in ["normal-layer-half", "translucent-half"]:
            self.assert_pixel(self.rows[name], [128, 0, 0, 128])
            self.assertAlmostEqual(self.rows[name]["depth"], self.rows["near-only"]["depth"], delta=.000001)
        self.assert_pixel(self.rows["clear-only"], [0, 0, 0, 0])
        self.assertEqual(self.rows["clear-only"]["depth"], 0)

    def test_disabled_near_writer_keeps_color_but_allows_later_far_model(self):
        alone = self.rows["normal-write-disabled-alone"]
        layered = self.rows["normal-write-disabled-far"]
        far = self.rows["far-only"]
        enabled = self.rows["normal-one"]
        for row in [alone, layered]:
            self.assertEqual(row["preparedWritesDepth"], [False, True])
            self.assertTrue(row["prepared"] and row["encoded"] and row["completed"])
            self.assertEqual(row["leases"], 1)
        self.assert_pixel(alone, [255, 0, 0, 255])
        self.assertEqual(alone["depth"], 0)
        self.assert_pixel(far, [0, 0, 255, 255])
        self.assertEqual(layered["rgba"], far["rgba"])
        self.assertEqual(layered["depth"], far["depth"])
        self.assertGreater(far["depth"], 0)
        self.assert_pixel(enabled, [255, 0, 0, 255])
        self.assertGreater(enabled["depth"], far["depth"])

    def test_real_shared_depth_completion_and_transparent_attachment_controls(self):
        for row in self.rows.values():
            with self.subTest(name=row["name"]):
                self.assertTrue(row["completed"])
                self.assertTrue(row["sharedDepth"])
                self.assertEqual(row["leases"], 1)
                self.assertEqual(row["outside"], [0, 0, 0, 0])
                self.assertTrue(row["prepared"])
                self.assertTrue(row["encoded"])

    def test_additive_adds_premultiplied_rgb_and_preserves_source_over_alpha(self):
        for name, expected in [
            ("additive-full", [255, 0, 255, 255]),
            ("additive-half", [128, 0, 255, 255]),
            ("additive-layer-half", [128, 0, 255, 255]),
            ("additive-texture-half", [128, 0, 255, 255]),
            ("additive-alone-half", [128, 0, 0, 128]),
            ("additive-over-half-background", [128, 0, 128, 191]),
            ("additive-renamed", [128, 0, 255, 255]),
        ]:
            with self.subTest(name=name):
                self.assertEqual(self.rows[name]["preparedBlend"], "additive")
                self.assert_pixel(self.rows[name], expected)
                self.assertEqual(self.rows[name]["depth"], self.rows["near-only"]["depth"])
        self.assertEqual(self.rows["additive-renamed"]["rgba"], self.rows["additive-half"]["rgba"])
        for name in ["additive-zero", "additive-texture-zero"]:
            self.assert_pixel(self.rows[name], [0, 0, 255, 255])
            self.assertEqual(self.rows[name]["depth"], self.rows["far-only"]["depth"])
        self.assert_pixel(self.rows["normal-after-background"], [255, 0, 0, 255])
        self.assert_pixel(self.rows["translucent-after-background"], [128, 0, 128, 255])

    def test_additive_does_not_override_geometric_depth_or_author_write_state(self):
        for name, expected in [
            ("additive-no-write-after-background", [128, 0, 255, 255]),
            ("additive-no-write-before-background", [0, 0, 255, 255]),
            ("near-no-write-far-additive", [255, 0, 255, 255]),
        ]:
            with self.subTest(name=name):
                self.assertEqual(self.rows[name]["preparedWritesDepth"], [False, True])
                self.assert_pixel(self.rows[name], expected)
                self.assertEqual(self.rows[name]["depth"], self.rows["far-only"]["depth"])
        row = self.rows["near-opaque-far-additive"]
        self.assertEqual(row["preparedFarBlend"], "additive")
        self.assert_pixel(row, [255, 0, 0, 255])
        self.assertEqual(row["depth"], self.rows["near-only"]["depth"])

    def test_depth_test_and_write_are_independent_for_the_later_far_model(self):
        near, far = self.rows["near-only"]["depth"], self.rows["far-only"]["depth"]
        self.assertGreater(near, far)
        for name, rgba, depth, writes in [
            ("depth-read-write", [255, 0, 0, 255], near, True),
            ("depth-read-only", [255, 0, 0, 255], near, False),
            ("depth-write-only", [0, 0, 255, 255], far, True),
            ("depth-neither", [0, 0, 255, 255], near, False),
        ]:
            with self.subTest(name=name):
                row = self.rows[name]
                self.assertEqual(row["preparedWritesDepth"], [True, writes])
                self.assert_pixel(row, rgba)
                self.assertEqual(row["depth"], depth)

    def test_depth_defaults_disable_aliases_and_zero_coverage_keep_their_boundaries(self):
        near, far = self.rows["near-only"]["depth"], self.rows["far-only"]["depth"]
        for name in ["normal-one", "depth-empty", "depth-unknown", "depth-disabled-zero-coverage"]:
            with self.subTest(name=name):
                self.assert_pixel(self.rows[name], [255, 0, 0, 255])
                self.assertEqual(self.rows[name]["depth"], near)
        for name in ["depth-false", "depth-off", "depth-zero", "depth-disabled-renamed"]:
            with self.subTest(name=name):
                self.assert_pixel(self.rows[name], [0, 0, 255, 255])
                self.assertEqual(self.rows[name]["depth"], far)
        self.assertEqual(self.rows["depth-disabled-renamed"]["rgba"], self.rows["depth-write-only"]["rgba"])

    def test_volume_camera_depth_uses_the_actual_model_surface_order(self):
        near, far = self.rows["volume-near"]["depth"], self.rows["volume-far"]["depth"]
        self.assertGreater(near, far)
        self.assertGreater(far, 0)
        for name, rgba, depth in [
            ("volume-near", [255, 0, 0, 255], near),
            ("volume-far", [0, 0, 255, 255], far),
            ("volume-near-then-far", [0, 0, 255, 255], far),
            ("volume-readonly-far", [0, 0, 255, 255], near),
        ]:
            with self.subTest(name=name):
                row = self.rows[name]
                self.assert_pixel(row, rgba)
                self.assertAlmostEqual(row["depth"], depth, delta=1e-7)
                self.assertAlmostEqual(row["volumeDepth"], depth, delta=1e-7)
                self.assertAlmostEqual(row["volumeDepth"], row["depth"], delta=1e-7)


if __name__ == "__main__":
    unittest.main()
