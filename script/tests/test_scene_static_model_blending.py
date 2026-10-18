"""Prepared static-model normal coverage through the real frame and Metal owners."""

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
             far=True, near=True, renamed=False, near_writes_depth=True):
        return dict(name=name, blend=blend, alpha=alpha, textureAlpha=texture_alpha,
                    layerAlpha=layer_alpha, far=far, near=near, renamed=renamed,
                    nearWritesDepth=near_writes_depth)

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
    ]


def prepare_fixture(root, rows):
    for row in rows:
        directory = root / row["name"]
        (directory / "models").mkdir(parents=True)
        (directory / "materials").mkdir()
        names = ["red", "blue"] if not row["renamed"] else ["ember_surface", "sky_surface"]
        for stem, z, rgba, blend, alpha, writes_depth in [
            (names[0], 10, [255, 0, 0, row["textureAlpha"]], row["blend"], row["alpha"], row["nearWritesDepth"]),
            (names[1], -10, [0, 0, 255, 255], "normal", 1, True),
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


if __name__ == "__main__":
    unittest.main()
