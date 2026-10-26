"""Real Manager request/stage/commit, App provider dispatch and source-bound clocks.

Native renderer, provider file preparation, desktop workspace and Timer delivery
are controlled leaves. This does not render media or claim visual/runtime parity.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_imported_video_autoplay_gate import GATE_SOURCES, MANAGER, product_harness
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryPlaybackTests(unittest.TestCase):
    def test_typed_provider_dispatch_and_original_product_commit(self):
        source = product_harness()
        source = source.replace('import Foundation', 'import AppKit\nimport Foundation', 1)
        source = source.replace('func isSwitchingPlaybackMode()->Bool{true}', 'func isSwitchingPlaybackMode()->Bool{mode != .loop}')
        source = source.replace('var autoSwitchEnabled=true,randomInterval=', 'var volume:Double=100\n        var autoSwitchEnabled=true,randomInterval=')
        source = source.replace('func stopCurrentPlayback(){_ = beginPlaybackIntent();currentWallpaper=nil;pendingWallpaper=nil;isPlaying=false;stopAutoSwitchTimer()}', '')
        source = source.replace('@discardableResult func advanceLibraryPlayback(cause:WallpaperPlaybackCause)->Bool{timerFires += 1;return false}', '')
        source = source.replace('func restoreSystemDesktopWallpaperOnTermination(){Trace.values.append("restoreDesktop")}', '')
        fields = '''
    enum PlaybackMode { case loop, sequential, random }
    var mode=PlaybackMode.sequential
    var pendingManualNavigationWorkItem:DispatchWorkItem?
    var pendingManualNavigationDirection:ManualNavigationDirection?
    func playbackMode()->PlaybackMode{mode}
    func pathExists(_ path:String)->Bool{FileManager.default.fileExists(atPath:path)}
    func applySystemAudioSpectrumToEngine(){}
'''
        source = source.replace('@MainActor final class WallpaperManager: ObservableObject {',
                                '@MainActor final class WallpaperManager: ObservableObject {' + fields)
        manager_source = (MANAGER / 'WallpaperManager.swift').read_text()
        desktop_fields = declaration(manager_source, '    struct SystemDesktopWallpaper') + '''
    var systemDesktopWallpapers: [UInt32: SystemDesktopWallpaper] = [:]
    var didApplySystemStillThisRun = false
    var staticFrameCacheDirectory = URL(fileURLWithPath: "/private/tmp/unconfigured-desktop-cache")
    var thumbnailCacheDirectory = URL(fileURLWithPath: "/private/tmp/unconfigured-thumbnail-cache")
    func bumpCacheGeneration() {}
    func clearThumbnailMemoryCache() {}
    func clearThumbnailInFlight() {}
    func clearStaticFrameSchedule() {}
'''
        source = source.replace('@MainActor final class WallpaperManager: ObservableObject {',
                                '@MainActor final class WallpaperManager: ObservableObject {' + desktop_fields)
        routing = (MANAGER / 'WallpaperManager+RuntimeSwitching.swift').read_text()
        application = (MANAGER / 'WallpaperManager+WallpaperApplication.swift').read_text()
        removal = (MANAGER / 'WallpaperManager+Removal.swift').read_text()
        navigation = (MANAGER / 'WallpaperManager+PlaybackControl.swift').read_text()
        methods = '\n'.join([
            declaration(application, '    func setAsWallpaper('),
            declaration(removal, '    func clearCurrentWallpaperReference('),
            declaration(removal, '    func stopCurrentPlayback('),
            declaration(routing, '    func prepareSceneDownloadRemoval('),
            declaration(routing, '    private func sceneSelection('),
            declaration(routing, '    func switchLost('),
            declaration(routing, '    func setWebWallpaper('),
            declaration(routing, '    func setSceneWallpaper('),
            declaration(routing, '    func handleLibraryPlaybackPause('),
            declaration(navigation, '    var librarySequenceMode:'),
            declaration(navigation, '    func navigateLibraryPlayback('),
            declaration(navigation, '    func advanceLibraryPlayback('),
            declaration(navigation, '    func updateLibraryPlaybackSource('),
        ])
        still = declaration(routing, '    func setStaticWallpaper(')
        self.assertEqual(still.count('NSWorkspace.shared'), 1)
        self.assertEqual(still.count('NSScreen.screens'), 1)
        still = still.replace('NSWorkspace.shared', 'DesktopLeaf.shared').replace('NSScreen.screens', 'DesktopLeaf.screens')
        methods += '\n' + still
        desktop_methods = '\n'.join(declaration(application, signature) for signature in (
            '    func rememberSystemDesktopWrite(', '    func restoreSystemDesktopWallpaperOnTermination(',
            '    var protectedSystemDesktopURLs:', '    func clearUnprotectedStaticFrameFiles(',
            '    private func applySourceImageDirectly(', '    private func removePreviousDesktopCopies('))
        # Only the native workspace/display boundary and private test visibility
        # change. All ownership, rollback and restoration policy is production.
        desktop_methods = desktop_methods.replace('NSWorkspace.shared', 'DesktopLeaf.shared').replace(
            'NSScreen.screens', 'DesktopLeaf.screens').replace('on screen: NSScreen', 'on screen: DesktopScreen')
        for name in ('applySourceImageDirectly', 'removePreviousDesktopCopies'):
            marker = '    private func ' + name + '('
            self.assertEqual(desktop_methods.count(marker), 1)
            desktop_methods = desktop_methods.replace(marker, '    func ' + name + '(', 1)
        persistence_path = MANAGER / 'WallpaperManager+Persistence.swift'
        desktop_methods += '\n' + declaration(persistence_path.read_text(), '    func clearPreviewCacheArtifacts(')
        cleanup_marker = '    private func removeFileIfExists('
        cleanup = declaration(removal, cleanup_marker)
        self.assertEqual(cleanup.count(cleanup_marker), 1)
        desktop_methods += '\n' + cleanup.replace(cleanup_marker, '    func removeFileIfExists(', 1)
        methods += '\n' + desktop_methods
        source += '\nextension WallpaperManager {\n' + methods + '\n}\n'
        # Keep the original Timer callback and all admission checks. Replace
        # scheduling/delivery only so a cancelled callback can be forced late.
        source = source.replace('var autoSwitchTimer:Timer?', 'var autoSwitchTimer:DeliveryTimer?')
        source = source.replace('let timer = Timer(timeInterval:', 'let timer = DeliveryTimer(timeInterval:')
        source = source.replace('RunLoop.main.add(timer, forMode: .common)', 'DeliveryTimer.add(timer)')
        fixture_path = ROOT / 'script/tests/fixtures/WallpaperLibraryPlaybackHarness.swift'
        desktop_fixture = ROOT / 'script/tests/fixtures/SystemDesktopWallpaperChecks.swift'
        support_path = MANAGER / 'WallpaperLibrarySupport.swift'
        fixture = declaration(support_path.read_text(), 'struct WallpaperDeletionFailure') + '\n'
        fixture += fixture_path.read_text() + '\n' + desktop_fixture.read_text()
        app = ROOT / 'MyWallpaperX/App/WallpaperLibraryPlaybackRouting.swift'
        observed = [*GATE_SOURCES, MANAGER / 'WallpaperManager.swift', MANAGER / 'WallpaperManager+RuntimeSwitching.swift',
            MANAGER / 'WallpaperManager+WallpaperApplication.swift', MANAGER / 'WallpaperManager+Removal.swift',
            MANAGER / 'WallpaperManager+PlaybackControl.swift', MANAGER / 'WallpaperManager+PlaybackSettings.swift',
            persistence_path, support_path, app, fixture_path, desktop_fixture, Path(__file__),
            ROOT / 'script/tests/test_imported_video_autoplay_gate.py']
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        with tempfile.TemporaryDirectory(prefix='mwx-library-playback-', dir='/private/tmp') as temporary:
            work = Path(temporary)
            paths = []
            for original in [*GATE_SOURCES, ROOT / 'MyWallpaperX/Models/WallpaperContent.swift',
                             ROOT / 'MyWallpaperX/Core/LibraryCollections/WallpaperLibraryQuery.swift', app]:
                copied = work / original.name
                copied.write_bytes(original.read_bytes()); paths.append(str(copied))
            harness = work / 'Harness.swift'; harness.write_text(source + '\n' + fixture)
            binary = work / 'checks'
            built = subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                *paths, str(harness), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            media = work / 'media'; media.mkdir()
            ran = subprocess.run([str(binary), str(media)], capture_output=True, text=True, timeout=20)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            checks = json.loads(ran.stdout)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == '__main__': unittest.main()
