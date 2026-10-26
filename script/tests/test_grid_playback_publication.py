"""Real Manager/transaction success -> Workspace publication -> shared CardState.

The canonical committed output owns UI; delayed renderer bookkeeping/retirement
must neither override nor duplicate it. Native rendering is outside this gate.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_imported_video_autoplay_gate import GATE_SOURCES, MANAGER, product_harness
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class GridPlaybackPublicationTests(unittest.TestCase):
    def test_grid_follows_committed_selection_through_delayed_retirement(self):
        product = ROOT / 'MyWallpaperX'
        source = product_harness()
        source = source.replace('func stopCurrentPlayback(){_ = beginPlaybackIntent();currentWallpaper=nil;pendingWallpaper=nil;isPlaying=false;stopAutoSwitchTimer()}', '')
        source = source.replace('var libraryPlaybackStopped:(()->Void)?', 'var libraryPlaybackStopped:(()->Void)?\n    var libraryPlaybackResetRequested:(()->Void)?\n    var libraryBackingPublished:((WallpaperContentBackingPublication)->Void)?')
        removal = (MANAGER / 'WallpaperManager+Removal.swift').read_text()
        source += '\nextension WallpaperManager {\n' + '\n'.join(declaration(removal, signature) for signature in (
            '    func clearCurrentWallpaperReference(', '    func stopCurrentPlayback(')) + '\n}\n'
        routing = (MANAGER / 'WallpaperManager+RuntimeSwitching.swift').read_text()
        source += '\nextension WallpaperManager {\n' + '\n'.join(declaration(routing, signature) for signature in (
            '    func prepareSceneDownloadRemoval(', '    private func sceneSelection(')) + '\n}\n'
        source = source.replace('@MainActor final class WallpaperManager: ObservableObject {', '''@MainActor final class WallpaperManager: ObservableObject {
    var pendingManualNavigationWorkItem:DispatchWorkItem?
    var pendingManualNavigationDirection:Int?
''', 1)
        source = source.replace('var autoSwitchTimer:Timer?', 'var autoSwitchTimer:PublicationTimer?')
        source = source.replace('let timer = Timer(timeInterval:', 'let timer = PublicationTimer(timeInterval:')
        source = source.replace('RunLoop.main.add(timer, forMode: .common)', 'PublicationTimer.add(timer)')
        workspace = (product / 'App/WallpaperLibraryWorkspace.swift').read_text()
        commands = (product / 'App/WallpaperLibraryCommands.swift').read_text()
        composition = (product / 'App/WallpaperLibraryWindowComposition.swift').read_text()
        start = composition.index('        workspace.playbackChanges.sink')
        end = composition.index('.store(in: &subscriptions)', start) + len('.store(in: &subscriptions)')
        subscription = composition[start:end].replace('&subscriptions', '&cancellables')
        fixture = (ROOT / 'script/tests/fixtures/GridPlaybackPublicationChecks.swift').read_text()
        fixture = fixture.replace('// WORKSPACE_BINDINGS', declaration(workspace, '    private func installPlaybackBindings('))
        self.assertEqual(fixture.count('// CARD_STATE_PROJECTION'), 1)
        fixture = fixture.replace('// CARD_STATE_PROJECTION', '\n'.join(declaration(commands, signature) for signature in (
            'nonisolated struct WallpaperLibraryFavoriteActionState',
            'nonisolated struct WallpaperLibraryCardStateProjection')))
        fixture = fixture.replace('// GRID_SUBSCRIPTION', subscription)
        with tempfile.TemporaryDirectory(prefix='mwx-grid-bar-', dir='/private/tmp') as directory:
            folder = Path(directory)
            harness = folder / 'Harness.swift'; harness.write_text(source + '\n' + fixture)
            executable = folder / 'checks'
            paths = [*GATE_SOURCES, product / 'Models/WallpaperContent.swift', product / 'Core/LibraryCollections/WallpaperLibraryQuery.swift']
            copies = []
            for path in paths:
                copy = folder / path.name; copy.write_bytes(path.read_bytes()); copies.append(str(copy))
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
                '-module-cache-path', str(folder / 'modules'), *copies, str(harness), '-o', str(executable)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
            if proof := os.environ.get('MWX_GRID_PLAYBACK_PROOF_DIR'):
                output = Path(proof); output.mkdir(parents=True, exist_ok=True)
                (output / 'runtime.log').write_text(run.stdout + run.stderr)
                (output / 'harness.swift').write_text(source + '\n' + fixture)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('playback publication passed: 16 runtime pairs', run.stdout)


if __name__ == '__main__': unittest.main()
