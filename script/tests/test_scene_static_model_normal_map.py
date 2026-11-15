"""Prepared model normals through the existing resource, frame and Metal owners."""
import json
import os
from pathlib import Path
import tempfile
import unittest

from script.tests import test_scene_static_model_parts as parts


HARNESS = parts.REPO / "script/tests/fixtures/SceneStaticModelNormalChecks.swift"


def cases():
    def row(name, **changes):
        return dict(name=name, **dict(dict(pixels=[255, 128, 128, 255],
            light=[1, 0, 0], scale=[1, 1, 1], rotation=0, tangentSign=1, tangent=[1, 0, 0],
            format=-1, storage="rgba", normalCombo=1, shader="generic4",
            missing=False, override=False, width=1, uv=.5, frameOffset=0,
            frameScale=1, repeat=False, nearest=True, ambient=False,
            alpha=1, far=False, reflection=False, renamed=False, additive=False), **changes))

    return [
        row("rgb-positive"), row("rgb-negative", pixels=[0, 128, 128, 255]),
        row("rg-positive", pixels=[255, 128], format=8, storage="rg"),
        row("ag-positive", pixels=[0, 128, 0, 255], format=0),
        row("ag-negative", pixels=[255, 128, 255, 0], format=0),
        row("compressed-ag", pixels=[0, 123, 0, 255], format=4),
        row("signed-rg", format=5, storage="bc5"),
        row("flat", pixels=[128, 128, 255, 255], light=[0, 0, 1]),
        row("omitted", normalCombo=-1),
        row("disabled", normalCombo=0), row("missing", missing=True),
        row("custom", shader="custom/generic4"), row("overridden", override=True),
        row("geometric", normalCombo=0, light=[0, 0, 1]),
        row("bitangent", pixels=[128, 255, 128, 255], light=[0, 1, 0]),
        row("negative-hand", pixels=[128, 255, 128, 255], light=[0, 1, 0], tangentSign=-1),
        row("mirror-x", scale=[-1, 1, 1], light=[-1, 0, 0]),
        row("mirror-y", pixels=[128, 255, 128, 255], scale=[1, -1, 1], light=[0, -1, 0]),
        row("rotated", rotation=1.5707963267948966, light=[0, 1, 0]),
        row("nonuniform", rotation=1.5707963267948966, scale=[1.5, .5, 1], light=[0, 1, 0]),
        row("oblique-nonuniform", tangent=[.7071067811865476, .7071067811865476, 0],
            scale=[3, 1, 1], light=[.9486832980505138, .31622776601683794, 0]),
        row("crop", width=2, pixels=[255, 128, 128, 255, 0, 128, 128, 255],
            uv=.25, frameOffset=.5, frameScale=.5),
        row("clamp", width=2, pixels=[255, 128, 128, 255, 0, 128, 128, 255], uv=1.125),
        row("repeat", width=2, pixels=[255, 128, 128, 255, 0, 128, 128, 255], uv=1.125, repeat=True),
        row("nearest", width=2, pixels=[255, 128, 255, 255, 0, 128, 255, 255], uv=.49),
        row("linear", width=2, pixels=[255, 128, 255, 255, 0, 128, 255, 255], uv=.49, nearest=False),
        row("ambient-flat", ambient=True, pixels=[128, 128, 255, 255]),
        row("ambient-tilted", ambient=True, pixels=[128, 255, 128, 255]),
        row("half", alpha=.5), row("zero-over-far", alpha=0, far=True),
        row("near-over-far", far=True),
        row("reflection-right", pixels=[218, 128, 218, 255], reflection=True),
        row("reflection-left", pixels=[37, 128, 218, 255], reflection=True),
        row("reflection-flat", pixels=[128, 128, 255, 255], reflection=True),
        row("reflection-additive", pixels=[218, 128, 218, 255], reflection=True, additive=True),
        row("renamed", renamed=True),
    ]


def prepare(root, rows):
    for row in rows:
        folder = root / row["name"]
        (folder / "models").mkdir(parents=True)
        (folder / "materials").mkdir()
        model = "alternate-body" if row["renamed"] else "input"
        material = "alternate-surface" if row["renamed"] else "input"
        normal = "surface-vectors" if row["renamed"] else "normal"
        vertices = [((x, y, 0), tuple(row.get("geometryNormal", [0., 0., 1.])),
                     (*row["tangent"], row["tangentSign"]), (row["uv"], .5))
                    for x, y in [(-40., -40.), (40., -40.), (40., 40.), (-40., 40.)]]
        (folder / f"models/{model}.mdl").write_bytes(parts.reader.build_model(
            vertices=vertices, indices=(0, 2, 1, 0, 3, 2), bounds=(-40, -40, 0, 40, 40, 0),
            material=f"materials/{material}.json".encode()))
        combos = {"LIGHTING": row.get("lighting", 1), **row.get("mapCombos", {})}
        if row["normalCombo"] >= 0:
            combos["NORMALMAP"] = row["normalCombo"]
        if row["reflection"] and "REFLECTION" not in combos:
            combos["REFLECTION"] = 1
        if "gradientCombo" in row:
            combos["SHADINGGRADIENT"] = row["gradientCombo"]
        albedo = "alternate-color" if row["renamed"] else "white"
        textures = [f"materials/{albedo}.png", f"materials/{normal}.png"]
        if row.get("materialPixels") is not None:
            textures.append("materials/alternate-components.png" if row["renamed"] else "materials/components.png")
            if not row.get("mapMissing", False):
                (folder / textures[-1]).write_bytes(parts.png([0, 0, 0, 255]))
        if row.get("gradientPixels") is not None:
            if row.get("gradientDefault", False):
                stock = folder / "stock/materials/gradient/gradient_toon_smooth.tex"
                stock.parent.mkdir(parents=True)
                stock.write_bytes((parts.REPO / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/materials/gradient/gradient_toon_smooth.tex").read_bytes())
            if not row.get("gradientDefault", False) or row.get("gradientExplicit", False):
                textures += [None] * (5 - len(textures))
                textures[4] = "materials/alternate-ramp.png" if row["renamed"] else "materials/ramp.png"
                if not row.get("gradientMissing", False):
                    (folder / textures[4]).write_bytes(parts.png([0, 0, 0, 255]))
            if row.get("gradientUser", False) and not row.get("gradientExplicit", False):
                textures += [None] * (5 - len(textures))
                textures[4] = {"user": "fixture-ramp"}
        (folder / f"materials/{material}.json").write_text(json.dumps({"passes": [{"shader": row["shader"],
            "textures": textures, "combos": combos,
            "constantshadervalues": {"alpha": row["alpha"], "roughness": 1, **row.get("constants", {})}}]}))
        (folder / "models/far.mdl").write_bytes(parts.quad(-40, 40, -40, 40, -10, "materials/far.json"))
        for stem, rgba in [(albedo, row.get("albedo", [255, 255, 255, 255])), ("blue", [0, 0, 255, 255])]:
            (folder / f"materials/{stem}.rgba").write_bytes(bytes(rgba))
            (folder / f"materials/{stem}.png").write_bytes(parts.png(rgba))
        # Only the texture transport is replaced; this file establishes a real VFS input.
        if not row["missing"]:
            (folder / f"materials/{normal}.png").write_bytes(parts.png([128, 128, 255, 255]))
        if row["override"]:
            (folder / "shaders").mkdir()
            (folder / "shaders/generic4.frag").write_text("author override")


class SceneStaticModelNormalMapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("MWX_MODEL_NORMAL_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-normal-input-", dir=parent))
        rows = cases()
        prepare(cls.root, rows)
        cls.report = parts.native.run_swift(parts.NATIVE_SOURCES,
            parts.resource_support() + HARNESS.read_text(), label="model-normal",
            metal_sources=[parts.MODEL_METAL], input_value={"root": str(cls.root), "cases": rows})
        cls.rows = {row["name"]: row for row in cls.report["rows"]}

    def test_prepared_formats_and_actual_directional_pixels(self):
        for name, encoding in [("rgb-positive", 1), ("rg-positive", 2), ("ag-positive", 3),
                               ("compressed-ag", 4), ("signed-rg", 5), ("omitted", 1)]:
            with self.subTest(name=name):
                row = self.rows[name]
                self.assertEqual(row["encoding"], encoding, row)
                self.assertGreater(row["rgba"][0], 120, row)
                self.assertEqual(row["rgba"][3], 255, row)
                self.assertIn({"path": "normal.png", "purpose": "normal"}, row["requests"])
        for name in ["rgb-negative", "ag-negative", "negative-hand"]:
            self.assertLessEqual(max(self.rows[name]["rgba"][:3]), 1, self.rows[name])

    def test_tangent_handedness_and_world_transform(self):
        for name in ["bitangent", "mirror-x", "mirror-y", "rotated", "nonuniform"]:
            self.assertGreater(self.rows[name]["rgba"][0], 120, self.rows[name])
        for actual, expected in zip(self.rows["oblique-nonuniform"]["rgba"], self.rows["rgb-positive"]["rgba"]):
            self.assertLessEqual(abs(actual - expected), 3, self.rows["oblique-nonuniform"])
        self.assertEqual(self.rows["renamed"]["rgba"], self.rows["rgb-positive"]["rgba"])
        self.assertEqual(self.rows["renamed"]["encoding"], 1)
        self.assertIn({"path": "surface-vectors.png", "purpose": "normal"}, self.rows["renamed"]["requests"])

    def test_optional_failures_and_disabled_or_custom_material_keep_geometry(self):
        for name in ["disabled", "missing", "custom", "overridden"]:
            row = self.rows[name]
            self.assertEqual(row["encoding"], 0, row)
            self.assertEqual(row["rgba"], [0, 0, 0, 255], row)
            self.assertEqual(row["depth"], 0, row)
            self.assertNotIn({"path": "normal.png", "purpose": "normal"}, row["requests"])
        for actual, wanted in zip(self.rows["flat"]["rgba"], self.rows["geometric"]["rgba"]):
            self.assertLessEqual(abs(actual - wanted), 1)

    def test_normal_uses_its_own_uv_filter_and_address(self):
        for name in ["crop", "clamp"]:
            self.assertEqual(self.rows[name]["rgba"], [0, 0, 0, 255], self.rows[name])
        self.assertGreater(self.rows["repeat"]["rgba"][0], 120, self.rows["repeat"])
        self.assertGreater(self.rows["nearest"]["rgba"][0], 95, self.rows["nearest"])
        self.assertLess(self.rows["linear"]["rgba"][0], 10, self.rows["linear"])

    def test_geometric_ambient_and_existing_alpha_depth_contract(self):
        self.assertEqual(self.rows["ambient-flat"]["rgba"], [128, 128, 128, 255])
        self.assertEqual(self.rows["ambient-tilted"]["rgba"], [128, 128, 128, 255])
        # The later opaque far draw covers the translucent nonwriter in author order.
        self.assertEqual(self.rows["rgb-positive"]["depth"], 0)
        self.assertEqual(self.rows["zero-over-far"]["rgba"], [0, 0, 255, 255])
        self.assertEqual(self.rows["near-over-far"]["rgba"], [0, 0, 255, 255])
        self.assertEqual(self.rows["near-over-far"]["depth"], self.rows["zero-over-far"]["depth"])
        self.assertGreater(self.rows["zero-over-far"]["depth"], 0)
        self.assertLess(self.rows["zero-over-far"]["depth"], self.rows["reflection-right"]["depth"])
        for actual, full in zip(self.rows["half"]["rgba"], self.rows["rgb-positive"]["rgba"]):
            self.assertLessEqual(abs(actual * 2 - full), 2)
        for row in self.rows.values():
            self.assertTrue(row["completed"], row)
            self.assertEqual(row["outside"], [64, 0, 0, 0]
                if row["name"] == "reflection-additive" else [0, 0, 0, 0], row)

    def test_perturbed_normal_selects_independent_reflection_bands(self):
        right, left, flat = [self.rows["reflection-" + name] for name in ["right", "left", "flat"]]
        self.assertGreater(right["rgba"][2], 10, right)
        self.assertEqual(right["rgba"][:2], [0, 0], right)
        self.assertGreater(left["rgba"][0], 10, left)
        self.assertEqual(left["rgba"][1:3], [0, 0], left)
        self.assertLessEqual(max(flat["rgba"][:3]), 1, flat)
        additive = self.rows["reflection-additive"]
        self.assertEqual(additive["rgba"][0], 64, additive)
        self.assertEqual(additive["rgba"][1:], right["rgba"][1:], additive)


if __name__ == "__main__":
    unittest.main()
