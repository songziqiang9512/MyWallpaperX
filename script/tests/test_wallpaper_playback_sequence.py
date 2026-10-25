"""Pure mixed-source sequence/deadline behavior; not a renderer handoff proof."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class WallpaperPlaybackSequenceTests(unittest.TestCase):
    def test_sequence_commits_navigation_and_monotonic_budget(self):
        paths = ["MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperLibraryPage.swift",
                 "MyWallpaperX/Core/PlaybackControl/WallpaperRuntimeSwitch.swift",
                 "MyWallpaperX/Core/PlaybackControl/PlaybackSwitchTransaction.swift",
                 "MyWallpaperX/Core/PlaybackControl/WallpaperPlaybackSequence.swift",
                 "MyWallpaperX/Core/PlaybackControl/WallpaperRotationDeadline.swift",
                 "script/tests/fixtures/WallpaperPlaybackSequenceHarness.swift"]
        hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-playback-sequence-", dir="/private/tmp") as folder:
            work = Path(folder)
            for path in paths:
                shutil.copy2(ROOT / path, work / Path(path).name)
            binary = work / "checks"
            compile = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *[str(work / Path(p).name) for p in paths], "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(compile.returncode, 0, compile.stdout + compile.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(hashes, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__":
    unittest.main()
