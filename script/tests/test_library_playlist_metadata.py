"""Real schema upgrade, cover/metadata transactions, Undo and hide receipts.

The only injected leaf is one SQLite COMMIT error; no media/source owner,
relationship writer or database method is doubled. No native App is launched.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [ROOT / "MyWallpaperX" / path for path in (
    "Models/WallpaperReference.swift",
    "Core/LibraryCollections/UserCollectionsStore.swift",
    "Core/LibraryCollections/UserCollectionsController.swift")]
FIXTURE = ROOT / "script/tests/fixtures/LibraryPlaylistMetadataHarness.swift"
SHIM = ROOT / "script/tests/fixtures/PlaylistMetadataSQLiteFault.c"


class LibraryPlaylistMetadataTests(unittest.TestCase):
    def test_real_metadata_assets_schema_upgrade_undo_and_conditional_exclusion(self):
        paths = SOURCES + [FIXTURE, SHIM]
        before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-playlist-metadata-", dir="/private/tmp") as directory:
            work = Path(directory)
            dylib = work / "libPlaylistMetadataFault.dylib"
            build_c = subprocess.run(["xcrun", "clang", "-dynamiclib", "-Wall", "-Wextra", "-Werror",
                str(SHIM), "-lsqlite3", "-o", str(dylib)], capture_output=True, text=True, timeout=60)
            self.assertEqual(build_c.returncode, 0, build_c.stdout + build_c.stderr)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors",
                "-parse-as-library", *map(str, SOURCES), str(FIXTURE), "-L", str(work),
                "-lPlaylistMetadataFault", "-Xlinker", "-rpath", "-Xlinker", str(work),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"; home.mkdir()
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=45,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            report = json.loads(run.stdout)
            self.assertGreaterEqual(len(report), 30)
            for name, passed in report.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            if output := os.environ.get("MWX_COLLECTIONS_PROOF_DIR"):
                proof = Path(output); proof.mkdir(parents=True, exist_ok=True)
                (proof / "playlist-metadata-report.json").write_text(json.dumps(report, indent=2) + "\n")
                (proof / "playlist-metadata-build.log").write_text(build_c.stdout + build_c.stderr + build.stdout + build.stderr)
        self.assertEqual(before, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths})


if __name__ == "__main__":
    unittest.main()
