"""Real online-image disk publication with isolated files and cancellation probes.

The fixture supplies already-validated bytes: no image decoding, network, login,
App build, user media or desktop mutation is performed here.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class OnlineImageLibraryStoreTests(unittest.TestCase):
    def test_local_manifest_revision_publication_and_cancellation(self):
        paths = ["MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
                 "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift",
                 "MyWallpaperX/Core/OnlineImages/OnlineImageLibraryStore.swift",
                 "script/tests/fixtures/OnlineImageLibraryStoreHarness.swift"]
        identities = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-online-image-store-", dir="/private/tmp") as directory:
            work = Path(directory)
            for path in paths:
                shutil.copy2(ROOT / path, work / Path(path).name)
            actual = work / "OnlineImageLibraryStore.swift"
            source = actual.read_text()
            marker = "        try Task.checkCancellation()\n        try data.write(to: manifestURL, options: .atomic)"
            self.assertEqual(source.count(marker), 1)
            source = source.replace(marker,
                "        OnlineImageCommitProbe.shared.pause(at: .beforeCheck)\n" + marker +
                "\n        OnlineImageCommitProbe.shared.pause(at: .afterWrite)", 1)
            actual.write_text(source)
            home = work / "home"; home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            binary = work / "checks"
            sources = [str(work / Path(path).name) for path in paths]
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *sources, "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120, env=environment)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            data = work / "data"; data.mkdir()
            run = subprocess.run([str(binary), str(data)], capture_output=True, text=True, timeout=40, env=environment)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(identities, {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths})


if __name__ == "__main__":
    unittest.main()
