"""Chroma noise against ordinary rendered light-color controls.

Production resource preparation, Frame, shadows and Metal draw both sides.
Only the documented signed scalar factor and endpoint quantization are used by
the oracle. The texture transport does not qualify the stock TEX decoder.
"""
import json
import os
from pathlib import Path
import tempfile
import unittest

from script.tests.scene import test_scene_static_model_normal_map as normal


PROBES = [[32, 32], [33, 32]]


def cases():
    base = normal.cases()[0]

    def row(name, amount=.2, constants=None, omitted=False, **changes):
        values = {"metallic": .1, "roughness": 0, "emissivebrightness": 0,
                  "tintpigmentation": amount, **(constants or {})}
        if omitted:
            values.pop("tintpigmentation")
        return {**base, "name": name, "shader": "chroma4", "normalCombo": 0,
            "geometryNormal": [0, 0, 1], "pixels": [128, 128, 255, 255],
            "light": [0, 0, 1], "lightIntensity": 2, "albedo": [32, 48, 64, 255],
            "constants": values, "noisePixels": [255, 255, 255, 255], "probePixels": PROBES,
            **changes}

    def pair(name, factor, **changes):
        actual = row(name, **changes)
        reference = {**actual, "name": name + "-reference", "lightColor": [factor] * 3,
            "constants": {**actual["constants"], "tintpigmentation": 0}}
        return [actual, reference]

    rows = [row("ordinary", amount=0, noisePixels=[0, 0, 0, 255])]
    rows += pair("dark", .8, noisePixels=[0, 0, 0, 255])
    rows += pair("bright", 1.2)
    rows += pair("point-normal", 1.2, lightKind="point", lightIntensity=4,
                 normalCombo=1, pixels=[218, 128, 218, 255])
    rows += pair("spot-dark", .8, lightKind="spot", lightIntensity=4, noisePixels=[0, 0, 0, 255])
    rows += [row("rgb-mean", noisePixels=[0, 255, 255, 0]),
             row("r8-dark", noiseStorage="r", noisePixels=[0]),
             row("rg-dark", noiseStorage="rg", noisePixels=[0, 255]),
             row("signed-dark", noiseStorage="bc5", noiseWidth=4, noiseHeight=4,
                 noiseFormat=-1, noisePixels=[129, 129, 0, 0, 0, 0, 0, 0] * 2),
             row("omitted", omitted=True), row("generic", shader="generic4"),
             row("unlit", lighting=0), row("user-amount", userShaderValues={"tintpigmentation": "pigment"}),
             row("stock-default", noiseDefault=True),
             row("explicit-missing-with-default", noiseDefault=True, noiseExplicit=True, noiseMissing=True),
             row("user-without-file", noiseDefault=True, noiseUser=True),
             row("user-with-file", noiseDefault=True, noiseExplicit=True, noiseUser=True),
             row("shadowed", gradientShadow=True)]
    rows += pair("mixed-hdr-half", 1.2, ambient=True, reflection=True, directLights=True,
        normalCombo=1, pixels=[218, 128, 218, 255], hdr=True, alpha=.5,
        albedo=[16, 24, 32, 255], materialPixels=[0, 0, 0, 255], mapHeader=8,
        constants={"metallic": .25, "roughness": .7, "emissivebrightness": 1, "brightness": 2})
    rows += [row("zero-over-far", alpha=0, far=True), row("ambient-only", ambient=True)]
    reflection = row("reflection-only", reflection=True, normalCombo=1, pixels=[218, 128, 218, 255])
    rows += [reflection, {**reflection, "name": "reflection-only-reference",
                         "constants": {**reflection["constants"], "tintpigmentation": 0}}]
    striped = dict(noiseWidth=2, noisePixels=[0, 0, 0, 255, 255, 255, 255, 255])
    rows += [row("screen-repeat", **striped),
             row("screen-clamp", **striped, noiseRepeat=False),
             row("screen-origin", **striped, noiseOrigin=[.5, 0]),
             row("screen-mapped-extent", noiseWidth=4, noisePixels=striped["noisePixels"] * 2,
                 noiseMappedSize=[2, 1], noiseXAxis=[.5, 0]),
             row("screen-linear", **striped, noiseOrigin=[.125, 0], noiseNearest=False),
             row("screen-swapped-axes", noiseWidth=2, noiseHeight=2, noisePixels=striped["noisePixels"] * 2,
                 noiseMappedSize=[2, 2], noiseOrigin=[.5, 0],
                 noiseXAxis=[0, 1], noiseYAxis=[1, 0]),
             row("renamed-mesh-uv-independent", **striped, renamed=True, uv=4)]
    # The wider mesh reaches literal fragment positions 2.5/3.5/4.5 without
    # changing the existing center-pixel lighting or the empty outside probe.
    probes = [[2, 32], [3, 32], [4, 32], [5, 32], [32, 32], [33, 32]]
    crop = striped["noisePixels"] * 2
    atlas = [255, 0, 255, 255] * 64
    for y in [2, 3]:
        atlas[(y * 8 + 2) * 4:(y * 8 + 4) * 4] = striped["noisePixels"]
    for variant, repeat, nearest, renamed in [
            ("nearest-repeat", True, True, False), ("nearest-clamp", False, True, False),
            ("renamed-repeat", True, True, True), ("linear-repeat", True, False, False),
            ("linear-clamp", False, False, False)]:
        shared = dict(scale=[4, 1, 1], probePixels=probes, noiseRepeat=repeat,
                      noiseNearest=nearest, renamed=renamed)
        rows.append(row("sprite-" + variant, **shared, noiseWidth=8, noiseHeight=8,
            noisePixels=atlas, noiseOrigin=[.25, .25], noiseXAxis=[.25, 0],
            noiseYAxis=[0, .25], noiseSprite=True))
        rows.append(row("crop-" + variant, **shared, noiseWidth=2, noiseHeight=2, noisePixels=crop))
    for repeat in [True, False]:
        rows.append(row("sprite-subpixel-" + ("repeat" if repeat else "clamp"),
            noiseWidth=8, noiseHeight=8, noisePixels=atlas, noiseOrigin=[.25, .25],
            noiseXAxis=[.03125, 0], noiseYAxis=[0, .03125], noiseSprite=True, noiseRepeat=repeat))
    return rows


def prepare(root, rows):
    normal.prepare(root, rows)
    for row in rows:
        folder = root / row["name"]
        material = folder / ("materials/alternate-surface.json" if row["renamed"] else "materials/input.json")
        contents = json.loads(material.read_text())
        textures = contents["passes"][0]["textures"]
        if row.get("noiseDefault", False):
            stock = folder / "stock/materials/util/noise.tex"
            stock.parent.mkdir(parents=True, exist_ok=True)
            stock.write_bytes((normal.parts.REPO / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/materials/util/noise.tex").read_bytes())
        if not row.get("noiseDefault", False) or row.get("noiseExplicit", False):
            textures += [None] * (9 - len(textures))
            textures[8] = "materials/alternate-grain.png" if row["renamed"] else "materials/noise.png"
            if not row.get("noiseMissing", False):
                (folder / textures[8]).write_bytes(normal.parts.png([0, 0, 0, 255]))
        elif row.get("noiseUser", False):
            textures += [None] * (9 - len(textures))
            textures[8] = {"user": "fixture-noise"}
        material.write_text(json.dumps(contents))


class SceneStaticModelPigmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("MWX_MODEL_PIGMENT_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-pigment-input-", dir=parent))
        cls.inputs = cases()
        prepare(cls.root, cls.inputs)
        cls.report = normal.parts.native.run_swift(normal.parts.NATIVE_SOURCES,
            normal.parts.resource_support() + normal.HARNESS.read_text(), label="model-pigment",
            metal_sources=[normal.parts.MODEL_METAL], input_value={"root": str(cls.root), "cases": cls.inputs})
        cls.rows = {row["name"]: row for row in cls.report["rows"]}

    def same(self, actual, reference, exact=False):
        left, right = self.rows[actual], self.rows[reference]
        if exact:
            self.assertEqual(left["rgba"], right["rgba"], (left, right))
        else:
            for a, b in zip(left["rgba"], right["rgba"]):
                self.assertLessEqual(abs(a-b), 1, (left, right))
        self.assertEqual(left["depth"], right["depth"])

    def probe(self, actual, index, reference):
        left, right = self.rows[actual]["probes"][index], self.rows[reference]["probes"][index]
        for a, b in zip(left, right):
            self.assertLessEqual(abs(a-b), 1, (actual, index, reference, left, right))

    def test_signed_rgb_mean_red_formats_and_snorm_saturation(self):
        for name in ["dark", "bright", "point-normal", "spot-dark"]:
            self.same(name, name + "-reference")
            self.assertTrue(self.rows[name]["pigment"], self.rows[name])
        for name in ["r8-dark", "rg-dark", "signed-dark"]:
            self.same(name, "dark")
        for name in ["r8-dark", "rg-dark"]:
            self.assertTrue(self.rows[name]["noiseReplicatesRed"])
        self.assertFalse(self.rows["signed-dark"]["noiseReplicatesRed"])
        dark, bright, color = [self.rows[name]["rgba"] for name in ["dark", "bright", "rgb-mean"]]
        for a, b, c in zip(dark[:3], bright[:3], color[:3]):
            self.assertLessEqual(abs(c-(a+(b-a)*2/3)), 1.5, (dark, bright, color))
        self.assertGreater(min(b-a for a, b in zip(dark[:3], bright[:3])), 3)
        self.assertEqual(color[3], 255)
        self.assertEqual(self.rows["point-normal"]["encoding"], 1)

    def test_default_missing_user_and_disabled_demand_stay_slot_local(self):
        self.same("stock-default", "bright", exact=True)
        self.same("user-with-file", "bright", exact=True)
        self.assertIn({"path": "noise.tex", "purpose": "noise"}, self.rows["stock-default"]["requests"])
        self.assertIn({"path": "noise.png", "purpose": "noise"}, self.rows["user-with-file"]["requests"])
        for name in ["ordinary", "omitted", "generic", "user-amount", "explicit-missing-with-default", "user-without-file"]:
            self.same(name, "ordinary", exact=True)
            self.assertFalse(self.rows[name]["pigment"], self.rows[name])
            self.assertNotIn({"path": "noise.tex", "purpose": "noise"}, self.rows[name]["requests"])
            self.assertNotIn({"path": "noise.png", "purpose": "noise"}, self.rows[name]["requests"])
        self.assertFalse(self.rows["unlit"]["pigment"])
        self.assertEqual(self.rows["unlit"]["rgba"], [32, 48, 64, 255])
        self.assertNotIn({"path": "noise.png", "purpose": "noise"}, self.rows["unlit"]["requests"])

    def test_shadow_mixed_radiance_hdr_opacity_and_depth_keep_original_owners(self):
        self.assertEqual(self.rows["shadowed"]["rgba"], [0, 0, 0, 255])
        self.assertTrue(self.rows["shadowed"]["pigment"])
        self.same("mixed-hdr-half", "mixed-hdr-half-reference")
        self.assertEqual(self.rows["mixed-hdr-half"]["rgba"][3], 128)
        self.assertGreater(min(self.rows["mixed-hdr-half"]["rgba"][:3]), 2)
        self.assertLess(max(self.rows["mixed-hdr-half"]["rgba"][:3]), 250)
        self.assertEqual(self.rows["ambient-only"]["rgba"], [16, 24, 32, 255])
        self.same("reflection-only", "reflection-only-reference", exact=True)
        self.assertGreater(self.rows["reflection-only"]["rgba"][2], 2)
        self.assertEqual(self.rows["zero-over-far"]["rgba"], [0, 0, 255, 255])
        self.assertLess(self.rows["zero-over-far"]["depth"], self.rows["bright"]["depth"])

    def test_physical_pixels_mapped_extent_independent_sampler_and_full_rename(self):
        self.probe("screen-repeat", 0, "dark-reference")
        self.probe("screen-repeat", 1, "bright-reference")
        for index in [0, 1]:
            self.probe("screen-clamp", index, "bright-reference")
            self.probe("screen-swapped-axes", index, "bright-reference")
        self.probe("screen-mapped-extent", 0, "dark-reference")
        self.probe("screen-mapped-extent", 1, "bright-reference")
        self.probe("screen-origin", 0, "bright-reference")
        self.probe("screen-origin", 1, "dark-reference")
        for index, weight in enumerate([.25, .75]):
            dark = self.rows["dark-reference"]["probes"][index]
            bright = self.rows["bright-reference"]["probes"][index]
            actual = self.rows["screen-linear"]["probes"][index]
            for a, b, c in zip(dark[:3], bright[:3], actual[:3]):
                self.assertLessEqual(abs(c-(a+(b-a)*weight)), 1.5, (index, actual, dark, bright))
        self.same("renamed-mesh-uv-independent", "screen-repeat", exact=True)
        self.assertEqual(self.rows["renamed-mesh-uv-independent"]["probes"], self.rows["screen-repeat"]["probes"])
        self.assertIn({"path": "alternate-grain.png", "purpose": "noise"}, self.rows["renamed-mesh-uv-independent"]["requests"])
        for variant in ["nearest-repeat", "nearest-clamp", "renamed-repeat", "linear-repeat", "linear-clamp"]:
            self.same("sprite-" + variant, "crop-" + variant, exact=True)
            self.assertEqual(self.rows["sprite-" + variant]["probes"], self.rows["crop-" + variant]["probes"])
        repeated = self.rows["crop-nearest-repeat"]["probes"]
        clamped = self.rows["crop-nearest-clamp"]["probes"]
        self.assertGreater(repeated[1][2] - repeated[0][2], 3)
        self.assertGreater(clamped[0][2] - repeated[0][2], 3)
        self.assertLessEqual(abs(repeated[0][2] - repeated[2][2]), 1)
        for variant in ["renamed-repeat", "linear-repeat"]:
            self.same("sprite-" + variant, "sprite-nearest-repeat", exact=True)
            self.assertEqual(self.rows["sprite-" + variant]["probes"], self.rows["sprite-nearest-repeat"]["probes"])
        self.same("sprite-linear-clamp", "sprite-nearest-clamp", exact=True)
        for name in ["sprite-subpixel-repeat", "sprite-subpixel-clamp"]:
            # Both legal subpixel domains resolve to their black center. The
            # ordinary light-color control supplies the independent finite output.
            self.same(name, "dark-reference")
            for index in range(len(PROBES)):
                self.probe(name, index, "dark-reference")
        for row in self.rows.values():
            self.assertTrue(row["completed"], row)
            self.assertEqual(row["outside"], [0, 0, 0, 0], row)


if __name__ == "__main__":
    unittest.main()
