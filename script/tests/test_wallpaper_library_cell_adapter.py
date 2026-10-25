"""Full App cell adapter with native collection construction and recording media leaves.

No window, user library, scanner, decoder or network is started. Provider cards'
real button/geometry/thumbnail lifecycles remain covered by their native gates.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit")
class WallpaperLibraryCellAdapterTests(unittest.TestCase):
    def test_identity_state_callbacks_and_display_demand(self):
        sources = [ROOT / "MyWallpaperX" / path for path in (
            "Models/WallpaperReference.swift", "Models/WallpaperContent.swift", "Models/VideoWallpaper.swift",
            "App/WallpaperLibraryCellAdapter.swift", "Shared/Components/WallpaperCardInteractionView.swift")]
        sources.append(ROOT / "script/tests/fixtures/WallpaperLibraryCellAdapterHarness.swift")
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        with tempfile.TemporaryDirectory(prefix="mwx-cell-adapter-", dir="/private/tmp") as directory:
            work = Path(directory)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                "-default-isolation", "MainActor", *map(str, sources), "-module-cache-path", str(work / "modules"),
                "-o", str(binary)], capture_output=True, text=True, timeout=150)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"; home.mkdir()
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 27)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})


if __name__ == "__main__":
    unittest.main()
