"""Prepared Chroma surfaces against shared rendered controls, without a BRDF copy.

The tint oracle decomposes measured white/zero specular endpoints. Color-order
controls prepare the equivalent albedo before the real shared response. The
stock pigment algorithm is outside this capability and supplies no test oracle.
"""
import os
from pathlib import Path
import tempfile
import unittest

from script.tests import test_scene_static_model_normal_map as normal
from script.tests.test_scene_static_model_material_map import sampled_component


TINT = [0, .5, 1]


def cases():
    base = normal.cases()[0]

    def row(name, constants=None, **changes):
        return {**base, "name": name, "shader": "chroma4", "normalCombo": 0,
            "geometryNormal": [0, 0, 1], "pixels": [128, 128, 255, 255],
            "light": [0, 0, 1], "lightIntensity": 2, "albedo": [48, 80, 112, 255],
            "constants": {"metallic": .25, "roughness": .7, "emissivebrightness": 0,
                          "tintpigmentation": 0, **(constants or {})}, **changes}

    def shared(name, **changes):
        actual = row(name, **changes)
        return [actual, {**actual, "name": name + "-generic", "shader": "generic4"}]

    rows = []
    for kind in ["directional", "point", "spot"]:
        rows += shared("white-" + kind, lightKind=kind, lightIntensity=2 if kind == "directional" else 4)
    shared_changes = dict(normalCombo=1, pixels=[218, 128, 218, 255],
        materialPixels=[128, 192, 0, 0], mapHeader=3,
        gradientCombo=2, gradientStorage="rgba", gradientPixels=[64, 128, 255, 255],
        mapCombos={"RIMLIGHTING": -1}, constants={"rimamount": 2, "rimexponent": 2})
    rows += shared("normal-map-gradient-rim", **shared_changes)
    rows += shared("shadowed", gradientShadow=True)
    rows += shared("normal-missing", normalCombo=1, missing=True)
    for roughness, prefix in [(0, "delta"), (.7, "specular")]:
        for suffix, tint in [("white", [1, 1, 1]), ("zero", [0, 0, 0]), ("color", TINT)]:
            rows.append(row(prefix + "-" + suffix, constants={"roughness": roughness, "speculartint": tint}))
    rows.append(row("generic-ignores-specular-tint", shader="generic4", constants={"speculartint": [0, 0, 0]}))
    rows.append(row("dynamic-specular-tint", constants={"speculartint": [0, 0, 0]},
                    userShaderValues={"speculartint": "tint-property"}))
    for alpha in [0, 128, 255]:
        for suffix, tint in [("white", [1, 1, 1]), ("zero", [0, 0, 0]), ("color", TINT)]:
            rows.append(row(f"mask-specular-{alpha}-{suffix}", albedo=[48, 80, 112, alpha],
                mapCombos={"TINTMASKALPHA": 1}, constants={"speculartint": tint}))
    rows += [row("no-mask-colored", constants={"color": TINT}),
             row("no-mask-black", constants={"color": [0, 0, 0]}),
             row("generic-colored", shader="generic4", constants={"color": TINT})]
    alpha = sampled_component(128)
    source = [sampled_component(byte) for byte in [32, 64, 96]]
    color = [.5, 1, .25]
    multiplier = [((1-alpha)*value + alpha*max(source)*tint)/value for value, tint in zip(source, color)]
    rows += [row("mask-color", albedo=[32, 64, 96, 128], mapCombos={"TINTMASKALPHA": 1},
                 constants={"color": color}),
             row("mask-color-reference", shader="generic4", albedo=[32, 64, 96, 255],
                 constants={"color": multiplier})]
    for alpha_byte in [0, 128, 255]:
        mask = sampled_component(alpha_byte)
        effective_tint = [1 + mask*(value-1) for value in TINT]
        rows += [row(f"mask-view-{alpha_byte}", albedo=[80, 80, 80, alpha_byte],
                     mapCombos={"TINTMASKALPHA": 1},
                     constants={"tintfront": TINT, "tintback": TINT}),
                 row(f"mask-view-{alpha_byte}-reference", shader="generic4", albedo=[80, 80, 80, 255],
                     constants={"color": effective_tint})]
    rows += [row("view-before-brdf", albedo=[80, 80, 80, 255],
                 constants={"metallic": .75, "tintfront": TINT, "tintback": TINT}),
             row("view-before-reference", shader="generic4", albedo=[0, 40, 80, 255], constants={"metallic": .75}),
             row("generic-view-after", shader="generic4", albedo=[80, 80, 80, 255],
                 constants={"metallic": .75, "tintfront": TINT, "tintback": TINT})]
    side = [.8660254037844386, 0, .5]
    for key in ["tintfront", "tintback"]:
        values = {key: TINT}
        rows += [row("only-" + key, geometryNormal=side, light=side, constants=values),
                 row("both-" + key, geometryNormal=side, light=side,
                     constants={"tintfront": [1, 1, 1], "tintback": [1, 1, 1], **values})]
    rows.append(row("side-no-tint", geometryNormal=side, light=side))
    rows += [row("dynamic-back", geometryNormal=side, light=side, dynamicBack=TINT,
                 constants={"tintfront": [1, 1, 1], "tintback": [1, 1, 1]}),
             row("dynamic-back-reference", geometryNormal=side, light=side,
                 constants={"tintfront": [1, 1, 1], "tintback": TINT})]
    unlit_tints = {"tintfront": [0, 1, 0], "tintback": [1, 0, 0]}
    for name, sign in [("front", 1), ("back", -1)]:
        rows += [row("unlit-normal-" + name, lighting=0, normalCombo=1,
                     pixels=[128, 128, 255 if sign == 1 else 0, 255], constants=unlit_tints),
                 row("unlit-normal-" + name + "-reference", lighting=0,
                     geometryNormal=[0, 0, sign], constants=unlit_tints)]
    rows += [row("unlit-dynamic-normal", lighting=0, normalCombo=1, pixels=[128, 128, 0, 255],
                 dynamicBack=TINT, constants={"tintfront": [1, 1, 1], "tintback": [1, 1, 1]}),
             row("unlit-dynamic-normal-reference", lighting=0, geometryNormal=[0, 0, -1],
                 constants={"tintfront": [1, 1, 1], "tintback": TINT}),
             row("unlit-constant-tint", lighting=0, normalCombo=1,
                 constants={"tintfront": TINT, "tintback": TINT})]
    for brightness in [0, 1, 2]:
        rows += shared(f"hdr-direct-{brightness}", hdr=True, constants={"brightness": brightness})
        rows += shared(f"hdr-reflection-{brightness}", hdr=True, reflection=True, normalCombo=1,
            pixels=[218, 128, 218, 255], albedo=[0, 0, 0, 255], constants={"brightness": brightness})
        rows += shared(f"hdr-emission-reflection-{brightness}", hdr=True, reflection=True, normalCombo=1,
            pixels=[218, 128, 218, 255], albedo=[16, 24, 32, 255],
            materialPixels=[0, 0, 0, 255], mapHeader=8,
            constants={"brightness": brightness, "emissivebrightness": 1})
        rows += shared(f"hdr-black-grazing-{brightness}", hdr=True,
            geometryNormal=side, light=[side[0], 0, -side[2]], albedo=[0, 0, 0, 255],
            constants={"brightness": brightness, "metallic": 1, "roughness": .6})
        rows += shared(f"hdr-mask-{brightness}", hdr=True, albedo=[48, 80, 112, 128],
            mapCombos={"TINTMASKALPHA": 1}, constants={"brightness": brightness})
    rows += shared("hdr-disabled-brightness", hdr=False, constants={"brightness": 2})
    rows += shared("hdr-renamed", hdr=True, renamed=True, constants={"brightness": 2})
    rows += shared("host-half", alpha=.5)
    rows += shared("texture-half", albedo=[48, 80, 112, 128])
    rows += [row("zero-over-far", alpha=0, far=True),
             row("mask-zero-is-coverage", albedo=[48, 80, 112, 0], mapCombos={"TINTMASKALPHA": 1})]
    levels = [[128, 128, 0 if level == 0 else 255, 255] * (max(1, 16 >> level)**2)
              for level in range(5)]
    for name, alpha, span in [("mip-opaque", 255, 16), ("mip-transparent-edge", 0, 16), ("mip-base-control", 255, 0)]:
        rows.append(row(name, normalCombo=1, width=16, normalHeight=16, normalLevels=levels,
            uvSpan=span, albedoPixels=[48, 80, 112, alpha, 48, 80, 112, 255], albedoWidth=2,
            albedoUVScale=1/16 if span else 1, probePixels=[[31, 32], [32, 32], [33, 32]]))
    rows += [row("renamed", renamed=True), row("custom", shader="custom/chroma4"),
             row("overridden-fragment", override=True), row("overridden-vertex", override=True, overrideStage="vert")]
    return rows


def prepare(root, rows):
    normal.prepare(root, [{**row, "override": False} for row in rows])
    for row in rows:
        folder = root / row["name"]
        if row["override"]:
            (folder / "shaders").mkdir()
            (folder / f"shaders/chroma4.{row.get('overrideStage', 'frag')}").write_text("author override")
        if "uvSpan" in row:
            span = row["uvSpan"]
            coordinates = [(0, 0), (span, 0), (span, span), (0, span)] if span else [(.5, .5)] * 4
            vertices = [((x, y, 0), tuple(row["geometryNormal"]), (*row["tangent"], row["tangentSign"]), uv)
                        for (x, y), uv in zip([(-40., -40.), (40., -40.), (40., 40.), (-40., 40.)], coordinates)]
            (folder / "models/input.mdl").write_bytes(normal.parts.reader.build_model(vertices=vertices,
                indices=(0, 2, 1, 0, 3, 2), bounds=(-40, -40, 0, 40, 40, 0), material=b"materials/input.json"))


class SceneStaticModelChromaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("MWX_MODEL_CHROMA_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-chroma-input-", dir=parent))
        cls.inputs = cases()
        prepare(cls.root, cls.inputs)
        cls.report = normal.parts.native.run_swift(normal.parts.NATIVE_SOURCES,
            normal.parts.resource_support() + normal.HARNESS.read_text(), label="model-chroma",
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

    def tint_between(self, actual, zero, white, factors):
        tinted, diffuse, combined = [self.rows[name]["rgba"] for name in [actual, zero, white]]
        # Endpoint quantization contributes at most one code value per lane.
        for channel, factor in enumerate(factors):
            expected = diffuse[channel] + factor*(combined[channel]-diffuse[channel])
            self.assertLessEqual(abs(tinted[channel]-expected), 1.5, (actual, tinted, diffuse, combined, factors))
        self.assertEqual(tinted[3], 255)

    def test_common_mr_lights_normal_map_gradient_rim_and_real_shadow(self):
        for name in ["white-directional", "white-point", "white-spot", "normal-map-gradient-rim", "shadowed", "normal-missing"]:
            self.same(name, name + "-generic")
            self.assertTrue(self.rows[name]["surfaceProfile"], self.rows[name])
        for name in ["white-directional", "white-point", "white-spot"]:
            self.assertGreater(min(self.rows[name]["rgba"][:3]), 2)
        self.assertEqual(self.rows["normal-map-gradient-rim"]["encoding"], 1)
        self.assertEqual(self.rows["normal-map-gradient-rim"]["components"], 3)
        self.assertTrue(self.rows["normal-map-gradient-rim"]["gradient"])
        self.assertEqual(self.rows["normal-missing"]["encoding"], 0)
        self.assertEqual(self.rows["shadowed"]["rgba"], [0, 0, 0, 255])

    def test_specular_tint_multiplies_only_the_existing_specular_lobe(self):
        self.same("delta-zero", "delta-white", exact=True)
        self.same("delta-color", "delta-white", exact=True)
        self.same("generic-ignores-specular-tint", "white-directional", exact=True)
        self.same("dynamic-specular-tint", "specular-white", exact=True)
        self.tint_between("specular-color", "specular-zero", "specular-white", TINT)
        diffuse, white = self.rows["specular-zero"]["rgba"], self.rows["specular-white"]["rgba"]
        self.assertGreater(min(diffuse[:3]), 2)
        self.assertGreater(min(b-a for a, b in zip(diffuse[:3], white[:3])), 2)
        self.assertEqual(self.rows["specular-color"]["rgba"][0], diffuse[0])

    def test_mask_uses_original_alpha_for_color_view_and_specular_independently(self):
        self.same("mask-color", "mask-color-reference")
        for alpha in [0, 128, 255]:
            self.tint_between(f"mask-specular-{alpha}-color", f"mask-specular-{alpha}-zero",
                              f"mask-specular-{alpha}-white", TINT)
            self.same(f"mask-view-{alpha}", f"mask-view-{alpha}-reference")
            self.assertEqual(self.rows[f"mask-view-{alpha}"]["rgba"][3], 255)
            if alpha == 0:
                self.same("mask-specular-0-zero", "mask-specular-0-white", exact=True)
            else:
                zero, white = [self.rows[f"mask-specular-{alpha}-" + suffix]["rgba"] for suffix in ["zero", "white"]]
                self.assertGreater(max(b-a for a, b in zip(zero[:3], white[:3])), 1)

    def test_chroma_color_order_defaults_and_typed_dynamic_back(self):
        self.same("no-mask-colored", "white-directional", exact=True)
        self.same("no-mask-black", "white-directional", exact=True)
        self.assertNotEqual(self.rows["generic-colored"]["rgba"], self.rows["white-directional"]["rgba"])
        self.same("view-before-brdf", "view-before-reference")
        self.assertGreater(self.rows["view-before-brdf"]["rgba"][0], self.rows["generic-view-after"]["rgba"][0] + 1)
        for key in ["tintfront", "tintback"]:
            self.same("only-" + key, "both-" + key, exact=True)
            self.assertNotEqual(self.rows["only-" + key]["rgba"], self.rows["side-no-tint"]["rgba"])
        self.same("dynamic-back", "dynamic-back-reference", exact=True)
        for name in ["unlit-normal-front", "unlit-normal-back", "unlit-dynamic-normal"]:
            self.same(name, name + "-reference")
            self.assertEqual(self.rows[name]["encoding"], 1)
            self.assertIn({"path": "normal.png", "purpose": "normal"}, self.rows[name]["requests"])
        self.assertNotEqual(self.rows["unlit-normal-front"]["rgba"], self.rows["unlit-normal-back"]["rgba"])
        constant = self.rows["unlit-constant-tint"]
        self.assertEqual(constant["rgba"], [0, 40, 112, 255])
        self.assertEqual(constant["encoding"], 0)
        self.assertNotIn({"path": "normal.png", "purpose": "normal"}, constant["requests"])

    def test_hdr_gain_scales_composed_radiance_once_including_reflection(self):
        for prefix in ["hdr-direct", "hdr-reflection", "hdr-emission-reflection", "hdr-black-grazing", "hdr-mask"]:
            for suffix in ["", "-generic"]:
                zero, one, two = [self.rows[f"{prefix}-{gain}{suffix}"]["rgba"] for gain in [0, 1, 2]]
                self.assertEqual(zero, [0, 0, 0, 255], (prefix, suffix, zero))
                self.assertGreater(max(one[:3]), 2, (prefix, suffix))
                self.assertLess(max(two[:3]), 250, (prefix, suffix))
                for a, b in zip(one[:3], two[:3]):
                    self.assertLessEqual(abs(2*a-b), 1, (prefix, suffix, one, two))
                self.assertEqual(one[3], two[3])
            for gain in [0, 1, 2]:
                self.same(f"{prefix}-{gain}", f"{prefix}-{gain}-generic")
        for suffix in ["", "-generic"]:
            self.same("hdr-disabled-brightness" + suffix, "hdr-direct-1" + suffix)
            self.same("hdr-renamed" + suffix, "hdr-direct-2" + suffix, exact=True)
        self.assertGreater(self.rows["hdr-emission-reflection-1"]["rgba"][2],
                           self.rows["hdr-reflection-1"]["rgba"][2] + 5)

    def test_coverage_mip_derivatives_and_source_qualification_remain_local(self):
        self.same("host-half", "host-half-generic")
        self.same("texture-half", "texture-half-generic")
        self.same("mask-zero-is-coverage", "white-directional", exact=True)
        self.same("renamed", "white-directional", exact=True)
        self.assertEqual(self.rows["zero-over-far"]["rgba"], [0, 0, 255, 255])
        # Ordinary fixture draws are translucent; reflection rows explicitly write near depth.
        self.assertEqual(self.rows["white-directional"]["depth"], 0)
        self.assertGreater(self.rows["zero-over-far"]["depth"], 0)
        self.assertLess(self.rows["zero-over-far"]["depth"], self.rows["hdr-reflection-1"]["depth"])
        opaque, edge, base = [self.rows[name] for name in ["mip-opaque", "mip-transparent-edge", "mip-base-control"]]
        self.assertEqual(edge["normalMipCount"], 5)
        self.assertEqual(edge["probes"][0], [0, 0, 0, 0])
        self.assertGreater(min(opaque["probes"][1][:3]), 2)
        self.assertEqual(base["probes"][1], [0, 0, 0, 255])
        self.assertEqual(edge["probes"][1:], opaque["probes"][1:])
        self.assertEqual(edge["depth"], opaque["depth"])
        for name in ["custom", "overridden-fragment", "overridden-vertex"]:
            self.assertFalse(self.rows[name]["surfaceProfile"], self.rows[name])
            self.assertGreater(max(self.rows[name]["rgba"][:3]), 2)
        for row in self.rows.values():
            self.assertTrue(row["completed"], row)
            self.assertEqual(row["outside"], [0, 0, 0, 0], row)


if __name__ == "__main__":
    unittest.main()
