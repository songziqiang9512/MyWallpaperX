"""Real terminal ledger and read projection; no network, App or user media."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "Combine requires macOS")
class DownloadHistoryTests(unittest.TestCase):
    def test_terminal_import_clear_atomicity_and_namespaced_projection(self):
        inputs = [ROOT / path for path in (
            "MyWallpaperX/Models/WallpaperReference.swift",
            "MyWallpaperX/Models/DownloadTask.swift",
            "MyWallpaperX/Modules/Downloads/Core/DownloadHistoryStore.swift",
            "MyWallpaperX/Modules/Downloads/Core/DownloadTaskProjection.swift",
            "script/tests/fixtures/DownloadHistoryHarness.swift",
        )]
        identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        with tempfile.TemporaryDirectory(prefix="mwx-download-history-", dir="/private/tmp") as directory:
            work = Path(directory)
            frozen = []
            for path in inputs:
                target = work / path.name
                target.write_bytes(path.read_bytes())
                frozen.append(str(target))
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors",
                                    "-parse-as-library", *frozen, "-module-cache-path", str(work / "modules"),
                                    "-o", str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr + repr(identities))
            data = work / "data"
            data.mkdir()
            run = subprocess.run([str(binary), str(data)], capture_output=True, text=True, timeout=20,
                                 env=dict(os.environ, HOME=str(work), CFFIXED_USER_HOME=str(work)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr + repr(identities))
            self.assertIn("download-history-pass", run.stdout)


if __name__ == "__main__":
    unittest.main()
