"""Real App restoration + original Manager admission/commit/failure owners.

Persistence uses isolated UserDefaults suites. Rendering, source facts and native
endpoint delivery are controlled leaves; no actual desktop or media is changed.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_imported_video_autoplay_gate import GATE_SOURCES, MANAGER, product_harness
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class WallpaperPlaybackRestorationTests(unittest.TestCase):
    def test_readiness_metadata_legacy_and_original_ticket_boundaries(self):
        source = product_harness().replace('struct VideoWallpaper {', 'struct VideoWallpaper:Codable {')
        source = source.replace('var autoSwitchEnabled=true,randomInterval=',
                                'var restorePlaybackOnLaunch=true\n        var autoSwitchEnabled=true,randomInterval=')
        source = source.replace('static let shared=PlaybackCommandMultiplexer();var isPlaybackPaused=false', '''
    static let shared=PlaybackCommandMultiplexer()
    var isPlaybackPaused=false,isUserPaused=false,isSystemPaused=false
    var onDispatch:(()->Void)?
    enum Command {case pause,resume}
    func dispatch(_ command:Command){isUserPaused = command == .pause;isPlaybackPaused=isUserPaused || isSystemPaused;onDispatch?()}
''')
        source = source.replace('var isPlaying=false', '''
    var isPlaying=false
    let playbackStateKey="PlaybackState"
    var recentlyUsedWallpapers:[VideoWallpaper]=[]
    var testDefaults:UserDefaults?
    let currentWallpaperKey="CurrentWallpaper"
    func migratedBundledVideoWallpaper(_ value:VideoWallpaper)->VideoWallpaper{value}
    private func loadCodableValue<T:Decodable>(forKey key:String)->T?{
        testDefaults?.data(forKey:key).flatMap{try? JSONDecoder().decode(T.self,from:$0)}
    }
''')
        persistence = (MANAGER / 'WallpaperManager+Persistence.swift').read_text()
        source += '\nextension WallpaperManager {\n' + declaration(persistence, '    func loadCurrentWallpaper(') + '\n}\n'
        component = ROOT / 'MyWallpaperX/App/WallpaperLibraryPlaybackRestoration.swift'
        fixture = ROOT / 'script/tests/fixtures/WallpaperPlaybackRestorationHarness.swift'
        with tempfile.TemporaryDirectory(prefix='mwx-playback-restoration-', dir='/private/tmp') as directory:
            work = Path(directory)
            paths = []
            for original in [*GATE_SOURCES, ROOT / 'MyWallpaperX/Models/WallpaperContent.swift', component]:
                copied = work / original.name
                copied.write_bytes(original.read_bytes()); paths.append(str(copied))
            harness = work / 'Harness.swift'; harness.write_text(source + '\n' + fixture.read_text())
            binary = work / 'checks'
            built = subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                *paths, str(harness), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            checks = json.loads(ran.stdout)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            print(json.dumps(checks, sort_keys=True))


if __name__ == '__main__': unittest.main()
