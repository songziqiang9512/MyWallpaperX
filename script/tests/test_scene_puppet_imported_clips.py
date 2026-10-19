"""Imported MDLV0023 records and exported clip identity through the sole MDLA reader."""
import json
from pathlib import Path
import struct
import subprocess
import unittest

import test_scene_puppet_animation as legacy
from test_scene_puppet_animation_bounds import SceneMdlPuppetAnimationBoundsTests as BoundsTests


def source(animation_id=101, *, frames=6, **kwargs):
    return legacy.animation_record(animation_id, "Source Ω", frames, 2, **kwargs)


def derived(animation_id=101, *, source_ordinal=0, first=1, end=3,
            control=0, root=-1, frames=2, flags=0x401, mode="", **kwargs):
    descriptor = struct.pack("<HIIIi", source_ordinal, first, end, control, root)
    return legacy.animation_record(animation_id, "Clip λ", frames, 2, mode=mode,
        transform_state=flags, modern_prefix=b"\0" * 25 + descriptor, **kwargs)


class SceneMdlPuppetImportedClipTests(BoundsTests):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.imported_fixtures = {
            "imported-same-id.mdl": legacy.build_mdl([source(), derived()]),
            "renamed-resource-Σ.mdl": legacy.build_mdl([
                legacy.animation_record(712, "Different source", 9, 2), source(811),
                derived(712, source_ordinal=1, first=4, end=6)]),
            "imported-two-source-ids.mdl": legacy.build_mdl([
                source(), source(frames=9), derived(331, source_ordinal=1, first=7, end=9)]),
            "imported-range-zero.mdl": legacy.build_mdl([source(), derived(first=0, end=2)]),
            "imported-loop.mdl": legacy.build_mdl([source(), derived(mode="loop")]),
            "imported-mirror.mdl": legacy.build_mdl([source(), derived(mode="mirror")]),
            "imported-single.mdl": legacy.build_mdl([source(), derived(mode="single")]),
            "imported-bad-duplicate.mdl": legacy.build_mdl([source(), derived(), derived()]),
            "imported-bad-full-mode.mdl": legacy.build_mdl([source(mode=""), derived()]),
            "imported-bad-mode.mdl": legacy.build_mdl([source(), derived(mode="unknown")]),
            "imported-bad-21.mdl": legacy.build_mdl([source(), derived()],
                magic=b"MDLV0021", skeleton_marker=b"MDLS0003\0"),
            "imported-bad-next-track.mdl": legacy.build_mdl([
                source(), derived(), derived(102, bad_track_bytes=True)]),
            "imported-bad-source-track.mdl": legacy.build_mdl([
                source(bad_track_bytes=True), derived()]),
            "imported-bad-next-event.mdl": legacy.build_mdl([
                source(), derived(), derived(102, events=[
                    legacy.event_record(0.1, {"name": "bad", "frame": 2})])]),
            "old23-zero-full-tail.mdl": legacy.build_mdl([source()]) + b"\2\3",
            "old23-bad-empty.mdl": legacy.build_mdl([source(mode="")]),
        }
        for label, options in {
            "self": {"source_ordinal": 1}, "future": {"source_ordinal": 2},
            "outside": {"source_ordinal": 65535}, "reversed": {"first": 3, "end": 1},
            "empty": {"first": 2, "end": 2}, "span": {"first": 1, "end": 4},
            "source-range": {"first": 5, "end": 7},
            "large-range": {"first": 0xFFFFFFFD, "end": 0xFFFFFFFF},
        }.items():
            cls.imported_fixtures[f"imported-bad-reference-{label}.mdl"] = legacy.build_mdl([
                source(), derived(**options)])
        cls.imported_fixtures["imported-bad-reference-derived.mdl"] = legacy.build_mdl([
            source(), derived(), derived(102, source_ordinal=1, first=0, end=2)])
        for flags in (1, 0x400, 0x402, 0xFFFFFFFF):
            cls.imported_fixtures[f"imported-bad-flags-{flags}.mdl"] = legacy.build_mdl([
                source(), derived(flags=flags)])
        for control, root in ((1, -1), (0xFFFFFFFF, -1), (0, 0), (0, -2)):
            cls.imported_fixtures[f"imported-bad-control-{control}-{root}.mdl"] = legacy.build_mdl([
                source(), derived(control=control, root=root)])
        for size in (1, 2, 6, 10, 14, 17):
            short = legacy.animation_record(101, "Short", 2, 2, transform_state=0x401,
                mode="", modern_prefix=b"\0" * 25 + b"\0" * size)
            cls.imported_fixtures[f"imported-bad-short-{size}.mdl"] = legacy.build_mdl([
                source(), short])
        for label, tail in (("zero", b"\0"), ("one", b"\1"), ("two", b"\0\0")):
            cls.imported_fixtures[f"imported-tail-{label}.mdl"] = (
                cls.imported_fixtures["imported-same-id.mdl"] + tail)
        constant = [(0, 0, 0, 0, 0, 0, 1, 1, 1)] * 3
        cls.imported_fixtures["imported-channels.mdl"] = legacy.build_mdl([
            source(), derived(auxiliary=True, alpha_by_bone=[[1, .5, 0], [.25, .5, 1]],
                track_states=[1, 0], track_samples={0: constant},
                events=[legacy.event_record(-3, {"name": "cue Ω", "frame": 1})])])
        paths = []
        for name, data in cls.imported_fixtures.items():
            path = Path(cls._tmp.name) / name
            path.write_bytes(data)
            paths.append(path)
        completed = subprocess.run([str(cls.binary), *map(str, paths)], capture_output=True, text=True)
        if completed.returncode:
            raise AssertionError(f"imported harness failed:\n{completed.stderr}")
        cls.imported_raw_output = completed.stdout
        cls.results.update({item["file"]: item for item in json.loads(completed.stdout)})

    def test_source_and_clip_ids_are_separate_and_samples_are_not_sliced_twice(self):
        entry = self.results["imported-same-id.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual([r["id"] for r in entry["records"]], [101, 101])
        self.assertEqual([r["recordOrdinal"] for r in entry["records"]], [0, 1])
        self.assertEqual([r["recordOrdinal"] for r in entry["animations"]], [1])
        clip = entry["animations"][0]
        self.assertEqual(clip["derivedSource"], {"sourceRecordOrdinal": 0,
            "firstFrame": 1, "endFrame": 3, "control": 0, "rootSelector": -1})
        self.assertEqual((clip["rawMode"], clip["mode"], clip["rawFlags"]), ("", "loop", 0x401))
        self.assertEqual(clip["sampleCounts"], [3, 3])
        self.assertEqual([clip["firstTransform"][1], clip["lastTransform"][1]], [0, 4])
        self.assertIsNone(entry["records"][0]["derivedSource"])

    def test_renamed_ids_resources_and_source_ordinals_keep_reference_identity(self):
        for name, expected_id, ordinal, end in (("renamed-resource-Σ.mdl", 712, 1, 6),
                ("imported-two-source-ids.mdl", 331, 1, 9),
                ("imported-range-zero.mdl", 101, 0, 2)):
            with self.subTest(name=name):
                entry = self.results[name]
                self.assertTrue(entry["ok"], entry)
                self.assertEqual(len(entry["animations"]), 1)
                clip = entry["animations"][0]
                self.assertEqual(clip["id"], expected_id)
                self.assertEqual(clip["derivedSource"]["sourceRecordOrdinal"], ordinal)
                self.assertEqual(clip["derivedSource"]["endFrame"], end)

    def test_only_qualified_23_derived_empty_mode_canonicalizes(self):
        for mode in ("loop", "mirror", "single"):
            clip = self.results[f"imported-{mode}.mdl"]["animations"][0]
            self.assertEqual((clip["rawMode"], clip["mode"]), (mode, mode))
        for name in ("old23-bad-empty.mdl", "imported-bad-full-mode.mdl",
                     "imported-bad-mode.mdl", "imported-bad-21.mdl"):
            self.assertFalse(self.results[name]["ok"], self.results[name])
        self.assertTrue(self.results["old23-zero-full-tail.mdl"]["ok"])
        old = self.results["valid.mdl"]
        self.assertEqual(old["animations"], old["records"])

    def test_reference_scope_and_unknown_semantics_fail_with_typed_reasons(self):
        for name in self.imported_fixtures:
            if name.startswith("imported-bad-"):
                with self.subTest(name=name):
                    entry = self.results[name]
                    self.assertFalse(entry["ok"], entry)
                    if "-reference-" in name:
                        self.assertIn("invalid MDLA derived source", entry["error"])
                    elif "-flags-" in name:
                        self.assertIn("flags " + name.removesuffix(".mdl").rsplit("-", 1)[1],
                                      entry["error"])
                    elif "-control-" in name:
                        self.assertIn("derived control", entry["error"])

    def test_all_records_channels_and_new_profile_tail_are_preserved(self):
        entry = self.results["imported-channels.mdl"]
        self.assertTrue(entry["ok"], entry)
        clip = entry["animations"][0]
        self.assertEqual(clip, entry["records"][1])
        self.assertEqual(clip["trackStates"], [1, 0])
        self.assertEqual(clip["alphaByBone"], [[1, .5, 0], [.25, .5, 1]])
        self.assertTrue(clip["hasAuxiliaryScalarTrack"])
        self.assertEqual(clip["events"], [{"name": "cue Ω", "frame": 1, "recordedTime": -3}])
        self.assertTrue(self.results["imported-tail-zero.mdl"]["ok"])
        for name in ("imported-tail-one.mdl", "imported-tail-two.mdl"):
            self.assertFalse(self.results[name]["ok"], self.results[name])

    def test_actual_catalog_and_default_34_keep_source_record_separate(self):
        if not self.direct_path:
            self.skipTest("set MWX_TEST_DIRECT_MODEL_ANIMATION_MDL to the isolated original model")
        entry = self.results[Path(self.direct_path).name]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual([r["id"] for r in entry["records"]],
            [28, 34, 32, 30, 28, 33, 37, 40, 43, 35, 29, 31, 39, 44, 49, 52, 55])
        self.assertEqual([r["recordOrdinal"] for r in entry["animations"]], list(range(1, 17)))
        self.assertEqual([r["id"] for r in entry["animations"]].count(28), 1)
        self.assertEqual(entry["records"][0]["frameCount"], 1322)
        for record in entry["animations"]:
            self.assertEqual((record["rawMode"], record["mode"], record["rawFlags"]),
                             ("", "loop", 0x401))
            self.assertEqual(record["derivedSource"]["sourceRecordOrdinal"], 0)
        clip = next(r for r in entry["animations"] if r["id"] == 34)
        self.assertEqual((clip["fps"], clip["frameCount"], clip["trackCount"]), (30, 16, 53))
        self.assertEqual(clip["sampleCounts"], [17] * 53)
        self.assertEqual(clip["trackStates"], [0] * 53)
        self.assertEqual(clip["derivedSource"], {"sourceRecordOrdinal": 0,
            "firstFrame": 814, "endFrame": 830, "control": 0, "rootSelector": -1})
        self.assertFalse(clip["hasAlphaContribution"])
        self.assertFalse(clip["hasAuxiliaryScalarTrack"])
        self.assertEqual(clip["events"], [])


if __name__ == "__main__":
    unittest.main()
