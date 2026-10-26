"""Freeze the real Foundation session lifetime owner against local URLProtocol fixtures.

No real HTTP, credentials, WebViews, App construction, or native windows.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "Foundation URLSession requires macOS")
class WallpaperNetworkSessionTests(unittest.TestCase):
    def test_retirement_task_creation_and_cancellation(self):
        sources = [ROOT / "MyWallpaperX/Shared/WallpaperNetworkSession.swift",
                   ROOT / "script/tests/fixtures/WallpaperNetworkSessionHarness.swift"]
        with tempfile.TemporaryDirectory(prefix="mwx-network-session-", dir="/private/tmp") as directory:
            work = Path(directory)
            home = work / "home"
            home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            frozen = []
            for source in sources:
                target = work / source.name
                target.write_bytes(source.read_bytes())
                frozen.append(str(target))
            build = subprocess.run(
                ["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                 "-target", "arm64-apple-macos26.0", "-warnings-as-errors", "-parse-as-library",
                 *frozen, "-module-cache-path", str(work / "modules"), "-o", str(work / "checks")],
                capture_output=True, text=True, env=environment, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(work / "checks")], capture_output=True, text=True,
                                 env=environment, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("Wallpaper network-session lifetime checks passed", run.stdout)


if __name__ == "__main__":
    unittest.main()
