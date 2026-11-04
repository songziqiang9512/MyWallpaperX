#!/usr/bin/env python3
"""Authored Between/Maintain inputs through the production parser and simulator."""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_particle_simulator import SWIFT_SOURCES


FIXTURE = Path(__file__).parent / "fixtures/SceneParticleControlPointComponentsHarness.swift"


class SceneParticleControlPointComponentsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-cp-components-")
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        cls.payloads = {}
        for mode, flags in (("debug", ["-D", "DEBUG"]), ("release", [])):
            binary = directory / mode
            compiled = subprocess.run(
                [swiftc, "-O", *flags, "-module-cache-path", str(directory / "module-cache"),
                 *map(str, SWIFT_SOURCES), str(FIXTURE), "-o", str(binary)],
                capture_output=True, text=True, timeout=180,
            )
            if compiled.returncode:
                raise RuntimeError(f"{mode} compilation failed:\n{compiled.stdout}\n{compiled.stderr}")
            actual = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            if actual.returncode:
                raise RuntimeError(f"{mode} execution failed:\n{actual.stdout}\n{actual.stderr}")
            print(f"{mode}: {actual.stdout}{actual.stderr}")
            cls.payloads[mode] = json.loads(actual.stdout)

    def assertCases(self, prefix: str) -> None:
        for mode, payload in self.payloads.items():
            cases = {key: value for key, value in payload["results"].items() if key.startswith(prefix)}
            self.assertTrue(cases, f"missing {prefix} cases in {mode}")
            for name, passed in cases.items():
                with self.subTest(mode=mode, case=name):
                    self.assertTrue(passed, f"{name}: {payload['observed']}")

    def test_defaults_renaming_and_unrelated_fields(self) -> None:
        self.assertCases("parse/")

    def test_literal_repeat_mirror_and_count_inputs(self) -> None:
        self.assertCases("sequence/")

    def test_independent_position_velocity_size_and_count_bits(self) -> None:
        self.assertCases("flags/")

    def test_unavailable_endpoint_and_partial_options_are_local(self) -> None:
        self.assertCases("failure/")

    def test_maintain_current_position_history_and_newborn_boundaries(self) -> None:
        self.assertCases("maintain/")

    def test_world_points_use_the_supplied_transform(self) -> None:
        self.assertCases("world/")

    def test_explicit_prefix_context_and_transaction_restore(self) -> None:
        self.assertCases("explicit/")

    def test_debug_and_release_behavior_agree(self) -> None:
        self.assertEqual(self.payloads["debug"]["results"], self.payloads["release"]["results"])


if __name__ == "__main__":
    unittest.main()
