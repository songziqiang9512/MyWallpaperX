"""Execute production adapters and IPC replay with captured transport boundaries."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "MyWallpaperX/Core"

HARNESS = r'''
import Foundation
enum ContentKind { case video, web }
enum WebWallpaperRuntimeCommand { case pause, resume(playbackRate: Float) }
final class WallpaperManager {
    static let shared = WallpaperManager()
    func stopCurrentPlayback() {}
    func setMuted(_ value: Bool) {}
}
final class WallpaperEngine {
    static let shared = WallpaperEngine()
    struct RunningProcess { var isRunning = true }
    final class DisplayDaemonSession {
        var process = RunningProcess()
        var nextRequestID = 0, latestRequestedPlayRequestID = 0
        var commands: [DaemonCommand] = []
    }
    var playbackPaused = false
    var currentPlaybackContentKind: ContentKind = .video
    var targetPlaybackRate: Float = 1.5
    var displaySessions: [Int: DisplayDaemonSession] = [:]
    var webCommands: [WebWallpaperRuntimeCommand] = []
    var effectiveVolumeNormalized: Float = 0.5
    var currentSystemAudioSpectrumEnabled = false
    var currentSpectrumLevels: [Float] = []
    var currentSystemAudioSpectrumBarCount = 28
    var currentSystemAudioSpectrumColorHex = "FFFFFF"
    var currentSystemAudioSpectrumOffsetX: Float = 0
    var currentSystemAudioSpectrumOffsetY: Float = 0
    var currentSystemAudioSpectrumPeakCapsEnabled = false
    func isPlaying() -> Bool { !playbackPaused }
    func setVolume(_ value: Float) {}
    func refreshSystemAudioSpectrumCapture() {}
    func dispatchWebRuntimeCommand(_ command: WebWallpaperRuntimeCommand) { webCommands.append(command) }
    func send(_ command: DaemonCommand, to session: DisplayDaemonSession) { session.commands.append(command) }
    // VIDEO_METHODS
}
struct PlaybackPerformanceProfile {
    var maxFPS = 60
    init() {}
    init?(rawValue: Int) { maxFPS = rawValue }
}
enum SceneDaemonProtocol { static let version = 1 }
final class SceneDaemonClient: PlaybackEngineControlling {
    let engineKind: PlaybackEngineKind = .scene
    var isPaused = false, endpointReady = false
    var isPlaying: Bool { activeIntent != nil && !isPaused }
    var activeIntent: ScenePlaybackLoadRequest?, pendingIntent: ScenePlaybackLoadRequest?
    var pendingRequestID: UUID?
    var performanceProfile = PlaybackPerformanceProfile()
    var commands: [[String: Any]] = []
    func send(_ command: [String: Any]) { commands.append(command) }
    func sendDisplayConfiguration() {}
    func requestLaunch(_ request: ScenePlaybackLoadRequest) { pendingIntent = request }
    func applyPropertyValues(_ values: [String: SceneUserPropertyValue], revision: UInt64, recordID: String) -> Bool { false }
    func cancelPendingLaunch(recordID: String) -> Bool { false }
    func stop(postsLaunchState: Bool) {}
    // SCENE_METHODS
}
@main enum Harness {
    static func main() {
        let mux = PlaybackCommandMultiplexer.shared
        let video = VideoPlaybackCommandHandler(), scene = SceneDaemonClient()
        mux.register(video); mux.register(video, as: .web); mux.register(scene)
        let engine = WallpaperEngine.shared
        let session = WallpaperEngine.DisplayDaemonSession()
        engine.displaySessions[1] = session
        mux.dispatch(.pause)
        precondition(session.commands.last?.action == "pause")
        precondition(scene.isPaused && scene.commands.isEmpty)
        // New and restarted Video sessions inherit manual pause.
        engine.sendPlayCommand(for: "/fixture.mp4", framePath: nil,
            fillMode: "aspectFill", shouldLoopCurrentItem: true, to: session)
        precondition(session.commands.suffix(2).map(\.action) == ["play", "pause"])
        // Scene handshake / restart replay must retain a pause received before ready.
        scene.pendingIntent = ScenePlaybackLoadRequest(rootURL: URL(fileURLWithPath: "/fixture"),
            propertyOverrides: [:], userPropertyTextures: [:], recordID: "fixture")
        scene.endpointReady = true
        scene.replayPendingIntent()
        precondition(scene.commands.first?["cmd"] as? String == "loadScene")
        precondition(scene.commands.last?["cmd"] as? String == "pause")
        // Web preparing alongside retained Video must pause/resume both surfaces.
        engine.currentPlaybackContentKind = .web
        mux.dispatch(.resume)
        precondition(session.commands.last?.action == "resume")
        precondition(scene.commands.last?["cmd"] as? String == "resume")
        guard case let .resume(rate) = engine.webCommands.last else { fatalError("missing Web resume") }
        precondition(rate == 1.5)
        mux.setSystemPaused(true)
        precondition(session.commands.last?.action == "pause")
        precondition(scene.commands.last?["cmd"] as? String == "pause")
        guard case .pause = engine.webCommands.last else { fatalError("missing Web pause") }
        let videoCount = session.commands.count, sceneCount = scene.commands.count
        mux.dispatch(.resume)
        precondition(session.commands.count == videoCount && scene.commands.count == sceneCount)
        mux.setSystemPaused(false)
        precondition(session.commands.last?.action == "resume")
        precondition(scene.commands.last?["cmd"] as? String == "resume")
        print("delivery-pass: Video/Web/Scene, retained surfaces, pre-ready/restart replay")
    }
}
'''


class PlaybackPolicyDeliveryTests(unittest.TestCase):
    def test_paused_scene_admission_presents_once_without_running_timer(self):
        driver = (CORE / "SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift").read_text()
        pause = (CORE / "SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+VideoProviders.swift").read_text()
        harness = r'''
import Foundation
import QuartzCore
enum SceneFrameDriverAttempt { case rendered, busy, dropped, inactive }
enum Counter { case framesRendered, framesBusy, framesDropped, framesInactive }
enum Phase { case firstVisibleFrame }
enum ScenePerformanceCounterHub {
    static let shared = ScenePerformanceCounterHub()
    func bump(_ counter: Counter) {}
    func recordLaunchPhase(_ phase: Phase, uptimeMicros: UInt64) {}
    static func nowUptimeMicros() -> UInt64 { 0 }
}
struct Clock {
    var isPaused = true
    mutating func pause(hostTime: Double) { isPaused = true }
    mutating func resume(hostTime: Double) { isPaused = false }
    func currentSceneTime(hostTime: Double) -> Double { 0 }
}
final class Providers {
    var paused = false
    func pause(sceneTime: Double, hostTime: Double) { paused = true }
    func resume(sceneTime: Double, hostTime: Double) { paused = false }
}
final class Sounds {
    var paused = false
    func pause() { paused = true }
    func resume() { paused = false }
}
final class Host {
    var sceneClock = Clock()
    var isVisible = true
    var launchContext: Int? = 1
    var videoTextureSourceRegistry: Providers?
    var soundPlaybackRegistry: Sounds?
    var frameTimer: Timer?
    var frameDriverDeadline: Double?
    var pausedFrameRetryDeadline: Double?
    var surfaces: [Int: Surface] = [:]
    final class Surface { var pendingPausedFrame: Int? }
    var sceneFrameInterval: Double = 1.0/60
    var sceneBusyFrameRetryInterval: Double = 0.002
    var frames = 0, timers = 0
    var result: SceneFrameDriverAttempt = .rendered
    func renderFrame() -> SceneFrameDriverAttempt { frames += 1; return result }
    func armFrameDriver(at deadline: Double) { timers += 1 }
    // METHODS
}
@main enum Harness {
    static func main() {
        let host = Host()
        host.startFrameDriver()
        precondition(host.frames == 1 && host.timers == 0 && host.sceneClock.isPaused)
        host.setPlaybackPaused(false)
        precondition(host.frames == 2 && host.timers == 1 && !host.sceneClock.isPaused)
        host.setPlaybackPaused(true)
        precondition(host.frameTimer == nil && host.sceneClock.isPaused)
        host.startFrameDriver() // Display rebuild while paused: one fresh still frame.
        precondition(host.frames == 3 && host.timers == 1 && host.sceneClock.isPaused)
        // Providers may be newly admitted while the clock is already paused.
        host.videoTextureSourceRegistry = Providers()
        host.soundPlaybackRegistry = Sounds()
        let pendingStillFrame = Timer(timeInterval: 1, repeats: false) { _ in }
        host.frameTimer = pendingStillFrame
        host.setPlaybackPaused(true)
        precondition(host.frameTimer === pendingStillFrame, "Repeated pause cancelled static first-frame retry")
        precondition(host.videoTextureSourceRegistry?.paused == true)
        precondition(host.soundPlaybackRegistry?.paused == true)
        let busyHost = Host()
        busyHost.result = .busy
        busyHost.startFrameDriver()
        precondition(busyHost.frames == 1 && busyHost.timers == 1)
        busyHost.result = .rendered
        busyHost.scheduleFrameDriver(after: busyHost.renderFrame(), scheduledDeadline: CACurrentMediaTime())
        precondition(busyHost.frames == 2 && busyHost.timers == 1)
        busyHost.pausedFrameRetryDeadline = CACurrentMediaTime() - 1
        busyHost.scheduleFrameDriver(after: .busy, scheduledDeadline: CACurrentMediaTime())
        precondition(busyHost.timers == 1, "Expired paused retry must not keep scheduling")
        print("scene-paused-first-frame-pass")
    }
}
'''.replace("// METHODS", "\n".join([
            method(driver, "func startFrameDriver("),
            method(driver, "private func scheduleFrameDriver("),
            method(pause, "func setPlaybackPaused("),
        ])).replace("enum ScenePerformanceCounterHub {", "struct ScenePerformanceCounterHub {")
        with tempfile.TemporaryDirectory(prefix="mwx-scene-pause-admission-") as directory:
            path = Path(directory)
            (path / "Harness.swift").write_text(harness)
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                str(path / "Harness.swift"), "-o", str(path / "harness")],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(path / "harness")], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_production_handlers_and_replay(self):
        video = (CORE / "Playback/WallpaperEngine+PlaybackControl.swift").read_text()
        session = (CORE / "Playback/WallpaperEngine+DaemonSessionLifecycle.swift").read_text()
        scene = (CORE / "SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift").read_text()
        harness = HARNESS.replace("// VIDEO_METHODS", "\n".join([
            method(video, "func applyPlaybackPaused("), method(video, "func sendPlaybackPaused("),
            method(session, "func sendPlayCommand("),
        ])).replace("// SCENE_METHODS", "\n".join([
            method(scene, "func handle("), method(scene, "func replayPendingIntent("),
            method(scene, "private func sendSimpleCommand("),
        ]))
        with tempfile.TemporaryDirectory(prefix="mwx-pause-delivery-") as directory:
            path = Path(directory)
            (path / "Harness.swift").write_text(harness)
            sources = [CORE / "Playback/DaemonProtocol.swift",
                CORE / "SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
                ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/VideoPlaybackCommandHandler.swift",
                *[CORE / "PlaybackControl" / name for name in ["WallpaperEngineCommand.swift",
                    "PlaybackEngineControlling.swift", "PlaybackCommandMultiplexer.swift"]]]
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                str(path / "Harness.swift"), "-o", str(path / "harness")],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(path / "harness")], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("delivery-pass", result.stdout)


if __name__ == "__main__":
    unittest.main()
