"""MDLV0023 clip bounds and channel-presence regression through the real reader."""
import json
import os
from pathlib import Path
import struct
import subprocess
import unittest

import test_scene_puppet_animation as legacy


class SceneMdlPuppetAnimationBoundsTests(legacy.SceneMdlPuppetAnimationReaderTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.bounds = (-4.0, -2.0, 0.25, 8.0, 3.0, 11.0)

        def record(values=cls.bounds, *, flag=0, **kwargs):
            return legacy.animation_record(741, "Renamed bounds", 2, 2,
                modern_prefix=struct.pack("<6fB", *values, flag), **kwargs)

        cls.bounds_fixtures = {
            "bounds.mdl": legacy.build_mdl([record()]),
            "bounds-keyed-scalar.mdl": legacy.build_mdl([record(auxiliary=True)]),
            "bounds-zero-extent.mdl": legacy.build_mdl([record((2, -3, 1, 2, -3, 1))]),
            "bounds-renamed-λ.mdl": legacy.build_mdl([legacy.animation_record(
                1981, "Other clip", 3, 2, modern_prefix=struct.pack("<6fB", *cls.bounds, 0))]),
            "bounds-next-clip.mdl": legacy.build_mdl([
                record(), legacy.animation_record(742, "Next", 3, 2)]),
            "bounds-bad-next-track.mdl": legacy.build_mdl([
                record(), legacy.animation_record(742, "Next", 3, 2, bad_track_bytes=True)]),
            "bounds-bad-next-events.mdl": legacy.build_mdl([
                record(), legacy.animation_record(742, "Next", 3, 2,
                    events=[legacy.event_record(0.1, {"name": "bad", "frame": 3})])]),
        }
        for label, values in (
            ("nan", (float("nan"), -2, 0, 8, 3, 11)),
            ("inf", (-4, -2, 0, float("inf"), 3, 11)),
            ("reversed", (-4, 4, 0, 8, 3, 11)),
            ("large", (-1_000_001, -2, 0, 8, 3, 11)),
        ):
            cls.bounds_fixtures[f"bounds-bad-{label}.mdl"] = legacy.build_mdl([record(values)])
        for flag in (1, 2):
            cls.bounds_fixtures[f"bounds-bad-flag{flag}.mdl"] = legacy.build_mdl([record(flag=flag)])
        for size in (23, 24):
            prefix = struct.pack("<6f", *cls.bounds)[:size]
            cls.bounds_fixtures[f"bounds-short-{size}.mdl"] = legacy.build_mdl([
                legacy.animation_record(741, "Short", 2, 2, modern_prefix=prefix)])
        # Declared MDLA ends before any tail; only one external zero is supported.
        for label, tail in (("zero", b"\0"), ("nonzero", b"\1"), ("two", b"\0\0")):
            cls.bounds_fixtures[f"bounds-tail-{label}.mdl"] = cls.bounds_fixtures["bounds.mdl"] + tail
        options21 = dict(magic=b"MDLV0021", skeleton_marker=b"MDLS0003\0")
        cls.bounds_fixtures["bounds-21-rejected.mdl"] = legacy.build_mdl([record()], **options21)
        cls.bounds_fixtures["bounds-21-zero.mdl"] = legacy.build_mdl(**options21)
        # The existing 0021 physical-tail contract is not tightened by 0023.
        cls.bounds_fixtures["bounds-21-tail.mdl"] = cls.bounds_fixtures["bounds-21-zero.mdl"] + b"\2\3"
        tmp = Path(cls._tmp.name)
        paths = []
        for name, data in cls.bounds_fixtures.items():
            path = tmp / name
            path.write_bytes(data)
            paths.append(path)
        cls.direct_path = os.environ.get("MWX_TEST_DIRECT_MODEL_ANIMATION_MDL")
        if cls.direct_path:
            paths.append(Path(cls.direct_path))
        completed = subprocess.run([str(cls.binary), *map(str, paths)], capture_output=True, text=True)
        if completed.returncode:
            raise AssertionError(f"bounds harness failed:\n{completed.stderr}")
        cls.bounds_raw_output = completed.stdout
        cls.results.update({item["file"]: item for item in json.loads(completed.stdout)})

    def test_bounds_metadata_and_scalar_presence_are_retained(self):
        for name in ("bounds.mdl", "bounds-keyed-scalar.mdl", "bounds-renamed-λ.mdl"):
            with self.subTest(name=name):
                entry = self.results[name]
                self.assertTrue(entry["ok"], entry)
                clip = entry["animations"][0]
                self.assertEqual(clip["bounds"], list(self.bounds))
                self.assertEqual(clip["hasAuxiliaryScalarTrack"], name == "bounds-keyed-scalar.mdl")
        self.assertEqual(self.results["bounds-zero-extent.mdl"]["animations"][0]["bounds"],
                         [2, -3, 1, 2, -3, 1])
        self.assertTrue(self.results["valid.mdl"]["animations"][1]["hasAuxiliaryScalarTrack"])

    def test_invalid_bounds_and_scalar_flags_fail_closed(self):
        for name in self.bounds_fixtures:
            if name.startswith(("bounds-bad-", "bounds-short-")) and "next" not in name:
                with self.subTest(name=name):
                    self.assertFalse(self.results[name]["ok"], self.results[name])
                    if not name.startswith("bounds-short-"):
                        self.assertIn("invalid verified auxiliary track", self.results[name]["error"])

    def test_all_records_and_known_0023_tail_are_required(self):
        self.assertEqual([clip["id"] for clip in self.results["bounds-next-clip.mdl"]["animations"]],
                         [741, 742])
        for name in ("bounds-bad-next-track.mdl", "bounds-bad-next-events.mdl",
                     "bounds-tail-nonzero.mdl", "bounds-tail-two.mdl"):
            with self.subTest(name=name):
                self.assertFalse(self.results[name]["ok"], self.results[name])
        self.assertTrue(self.results["bounds-tail-zero.mdl"]["ok"])

    def test_0021_keeps_zero_fields_and_its_existing_tail_contract(self):
        self.assertFalse(self.results["bounds-21-rejected.mdl"]["ok"])
        for name in ("bounds-21-zero.mdl", "bounds-21-tail.mdl"):
            self.assertTrue(self.results[name]["ok"], self.results[name])
            self.assertIsNone(self.results[name]["animations"][0]["bounds"])

    def test_real_direct_model_all_clips_and_default_are_available_when_provided(self):
        if not self.direct_path:
            self.skipTest("set MWX_TEST_DIRECT_MODEL_ANIMATION_MDL to the isolated original model")
        entry = self.results[Path(self.direct_path).name]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["boneCount"], 53)
        self.assertEqual(len(entry["records"]), 17)
        self.assertEqual(len(entry["animations"]), 16)
        self.assertEqual(len([clip for clip in entry["animations"] if clip["id"] == 34]), 1)


if __name__ == "__main__":
    unittest.main()
