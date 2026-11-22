"""Real prepared model Tube radiance against independent Point controls."""
import os
from pathlib import Path
import tempfile
import unittest

from script.tests.scene import test_scene_static_model_normal_map as normal
from script.tests.scene import test_scene_static_model_pigment as pigment


def cases():
    base = normal.cases()[0]

    def row(name, **changes):
        return {**base, "name": name, "normalCombo": 0, "pixels": [128, 128, 255, 255],
                "albedo": [96, 128, 160, 255], "constants": {"metallic": 0, "roughness": 1,
                    "emissivebrightness": 0}, "renderSize": 65, "lightKind": "tube",
                "lightIntensity": 4, "lightRadius": 512, "lightExponent": 2,
                "tubePosition": [100, 0, 80], "tubeDirection": [1, 0, 0],
                "tubeLength": 80, **changes}

    def pair(name, position, **changes):
        return [row(name + "-tube", **changes),
                row(name + "-point", lightKind="point", lightPosition=position, **changes)]

    rows = pair("zero-length", [0, 0, 80], tubePosition=[0, 0, 80],
                tubeDirection=[0, 0, 0], tubeLength=0)
    rows += pair("start-clamp", [100, 0, 80], fullPixels=True)
    rows += pair("end-clamp", [-100, 0, 80], tubePosition=[-180, 0, 80], fullPixels=True)
    rows += [row("interior-short", tubePosition=[-100, 0, 80], tubeLength=200,
                 fullPixels=True, probePixels=[[20, 32], [32, 32], [44, 32]]),
             row("interior-long", tubePosition=[-160, 0, 80], tubeLength=320,
                 fullPixels=True, probePixels=[[20, 32], [32, 32], [44, 32]]),
             row("interior-point", lightKind="point", lightPosition=[0, 0, 80],
                 fullPixels=True, probePixels=[[20, 32], [32, 32], [44, 32]])]
    rows += pair("zero-exponent-outside", [0, 0, 640], tubePosition=[0, 0, 640],
                 tubeDirection=[0, 0, 0], tubeLength=0, lightRadius=160,
                 lightExponent=0, lightIntensity=.25)
    rows += [row("zero-intensity", lightIntensity=0), row("no-lamps", directLights=False),
             row("unlit-tube", lighting=0), row("unlit-control", lighting=0, directLights=False)]
    rows += pair("normal-front", [100, 0, 80], normalCombo=1)
    rows += pair("normal-away", [100, 0, 80], normalCombo=1, pixels=[128, 128, 0, 255])
    rows += pair("chroma", [100, 0, 80], shader="chroma4",
                 constants={"metallic": .2, "roughness": .7, "emissivebrightness": 0,
                            "speculartint": [.25, 1, .5], "tintfront": [1, .5, .25]})
    for amount in [0, 2]:
        rows += pair("rim-" + str(amount), [100, 0, 80], geometryNormal=[.8660254038, 0, .5],
                     mapCombos={"RIMLIGHTING": 1}, constants={"metallic": 0, "roughness": 1,
                         "emissivebrightness": 0, "rimamount": amount, "rimexponent": 4})
    rows += pair("pigment", [100, 0, 80], shader="chroma4", noisePixels=[255, 255, 255, 255],
                 noiseWidth=1, noiseHeight=1, constants={"metallic": 0, "roughness": 1,
                     "emissivebrightness": 0, "tintpigmentation": .2})
    rows += pair("half", [100, 0, 80], alpha=.5)
    rows += pair("writes-depth", [100, 0, 80], blending="normal")
    rows += pair("zero-over-far", [100, 0, 80], alpha=0, far=True)
    rows += pair("material-map", [100, 0, 80], materialPixels=[128, 64, 255, 0],
                 mapHeader=3)
    rows.append(row("renamed", renamed=True, fullPixels=True))
    rows.append(row("four-tubes", tubeCopies=4, lightIntensity=1, fullPixels=True))
    return rows


class SceneStaticModelTubeLightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parent = os.environ.get("MWX_MODEL_TUBE_EVIDENCE")
        if parent:
            Path(parent).mkdir(parents=True, exist_ok=True)
        cls.root = Path(tempfile.mkdtemp(prefix="model-tube-input-", dir=parent))
        cls.inputs = cases()
        normal.prepare(cls.root, [row for row in cls.inputs if "noisePixels" not in row])
        pigment.prepare(cls.root, [row for row in cls.inputs if "noisePixels" in row])
        cls.report = normal.parts.native.run_swift(normal.parts.NATIVE_SOURCES,
            normal.parts.resource_support() + normal.HARNESS.read_text(), label="model-tube",
            metal_sources=[normal.parts.MODEL_METAL],
            input_value={"root": str(cls.root), "cases": cls.inputs})
        cls.rows = {row["name"]: row for row in cls.report["rows"]}

    def same(self, actual, reference, full=False):
        left, right = self.rows[actual], self.rows[reference]
        for a, b in zip(left["rgba"], right["rgba"]):
            self.assertLessEqual(abs(a-b), 1, (left, right))
        self.assertEqual(left["depth"], right["depth"])
        if full:
            self.assertEqual((left["size"], right["size"]), (65, 65))
            self.assertEqual(len(left["pixels"]), 65 * 65 * 4)
            self.assertEqual(len(left["pixels"]), len(right["pixels"]))
            self.assertLessEqual(max(abs(a-b) for a, b in zip(left["pixels"], right["pixels"])), 1)

    def test_zero_length_and_finite_endpoint_clamps_match_real_point_surfaces(self):
        self.same("zero-length-tube", "zero-length-point")
        for name in ["start-clamp", "end-clamp"]:
            self.same(name + "-tube", name + "-point", full=True)
            self.assertGreater(min(self.rows[name + "-point"]["rgba"][:3]), 3)
        self.same("zero-exponent-outside-tube", "zero-exponent-outside-point")
        self.assertGreater(min(self.rows["zero-exponent-outside-point"]["rgba"][:3]), 1)
        self.same("renamed", "start-clamp-point", full=True)
        self.same("four-tubes", "start-clamp-tube", full=True)

    def test_interior_has_length_invariance_and_spatially_extended_illumination(self):
        self.same("interior-short", "interior-long", full=True)
        tube, point = self.rows["interior-short"], self.rows["interior-point"]
        for a, b in zip(tube["probes"][1], point["probes"][1]):
            self.assertLessEqual(abs(a-b), 1, (tube, point))
        for index in [0, 2]:
            self.assertGreater(sum(tube["probes"][index][:3]), sum(point["probes"][index][:3]))

    def test_zero_energy_and_unlit_do_not_invent_direct_radiance(self):
        self.same("zero-intensity", "no-lamps")
        self.assertEqual(self.rows["zero-intensity"]["rgba"], [0, 0, 0, 255])
        self.same("unlit-tube", "unlit-control")
        self.assertEqual(self.rows["unlit-control"]["rgba"], [96, 128, 160, 255])

    def test_normal_chroma_material_maps_and_rim_use_the_original_surface_response(self):
        for name in ["normal-front", "normal-away", "chroma", "rim-0", "rim-2", "material-map"]:
            self.same(name + "-tube", name + "-point")
        for name in ["normal-front", "normal-away"]:
            self.assertEqual(self.rows[name + "-tube"]["encoding"], 1)
        self.assertGreater(sum(self.rows["normal-front-tube"]["rgba"][:3]),
                           sum(self.rows["normal-away-tube"]["rgba"][:3]))
        self.assertGreater(sum(self.rows["rim-2-point"]["rgba"][:3]),
                           sum(self.rows["rim-0-point"]["rgba"][:3]))
        self.assertEqual(self.rows["material-map-tube"]["components"], 3)

    def test_pigment_keeps_tube_as_a_direct_light_consumer(self):
        self.same("pigment-tube", "pigment-point")
        self.assertTrue(self.rows["pigment-tube"]["pigment"])
        self.assertIn({"path": "noise.png", "purpose": "noise"}, self.rows["pigment-tube"]["requests"])

    def test_alpha_and_camera_depth_keep_the_original_material_contract(self):
        for name in ["half", "writes-depth", "zero-over-far"]:
            self.same(name + "-tube", name + "-point")
        for a, b in zip(self.rows["half-tube"]["rgba"], self.rows["start-clamp-tube"]["rgba"]):
            self.assertLessEqual(abs(a * 2-b), 2)
        self.assertEqual(self.rows["half-tube"]["depth"], 0)
        self.assertGreater(self.rows["writes-depth-tube"]["depth"], 0)
        self.assertEqual(self.rows["zero-over-far-tube"]["rgba"], [0, 0, 255, 255])
        self.assertGreater(self.rows["zero-over-far-tube"]["depth"], 0)
        for row in self.rows.values():
            self.assertTrue(row["completed"], row)
            self.assertEqual(row["outside"], [0, 0, 0, 0], row)


if __name__ == "__main__":
    unittest.main()
