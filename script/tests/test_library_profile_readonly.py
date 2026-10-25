"""Recovery-state organization/import UI denial; real profile codec/owner
admission and successful apply are covered by test_personal_settings_import.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class LibraryProfileReadOnlyTests(unittest.TestCase):
    def test_recovery_organization_and_import_ui_denial(self):
        paths = ["MyWallpaperX/Models/VideoWallpaper.swift", "MyWallpaperX/Models/WallpaperIndexStartupChanges.swift",
                 "script/tests/fixtures/LibraryProfileReadOnlyHarness.swift",
                 "MyWallpaperX/Shared/UI/ModalPresentation.swift",
                 "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+ImportPresentation.swift",
                 "MyWallpaperX/Shared/UI/AppCenteredAlertPresentation.swift",
                 "MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift"]
        identities = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
        fixture = (ROOT / paths[2]).read_text()
        fixture = fixture.replace("// PRODUCTION_IMPORT_UI", declaration((ROOT / paths[4]).read_text(), "    func importVideos(presentingIn window:"))
        with tempfile.TemporaryDirectory(prefix="mwx-profile-readonly-", dir="/private/tmp") as folder:
            work = Path(folder)
            source = work / "Checks.swift"
            source.write_text(fixture)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                str(ROOT / paths[0]), str(ROOT / paths[1]), str(ROOT / paths[3]), str(ROOT / paths[5]), str(ROOT / paths[6]), str(source), "-module-cache-path", str(work / "modules"),
                "-o", str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name)
        self.assertEqual(identities, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__":
    unittest.main()
