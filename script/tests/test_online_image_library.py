"""Actual shared image service, disk publication, ImageIO and playback intent.

Source, cookie preparation, credential, file transfer and thumbnail leaves are
controlled; the actual shared network lifetime is compiled unchanged.
Every Swift input is frozen before compilation so a concurrent product edit does
not alter the running harness. No App, WebView, network, keychain or user media.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "ImageIO and Combine require macOS")
class OnlineImageLibraryTests(unittest.TestCase):
    def test_async_consumers_queue_publication_and_playback_intent(self):
        paths = [
            "MyWallpaperX/Models/WallpaperReference.swift",
            "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageContentProjection.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageLibraryStore.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageLibrary.swift",
            "MyWallpaperX/Shared/WallpaperNetworkSession.swift",
            "MyWallpaperX/Core/PlaybackControl/ImportedVideoAutoplayGate.swift",
            "script/tests/fixtures/OnlineImageLibraryHarness.swift",
        ]
        with tempfile.TemporaryDirectory(prefix="mwx-online-image-service-", dir="/private/tmp") as directory:
            work = Path(directory)
            sources = work / "sources"; sources.mkdir()
            identities = {}
            frozen = []
            for path in paths:
                data = (ROOT / path).read_bytes()
                identities[path] = hashlib.sha256(data).hexdigest()
                target = sources / Path(path).name
                target.write_bytes(data)
                frozen.append(str(target))
            home = work / "home"; home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            binary = work / "checks"
            build = subprocess.run([
                "xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-target", "arm64-apple-macos26.0",
                "-warnings-as-errors", "-parse-as-library", *frozen,
                "-module-cache-path", str(work / "modules"), "-o", str(binary),
            ], capture_output=True, text=True, timeout=120, env=environment)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr + repr(identities))
            data = work / "data"; data.mkdir()
            run = subprocess.run([str(binary), str(data)], capture_output=True, text=True,
                                 timeout=60, env=environment)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr + repr(identities))
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 25)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            print(json.dumps(checks, sort_keys=True))


if __name__ == "__main__":
    unittest.main()
