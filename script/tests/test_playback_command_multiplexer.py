"""Production command dispatch must observe concrete playback state."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'MyWallpaperX/Core/PlaybackControl'
HARNESS = r'''
import Foundation
final class Handler: PlaybackEngineControlling {
    let engineKind: PlaybackEngineKind
    var isPlaying: Bool
    init(_ kind: PlaybackEngineKind, playing: Bool) {
        engineKind = kind; isPlaying = playing
    }
    func handle(_ command: WallpaperEngineCommand) -> Bool {
        switch command {
        case .pause: isPlaying = false; return true
        case .resume: isPlaying = true; return true
        default: return false
        }
    }
}
@main enum Harness {
    static func main() {
        let mux = PlaybackCommandMultiplexer()
        let scene = Handler(.scene, playing: true)
        let video = Handler(.video, playing: false)
        precondition(!mux.isAnyEnginePlaying)
        mux.register(scene); mux.register(video)
        precondition(mux.isAnyEnginePlaying, "Playing Scene must make global pause available")
        precondition(mux.dispatch(.pause).values.allSatisfy { $0 })
        precondition(!mux.isAnyEnginePlaying)
        precondition(mux.dispatch(.resume, to: .video))
        precondition(mux.isAnyEnginePlaying && !scene.isPlaying)
        mux.unregister(.video)
        precondition(!mux.isAnyEnginePlaying)
        precondition(!mux.dispatch(.setProperty([:], revision: 1), to: .scene))
        print("playback-dispatch-pass")
    }
}
'''


class PlaybackCommandMultiplexerTests(unittest.TestCase):
    def test_existential_state_tracks_registered_engine_and_commands(self):
        with tempfile.TemporaryDirectory(prefix='mwx-playback-dispatch-') as directory:
            path = Path(directory)
            harness = path / 'Harness.swift'
            harness.write_text(HARNESS)
            binary = path / 'harness'
            result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                *[str(SOURCES / name) for name in ['WallpaperEngineCommand.swift', 'PlaybackEngineControlling.swift', 'PlaybackCommandMultiplexer.swift']],
                str(harness), '-o', str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('playback-dispatch-pass', result.stdout)

    def test_scene_stop_cancels_preparation_without_an_active_context(self):
        support = r'''
import Foundation
struct SceneUserPropertyValue { static func parse(_ raw: String) -> Self? { Self() } }
final class SoundRegistry { func setMuted(_ value: Bool) {} }
final class SceneDesktopWallpaperHost {
    var launchContext: Int? = nil
    var pending = true
    var isPlaybackActive = false
    var soundPlaybackRegistry: SoundRegistry? = nil
    func requestLaunch(rootURL: URL, propertyOverrides: [String: SceneUserPropertyValue], recordID: String?, completion: (Int) -> Void) {}
    func setPlaybackPaused(_ paused: Bool) {}
    func applyPerformanceProfile(_ profile: PlaybackPerformanceProfile) {}
    func stop() { pending = false; launchContext = nil }
}
@main enum Harness {
    static func main() {
        let host = SceneDesktopWallpaperHost()
        precondition(host.handle(.stop))
        precondition(!host.pending, "Stop must cancel preparation before activation")
        precondition(host.handle(.stop), "Stop is idempotent")
        print("pending-stop-pass")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-playback-pending-stop-') as directory:
            root = Path(directory); harness = root / 'Harness.swift'; binary = root / 'harness'
            harness.write_text(support)
            files = [SOURCES / name for name in ['WallpaperEngineCommand.swift', 'PlaybackEngineControlling.swift', 'PlaybackCommandMultiplexer.swift', 'PlaybackPerformanceProfile.swift']]
            files.append(ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+PlaybackControl.swift')
            compiled = subprocess.run(['xcrun','swiftc','-parse-as-library',*[str(p) for p in files],str(harness),'-o',str(binary)],capture_output=True,text=True,timeout=60)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result = subprocess.run([str(binary)],capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('pending-stop-pass',result.stdout)
