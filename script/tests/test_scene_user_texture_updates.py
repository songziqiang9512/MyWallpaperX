from __future__ import annotations

import importlib.util
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
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
            SCENE / "Resources/Assets/SceneResourceIndex.swift",
            SCENE / "Resources/Assets/SceneResourceView.swift",
            SCENE / "../SteamWorkshopStorage/ScenePlaybackSource.swift",
            SCENE / "Format/ScenePkgReader.swift",
            SCENE / "Resources/Assets/SceneResourceIdentity.swift",
            SCENE / "Resources/Assets/SceneResourceView+Backing.swift",
            SCENE / "Systems/Properties/SceneUserPropertyTextureLoader.swift",
            SCENE / "Runtime/Session/SceneDesktopWallpaperSession+UserTextures.swift",
            ROOT / "script/tests/fixtures/SceneUserTextureUpdateChecks.swift",
        ]
        source_hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
        receipt = {"module": __name__, "sourceSHA256Before": source_hashes,
                   "scope": "production Loader/Session/live-state; scripted file/Registry/Source/publication/Metal boundaries"}
        receipt_root = os.environ.get("MWX_SCENE_USER_TEXTURE_TEST_RECEIPT")
        with tempfile.TemporaryDirectory(prefix="mwx-user-texture-updates-") as directory:
            binary = Path(directory) / "checks"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(Path(directory) / "clang-cache")
            compile_argv = ["swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                *map(str, sources), "-module-cache-path", str(Path(directory) / "module-cache"), "-o", str(binary)]
            started = time.monotonic()
            compile_result = subprocess.run(compile_argv, env=environment,
                capture_output=True, text=True, timeout=120)
            receipt["compile"] = {"argv": compile_argv, "exitCode": compile_result.returncode,
                                  "seconds": time.monotonic() - started}
            cls.compiler_warnings = compile_result.stderr
            try:
                if compile_result.returncode:
                    raise RuntimeError(compile_result.stderr)
                started = time.monotonic()
                completed = subprocess.run([str(binary)], capture_output=True, text=True,
                                           env=environment, timeout=20)
                receipt["run"] = {"argv": [str(binary)], "exitCode": completed.returncode,
                                  "seconds": time.monotonic() - started}
                if completed.returncode:
                    raise RuntimeError(completed.stdout + "\n" + completed.stderr)
                cls.checks = json.loads(completed.stdout)
                receipt["checks"] = cls.checks
            finally:
                after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
                receipt["sourceSHA256After"] = after
                receipt["sourceDrift"] = [path for path, sha in source_hashes.items() if after[path] != sha]
                if receipt_root:
                    output = Path(receipt_root)
                    output.mkdir(parents=True, exist_ok=True)
                    (output / "execution.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
                    (output / "compile.stderr.log").write_text(compile_result.stderr)
                    (output / "compile.stdout.log").write_text(compile_result.stdout)
                    if "completed" in locals():
                        (output / "run.stderr.log").write_text(completed.stderr)
                        (output / "run.stdout.log").write_text(completed.stdout)
            if receipt["sourceDrift"]:
                raise RuntimeError("gate input changed: " + ", ".join(receipt["sourceDrift"]))

    def test_resource_and_value_transaction_counterexamples(self):
        self.assertTrue(self.checks)
        for name, passed in self.checks.items():
            with self.subTest(name=name):
                self.assertTrue(passed)

    def test_default_actor_isolation_has_no_warnings(self):
        self.assertNotIn("warning:", self.compiler_warnings)


if __name__ == "__main__":
    unittest.main()
