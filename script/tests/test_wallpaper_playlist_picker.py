"""Real Picker, Grid, menu input domain and SQLite/FIFO member publication.

Provider pixels and runtime output are leaves. The sheet, selection, density,
canonical query, relationship transaction and menu dispatcher are production.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.test_main_menu_commands import browser_menu_fixture
from script.tests.test_wallpaper_library_query import instrument_catalog_preparations

ROOT = Path(__file__).resolve().parents[2]


class WallpaperPlaylistPickerTests(unittest.TestCase):
    def test_real_sheet_density_existing_members_focus_and_committed_lifetime(self):
        relative = [
            'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
            'Core/LibraryCollections/WallpaperLibraryQuery.swift', 'Core/LibraryCollections/UserCollectionsStore.swift',
            'Core/LibraryCollections/UserCollectionsController.swift',
            'Shared/Components/WallpaperLibraryControlStyle.swift',
            'Shared/UI/ListThumbnailTintSource.swift', 'Shared/UI/WallpaperLibrarySheetPresentation.swift',
            'Shared/Components/ActionMenuItem.swift', 'Shared/Components/WallpaperLibraryGridMetrics.swift',
            'Shared/Components/WallpaperLibraryZoomControl.swift', 'Shared/Components/WallpaperCardInteractionView.swift',
            'Shared/UI/WallpaperGridScrollView.swift', 'Shared/UI/BoxSelectionState.swift',
            'Shared/UI/GridThumbnailPrefetchDemand.swift', 'Shared/UI/WallpaperInspectorActions.swift',
            'Shell/WallpaperLibraryGridController.swift', 'App/WallpaperPlaylistPickerController.swift',
            'App/MainMenuBuilder.swift', 'App/MainWindowMenuCommands.swift',
        ]
        paths = [ROOT / 'MyWallpaperX' / path for path in relative]
        paths.append(ROOT / 'script/tests/fixtures/NativeAppHarness.swift')
        paths.append(ROOT / 'script/tests/fixtures/WallpaperLibraryModalInputChecks.swift')
        fixture = ROOT / 'script/tests/fixtures/WallpaperPlaylistPickerHarness.swift'
        menu_fixture = ROOT / 'script/tests/fixtures/MainMenuCommandsHarness.swift'
        delegate = ROOT / 'MyWallpaperX/App/AppDelegate.swift'
        commands = ROOT / 'MyWallpaperX/App/WallpaperLibraryCommands.swift'
        observed = [*paths, fixture, menu_fixture, delegate, commands, Path(__file__),
                    ROOT / 'script/tests/native_app_harness.py', ROOT / 'script/tests/test_ui_library_algorithms.py',
                    ROOT / 'script/tests/test_main_menu_commands.py', ROOT / 'script/tests/fixtures/MainMenuBrowserSelectionHarness.swift',
                    ROOT / 'MyWallpaperX/App/WallpaperLibraryWindowComposition.swift',
                    ROOT / 'script/tests/test_wallpaper_library_query.py']
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        prelude = menu_fixture.read_text().split('@main enum MainMenuCommandChecks')[0] + '\n' + browser_menu_fixture()
        controlled_picker = declaration(prelude, 'final class WallpaperPlaylistPickerController:')
        self.assertEqual(prelude.count(controlled_picker), 1)
        prelude = prelude.replace(controlled_picker, '')
        prelude = prelude.replace('// ACTUAL_FAVORITE_ACTION_STATE',
            declaration(commands.read_text(), 'nonisolated struct WallpaperLibraryFavoriteActionState'))
        methods = declaration(delegate.read_text(), ' func validateMenuItem(')
        for action in ['createPlaylist', 'import', 'undo', 'redo', 'toggleMultiSelect', 'deleteSelected',
                       'focusSearch', 'zoomIn', 'zoomOut', 'setAsWallpaper', 'nextWallpaper', 'previousWallpaper',
                       'toggleFavorite', 'addToPlaylist', 'showInfo', 'preview', 'revealInFinder', 'navigateLibraryPage', 'closeWindow']:
            methods += '\n' + declaration(delegate.read_text(), ' @objc func ' + action + 'MenuAction(')
        prelude = prelude.replace('// ACTUAL_DELEGATE_MENU', methods)
        template = fixture.read_text()
        self.assertEqual(template.count('// ACTUAL_CARD_STATE'), 1)
        template = template.replace('// ACTUAL_CARD_STATE', declaration(
            commands.read_text(), 'nonisolated struct WallpaperLibraryCardStateProjection'))
        with tempfile.TemporaryDirectory(prefix='mwx-playlist-picker-', dir='/private/tmp') as directory:
            work = Path(directory)
            copies = []
            for path in paths:
                copied = work / path.name
                if path.name == 'WallpaperLibraryQuery.swift':
                    copied.write_text(instrument_catalog_preparations(path.read_text()))
                elif path.name == 'WallpaperPlaylistPickerController.swift':
                    content = path.read_text()
                    refresh = declaration(content, '    private func refresh(')
                    self.assertEqual(content.count(refresh), 1)
                    start = '            var seen = Set<WallpaperReference>()'
                    end = '            let committed = manager.libraryPlaybackSequence.committed'
                    self.assertEqual(refresh.count(start), 1)
                    self.assertEqual(refresh.count(end), 1)
                    instrumented = refresh.replace(start, start + '\n            let preparationsBefore = WallpaperLibraryQuery.fullResolverInitializations', 1)
                    instrumented = instrumented.replace(end, '            FileHandle.standardError.write(Data("CATALOG PREPARATIONS picker \\(pages.count) \\(WallpaperLibraryQuery.fullResolverInitializations - preparationsBefore)\\n".utf8))\n' + end, 1)
                    content = content.replace(refresh, instrumented, 1)
                    copied.write_text(content)
                else:
                    shutil.copy2(path, copied)
                copies.append(str(copied))
            source = work / 'Checks.swift'
            source.write_text(prelude + '\n' + template)
            binary = prepare_native_app(work, 'WallpaperPlaylistPicker')
            build = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *copies, str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, (str(work / 'relations.sqlite3'),), timeout=60)
            diagnostic = f'LaunchServices={run.launch_returncode}\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}'
            self.assertEqual(run.launch_returncode, 0, diagnostic)
            self.assertTrue(run.stdout.strip(), diagnostic)
            try:
                checks = json.loads(run.stdout)
            except json.JSONDecodeError as error:
                self.fail(f'Picker native result missing: {error}\n{diagnostic}')
            print(json.dumps(checks, sort_keys=True))
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, diagnostic)
            preparations = [line.removeprefix('CATALOG PREPARATIONS ').split()
                for line in run.stderr.splitlines() if line.startswith('CATALOG PREPARATIONS ')]
            self.assertTrue({1, 2, 3}.issubset({int(pages) for _, pages, _ in preparations}), run.stderr)
            print(json.dumps({'catalogPreparations': preparations}, sort_keys=True))
            for scope, pages, count in preparations:
                with self.subTest(scope=scope, pages=pages):
                    self.assertGreaterEqual(int(count), 0)
                    self.assertLessEqual(int(count), 1)
            self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == '__main__':
    unittest.main()
