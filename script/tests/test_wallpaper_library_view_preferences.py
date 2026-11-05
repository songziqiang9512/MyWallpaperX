"""Current page preferences, geometry and facet sessions use the actual codec/query."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.test_wallpaper_library_query import instrument_catalog_preparations

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryViewPreferencesTests(unittest.TestCase):
    def test_frozen_preferences_preserve_context_without_replaying_old_owners(self):
        paths = ["MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
                 "MyWallpaperX/Models/WallpaperLibraryPage.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsController.swift",
                 "MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift",
                 "MyWallpaperX/Shell/WallpaperLibraryPresentation.swift",
                 "script/tests/fixtures/WallpaperLibraryViewPreferencesHarness.swift"]
        observed = paths + ['script/tests/test_wallpaper_library_view_preferences.py', 'script/tests/test_wallpaper_library_query.py']
        identities = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in observed}
        with tempfile.TemporaryDirectory(prefix="mwx-library-view-preferences-", dir="/private/tmp") as directory:
            work = Path(directory)
            for path in paths:
                shutil.copy2(ROOT / path, work / Path(path).name)
            query = work / 'WallpaperLibraryQuery.swift'
            query.write_text(instrument_catalog_preparations(query.read_text()))
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *[str(work / Path(p).name) for p in paths], "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work / "relationships.sqlite3")], capture_output=True, text=True, timeout=40)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name)
            print(json.dumps(checks, sort_keys=True))
            preparations = [line.removeprefix('FACET PREPARATIONS ').split()
                for line in run.stderr.splitlines() if line.startswith('FACET PREPARATIONS ')]
            expected = {'active-kinds', 'known-0', 'known-1', 'updated-catalog', 'failed-update',
                        'unknown-playlist', 'unknown-missing', 'uninitialized', *{f'empty-{i}' for i in range(5)}}
            self.assertEqual({label for label, _, _ in preparations}, expected, run.stderr)
            print(json.dumps({'facetPreparations': preparations}, sort_keys=True))
            for label, ceiling, count in preparations:
                with self.subTest(facet=label):
                    self.assertGreaterEqual(int(count), 0)
                    self.assertLessEqual(int(count), int(ceiling))
            self.assertEqual(identities, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in observed})


if __name__ == "__main__":
    unittest.main()
