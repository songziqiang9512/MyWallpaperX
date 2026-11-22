"""Model rim diffuse energy against ordinary light-color controls.

Only the documented rim curve is calculated here. Production preparation,
Frame, BRDF, attenuation, visibility and Metal draw both sides. Geometry facts
qualify the fixed camera/pixel used by the independent pinhole oracle.
"""
import math
import os
from pathlib import Path
import tempfile
import unittest

from script.tests.scene import test_scene_static_model_normal_map as normal


SIDE = [math.sqrt(3) / 2, 0, .5]
BACK = [math.sqrt(3) / 2, 0, -.5]
PIXEL_POSITION = [160 * math.tan(math.pi / 6) / 64, -160 * math.tan(math.pi / 6) / 64, 0]
EYE = [0, 0, 160]


def unit(vector):
    length = math.sqrt(sum(value * value for value in vector))
    return [value / length for value in vector]


def no_v(normal_vector, position=PIXEL_POSITION, eye=EYE):
    view = unit([a-b for a, b in zip(eye, position)])
    return min(1, abs(sum(a*b for a, b in zip(unit(normal_vector), view))))


def cases():
    base = normal.cases()[0]

    def row(name, constants=None, **changes):
        return {**base, "name": name, "normalCombo": 0, "pixels": [128, 128, 255, 255],
            "geometryNormal": SIDE, "light": SIDE, "lightIntensity": 1, "geometryFacts": True,
            "albedo": [32, 64, 96, 255], "mapCombos": {"RIMLIGHTING": 1},
            "constants": {"metallic": 0, "roughness": 0, "emissivebrightness": 0, **(constants or {})},
            **changes}

    def pair(name, normal_vector=SIDE, amount=2, exponent=4, gradient=None, **changes):
        curve = amount if exponent == 0 else amount * (1 - no_v(normal_vector)) ** exponent
        gain = [1 + curve / value for value in (gradient or [1, 1, 1])]
        actual = row(name, geometryNormal=normal_vector, light=normal_vector,
                     constants={"rimamount": amount, "rimexponent": exponent}, **changes)
        reference = {**actual, "name": name + "-reference", "normalCombo": 0,
                     "geometryNormal": normal_vector, "mapCombos": {"RIMLIGHTING": 0}, "lightColor": gain}
        return [actual, reference]

    face = unit([a-b for a, b in zip(EYE, PIXEL_POSITION)])
    rows = pair("default-side")
    # The omitted scalars must use the same 2/4 profile as the explicit control.
    rows[0]["constants"].pop("rimamount")
    rows[0]["constants"].pop("rimexponent")
    rows += [row("combo-two", mapCombos={"RIMLIGHTING": 2}),
             row("combo-negative", mapCombos={"RIMLIGHTING": -1}),
             row("ordinary-side", mapCombos={"RIMLIGHTING": 0}),
             row("amount-zero", constants={"rimamount": 0}),
             row("flag-zero", mapCombos={"RIMLIGHTING": 0}), row("omitted", mapCombos={})]
    rows += [row("face-default", geometryNormal=face, light=face),
             row("ordinary-face", geometryNormal=face, light=face, mapCombos={"RIMLIGHTING": 0})]
    rows += pair("face-exponent-zero", normal_vector=face, exponent=0)
    rows += pair("back-exponent-zero", normal_vector=[-value for value in face], exponent=0)
    rows += pair("side-exponent-two", amount=4, exponent=2)
    rows += pair("back-side", normal_vector=BACK)
    mapped = unit([1/255, 1, 1/255])
    mapped_rows = pair("normal-mapped", normal_vector=mapped, normalCombo=1, pixels=[128, 255, 128, 255])
    mapped_rows[0]["geometryNormal"] = [0, 0, 1]
    rows += mapped_rows
    rows += pair("colored-gradient", gradient=[64/255, 128/255, 1], gradientCombo=1,
                 gradientStorage="rgba", gradientPixels=[64, 128, 255, 255])
    rows += [row("gradient-no-l", geometryNormal=[1, 0, 0], light=[0, 0, 1],
                 gradientCombo=1, gradientStorage="r", gradientPixels=[255]),
             row("gradient-no-l-reference", geometryNormal=[1, 0, 0], light=[0, 0, 1],
                 gradientCombo=1, gradientStorage="r", gradientPixels=[255], mapCombos={"RIMLIGHTING": 0}),
             row("pure-metal", constants={"metallic": 1, "roughness": .7}),
             row("pure-metal-reference", constants={"metallic": 1, "roughness": .7}, mapCombos={"RIMLIGHTING": 0})]
    rows += pair("point-side", lightKind="point", lightIntensity=4)
    rows += pair("spot-side", lightKind="spot", lightIntensity=4)
    rows += [row("no-lights", lightKind="none"), row("ambient-only", ambient=True),
             row("shadowed", gradientShadow=True)]
    hdr_rows = pair("half-hdr", alpha=.5, hdr=True)
    for item in hdr_rows:
        item["constants"] = {**item["constants"], "brightness": 4}
    rows += hdr_rows
    rows += [row("user-bound", userShaderValues={"rimamount": "gain"}), row("unlit", lighting=0),
             row("renamed", renamed=True),
             row("reflection", reflection=True, normalCombo=1, geometryNormal=[0, 0, 1], pixels=[218, 128, 218, 255]),
             row("reflection-reference", reflection=True, normalCombo=1, geometryNormal=[0, 0, 1],
                 pixels=[218, 128, 218, 255], mapCombos={"RIMLIGHTING": 0}),
             row("emission", lightKind="none", materialPixels=[0, 0, 0, 255], mapHeader=8,
                 constants={"emissivebrightness": 1}),
             row("point-outside", lightKind="point", lightRadius=1),
             row("spot-outside", lightKind="spot", spotAway=True),
             row("no-l", geometryNormal=[1, 0, 0], light=[0, 0, 1]),
             row("zero-over-far", alpha=0, far=True)]
    return rows


class SceneStaticModelRimLightingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("MWX_MODEL_RIM_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-rim-input-", dir=parent))
        cls.inputs = cases()
        normal.prepare(cls.root, cls.inputs)
        cls.report = normal.parts.native.run_swift(normal.parts.NATIVE_SOURCES,
            normal.parts.resource_support() + normal.HARNESS.read_text(), label="model-rim",
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

    def test_closed_rim_curve_and_native_geometry_facts(self):
        for name in ["default-side", "face-exponent-zero", "back-exponent-zero", "side-exponent-two", "back-side"]:
            self.same(name, name + "-reference")
        for item in self.inputs:
            geometry = self.rows[item["name"]]["geometry"]
            for actual, expected in zip(geometry["position"], PIXEL_POSITION):
                self.assertAlmostEqual(actual, expected, delta=.001, msg=item["name"])
            self.assertEqual(geometry["eye"], EYE)
            self.assertAlmostEqual(no_v(geometry["normal"], geometry["position"], geometry["eye"]),
                                   no_v(item["geometryNormal"]), delta=3e-6, msg=item["name"])
        self.assertGreater(self.rows["default-side"]["rgba"][2], self.rows["ordinary-side"]["rgba"][2] + 2)

    def test_flags_zero_and_nonzero_variants_and_full_rename(self):
        for name in ["combo-two", "combo-negative", "renamed"]:
            self.same(name, "default-side", exact=True)
        for name in ["amount-zero", "flag-zero", "omitted", "user-bound"]:
            self.same(name, "ordinary-side", exact=True)
        self.same("face-default", "ordinary-face", exact=True)

    def test_perturbed_normal_gradient_and_metallic_keep_the_shared_response(self):
        self.same("normal-mapped", "normal-mapped-reference")
        self.assertEqual(self.rows["normal-mapped"]["encoding"], 1)
        self.same("colored-gradient", "colored-gradient-reference")
        self.assertTrue(self.rows["colored-gradient"]["gradient"])
        self.same("gradient-no-l", "gradient-no-l-reference", exact=True)
        self.assertGreater(max(self.rows["gradient-no-l"]["rgba"][:3]), 1)
        self.same("pure-metal", "pure-metal-reference", exact=True)
        self.assertGreater(max(self.rows["pure-metal"]["rgba"][:3]), 0)

    def test_lamp_energy_shadow_and_absence_boundaries(self):
        self.same("point-side", "point-side-reference")
        self.same("spot-side", "spot-side-reference")
        for name in ["no-lights", "shadowed", "point-outside", "spot-outside", "no-l"]:
            self.assertEqual(self.rows[name]["rgba"], [0, 0, 0, 255], self.rows[name])
        self.assertEqual(self.rows["ambient-only"]["rgba"], [16, 32, 48, 255])
        self.assertEqual(self.rows["emission"]["rgba"], [32, 64, 96, 255])
        self.assertEqual(self.rows["unlit"]["rgba"], [32, 64, 96, 255])

    def test_hdr_opacity_reflection_and_depth_remain_in_the_original_terminal(self):
        self.same("half-hdr", "half-hdr-reference")
        self.same("reflection", "reflection-reference", exact=True)
        self.assertGreater(self.rows["reflection"]["rgba"][2], 1)
        self.assertEqual(self.rows["zero-over-far"]["rgba"], [0, 0, 255, 255])
        self.assertLess(self.rows["zero-over-far"]["depth"], self.rows["default-side"]["depth"])
        for row in self.rows.values():
            self.assertTrue(row["completed"], row)
            self.assertTrue(row["surfaceProfile"], row)
            self.assertEqual(row["outside"], [0, 0, 0, 0], row)
            self.assertGreater(row["depth"], 0, row)


if __name__ == "__main__":
    unittest.main()
