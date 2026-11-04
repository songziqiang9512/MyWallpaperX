"""Real value query: canonical membership, multi-select filters, codec and stable order."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


def instrument_catalog_preparations(source):
    """Observe full Resolver entries only in each serialized fixture process."""
    owner = 'nonisolated enum WallpaperLibraryQuery {'
    entry = '            try self.init(aliases: relationships.aliases)'
    if source.count(owner) != 1 or source.count(entry) != 1:
        raise AssertionError('Full query preparation boundary must be unique')
    return source.replace(owner, owner + '\n    nonisolated(unsafe) static var fullResolverInitializations = 0', 1).replace(
        entry, '            WallpaperLibraryQuery.fullResolverInitializations += 1\n' + entry, 1)


class WallpaperLibraryQueryTests(unittest.TestCase):
    def test_query_preserves_relationships_order_and_source_ownership(self):
        paths = ["MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
                 "MyWallpaperX/Models/WallpaperLibraryPage.swift",
                 "MyWallpaperX/Models/VideoWallpaper.swift",
                 "MyWallpaperX/Modules/VideoLibrary/Core/VideoLibraryContentProjection.swift",
                 "MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift",
                 "script/tests/fixtures/WallpaperLibraryQueryHarness.swift"]
        observed = paths + ['script/tests/test_wallpaper_library_query.py']
        identities = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in observed}
        with tempfile.TemporaryDirectory(prefix="mwx-library-query-", dir="/private/tmp") as directory:
            work = Path(directory)
            for path in paths:
                shutil.copy2(ROOT / path, work / Path(path).name)
            query_path = work / 'WallpaperLibraryQuery.swift'
            query = instrument_catalog_preparations(query_path.read_text())
            enum_marker = 'nonisolated enum WallpaperLibraryQuery {'
            self.assertEqual(query.count(enum_marker), 1, enum_marker)
            counters = ('resolverInitializations', 'locatorReads', 'membershipReads', 'favoriteDateReads', 'recentDateReads',
                        'contentResolutions', 'normalizedDTOs', 'unavailableDTOs', 'itemWrites', 'locatorWrites')
            query = query.replace(enum_marker, enum_marker + '\n' + '\n'.join(
                f'    nonisolated(unsafe) static var {name} = 0' for name in counters), 1)
            seams = {
                '            self.aliases = try WallpaperLibraryQuery.aliasMap(aliases)':
                    '            WallpaperLibraryQuery.resolverInitializations += 1\n            self.aliases = try WallpaperLibraryQuery.aliasMap(aliases)',
                '            for item in relationships.locators {':
                    '            for item in relationships.locators {\n                WallpaperLibraryQuery.locatorReads += 1\n',
                'items[key] = normalized':
                    'WallpaperLibraryQuery.itemWrites += 1; items[key] = normalized',
                '    private static func replacingReference(_ item: WallpaperContentItem, with reference: WallpaperReference) -> WallpaperContentItem {\n        WallpaperContentItem':
                    '    private static func replacingReference(_ item: WallpaperContentItem, with reference: WallpaperReference) -> WallpaperContentItem {\n        WallpaperLibraryQuery.normalizedDTOs += 1\n        return WallpaperContentItem',
                '    private static func unavailable(_ reference: WallpaperReference, locator: WallpaperLocator?) -> WallpaperContentItem {':
                    '    private static func unavailable(_ reference: WallpaperReference, locator: WallpaperLocator?) -> WallpaperContentItem {\n        WallpaperLibraryQuery.unavailableDTOs += 1',
                '            for member in relationships.members {':
                    '            for member in relationships.members {\n                WallpaperLibraryQuery.membershipReads += 1',
                '            for favorite in relationships.favorites {':
                    '            for favorite in relationships.favorites {\n                WallpaperLibraryQuery.favoriteDateReads += 1',
                '            for recent in relationships.recent {':
                    '            for recent in relationships.recent {\n                WallpaperLibraryQuery.recentDateReads += 1',
                '        func resolve(_ reference: WallpaperReference) throws -> WallpaperContentItem {\n':
                    '        func resolve(_ reference: WallpaperReference) throws -> WallpaperContentItem {\n            WallpaperLibraryQuery.contentResolutions += 1\n',
            }
            for marker, instrumented in seams.items():
                self.assertEqual(query.count(marker), 1, marker)
                query = query.replace(marker, instrumented, 1)
            locator_assignments = ['locators[try canonical(item.reference)] = item.locator', 'locators[key] = item.locator']
            self.assertEqual(sum(query.count(marker) for marker in locator_assignments), 1)
            for marker in locator_assignments:
                query = query.replace(marker, 'WallpaperLibraryQuery.locatorWrites += 1; ' + marker)
            query_path.write_text(query)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *[str(work / Path(p).name) for p in paths], "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name)
            print(json.dumps(checks, sort_keys=True))
            preparations = [line.removeprefix('CATALOG PREPARATIONS ').split()
                for line in run.stderr.splitlines() if line.startswith('CATALOG PREPARATIONS ')]
            self.assertTrue(preparations, run.stderr)
            print(json.dumps({'catalogPreparations': preparations}, sort_keys=True))
            for scope, pages, count in preparations:
                with self.subTest(scope=scope, pages=pages):
                    self.assertGreaterEqual(int(count), 0)
                    self.assertLessEqual(int(count), 0 if scope == 'query-empty' else 1)
            memberships = [line.removeprefix('MEMBERSHIP PREPARATIONS ').split()
                for line in run.stderr.splitlines() if line.startswith('MEMBERSHIP PREPARATIONS ')]
            self.assertEqual({name for name, _, _ in memberships},
                             {'three', 'repeated', 'second-name', 'duplicate-name', 'whitespace', 'empty', 'remote'})
            print(json.dumps({'membershipPreparations': memberships}, sort_keys=True))
            for name, count, budget in memberships:
                with self.subTest(memberships=name):
                    self.assertGreaterEqual(int(count), 0)
                    self.assertLessEqual(int(count), int(budget))
            single_work = [line.removeprefix('RESOLUTION WORK ').split()
                for line in run.stderr.splitlines() if line.startswith('RESOLUTION WORK ')]
            self.assertEqual({row[0] for row in single_work},
                {'tail', 'missing', 'no-locator', 'native', 'backing', 'repeated', 'updated', 'duplicates', 'empty'})
            self.assertTrue(all(len(row) == 7 and all(int(value) >= 0 for value in row[1:]) for row in single_work))
            print(json.dumps({'resolutionWork': single_work}, sort_keys=True))
            self.assertEqual(identities, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in observed})


if __name__ == "__main__":
    unittest.main()
