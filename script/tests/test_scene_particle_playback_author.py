#!/usr/bin/env python3
"""RF03 call boundary: unprepared generic layer never gains particle capability."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script"
FIXTURES = Path(__file__).parent / "fixtures"

class SceneParticlePlaybackAuthorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory(prefix="mwx-rf03-author-")
        cls.binary = Path(cls.workspace.name) / "author"
        sources = [SCRIPT / "SceneQuickJS.c", *sorted(SCRIPT.glob("SceneQuickJS*Host.c")),
                   *[SCRIPT / "QuickJSNG" / name for name in ("quickjs.c", "dtoa.c", "libregexp.c", "libunicode.c")],
                   FIXTURES / "SceneParticlePlaybackQuickJSHarness.c"]
        result = subprocess.run(["clang", "-std=c11", "-O0", "-I", str(SCRIPT), "-I", str(SCRIPT / "QuickJSNG"),
                                 *map(str, sources), "-lm", "-o", str(cls.binary)], capture_output=True, text=True)
        if result.returncode:
            cls.workspace.cleanup()
            raise AssertionError(result.stdout + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    def run_author(self, scenario):
        return subprocess.run([str(self.binary), str(FIXTURES / "SceneParticlePlaybackAuthorFixture.js"), str(scenario)],
                              capture_output=True, text=True)

    def test_real_layer_handle_control(self):
        result = self.run_author(0)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_four_methods_reject_unprepared_layer(self):
        # No observation has been published: all four calls must fail closed.
        # Prepared real-simulator acceptance lives in the transaction fixture.
        for scenario in (1, 2, 3, 4, 5, 6, 7, 101, 102, 103):
            with self.subTest(scenario=scenario):
                result = self.run_author(scenario)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("unavailable", result.stdout)

    def test_explicit_emit_stays_unsupported(self):
        result = self.run_author(8)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

if __name__ == "__main__":
    unittest.main()
