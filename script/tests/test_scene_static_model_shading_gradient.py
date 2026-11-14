"""Prepared model ramps against ordinary light-color controls, without a BRDF copy.

The shared native fixture keeps production resource/Frame/Metal owners. Texture
transport supplies deterministic texels, including the stock default identity;
the real stock TEX decoder and original author image are separate App evidence.
"""
import os
from pathlib import Path
import tempfile
import unittest

from script.tests import test_scene_static_model_normal_map as normal


def cases():
    base = normal.cases()[0]

    def row(name, constants=None, omitted=False, **changes):
        result = {**base, "name": name, "normalCombo": 0, "geometryNormal": [0, 0, -1],
            "pixels": [128, 128, 255, 255], "light": [0, 0, 1], "lightIntensity": 1,
            "albedo": [48, 80, 112, 255], "gradientCombo": 1,
            "gradientPixels": [255], "gradientStorage": "r",
            "constants": {"metallic": 0, "roughness": 0, "emissivebrightness": 0, **(constants or {})},
            **changes}
        if omitted:
            result.pop("gradientCombo")
        return result

    def control(name, **changes):
        return row(name, gradientCombo=0, geometryNormal=[0, 0, 1], **changes)

    colors = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255]
    rows = [
        control("ordinary-white"),
        control("ordinary-red", lightColor=[1, 0, 0]),
        control("ordinary-green", lightColor=[0, 1, 0]),
        control("ordinary-blue", lightColor=[0, 0, 1]),
        control("ordinary-gray128", lightColor=[128/255] * 3),
        control("ordinary-gray96", lightColor=[96/255] * 3),
        row("white-back"), row("combo-two", gradientCombo=2), row("combo-negative", gradientCombo=-1),
        row("step-negative", gradientPixels=colors, gradientStorage="rgba", gradientWidth=3),
        row("step-zero", gradientPixels=colors, gradientStorage="rgba", gradientWidth=3, geometryNormal=[1, 0, 0]),
        row("step-positive", gradientPixels=colors, gradientStorage="rgba", gradientWidth=3, geometryNormal=[0, 0, 1]),
        row("r8-gray", gradientPixels=[128]),
        row("r8-no-format", gradientPixels=[128], gradientFormat=-1),
        row("rg-gray", gradientPixels=[128, 255], gradientStorage="rg"),
        row("rgb-gray", gradientPixels=[128, 128, 128, 0], gradientStorage="rgba"),
        row("typed-r8-rgba", gradientPixels=[128, 255, 0, 255], gradientStorage="rgba", gradientFormat=9),
        row("rgba-zero-alpha", gradientPixels=[255, 0, 0, 0], gradientStorage="rgba"),
        row("ramp-nearest", gradientPixels=[0, 64, 128, 255], gradientWidth=4, geometryNormal=[1, 0, 0]),
        row("ramp-linear", gradientPixels=[0, 64, 128, 255], gradientWidth=4,
            geometryNormal=[1, 0, 0], gradientNearest=False),
        row("mapped-domain", gradientPixels=[0, 64, 128, 255], gradientWidth=4,
            geometryNormal=[1, 0, 0], gradientOrigin=[.5, 0], gradientXAxis=[.5, 0]),
        row("half-y-projection", gradientPixels=[0, 64, 128, 255], gradientWidth=4,
            geometryNormal=[0, 0, 1], gradientXAxis=[0, 0], gradientYAxis=[1, 0]),
        row("row-center", gradientPixels=[255, 0, 0, 255, 0, 0, 255, 255],
            gradientStorage="rgba", gradientHeight=2),
        row("mesh-uv-independent", gradientPixels=[0, 64, 128, 255], gradientWidth=4,
            geometryNormal=[0, 0, 1], uv=.125),
        row("normal-flipped", gradientPixels=colors, gradientStorage="rgba", gradientWidth=3,
            geometryNormal=[0, 0, 1], normalCombo=1, pixels=[128, 128, 0, 255]),
        row("normal-front", gradientPixels=colors, gradientStorage="rgba", gradientWidth=3,
            geometryNormal=[0, 0, 1], normalCombo=1),
        row("stock-default", gradientDefault=True, gradientNearest=False),
        row("user-without-file", gradientDefault=True, gradientUser=True),
        row("user-with-file", gradientDefault=True, gradientExplicit=True, gradientUser=True),
        row("explicit-missing-with-default", gradientDefault=True, gradientExplicit=True, gradientMissing=True),
        row("missing", gradientMissing=True), row("disabled", gradientCombo=0), row("omitted", omitted=True),
        row("custom", shader="custom/generic4"), row("overridden", override=True),
        row("unlit", lighting=0), row("no-lights", lightKind="none"),
        row("renamed", renamed=True),
        row("half-hdr", alpha=.5, hdr=True, constants={"brightness": 4}),
        control("ordinary-half-hdr", alpha=.5, hdr=True, constants={"brightness": 4}),
        row("zero-over-far", alpha=0, far=True),
        row("ambient-on", ambient=True, gradientPixels=[0]),
        row("ambient-off", ambient=True, gradientPixels=[0], gradientCombo=0),
        row("emission-on", lightKind="none", gradientPixels=[0],
            materialPixels=[0, 0, 0, 255], mapHeader=8, constants={"emissivebrightness": 1}),
        row("emission-off", lightKind="none", gradientPixels=[0], gradientCombo=0,
            materialPixels=[0, 0, 0, 255], mapHeader=8, constants={"emissivebrightness": 1}),
        row("specular-on", geometryNormal=[0, 0, 1], gradientPixels=[0], constants={"metallic": 1, "roughness": .7}),
        row("specular-off", geometryNormal=[0, 0, 1], gradientCombo=0, constants={"metallic": 1, "roughness": .7}),
        row("reflection-on", reflection=True, geometryNormal=[0, 0, 1], normalCombo=1,
            pixels=[218, 128, 218, 255], gradientPixels=[0]),
        row("reflection-off", reflection=True, geometryNormal=[0, 0, 1], normalCombo=1,
            pixels=[218, 128, 218, 255], gradientCombo=0),
        row("point-back", lightKind="point", lightIntensity=4),
        control("point-control", lightKind="point", lightIntensity=4),
        row("spot-back", lightKind="spot", lightIntensity=4),
        control("spot-control", lightKind="spot", lightIntensity=4),
        row("point-outside", lightKind="point", lightIntensity=4, lightRadius=1),
        row("spot-outside", lightKind="spot", lightIntensity=4, spotAway=True),
        row("shadowed", gradientShadow=True),
    ]
    return rows


class SceneStaticModelShadingGradientTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("MWX_MODEL_GRADIENT_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-gradient-input-", dir=parent))
        rows = cases()
        normal.prepare(cls.root, rows)
        cls.report = normal.parts.native.run_swift(normal.parts.NATIVE_SOURCES,
            normal.parts.resource_support() + normal.HARNESS.read_text(), label="model-gradient",
            metal_sources=[normal.parts.MODEL_METAL], input_value={"root": str(cls.root), "cases": rows})
        cls.rows = {row["name"]: row for row in cls.report["rows"]}

    def same(self, actual, control):
        left, right = self.rows[actual], self.rows[control]
        for a, b in zip(left["rgba"], right["rgba"]):
            self.assertLessEqual(abs(a-b), 1, (actual, control, left, right))
        self.assertAlmostEqual(left["depth"], right["depth"], places=7)

    def test_signed_response_and_integer_combos_reach_real_pixels(self):
        for actual, control in [("white-back", "ordinary-white"), ("combo-two", "ordinary-white"),
                                ("combo-negative", "ordinary-white"), ("step-negative", "ordinary-red"),
                                ("step-zero", "ordinary-green"), ("step-positive", "ordinary-blue")]:
            self.same(actual, control)
            self.assertTrue(self.rows[actual]["gradient"])
        self.assertGreater(min(self.rows["ordinary-white"]["rgba"][:3]), 5)

    def test_format_replication_sampling_and_prepared_domain(self):
        for name in ["r8-gray", "r8-no-format", "rg-gray", "rgb-gray", "typed-r8-rgba", "ramp-nearest", "half-y-projection"]:
            self.same(name, "ordinary-gray128")
        self.same("ramp-linear", "ordinary-gray96")
        self.same("mapped-domain", "ordinary-white")
        self.same("row-center", "ordinary-blue")
        self.same("rgba-zero-alpha", "ordinary-red")
        self.same("mesh-uv-independent", "ordinary-white")
        for name in ["r8-gray", "r8-no-format", "rg-gray", "typed-r8-rgba"]:
            self.assertTrue(self.rows[name]["replicatesRed"])
        self.assertFalse(self.rows["rgb-gray"]["replicatesRed"])

    def test_normal_default_supply_and_local_failure_boundaries(self):
        self.same("normal-flipped", "ordinary-red")
        self.same("normal-front", "ordinary-blue")
        self.same("stock-default", "ordinary-white")
        self.same("user-with-file", "ordinary-white")
        self.same("renamed", "ordinary-white")
        self.assertIn({"path": "gradient_toon_smooth.tex", "purpose": "mask"}, self.rows["stock-default"]["requests"])
        self.assertIn({"path": "alternate-ramp.png", "purpose": "mask"}, self.rows["renamed"]["requests"])
        for name in ["explicit-missing-with-default", "user-without-file", "missing", "disabled", "omitted", "custom", "overridden"]:
            row = self.rows[name]
            self.assertFalse(row["gradient"], row)
            self.assertEqual(row["rgba"], [0, 0, 0, 255], row)
            self.assertGreater(row["depth"], 0, row)
            self.assertNotIn({"path": "gradient_toon_smooth.tex", "purpose": "mask"}, row["requests"])
        self.assertFalse(self.rows["unlit"]["gradient"])
        self.assertEqual(self.rows["unlit"]["rgba"], [48, 80, 112, 255])

    def test_other_radiance_coverage_and_depth_do_not_get_a_final_ramp(self):
        for name in ["ambient", "emission", "specular", "reflection"]:
            self.same(name + "-on", name + "-off")
            self.assertGreater(max(self.rows[name + "-on"]["rgba"][:3]), 1)
        self.same("half-hdr", "ordinary-half-hdr")
        self.assertEqual(self.rows["zero-over-far"]["rgba"], [0, 0, 255, 255])
        self.assertLess(self.rows["zero-over-far"]["depth"], self.rows["white-back"]["depth"])
        self.assertEqual(self.rows["no-lights"]["rgba"], [0, 0, 0, 255])

    def test_lamp_attenuation_cone_shadow_and_gpu_completion(self):
        self.same("point-back", "point-control")
        self.same("spot-back", "spot-control")
        for name in ["point-outside", "spot-outside", "shadowed"]:
            self.assertEqual(self.rows[name]["rgba"], [0, 0, 0, 255], self.rows[name])
        for row in self.rows.values():
            self.assertTrue(row["completed"], row)
            self.assertEqual(row["outside"], [0, 0, 0, 0], row)


if __name__ == "__main__":
    unittest.main()
