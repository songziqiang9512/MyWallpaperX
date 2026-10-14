#!/usr/bin/env python3
"""Value semantics and a reusable optimized CPU fixture for texture overlays."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_frame_texture_registry import SWIFT_SOURCES


FIXTURE = Path(__file__).with_name("fixtures") / "SceneTextureSnapshotOverlayHarness.swift"


def compile_fixture(directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / "texture-snapshot-overlays"
    command = [
        "xcrun", "--sdk", "macosx", "swiftc", "-O", "-parse-as-library",
        *(str(path) for path in SWIFT_SOURCES), str(FIXTURE),
        "-module-cache-path", str(directory / "module-cache"), "-o", str(binary),
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    (directory / "compile-command.json").write_text(json.dumps(command, indent=2))
    (directory / "compile.log").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise AssertionError(result.stderr)
    return binary


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneTextureSnapshotOverlayTests(unittest.TestCase):
    def test_independent_atoms_digest_branches_and_retirement(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-snapshot-overlay-") as name:
            binary = compile_fixture(Path(name))
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            if not payload["metalAvailable"]:
                self.skipTest("Metal is unavailable")
            self.assertIn("sameSelectionNewPhysicalAtom", payload["checks"])
            self.assertIn("explicitBranchRetiresAtLastValue", payload["checks"])
            for key, passed in payload["checks"].items():
                self.assertTrue(passed, key)


if __name__ == "__main__":
    unittest.main()
