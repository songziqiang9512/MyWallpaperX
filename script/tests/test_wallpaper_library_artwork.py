"""Demand-lifetime playlist composition and delegation to original thumbnail owners.

Pixel producers are controlled leaves. Real provider decoding/cache/visibility
regressions remain in their nearest gates; this gate does not claim media decode.
Single-image selection, source alpha and cancellation use actual composed pixels.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryArtworkTests(unittest.TestCase):
    def test_visible_demand_identity_cancellation_composition_and_tint(self):
        paths = [ROOT / name for name in (
            "MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Models/WallpaperLibraryPage.swift", "MyWallpaperX/Shared/UI/WallpaperPlaylistArtwork.swift", "MyWallpaperX/Shared/UI/ListThumbnailTintSource.swift",
            "MyWallpaperX/App/WallpaperLibraryArtworkProvider.swift", "script/tests/fixtures/WallpaperLibraryArtworkHarness.swift")]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-artwork-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen = []
            for index, path in enumerate(paths):
                target = work / f"Source{index}.swift"
                target.write_bytes(path.read_bytes()); frozen.append(target)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor",
                *map(str, frozen), "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"; home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__": unittest.main()
