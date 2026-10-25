"""Full native shared-grid keyboard semantics and released window/view leases.

Sorting/filtering/migration are Query and Presentation responsibilities. This
gate navigates the exact accepted display order without a copied sorter.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class LibraryKeyboardNavigationTests(unittest.TestCase):
    def test_native_four_direction_navigation_first_responder_and_retired_leases(self):
        paths = ["MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Models/WallpaperLibraryPage.swift", "MyWallpaperX/Shared/Components/WallpaperLibraryGridMetrics.swift",
            "MyWallpaperX/Shared/Components/WallpaperCardInteractionView.swift", "MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift",
            "MyWallpaperX/Shared/UI/BoxSelectionState.swift", "MyWallpaperX/Shared/UI/GridThumbnailPrefetchDemand.swift",
            "MyWallpaperX/Shell/WallpaperLibraryGridController.swift", "script/tests/fixtures/NativeAppHarness.swift",
            "script/tests/fixtures/LibraryKeyboardNavigationHarness.swift"]
        identities = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-library-keyboard-", dir="/private/tmp") as directory:
            work = Path(directory)
            for path in paths: shutil.copy2(ROOT / path, work / Path(path).name)
            binary = prepare_native_app(work, "LibraryKeyboardNavigation")
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *[str(work / Path(p).name) for p in paths], "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=45)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertEqual(len(checks), 15)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stdout + run.stderr)
        self.assertEqual(identities, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__":
    unittest.main()
