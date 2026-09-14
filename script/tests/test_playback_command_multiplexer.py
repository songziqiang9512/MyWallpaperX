"""Production command dispatch must observe concrete playback state."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'MyWallpaperX/Core/PlaybackControl'
PROPERTY = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneUserProperty.swift'
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
        precondition(!mux.dispatch(
            .setProperty([:], revision: 1, recordID: "fixture"),
            to: .scene
        ))
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
                str(PROPERTY),
                *[str(SOURCES / name) for name in ['WallpaperEngineCommand.swift', 'PlaybackEngineControlling.swift', 'PlaybackCommandMultiplexer.swift']],
                str(harness), '-o', str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('playback-dispatch-pass', result.stdout)

    def test_product_scene_handler_is_daemon_client(self):
        application = (ROOT / 'MyWallpaperX/App/MyWallpaperXApplication.swift').read_text()
        status_bar = (ROOT / 'MyWallpaperX/App/StatusBarController.swift').read_text()
        client = (ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDaemonClient.swift').read_text()
        self.assertIn('register(SceneDaemonClient.shared)', application)
        self.assertNotIn('register(SceneDesktopWallpaperHost.shared)', status_bar)
        self.assertIn('final class SceneDaemonClient: PlaybackEngineControlling', client)
        self.assertFalse(
            (ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost+PlaybackControl.swift').exists()
        )
