"""Actual terminal owner: attachment pixels, preparation faults and budget order."""
import unittest
from pathlib import Path

from script.tests.test_scene_persistent_color_output import _compile_and_run


class ScenePersistentColorAttachmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        name = "ScenePersistentColorAttachmentHarness.swift"
        source = (Path(__file__).parent / "fixtures" / name).read_text()
        cls.result = _compile_and_run(name, source=source)

    def test_frame_eligibility_preserves_upstream_budget_and_lazy_demand(self):
        for name, passed in self.result["admissionChecks"].items():
            with self.subTest(name=name):
                self.assertTrue(passed, name)

    def test_actual_attachment_matches_complete_pixels_and_public_transfer(self):
        if not self.result["nativeSupported"]:
            self.skipTest("attachment PSO unavailable on this physical device; legacy admission checked")
        self.assertGreater(self.result["comparedPixels"], 1000)
        for name, passed in self.result["pixelChecks"].items():
            with self.subTest(name=name):
                self.assertTrue(passed, name)

    def test_optional_preparation_and_actual_terminal_encoder_failure_recover(self):
        if not self.result["nativeSupported"]:
            self.skipTest("attachment fault cases require a prepared physical-device PSO")
        for name, passed in self.result["failureChecks"].items():
            with self.subTest(name=name):
                self.assertTrue(passed, name)


if __name__ == "__main__":
    unittest.main()
