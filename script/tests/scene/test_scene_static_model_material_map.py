"""Packed model material components against equivalent prepared scalar surfaces.

The shared normal-map fixture replaces texture transport only. Real model
preparation, typed Frame draws, SurfaceResponse and Metal produce both sides;
the oracle does not reproduce the BRDF or infer coverage from map alpha.
"""
import os
from pathlib import Path
import struct
import tempfile
import unittest

from script.tests.scene import test_scene_static_model_normal_map as normal


def sampled_component(byte):
    return struct.unpack("<e", struct.pack("<e", byte / 255))[0]


def cases():
    base = normal.cases()[0]

    def row(name, constants=None, defaultEmission=False, **changes):
        values = dict(metallic=.25, roughness=.7, emissivebrightness=0)
        values.update(constants or {})
        if defaultEmission:
            values.pop("emissivebrightness")
        return {**base, "name": name, "normalCombo": 0, "pixels": [128, 128, 255, 255],
                "light": [.6, 0, .8], "albedo": [64, 128, 192, 255],
                "constants": values, **changes}

    partition = [0, 255, 255, 0, 255, 0, 64, 255]
    rows = [
        row("mr-first", materialPixels=partition, materialWidth=2, mapHeader=3, uv=.25),
        row("mr-second", materialPixels=partition, materialWidth=2, mapHeader=3, uv=.75),
        row("scalar-first", constants=dict(metallic=0, roughness=1)),
        row("scalar-second", constants=dict(metallic=1, roughness=0)),
        row("scalar-fallback"),
        row("mr-explicit", materialPixels=partition, materialWidth=2, mapHeader=3, uv=.25,
            mapCombos=dict(METALLIC_MAP=1, ROUGHNESS_MAP=1)),
        row("mr-disabled", materialPixels=partition, materialWidth=2, mapHeader=3, uv=.25,
            mapCombos=dict(METALLIC_MAP=0, ROUGHNESS_MAP=0)),
        row("mr-nonzero-two", materialPixels=partition, materialWidth=2, mapHeader=3, uv=.75,
            mapCombos=dict(METALLIC_MAP=2, ROUGHNESS_MAP=1)),
        row("mr-nonzero-negative", materialPixels=partition, materialWidth=2, mapHeader=0, uv=.25,
            mapCombos=dict(METALLIC_MAP=-1, ROUGHNESS_MAP=2)),
        row("scalar-g-only", constants=dict(roughness=0)),
        row("r-header-forced", materialPixels=[255, 0, 255, 255], mapHeader=1,
            mapCombos=dict(METALLIC_MAP=1, ROUGHNESS_MAP=1, REFLECTION_MAP=1, EMISSIVE_MAP=1)),
        row("g-header-only", materialPixels=[255, 0, 255, 255], mapHeader=2),
        row("mr-no-header", materialPixels=partition, materialWidth=2, mapHeader=0, uv=.25,
            mapCombos=dict(METALLIC_MAP=1, ROUGHNESS_MAP=1)),
        row("mr-direct-image", materialPixels=partition, materialWidth=2, mapHeader=-1, uv=.25,
            mapCombos=dict(METALLIC_MAP=1, ROUGHNESS_MAP=1)),
        row("mr-pbr-disabled", materialPixels=partition, materialWidth=2, mapHeader=15, uv=.25,
            mapCombos=dict(PBRMASKS=0, METALLIC_MAP=2, ROUGHNESS_MAP=-1)),
        row("mr-pbr-nonzero", materialPixels=partition, materialWidth=2, mapHeader=3, uv=.25,
            mapCombos=dict(PBRMASKS=2)),
        row("mr-missing", materialPixels=partition, materialWidth=2, mapHeader=3, mapMissing=True),
        row("mr-crop", materialPixels=partition, materialWidth=2, mapHeader=3,
            uv=.25, mapOffset=.5, mapScale=.5),
        row("mr-clamp", materialPixels=partition, materialWidth=2, mapHeader=3, uv=1.125),
        row("mr-repeat", materialPixels=partition, materialWidth=2, mapHeader=3, uv=1.125, mapRepeat=True),
        row("r-nearest", materialPixels=[0, 0, 0, 255, 255, 0, 0, 255],
            materialWidth=2, mapHeader=1, uv=.49),
        row("r-linear", materialPixels=[0, 0, 0, 255, 255, 0, 0, 255],
            materialWidth=2, mapHeader=1, uv=.5, mapNearest=False),
        row("scalar-r-zero", constants=dict(metallic=0)),
        row("scalar-r-half", constants=dict(metallic=.5)),
        row("renamed-material-map", materialPixels=partition, materialWidth=2, mapHeader=3, uv=.25, renamed=True),
        row("mr-half-hdr", materialPixels=partition, materialWidth=2, mapHeader=3, uv=.25,
            alpha=.5, hdr=True, constants=dict(brightness=1.25)),
        row("scalar-half-hdr", alpha=.5, hdr=True,
            constants=dict(metallic=0, roughness=1, brightness=1.25)),
        row("mr-zero-over-far", materialPixels=partition, materialWidth=2, mapHeader=3,
            uv=.25, alpha=0, far=True),
    ]
    for name, changes in [
        ("unlit-stock", {}),
        ("unlit-no-a", dict(materialPixels=[255, 0, 255, 255], mapHeader=3)),
        ("unlit-a-disabled", dict(materialPixels=[0, 0, 0, 255], mapHeader=8,
                                  mapCombos=dict(EMISSIVE_MAP=0))),
        ("unlit-forced-a-without-header", dict(materialPixels=[0, 0, 0, 255], mapHeader=0,
                                               mapCombos=dict(EMISSIVE_MAP=1))),
        ("unlit-forced-a-two", dict(materialPixels=[0, 0, 0, 255], mapHeader=0,
                                    mapCombos=dict(EMISSIVE_MAP=2))),
        ("unlit-forced-a-negative", dict(materialPixels=[0, 0, 0, 255], mapHeader=-1,
                                         mapCombos=dict(EMISSIVE_MAP=-1))),
        ("unlit-pbr-disabled", dict(materialPixels=[0, 0, 0, 255], mapHeader=8,
                                    mapCombos=dict(PBRMASKS=0, EMISSIVE_MAP=2))),
        ("unlit-pbr-nonzero", dict(materialPixels=[0, 0, 0, 255], mapHeader=8,
                                   mapCombos=dict(PBRMASKS=2))),
        ("unlit-a-zero", dict(materialPixels=[0, 0, 0, 0], mapHeader=8)),
        ("unlit-a-half", dict(materialPixels=[0, 0, 0, 128], mapHeader=8)),
        ("unlit-a-default", dict(materialPixels=[0, 0, 0, 255], mapHeader=8)),
    ]:
        rows.append(row(name, defaultEmission=True, lighting=0, normalCombo=1,
                        albedo=[32, 48, 64, 255], **changes))
    rows += [
        row("unlit-a-half-control", lighting=0, albedo=[32, 48, 64, 255],
            materialPixels=[0, 0, 0, 255], mapHeader=8, constants=dict(emissivebrightness=sampled_component(128))),
        row("unlit-a-explicit-control", lighting=0, albedo=[32, 48, 64, 255],
            materialPixels=[0, 0, 0, 255], mapHeader=8, constants=dict(emissivebrightness=1)),
        row("legacy-default", shader="genericimage", lighting=0, defaultEmission=True,
            materialPixels=[255, 255, 255, 255], mapHeader=15, albedo=[32, 48, 64, 255]),
        row("legacy-a-half", shader="genericimage", lighting=0, constants=dict(emissivebrightness=1),
            materialPixels=[255, 255, 255, 128], mapHeader=0, albedo=[32, 48, 64, 255]),
        row("legacy-a-control", shader="genericimage", lighting=0,
            constants=dict(emissivebrightness=sampled_component(128)), materialPixels=[0, 0, 0, 255],
            mapHeader=0, albedo=[32, 48, 64, 255]),
    ]
    reflective = dict(reflection=True, normalCombo=1, pixels=[218, 128, 218, 255])
    for suffix, value in [("zero", 0), ("quarter", 64), ("one", 255)]:
        rows += [
            row("b-" + suffix, materialPixels=[255, 0, value, 255], mapHeader=4,
                constants=dict(reflectivity=1), **reflective),
            row("b-control-" + suffix, constants=dict(reflectivity=sampled_component(value)), **reflective),
        ]
    rows += [
        row("b-disabled", materialPixels=[0, 0, 0, 255], mapHeader=4,
            mapCombos=dict(REFLECTION_MAP=0), constants=dict(reflectivity=1), **reflective),
        row("b-scalar-zero", materialPixels=[0, 0, 255, 255], mapHeader=4,
            constants=dict(reflectivity=0), **reflective),
        row("b-reflection-two", materialPixels=[0, 0, 64, 255], mapHeader=0,
            mapCombos=dict(REFLECTION=2, REFLECTION_MAP=2), constants=dict(reflectivity=1), **reflective),
        row("b-reflection-negative", materialPixels=[0, 0, 64, 255], mapHeader=-1,
            mapCombos=dict(REFLECTION=-1, REFLECTION_MAP=-1), constants=dict(reflectivity=1), **reflective),
        row("b-reflection-disabled", materialPixels=[0, 0, 255, 255], mapHeader=4,
            mapCombos=dict(REFLECTION=0, REFLECTION_MAP=2), constants=dict(reflectivity=1), **reflective),
        row("mrb-normal", materialPixels=[255, 0, 64, 255], mapHeader=15,
            constants=dict(reflectivity=1), **reflective),
        row("mrb-normal-control", constants=dict(metallic=1, roughness=0, reflectivity=sampled_component(64)), **reflective),
        row("b-zero-hdr-metal", hdr=True, materialPixels=[0, 0, 0, 255], mapHeader=4,
            constants=dict(metallic=1, brightness=16, reflectivity=1), **reflective),
        row("b-zero-hdr-control", hdr=True,
            constants=dict(metallic=1, brightness=16, reflectivity=0), **reflective),
        row("b-one-hdr-metal", hdr=True, materialPixels=[0, 0, 255, 255], mapHeader=4,
            constants=dict(metallic=1, brightness=16, reflectivity=1), **reflective),
    ]
    def glow(name, constants=None, **changes):
        values = dict(metallic=1, roughness=.6, reflectivity=1, color=[0, 0, 0],
                      emissivebrightness=1, emissivecolor=[1, 1, 1], brightness=1)
        values.update(constants or {})
        inputs = dict(hdr=True, lighting=0, reflection=True, directLights=False,
                      normalCombo=1, pixels=[185, 128, 242, 255], albedo=[0, 0, 0, 255],
                      materialPixels=[0, 0, 0, 0], mapHeader=8)
        return row(name, constants=values, **{**inputs, **changes})

    opaque_a = dict(materialPixels=[0, 0, 0, 255])
    no_history = dict(reflection=False, normalCombo=0, albedo=[4, 8, 12, 255],
                      **opaque_a)
    unlit = dict(color=[1, 1, 1], reflectivity=0, emissivebrightness=4)
    rows += [
        glow("hdr-e-one", **opaque_a),
        glow("hdr-reflection-gain", constants=dict(emissivebrightness=4), **opaque_a),
        glow("hdr-brightness-control", constants=dict(brightness=4)),
        glow("hdr-a-half", constants=dict(emissivebrightness=4), materialPixels=[0, 0, 0, 128]),
        glow("hdr-a-half-control", constants=dict(brightness=1 + 3 * sampled_component(128))),
        glow("hdr-chroma-gain", shader="chroma4", constants=dict(emissivebrightness=4), **opaque_a),
        glow("hdr-chroma-control", shader="chroma4", constants=dict(brightness=4)),
        glow("hdr-gain-renamed", renamed=True, constants=dict(emissivebrightness=4.0), **opaque_a),
        glow("hdr-off", hdr=False, constants=dict(emissivebrightness=4), **opaque_a),
        glow("hdr-e-half", constants=dict(emissivebrightness=.5), **opaque_a),
        glow("hdr-a-zero", constants=dict(emissivebrightness=4)),
        glow("hdr-map-disabled", mapCombos=dict(EMISSIVE_MAP=0),
             constants=dict(emissivebrightness=4), **opaque_a),
        glow("hdr-red-emissive", constants=dict(emissivebrightness=4, emissivecolor=[1, 0, 0]), **opaque_a),
        glow("hdr-half", alpha=.5, constants=dict(emissivebrightness=4), **opaque_a),
        glow("hdr-zero", alpha=0, constants=dict(emissivebrightness=4), **opaque_a),
        glow("hdr-neither", mapCombos=dict(REFLECTION=0), constants=unlit, **no_history),
        glow("hdr-neither-control", mapCombos=dict(REFLECTION=0),
             constants={**unlit, "brightness": 4}, **no_history),
        glow("hdr-author-reflection-zero", mapCombos=dict(REFLECTION=2), constants=unlit, **no_history),
        glow("hdr-author-reflection-missing", mapCombos=dict(REFLECTION=-1),
             constants={**unlit, "reflectivity": 1}, **no_history),
        glow("hdr-light-no-lamps", lighting=2, mapCombos=dict(REFLECTION=0), constants=unlit, **no_history),
        glow("hdr-light-control", lighting=2, mapCombos=dict(REFLECTION=0),
             constants={**unlit, "brightness": 16, "emissivebrightness": 1}, **no_history),
        glow("hdr-legacy", shader="genericimage", mapCombos=dict(REFLECTION=0),
             constants=unlit, **no_history),
    ]
    return rows


class SceneStaticModelMaterialMapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("MWX_MODEL_MATERIAL_MAP_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-material-map-input-", dir=parent))
        rows = cases()
        normal.prepare(cls.root, rows)
        cls.report = normal.parts.native.run_swift(normal.parts.NATIVE_SOURCES,
            normal.parts.resource_support() + normal.HARNESS.read_text(), label="model-material-map",
            metal_sources=[normal.parts.MODEL_METAL], input_value={"root": str(cls.root), "cases": rows})
        cls.rows = {row["name"]: row for row in cls.report["rows"]}

    def same(self, actual, control):
        left, right = self.rows[actual], self.rows[control]
        for a, b in zip(left["rgba"], right["rgba"]):
            self.assertLessEqual(abs(a-b), 1, (actual, control, left, right))
        self.assertAlmostEqual(left["depth"], right["depth"], places=7)

    def test_header_components_and_scalar_equivalence(self):
        for actual, control, components in [
            ("mr-first", "scalar-first", 3), ("mr-second", "scalar-second", 3),
            ("mr-explicit", "scalar-first", 3), ("mr-nonzero-two", "scalar-second", 3),
            ("mr-nonzero-negative", "scalar-first", 3), ("r-header-forced", "scalar-second", 3),
            ("g-header-only", "scalar-g-only", 2),
            ("mr-no-header", "scalar-first", 3), ("mr-direct-image", "scalar-first", 3),
            ("mr-pbr-nonzero", "scalar-first", 3),
        ]:
            with self.subTest(actual=actual):
                self.same(actual, control)
                self.assertEqual(self.rows[actual]["components"], components)
        self.assertGreater(max(abs(a-b) for a, b in zip(
            self.rows["scalar-first"]["rgba"][:3], self.rows["scalar-second"]["rgba"][:3])), 3)
        for name in ["mr-disabled", "mr-pbr-disabled", "mr-missing"]:
            self.same(name, "scalar-fallback")
            self.assertEqual(self.rows[name]["components"], 0)

    def test_map_uv_address_filter_and_complete_resource_rename(self):
        for actual, control in [("mr-crop", "scalar-second"), ("mr-clamp", "scalar-second"),
                                ("mr-repeat", "scalar-first"), ("r-nearest", "scalar-r-zero"),
                                ("r-linear", "scalar-r-half"), ("renamed-material-map", "mr-first")]:
            self.same(actual, control)
        self.assertIn({"path": "alternate-components.png", "purpose": "mask"},
                      self.rows["renamed-material-map"]["requests"])

    def test_real_alpha_metadata_and_stock_vs_legacy_defaults(self):
        for name in ["unlit-no-a", "unlit-a-disabled", "unlit-pbr-disabled", "unlit-a-zero", "legacy-default"]:
            self.same(name, "unlit-stock")
        for name in ["unlit-forced-a-without-header", "unlit-forced-a-two", "unlit-forced-a-negative", "unlit-pbr-nonzero"]:
            self.same(name, "unlit-a-default")
            self.assertEqual(self.rows[name]["components"], 8)
        self.same("unlit-a-half", "unlit-a-half-control")
        self.same("unlit-a-default", "unlit-a-explicit-control")
        self.same("legacy-a-half", "legacy-a-control")
        self.assertEqual(self.rows["unlit-a-default"]["components"], 8)
        self.assertEqual(self.rows["unlit-a-default"]["emissionSeed"], 1)
        self.assertEqual(self.rows["legacy-default"]["emissionSeed"], 0)
        self.assertEqual(self.rows["legacy-a-half"]["components"], 8)
        self.assertGreater(self.rows["unlit-a-default"]["rgba"][0], self.rows["unlit-stock"]["rgba"][0])
        for name in ["unlit-stock", "unlit-no-a", "unlit-a-default"]:
            self.assertTrue(self.rows[name]["surfaceProfile"])
            self.assertEqual(self.rows[name]["encoding"], 0)
            self.assertNotIn({"path": "normal.png", "purpose": "normal"}, self.rows[name]["requests"])
        self.assertFalse(self.rows["legacy-default"]["surfaceProfile"])

    def test_reflection_multiplier_normal_coexistence_and_scalar_zero(self):
        for suffix in ["zero", "quarter", "one"]:
            self.same("b-" + suffix, "b-control-" + suffix)
        self.same("b-disabled", "b-control-one")
        self.same("b-scalar-zero", "b-control-zero")
        self.same("b-reflection-two", "b-control-quarter")
        self.same("b-reflection-negative", "b-control-quarter")
        self.same("b-reflection-disabled", "b-control-zero")
        self.same("mrb-normal", "mrb-normal-control")
        self.assertEqual(self.rows["mrb-normal"]["components"], 7)
        self.assertEqual(self.rows["mrb-normal"]["encoding"], 1)
        self.assertGreater(self.rows["b-one"]["rgba"][2], self.rows["b-zero"]["rgba"][2] + 3)
        self.assertEqual(self.rows["b-zero-hdr-metal"]["rgba"], self.rows["b-zero-hdr-control"]["rgba"])
        self.assertEqual(self.rows["b-zero-hdr-metal"]["rgba"], [0, 0, 0, 255])
        self.assertGreater(self.rows["b-one-hdr-metal"]["rgba"][2], 10)

    def test_hdr_opacity_and_depth_stay_in_the_original_terminal(self):
        self.same("mr-half-hdr", "scalar-half-hdr")
        self.assertEqual(self.rows["mr-zero-over-far"]["rgba"], [0, 0, 255, 255])
        self.assertEqual(self.rows["mr-first"]["depth"], 0)
        self.assertGreater(self.rows["mr-zero-over-far"]["depth"], 0)
        self.assertLess(self.rows["mr-zero-over-far"]["depth"], self.rows["b-one"]["depth"])
        for row in self.rows.values():
            self.assertTrue(row["completed"], row)
            self.assertEqual(row["outside"], [0, 0, 0, 0], row)

    def test_hdr_emission_gains_reflected_radiance_against_real_brightness(self):
        for actual, control in [("hdr-reflection-gain", "hdr-brightness-control"),
                                ("hdr-a-half", "hdr-a-half-control"),
                                ("hdr-chroma-gain", "hdr-chroma-control"),
                                ("hdr-gain-renamed", "hdr-reflection-gain")]:
            self.same(actual, control)
        self.assertGreater(self.rows["hdr-brightness-control"]["rgba"][2],
                           self.rows["hdr-e-one"]["rgba"][2] + 5)
        self.assertIn({"path": "alternate-components.png", "purpose": "mask"},
                      self.rows["hdr-gain-renamed"]["requests"])
        for name in ["hdr-reflection-gain", "hdr-chroma-gain"]:
            self.assertEqual(self.rows[name]["components"], 8)
            self.assertEqual(self.rows[name]["encoding"], 1)

    def test_hdr_emission_uses_author_features_without_history_or_lamps(self):
        for name in ["hdr-author-reflection-zero", "hdr-author-reflection-missing"]:
            self.same(name, "hdr-neither-control")
        self.same("hdr-light-no-lamps", "hdr-light-control")
        self.same("hdr-legacy", "hdr-neither")
        for name, wanted in [("hdr-neither", [20, 40, 60, 255]),
                             ("hdr-neither-control", [80, 160, 240, 255]),
                             ("hdr-light-control", [64, 128, 192, 255])]:
            for actual, expected in zip(self.rows[name]["rgba"], wanted):
                self.assertLessEqual(abs(actual - expected), 1, (name, self.rows[name]))
        self.assertFalse(self.rows["hdr-legacy"]["surfaceProfile"])

    def test_hdr_emission_disabled_inputs_and_coverage_keep_original_contract(self):
        for name in ["hdr-off", "hdr-e-half", "hdr-a-zero", "hdr-map-disabled", "hdr-red-emissive"]:
            self.same(name, "hdr-e-one")
        self.assertEqual(self.rows["hdr-map-disabled"]["components"], 0)
        full, half, zero = [self.rows[name] for name in ["hdr-reflection-gain", "hdr-half", "hdr-zero"]]
        for faded, opaque in zip(half["rgba"], full["rgba"]):
            self.assertLessEqual(abs(faded * 2 - opaque), 2, (half, full))
        self.assertGreater(full["depth"], 0)
        self.assertAlmostEqual(half["depth"], full["depth"], places=7)
        self.assertEqual(zero["rgba"], [0, 0, 0, 0])
        self.assertEqual(zero["depth"], 0)


if __name__ == "__main__":
    unittest.main()
