"""The full window toolbar with native menus and real multiselect query state.

Commands and remote controls are recording leaves; their transaction/media
contracts have separate gates. This does not exercise a full App window.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class LibraryWindowToolbarTests(unittest.TestCase):
    def test_native_menu_toolbar_and_fixed_page_query_routing(self):
        relative = [
            'Models/WallpaperReference.swift', 'Models/WallpaperContent.swift', 'Models/WallpaperLibraryPage.swift',
            'Core/OnlineImages/OnlineImageModels.swift',
            'Core/LibraryCollections/UserCollectionsStore.swift', 'Core/LibraryCollections/UserCollectionsController.swift',
            'Core/LibraryCollections/WallpaperLibraryQuery.swift', 'Shell/WallpaperLibraryPresentation.swift',
            'Shared/Components/ActionMenuItem.swift', 'Shared/Components/WallpaperLibraryControlStyle.swift', 'Shared/Components/WallpaperLibraryGridMetrics.swift',
            'Shared/Components/WallpaperLibraryZoomControl.swift', 'App/WallpaperLibraryWindowToolbar.swift',
            'Shared/UI/WallpaperFilterPanelController.swift', 'Shared/UI/ToolbarMenuPopover.swift',
        ]
        paths = [Path(os.environ.get('MWX_LIBRARY_TOOLBAR_SOURCE', ROOT / 'MyWallpaperX' / name))
                 if name == 'App/WallpaperLibraryWindowToolbar.swift' else ROOT / 'MyWallpaperX' / name for name in relative]
        paths.append(ROOT / 'script/tests/fixtures/NativeAppHarness.swift')
        paths.append(ROOT / 'script/tests/fixtures/NativeFilterPanelSnapshot.swift')
        fixture = ROOT / 'script/tests/fixtures/LibraryWindowToolbarHarness.swift'
        sheet = ROOT / 'MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift'
        observed = paths + [sheet, fixture, Path(__file__).resolve(), ROOT / 'script/tests/native_app_harness.py']
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        with tempfile.TemporaryDirectory(prefix='mwx-window-toolbar-', dir='/private/tmp') as directory:
            work = Path(directory)
            copies = []
            for path in paths:
                copied = work / path.name
                if path.name == 'WallpaperLibraryWindowToolbar.swift':
                    source = path.read_text()
                    for name in ('makeFilterPanel', 'makeDownloadFilterMenu'):
                        marker = '    private func ' + name + '('
                        self.assertEqual(source.count(marker), 1)
                        source = source.replace(marker, '    func ' + name + '(', 1)
                    copied.write_text(source)
                else:
                    shutil.copy2(path, copied)
                copies.append(str(copied))
            harness = work / 'Checks.swift'
            harness.write_text('import AppKit\n' + declaration(sheet.read_text(), '@MainActor enum WallpaperLibrarySheetPresentation') + '\n'
                + declaration(sheet.read_text(), '@MainActor class WallpaperLibraryModalPanel:') + '\n' + fixture.read_text())
            binary = prepare_native_app(work, 'LibraryWindowToolbar')
            built = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *copies, str(harness), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            try:
                ran = run_native_app(binary, [str(work)], timeout=35)
            finally:
                if output := os.environ.get('MWX_LIBRARY_TOOLBAR_PROOF_DIR'):
                    proof = Path(output); proof.mkdir(parents=True, exist_ok=True)
                    for name in ('native-app.stdout', 'native-app.stderr', 'native-app.pid'):
                        if (work / name).exists(): shutil.copy2(work / name, proof / name)
                    (proof / 'inputs.json').write_text(json.dumps(hashes, indent=2))
            self.assertEqual(ran.launch_returncode, 0, ran.stdout + ran.stderr)
            self.assertTrue(ran.stdout.strip(), ran.stderr)
            checks = json.loads(ran.stdout)
            self.assertGreaterEqual(len(checks), 25)
            print(json.dumps(checks, sort_keys=True))
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, ran.stdout + ran.stderr)
            self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == '__main__': unittest.main()
