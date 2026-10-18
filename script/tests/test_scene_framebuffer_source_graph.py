"""Actual graph base Program, pair color propagation and current-main identity.

The existing executor/finalizer/encoder/resource owners run unchanged. The
runtime bridge leaf obtains both DTO declarations directly from product code.
No App, terminal compositor, native projection, scene depth or parity claim.
"""
import json
from pathlib import Path
import shutil
import unittest

from script.tests import test_scene_resolved_material_graph_executor as graph


FIXTURE = Path(__file__).with_name("fixtures") / "SceneFramebufferSourceGraphChecks.swift"


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneFramebufferSourceGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        prefix, marker, _ = graph.HARNESS.partition("@main\nprivate enum Harness")
        assert marker, "shared actual executor support boundary missing"
        compiled, ran = graph.compile_lit_harness(graph.SUPPORT, prefix + FIXTURE.read_text())
        if compiled.returncode:
            raise AssertionError(compiled.stdout + compiled.stderr)
        if ran is None or ran.returncode:
            raise AssertionError(None if ran is None else ran.stdout + ran.stderr)
        cls.report = json.loads(ran.stdout)
        if not cls.report["metalAvailable"]:
            raise unittest.SkipTest("Metal unavailable")
        if "failure" in cls.report:
            raise AssertionError(cls.report)
        cls.rows = {row["name"]: row for row in cls.report["rows"]}

    def test_source_program_writes_same_pair_then_effect_preserves_straight_color(self):
        row = self.rows["program"]
        self.assertNotIn("failure", row, row)
        for key in ("gpu", "prepareDidNotWrite", "usesOriginalPair", "baseMatches", "effectMatches",
                    "finalIsStraight", "effectProgramExecuted"):
            self.assertTrue(row[key], (key, row))

    def test_wrong_frame_consumer_and_texture_reject_before_any_pair_write(self):
        for name in ("wrong-epoch", "wrong-consumer", "wrong-texture"):
            with self.subTest(name=name):
                row = self.rows[name]
                self.assertNotIn("failure", row, row)
                self.assertEqual(row["rejection"], "capture-rejected", row)
                self.assertTrue(row["typedFailurePreserved"], row)
                self.assertFalse(row["localizable"], row)
                self.assertTrue(row["gpu"], row)
                self.assertTrue(row["pairUntouched"], row)

    def test_source_failures_preserve_typed_cause_and_localize_only_color(self):
        for name, localizable in (("bind-color", True), ("bind-frame", False), ("pass-color", True)):
            with self.subTest(name=name):
                row = self.rows[name]
                self.assertNotIn("failure", row, row)
                self.assertTrue(row["typedFailurePreserved"], row)
                self.assertEqual(row["localizable"], localizable, row)
                self.assertTrue(row["gpu"], row)
                self.assertTrue(row["pairUntouched"], row)

    def test_ordinary_resource_source_still_uses_fixed_capture(self):
        row = self.rows["fixed"]
        self.assertNotIn("failure", row, row)
        for key in ("gpu", "prepareDidNotWrite", "usesOriginalPair", "baseMatches", "effectMatches",
                    "effectProgramExecuted"):
            self.assertTrue(row[key], (key, row))


if __name__ == "__main__":
    unittest.main()
