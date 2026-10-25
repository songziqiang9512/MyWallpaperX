"""Real menu construction, native responder actions and sheet input domains.

The original capability gate controls only the key-window getter. The sheet
regression uses actual LaunchServices/native windows and NSApplication events.
"""
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.native_app_harness import prepare_native_app, run_native_app

ROOT = Path(__file__).resolve().parents[2]


class MainMenuCommandTests(unittest.TestCase):
    def test_native_sheet_key_equivalents_do_not_borrow_background_page_commands(self):
        paths = [ROOT / 'MyWallpaperX' / p for p in (
            'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
            'Shared/UI/WallpaperInspectorActions.swift', 'Shared/UI/WallpaperLibrarySheetPresentation.swift',
            'App/MainMenuBuilder.swift', 'App/MainWindowMenuCommands.swift')]
        paths.append(ROOT / 'script/tests/fixtures/NativeAppHarness.swift')
        delegate_path = ROOT / 'MyWallpaperX/App/AppDelegate.swift'
        commands_path = ROOT / 'MyWallpaperX/App/WallpaperLibraryCommands.swift'
        original_fixture = ROOT / 'script/tests/fixtures/MainMenuCommandsHarness.swift'
        sheet_fixture = ROOT / 'script/tests/fixtures/MainMenuSheetCommandsHarness.swift'
        inputs = [*paths, delegate_path, commands_path, original_fixture, sheet_fixture, Path(__file__), ROOT / 'script/tests/native_app_harness.py']
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        delegate = delegate_path.read_text()
        methods = declaration(delegate, ' func validateMenuItem(')
        actions = ['createPlaylist', 'import', 'undo', 'redo', 'selectAll', 'toggleMultiSelect', 'deleteSelected',
                   'focusSearch', 'zoomIn', 'zoomOut', 'setAsWallpaper', 'nextWallpaper', 'previousWallpaper',
                   'toggleFavorite', 'addToPlaylist', 'showInfo', 'preview', 'revealInFinder', 'navigateLibraryPage']
        methods += '\n' + '\n'.join(declaration(delegate, ' @objc func ' + name + 'MenuAction(') for name in actions)
        prelude = original_fixture.read_text().split('@main enum MainMenuCommandChecks')[0]
        fixture = prelude.replace('// ACTUAL_DELEGATE_MENU', methods).replace('// ACTUAL_FAVORITE_ACTION_STATE',
            declaration(commands_path.read_text(), 'nonisolated struct WallpaperLibraryFavoriteActionState')) + '\n' + sheet_fixture.read_text()
        with tempfile.TemporaryDirectory(prefix='mwx-menu-sheet-', dir='/private/tmp') as directory:
            work = Path(directory)
            copies = []
            for path in paths:
                copied = work / path.name
                shutil.copy2(path, copied)
                copies.append(str(copied))
            source = work / 'Checks.swift'; source.write_text(fixture)
            binary = prepare_native_app(work, 'MainMenuSheetChecks')
            with open('/private/tmp/mywallpaperx-checkpoint-build.flock', 'a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                built = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                    *copies, str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                    capture_output=True, text=True, timeout=120)
                self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
                ran = run_native_app(binary, timeout=35)
                self.assertEqual(ran.launch_returncode, 0, ran.stdout + ran.stderr)
                self.assertTrue(ran.stdout.strip().startswith('{'), ran.stdout + ran.stderr)
            checks = json.loads(ran.stdout)
            print(json.dumps(checks, sort_keys=True))
            self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})
            self.assertGreaterEqual(len(checks), 15)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, ran.stdout + ran.stderr)
    def test_native_menu_page_capabilities_and_responder_priority(self):
        paths = [ROOT / 'MyWallpaperX' / p for p in (
            'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
            'Shared/UI/WallpaperInspectorActions.swift', 'Shared/UI/WallpaperLibrarySheetPresentation.swift',
            'App/MainMenuBuilder.swift', 'App/MainWindowMenuCommands.swift')]
        delegate = (ROOT / 'MyWallpaperX/App/AppDelegate.swift').read_text()
        methods = declaration(delegate, ' func validateMenuItem(')
        actions = ['createPlaylist', 'import', 'undo', 'redo', 'selectAll', 'toggleMultiSelect', 'deleteSelected',
                   'focusSearch', 'zoomIn', 'zoomOut', 'setAsWallpaper', 'nextWallpaper', 'previousWallpaper',
                   'toggleFavorite', 'addToPlaylist', 'showInfo', 'preview', 'revealInFinder', 'navigateLibraryPage']
        methods += '\n' + '\n'.join(declaration(delegate, ' @objc func ' + name + 'MenuAction(') for name in actions)
        fixture = (ROOT / 'script/tests/fixtures/MainMenuCommandsHarness.swift').read_text().replace('// ACTUAL_DELEGATE_MENU', methods)
        fixture = fixture.replace('// ACTUAL_FAVORITE_ACTION_STATE', declaration(
            (ROOT / 'MyWallpaperX/App/WallpaperLibraryCommands.swift').read_text(), 'nonisolated struct WallpaperLibraryFavoriteActionState'))
        with tempfile.TemporaryDirectory(prefix='mwx-main-menu-', dir='/private/tmp') as directory:
            work = Path(directory); copies = []
            for path in paths:
                copied = work / path.name
                if path.name == 'MainWindowMenuCommands.swift':
                    # Replace only the native focus getter. Validation and all
                    # dispatched NSTextView / UndoManager calls stay intact.
                    text = path.read_text()
                    self.assertEqual(text.count('NSApp.keyWindow'), 1)
                    copied.write_text(text.replace('NSApp.keyWindow', 'MenuTestFocus.keyWindow'))
                else: shutil.copy2(path, copied)
                copies.append(str(copied))
            source = work / 'Checks.swift'; source.write_text(fixture)
            binary = work / 'checks'
            built = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *copies, str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            checks = json.loads(ran.stdout)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, ran.stderr)
            print(json.dumps(checks, sort_keys=True))


if __name__ == '__main__': unittest.main()
