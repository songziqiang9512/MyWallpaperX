"""Exercise product commit/finalize against the real Combine grid subscription."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]


class GridPlaybackPublicationTests(unittest.TestCase):
    def test_grid_follows_finalized_execution_after_delayed_retirement(self):
        product = ROOT / 'MyWallpaperX'
        manager = product / 'Modules/VideoLibrary/Core'
        switching = (manager / 'WallpaperManager+RuntimeSwitching.swift').read_text()
        removal = (manager / 'WallpaperManager+Removal.swift').read_text()
        model = (manager / 'WallpaperManager.swift').read_text()
        core = product / 'Modules/SteamWorkshop/Core'
        accessors = (core / 'SteamWorkshopService+DownloadAccessors.swift').read_text()
        grid = (product / 'Modules/SteamWorkshop/UI/AppKitSteamWorkshopDownloadsGridView.swift').read_text()
        start = grid.index('        WallpaperManager.shared.objectWillChange')
        end = grid.index('.store(in: &cancellables)', start) + len('.store(in: &cancellables)')
        methods = '\n'.join(method(switching, signature) for signature in [
            '    func runSwitchEffects(', '    private func commitSwitch(',
            '    private func pruneSwitchSelection('])
        methods += '\n' + method(model, '    func beginPlaybackIntent(')
        methods += '\n' + '\n'.join(method(removal, signature) for signature in [
            '    func clearCurrentWallpaperReference(', '    func stopCurrentPlayback('])
        template = (ROOT / 'script/tests/fixtures/GridPlaybackPublicationChecks.swift').read_text()
        source = template.replace('// MANAGER_METHODS', methods)
        source = source.replace('// PLAYING_ACCESSOR', method(accessors, '    func isRecordCurrentlyPlaying('))
        source = source.replace('// GRID_SUBSCRIPTION', grid[start:end])
        with tempfile.TemporaryDirectory(prefix='mwx-grid-bar-', dir='/private/tmp') as directory:
            folder = Path(directory)
            harness = folder / 'Harness.swift'
            harness.write_text(source)
            executable = folder / 'checks'
            shared = product / 'Core/PlaybackControl'
            build = subprocess.run([
                'xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
                '-module-cache-path', str(folder / 'modules'),
                str(shared / 'WallpaperRuntimeSwitch.swift'),
                str(shared / 'PlaybackSwitchTransaction.swift'), str(harness),
                '-o', str(executable)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
            if proof := os.environ.get('MWX_GRID_PLAYBACK_PROOF_DIR'):
                output = Path(proof)
                output.mkdir(parents=True, exist_ok=True)
                (output / 'runtime.log').write_text(run.stdout + run.stderr)
                (output / 'harness.swift').write_text(source)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('playback publication passed', run.stdout)


if __name__ == '__main__':
    unittest.main()
