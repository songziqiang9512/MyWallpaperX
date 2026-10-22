"""Real Video arrow navigation against the former sort-then-filter contract.

The model, source context, sort/filter and navigation bodies are production
inputs. Only manager state is a recording boundary. Comparison counters observe
the actual sort closures; they do not replace the ordering expressions.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'MyWallpaperX'
SELECTION = APP / 'Modules/VideoLibrary/Core/WallpaperManager+Selection.swift'
CONTEXT = APP / 'Shell/WallpaperSelectionContext.swift'
SUPPORT = APP / 'Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift'
SETTINGS = APP / 'Models/WallpaperSettings.swift'
MODEL = APP / 'Models/VideoWallpaper.swift'
CONTROLS = APP / 'Models/WallpaperControls.swift'
FIXTURE = ROOT / 'script/tests/fixtures/VideoSelectionNavigationHarness.swift'
CHECKS = {
    'matrixArrowResultMatchesLegacySortThenFilter',
    'matrixSelectionWritesMatchHandledNavigation',
    'matrixNavigationLeavesInputsUnchanged',
    'settingsCategoryUsesRealLibraryFallback',
    'selectedTagOverridesCategoryAndSortKey',
    'equalNameKeysReverseTheirInputOrderWhenDescending',
    'unknownAndMaximumSizesKeepTheFormerTieOrder',
    'dateSortUsesLastUsedAndKeepsItsFormerTieOrder',
    'defaultSortIgnoresDescendingAndKeepsSourceOrder',
    'displayTitleFallbackSortDoesNotMakeThePathSearchable',
    'normalizedQueryMatchesTitlesAndTagsInVisibleOrder',
    'duplicateIDsStillLocateTheFirstVisibleOccurrence',
    'missingCurrentSelectionStillStartsFromIndexZero',
    'directionalBoundsAndColumnFallbackStayUnchanged',
    'emptyContextAndNoMatchDoNotWriteSelection',
    'multiSelectSearchFieldAndUnsupportedGuardsDoNotSortOrWrite',
    'explicitIgnoreSearchFieldStillNavigates',
    'largeNarrowSearchKeepsLegacySelection',
    'narrowSearchSortsOnlyMatchingInputs',
    'noMatchSearchDoesNoSortComparisons',
    'emptyQueryRetainsFullSortingInput',
    'defaultModeAlwaysAvoidsSortComparisons',
}


class VideoSelectionNavigationTests(unittest.TestCase):
    def test_real_navigation_order_guards_and_filtered_sort_work(self):
        paths = [SELECTION, CONTEXT, SUPPORT, SETTINGS, MODEL, CONTROLS, FIXTURE, Path(__file__)]

        def fingerprints():
            return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}

        identities = fingerprints()
        selection, context = SELECTION.read_text(), CONTEXT.read_text()
        support, settings = SUPPORT.read_text(), SETTINGS.read_text()
        sort = declaration(selection, '    func sortedWallpapers(')
        opening = sort.index('{')
        sort = sort[:opening + 1] + '\n        sortInputs.append(wallpapers.map(\\.id))' + sort[opening + 1:]
        for expression in [
            '$0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending',
            '($0.fileSize ?? Int64.max) < ($1.fileSize ?? Int64.max)',
            '$0.lastUsed < $1.lastUsed',
        ]:
            self.assertEqual(sort.count(expression), 1)
            sort = sort.replace(expression, 'sortComparisons += 1\n                return ' + expression)
        fragments = {
            '// PRODUCTION_VALUE_TYPES': '\n'.join([
                declaration(settings, 'public enum WallpaperSortMode:'),
                declaration(settings, 'public struct SortState:'),
                declaration(support, 'enum ImportContext:'),
                declaration(support, 'enum WallpaperRemovalScope {'),
                declaration(context, 'enum WallpaperSelectionContext:'),
            ]),
            '// PRODUCTION_MANAGER_METHODS': '\n'.join([
                declaration(selection, '    var favoriteWallpapers:'),
                declaration(selection, '    var normalizedSearchQuery:'),
                declaration(selection, '    func filterWallpapers('), sort,
                declaration(selection, '    func moveSingleSelectionByArrowKey('),
                declaration(selection, '    func setSingleSelection('),
                declaration(context, '    var currentSelectionContext:'),
            ]),
        }
        template = FIXTURE.read_text()
        for marker, fragment in fragments.items():
            self.assertEqual(template.count(marker), 1)
            template = template.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix='mwx-video-navigation-', dir='/private/tmp') as directory:
            work = Path(directory)
            proof = os.environ.get('MWX_VIDEO_NAVIGATION_PROOF_DIR')
            target = Path(proof) if proof else None
            if target:
                target.mkdir(parents=True, exist_ok=True)

            def save(name, value):
                if target:
                    (target / name).write_text(value)

            save('inputs.json', json.dumps({'inputs': identities,
                'transforms': ['sort entry input IDs', 'three real comparator counters with explicit return'],
                'flags': SWIFT_ISOLATION_FLAGS, 'scope': __doc__}, indent=2) + '\n')
            source = work / 'Harness.swift'
            source.write_text(template)
            binary = work / 'video-navigation'
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors',
                '-parse-as-library', str(MODEL), str(CONTROLS), str(source),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            save('compile.log', build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(identities, fingerprints())
            home = work / 'home'
            home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            save('runtime.log', run.stderr)
            save('stdout.log', run.stdout)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            save('checks.json', json.dumps(checks, indent=2) + '\n')
            self.assertEqual(set(checks), CHECKS)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed, run.stderr)
            self.assertEqual(identities, fingerprints())


if __name__ == '__main__':
    unittest.main()
