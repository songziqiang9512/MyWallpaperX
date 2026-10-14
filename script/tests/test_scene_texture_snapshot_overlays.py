#!/usr/bin/env python3
"""Value semantics and a reusable optimized CPU fixture for texture overlays."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_frame_texture_registry import SWIFT_SOURCES, TEST_ACCESS_SOURCE


FIXTURE = Path(__file__).with_name("fixtures") / "SceneTextureSnapshotOverlayHarness.swift"
REGISTRY_TEST_ACCESS = TEST_ACCESS_SOURCE + r'''
extension SceneFrameTextureRegistry {
    func testSetResourceLessReady(_ texture: MTLTexture, for identity: SceneFrameTextureIdentity) {
        entries[identity] = Entry(status: .ready(texture), generation: frameEpoch, resource: nil)
    }
}
'''


def compile_fixture(directory: Path, *, module_cache: Path | None = None) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / "texture-snapshot-overlays"
    registry = next(path for path in SWIFT_SOURCES if path.name == "SceneFrameTextureRegistry.swift")
    test_registry = directory / registry.name
    test_registry.write_text(registry.read_text() + REGISTRY_TEST_ACCESS)
    sources = [test_registry if path == registry else path for path in SWIFT_SOURCES]
    command = [
        "xcrun", "--sdk", "macosx", "swiftc", "-O", "-parse-as-library",
        *(str(path) for path in sources), str(FIXTURE),
        "-module-cache-path", str(module_cache or directory / "module-cache"), "-o", str(binary),
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
