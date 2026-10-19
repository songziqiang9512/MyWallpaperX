#!/usr/bin/env python3
"""Shared Puppet pose/LBS transports direct XYZ and raw affine vertex frames."""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_puppet_playback import SCENE_ROOT, SWIFT_SOURCES as PLAYBACK_SOURCES

FIXTURE = Path(__file__).with_name("fixtures") / "ScenePuppetDirectSkinningHarness.swift"
SWIFT_SOURCES = [*PLAYBACK_SOURCES, SCENE_ROOT / "Format/SceneMdlStaticModel.swift",
                 SCENE_ROOT / "Systems/Puppet/ScenePuppetAnimationEvaluator+Skinning.swift"]


def affine(x=1, y=1, z=1, translation=(0, 0, 0)):
    return [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, *translation, 1]


def case(name, matrices=None, weights=(1, 0, 0, 0), **options):
    return {"name": name, "matrices": matrices or [affine()], "weights": list(weights), **options}


CASES = [
    case("identity"),
    case("translated", [affine(translation=(4, 5, 6))]),
    case("rotated-x", [[1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1]]),
    case("nonuniform-mixed", [affine(2, 1, 1), affine(1, 3, 1)], (.5, .5, 0, 0)),
    case("renamed-equivalent", [affine(2, 1, 1), affine(1, 3, 1)], (.5, .5, 0, 0), renamed=True),
    case("mirror", [affine(-2, 3, 4)]),
    case("shear", [[1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]]),
    case("tiny-invertible", [affine(1e-10, 1e-10, 1e-10)]),
    case("zero-directions", [affine(2, 3, 4)], fault="zeroDirections"),
    case("inverse-bind-once", [affine(translation=(7, 9, 11))],
         bind=[affine(translation=(3, 4, 5))]),
    case("parent-world-once", [affine(translation=(1, 0, 4)), affine(translation=(0, 2, 1))],
         (0, 1, 0, 0), parents=[-1, 0], bind=[affine(translation=(1, 0, 0)),
                                            affine(translation=(0, 2, 0))]),
    case("four-contributions", [affine(translation=(i * 10, 0, i + 1)) for i in range(4)],
         (.1, .2, .3, .4)),
    case("selected-clip", [affine(), affine()], (.5, .5, 0, 0), animation=True),
    case("selected-blend", [affine(), affine()], (.5, .5, 0, 0), animation=True, blend=.5),
    case("selected-override", [affine(), affine()], (.5, .5, 0, 0),
         animation=True, blend=.5, boneOverride=10),
    case("renamed-clip", [affine(), affine()], (.5, .5, 0, 0), animation=True, renamed=True),
    case("singular-zero", [affine(0, 1, 1)]),
    case("singular-rigid-blend", [affine(), affine(-1, -1, 1)], (.5, .5, 0, 0)),
    case("projective-pose", [[1, 0, 0, .1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]]),
    case("projective-bind", bind=[[1, 0, 0, .1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]]),
    case("nonfinite-tangent", fault="nonfiniteTangent"),
    case("raw-normal-overflow", [affine(1e-40, 1, 1)]),
    case("z-only-overflow", [affine(1, 1, 3.0e38)], fault="zOverflow"),
    case("wrong-count", fault="wrongCount"),
    case("short-output", fault="shortOutput"),
]


class ScenePuppetDirectSkinningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        retained = os.environ.get("MWX_DIRECT_SKINNING_OUTPUT")
        cls.temporary = None if retained else tempfile.TemporaryDirectory(prefix="mwx-direct-skinning-")
        cls.directory = Path(retained or cls.temporary.name)
        cls.directory.mkdir(parents=True, exist_ok=True)
        inputs = cls.directory / "cases.json"
        inputs.write_text(json.dumps(CASES))
        binary = cls.directory / "direct-skinning"
        command = ["xcrun", "--sdk", "macosx", "swiftc", *map(str, SWIFT_SOURCES),
                   str(FIXTURE), "-o", str(binary)]
        compiled = subprocess.run(command, capture_output=True, text=True)
        (cls.directory / "compile.stdout").write_text(compiled.stdout)
        (cls.directory / "compile.stderr").write_text(compiled.stderr)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        completed = subprocess.run([str(binary), str(inputs)], capture_output=True, text=True)
        (cls.directory / "raw.stdout").write_text(completed.stdout)
        (cls.directory / "raw.stderr").write_text(completed.stderr)
        if completed.returncode:
            raise RuntimeError(completed.stderr)
        cls.rows = {row["name"]: row for row in json.loads(completed.stdout)}

    @classmethod
    def tearDownClass(cls):
        if cls.temporary:
            cls.temporary.cleanup()

    def vector(self, actual, expected, tolerance=1e-5):
        self.assertEqual(len(actual), len(expected))
        for value, target in zip(actual, expected, strict=True):
            self.assertTrue(math.isfinite(value))
            self.assertAlmostEqual(value, target, delta=max(tolerance, abs(target) * 2e-6))

    def test_raw_xyz_normal_tangent_and_handedness_follow_one_affine_skin(self):
        expected = {
            "identity": ([1, 2, 3], [2, 1, 0], [1, -2, 1, -1]),
            "translated": ([5, 7, 9], [2, 1, 0], [1, -2, 1, -1]),
            "rotated-x": ([1, -3, 2], [2, 0, 1], [1, -1, -2, -1]),
            "nonuniform-mixed": ([1.5, 4, 3], [4/3, .5, 0], [1.5, -4, 1, -1]),
            "mirror": ([-2, 6, 12], [-1, 1/3, 0], [-2, -6, 4, 1]),
            "shear": ([3, 2, 3], [2, -1, 0], [-1, -2, 1, -1]),
            "tiny-invertible": ([1e-10, 2e-10, 3e-10], [2e10, 1e10, 0], [1e-10, -2e-10, 1e-10, -1]),
            "zero-directions": ([2, 6, 12], [0, 0, 0], [0, 0, 0, 0]),
            "inverse-bind-once": ([5, 7, 9], [2, 1, 0], [1, -2, 1, -1]),
            "parent-world-once": ([1, 2, 8], [2, 1, 0], [1, -2, 1, -1]),
            "four-contributions": ([21, 2, 6], [2, 1, 0], [1, -2, 1, -1]),
        }
        for name, channels in expected.items():
            with self.subTest(case=name):
                row = self.rows[name]
                self.assertNotIn("error", row, row)
                for key, values in zip(("position", "normal", "tangent"), channels, strict=True):
                    self.vector(row[key], values, tolerance=1e-15 if name == "tiny-invertible" else 1e-5)
                self.assertEqual(row["uv"], [.25, .75])
                self.vector(row["imageXY"], row["position"][:2])
        mixed = self.rows["nonuniform-mixed"]
        self.assertAlmostEqual(sum(n*t for n, t in zip(mixed["normal"], mixed["tangent"][:3])), 0, delta=1e-6)
        for key in ("position", "normal", "tangent", "uv", "imageXY"):
            self.assertEqual(mixed[key], self.rows["renamed-equivalent"][key])

    def test_real_selector_blend_override_and_legacy_image_interface_share_pose(self):
        for name, z in (("selected-clip", 6), ("selected-blend", 4.5), ("selected-override", 8.5),
                        ("renamed-clip", 6)):
            with self.subTest(case=name):
                row = self.rows[name]
                self.assertNotIn("error", row, row)
                self.vector(row["position"], [1, 2, z])
                self.vector(row["imageXY"], [1, 2])
                self.vector(row["normal"], [2, 1, 0])
                self.vector(row["tangent"], [1, -2, 1, -1])

    def test_invalid_direct_frames_reject_without_tightening_legacy_xy(self):
        for name, reason in {
            "singular-zero": "singularSkinFrame", "singular-rigid-blend": "singularSkinFrame",
            "projective-pose": "nonAffinePoseTransform", "projective-bind": "nonAffineBindTransform",
            "nonfinite-tangent": "invalidVertex", "raw-normal-overflow": "invalidVertex",
            "z-only-overflow": "invalidVertex", "wrong-count": "vertexCountMismatch",
            "short-output": "vertexCountMismatch",
        }.items():
            with self.subTest(case=name):
                row = self.rows[name]
                self.assertIn(reason, row.get("error", ""), row)
                self.assertNotIn("position", row)
                self.assertIn("imageXY", row, row)
        self.assertEqual(self.rows["z-only-overflow"]["imageXY"], [1, 2])


if __name__ == "__main__":
    unittest.main()
