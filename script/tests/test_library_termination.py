"""Production quit admission and FIFO flush with real SQLite failures.

Renderer/process and profile leaves are controlled; no wallpaper, window,
GPU process, user defaults, or real application termination is exercised.
SQLite trigger gates only suspend actual writes in the temporary database.
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


class LibraryTerminationTests(unittest.TestCase):
    def test_failed_quit_remains_usable_and_flush_waits_for_late_fifo(self):
        relative = [
            'Models/WallpaperReference.swift',
            'Models/WallpaperContent.swift',
            'Models/WallpaperLibraryPage.swift',
            'Core/LibraryCollections/UserCollectionsStore.swift',
            'Core/LibraryCollections/UserCollectionsController.swift',
            'Core/PlaybackControl/WallpaperRuntimeSwitch.swift',
            'Core/PlaybackControl/PlaybackSwitchTransaction.swift',
            'Core/PlaybackControl/WallpaperPlaybackSequence.swift',
        ]
        owner_paths = [ROOT / 'MyWallpaperX' / name for name in relative]
        delegate_path = ROOT / 'MyWallpaperX/App/AppDelegate.swift'
        app_path = ROOT / 'MyWallpaperX/App/MyWallpaperXApplication.swift'
        harness_path = ROOT / 'script/tests/fixtures/LibraryTerminationHarness.swift'
        observed = owner_paths + [delegate_path, app_path, harness_path]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        delegate, app = delegate_path.read_text(), app_path.read_text()
        fixture = harness_path.read_text()
        fixture = fixture.replace('// ACTUAL_TERMINATION_METHODS', '\n'.join(declaration(delegate, signature) for signature in (
            ' func applicationShouldTerminate(', ' private func replyAfterPlaybackProcessesExit(',
            ' private func prepareProductTermination(')))
        fixture = fixture.replace('// ACTUAL_APP_HELPERS', '\n'.join(declaration(app, signature) for signature in (
            '    @MainActor static func prepareLibraryForTermination(',
            '    @MainActor static func cancelLibraryTermination(',
            '    @MainActor static func flushLibraryBeforeTermination(')))
        with tempfile.TemporaryDirectory(prefix='mwx-library-termination-', dir='/private/tmp') as directory:
            work = Path(directory)
            copies = []
            for path in owner_paths:
                text = path.read_text()
                if path.name == 'UserCollectionsStore.swift':
                    # Test-only connection access, in the temporary source
                    # copy, installs SQLite triggers without product switches.
                    text += fixture.split('// SQL_GATE_EXTENSION_BEGIN\n')[1].split('// SQL_GATE_EXTENSION_END')[0]
                copied = work / path.name
                copied.write_text(text)
                copies.append(str(copied))
            fixture = fixture.split('// SQL_GATE_EXTENSION_BEGIN')[0]
            harness = work / 'Checks.swift'; harness.write_text(fixture)
            binary = work / 'checks'
            built = subprocess.run(['xcrun', 'swiftc', *SWIFT_ISOLATION_FLAGS, '-warnings-as-errors', '-parse-as-library',
                *copies, str(harness), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            checks = json.loads(ran.stdout)
            self.assertGreaterEqual(len(checks), 12)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            print(json.dumps(checks, sort_keys=True))
            self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == '__main__': unittest.main()
