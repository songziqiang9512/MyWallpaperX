from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


class SceneUserTextureUpdateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("swiftc unavailable")
        spec = importlib.util.spec_from_file_location("property_sources", ROOT / "script/tests/test_scene_property_live_update_state.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        sources = list(module.SWIFT_SOURCES) + [
            SCENE / "Systems/Properties/SceneUserPropertyTextureLoader.swift",
            SCENE / "Runtime/Session/SceneDesktopWallpaperSession+UserTextures.swift",
            ROOT / "script/tests/fixtures/SceneUserTextureUpdateChecks.swift",
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-user-texture-updates-") as directory:
            binary = Path(directory) / "checks"
            compile_result = subprocess.run(["swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                *map(str, sources), "-module-cache-path", str(Path(directory) / "module-cache"), "-o", str(binary)],
                capture_output=True, text=True)
            if compile_result.returncode:
                raise RuntimeError(compile_result.stderr)
            cls.compiler_warnings = compile_result.stderr
            completed = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            cls.checks = json.loads(completed.stdout)

    def test_resource_and_value_transaction_counterexamples(self):
        self.assertTrue(self.checks)
        for name, passed in self.checks.items():
            with self.subTest(name=name):
                self.assertTrue(passed)

    def test_default_actor_isolation_has_no_warnings(self):
        self.assertNotIn("warning:", self.compiler_warnings)


if __name__ == "__main__":
    unittest.main()
