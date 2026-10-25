"""Explicit local relocation through actual source workers and SQLite.

Only the native picker, runtime/cache leaves and Video durability acknowledgement
are controlled. No App, NSApplication, window, renderer or user media is opened.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_wallpaper_library_import import ROOT, actual_import_fixture
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS


class WallpaperLibraryRelocationTests(unittest.TestCase):
    def test_explicit_relocation_preserves_relationships_and_rejects_stale_proofs(self):
        paths, assembled, inputs = actual_import_fixture()
        fixture = ROOT / "script/tests/fixtures/WallpaperLibraryRelocationHarness.swift"
        inputs += [fixture, Path(__file__), ROOT / "script/tests/test_wallpaper_library_import.py"]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        prelude = assembled.split("@main struct WallpaperLibraryImportHarness")[0]
        with tempfile.TemporaryDirectory(prefix="mwx-library-relocation-", dir="/private/tmp") as directory:
            work = Path(directory)
            sources = []
            for index, path in enumerate(paths):
                content = (ROOT / path).read_text()
                if path.endswith("WallpaperLibraryImportCoordinator.swift"):
                    self.assertEqual(content.count("NSOpenPanel()"), 2)
                    content = content.replace("NSOpenPanel()", "RelocationOpenPanel()")
                copy = work / (str(index) + ".swift")
                copy.write_text(content)
                sources.append(str(copy))
            checks_source = work / "Checks.swift"
            checks_source.write_text(prelude + "\n" + fixture.read_text())
            binary = work / "checks"
            home = work / "home"; home.mkdir()
            with open("/private/tmp/mywallpaperx-checkpoint-build.flock", "a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-parse-as-library",
                    *sources, str(checks_source), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                    capture_output=True, text=True, timeout=150)
                self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
                run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=50,
                    env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 25)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, run.stdout + run.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})


if __name__ == "__main__":
    unittest.main()
