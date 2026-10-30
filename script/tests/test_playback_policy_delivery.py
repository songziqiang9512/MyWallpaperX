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
final class WebDaemonHostAdapter { var hasLivePlayback = false }
final class WallpaperEngine {
    static let shared = WallpaperEngine()
    struct RunningProcess { var isRunning = true }
    final class DisplayDaemonSession {
        var process = RunningProcess()
        var nextRequestID = 0
        var latestRequestedPlayRequestID: Int?
        var latestPreparedPlayRequestID: Int?
        var latestCommittedPlayRequestID: Int?
        var latestReadyPlayRequestID: Int?
        var commands: [DaemonCommand] = []
    }
    var playbackPaused = false
    var currentPlaybackContentKind: ContentKind = .video
    let dedicatedWebHostAdapter: AnyObject = WebDaemonHostAdapter()
    var currentWebRequestID: UUID? { didSet { (dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.hasLivePlayback = currentWebRequestID != nil } }
    struct SpectrumDelivery { var currentOverlayLevels: [Float] = [] }
    var spectrumDelivery = SpectrumDelivery()
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
enum SceneDaemonProtocolFailure: Error { case invalidPayload(String) }
enum SceneDaemonProtocol {
    static let version = 2
    // SOURCE_ENCODER
}
final class DaemonPlaybackProcessRegistry {
    static let shared = DaemonPlaybackProcessRegistry()
    var acceptsNewProcesses = true
}
final class SceneDaemonClient: PlaybackEngineControlling {
    let engineKind: PlaybackEngineKind = .scene
    var stopPlaybackRequested: (() -> Void)?
    var isPaused = false, endpointReady = false
    var hasRequestRetirementControl = false
    var idleTransport: NSObject?
    var sourceSchemaVersion: Int?
    var localStops=0
    var isPlaying: Bool { activeIntent != nil && !isPaused }
    var activeIntent: ScenePlaybackLoadRequest?, pendingIntent: ScenePlaybackLoadRequest?
    var pendingRequestID: UUID?
    struct Lifetime { let lifetime: Int }
    var pendingResourceLifetime: Lifetime?
    var requestResourceLifetimes: [UUID: Int] = [:]
    var performanceProfile = PlaybackPerformanceProfile()
    var commands: [[String: Any]] = []
    var launchFailures: [[String: Any]] = []
    func handleLaunchState(_ payload: [String: Any]) { launchFailures.append(payload) }
    func send(_ command: [String: Any]) { commands.append(command) }
    func sendDisplayConfiguration() {}
    func requestLaunch(_ request: ScenePlaybackLoadRequest) { pendingIntent = request }
    func applyPropertyValues(_ values: [String: SceneUserPropertyValue], revision: UInt64, recordID: String) -> Bool { false }
    func cancelPendingLaunch(recordID: String) -> Bool { false }
    func stop(postsLaunchState: Bool) {localStops += 1}
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
        // Actual prepareVideoSwitch + sendPlaybackPaused replay is covered by
        // test_playback_switch_endpoints; this harness keeps multiplexer and
        // Scene pre-handshake/restart delivery at their real production owners.
        // Scene handshake / restart replay must retain a pause received before ready.
        scene.pendingIntent = ScenePlaybackLoadRequest(rootURL: URL(fileURLWithPath: "/fixture"),
            propertyOverrides: [:], userPropertyTextures: [:], recordID: "fixture")
        scene.endpointReady = true
        scene.hasRequestRetirementControl = true
        scene.replayPendingIntent()
        precondition(scene.commands.isEmpty, "Retiring sessions must not replay a load")
        scene.hasRequestRetirementControl = false
        scene.idleTransport = NSObject()
        scene.replayPendingIntent()
        precondition(scene.commands.isEmpty, "Idle transports must not replay a load")
        scene.idleTransport = nil
        DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses = false
        scene.replayPendingIntent()
        precondition(scene.commands.isEmpty, "App shutdown must not replay a load")
        DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses = true
        scene.replayPendingIntent()
        precondition(scene.commands.first?["cmd"] as? String == "loadScene")
        precondition(scene.commands.last?["cmd"] as? String == "pause")
        // Web preparing alongside retained Video must pause/resume both surfaces.
        engine.currentPlaybackContentKind = .web
        engine.currentWebRequestID = UUID()
        mux.dispatch(.resume)
        precondition(session.commands.last?.action == "resume")
        precondition(scene.commands.last?["cmd"] as? String == "resume")
        guard case let .resume(rate) = engine.webCommands.last else { fatalError("missing Web resume") }
        precondition(rate == 1.5)
        engine.currentPlaybackContentKind = .video // retained Web during Video preparation
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
        var productStops=0
        scene.stopPlaybackRequested={productStops += 1}
        mux.dispatch(.stop,to:.scene)
        precondition(productStops == 1 && scene.localStops == 0,
            "directed Scene stop must recycle product selection through its owner")
        scene.stopPlaybackRequested=nil
        mux.dispatch(.stop,to:.scene)
        precondition(scene.localStops == 1,"standalone Scene keeps its local stop fallback")
        print("delivery-pass: Video/Web/Scene, retained surfaces, pre-ready/restart replay")
    }
}
'''


SCREEN_NOTIFICATION_HARNESS = r'''
import AppKit
struct ScreenData {
    var deviceDescription: [NSDeviceDescriptionKey: Any]
    var frame: CGRect
    var visibleFrame: CGRect
}
enum ScreenLeaf { static var screens: [ScreenData] = [] }
final class WallpaperEngine: NSObject {
    struct Candidate { let ticket = UUID() }
    var displayIDs: [CGDirectDisplayID] = [], displayFrames: [CGRect] = []
    var currentWallpaper: String? = "unchanged-video"
    var currentMultiDisplayEnabled = true, currentShouldLoopCurrentItem = true
    var currentVideoFillMode = "aspectFit"
    var videoCandidate: Candidate?
    var cancellations = 0, reloads = 0, failures = 0
    lazy var switchFailed: ((UUID, String) -> Void)? = { [weak self] _, _ in self?.failures += 1 }
    func cancelVideoExecution(_ candidate: Candidate, completion: () -> Void) { cancellations += 1; completion() }
    func applyWallpaper(_ wallpaper: String, multiDisplayEnabled: Bool, videoFillMode: String, shouldLoopCurrentItem: Bool) {
        precondition(wallpaper == "unchanged-video" && multiDisplayEnabled && videoFillMode == "aspectFit" && shouldLoopCurrentItem)
        reloads += 1
    }
    // SCAN
    // NOTIFICATION
}
@main enum Checks {
    static func main() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        ScreenLeaf.screens = [.init(deviceDescription: [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: 1)],
            frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 30))]
        let engine = WallpaperEngine()
        engine.scanDisplays()
        engine.videoCandidate = .init()
        for _ in 0..<8 {
            ScreenLeaf.screens[0].visibleFrame.size.height -= 1
            engine.handleScreenParametersChanged()
        }
        precondition(engine.reloads == 0 && engine.cancellations == 0 && engine.failures == 0,
                     "Dock/work-area notifications must not reload video or cancel a pending switch")
        ScreenLeaf.screens[0].frame.size.width = 1920
        engine.handleScreenParametersChanged()
        precondition(engine.reloads == 1 && engine.cancellations == 1 && engine.failures == 1)
        engine.handleScreenParametersChanged()
        precondition(engine.reloads == 1 && engine.cancellations == 1)
        ScreenLeaf.screens.append(.init(deviceDescription: [NSDeviceDescriptionKey("NSScreenNumber"): NSNumber(value: 2)],
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), visibleFrame: .zero))
        engine.handleScreenParametersChanged()
        precondition(engine.reloads == 2 && engine.displayIDs == [1, 2])
        ScreenLeaf.screens[1].frame.origin.y = 200
        engine.handleScreenParametersChanged()
        precondition(engine.reloads == 3, "real display rearrangement must still rebuild video surfaces")
        ScreenLeaf.screens.removeLast()
        engine.handleScreenParametersChanged()
        precondition(engine.reloads == 4 && engine.displayIDs == [1])
        ScreenLeaf.screens[0].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] = NSNumber(value: 3)
        engine.currentWallpaper = nil
        engine.handleScreenParametersChanged()
        precondition(engine.reloads == 4 && engine.cancellations == 5 && engine.displayIDs == [3])
        engine.handleScreenParametersChanged()
        precondition(engine.cancellations == 5)
        print("display-notification-checks-passed")
    }
}
'''


class PlaybackPolicyDeliveryTests(unittest.TestCase):
    def test_screen_parameter_notifications_only_reload_changed_video_geometry(self):
        events = (CORE / "Playback/WallpaperEngine+DaemonEvents.swift").read_text()
        controls = (CORE / "Playback/WallpaperEngine+PlaybackControl.swift").read_text()
        harness = SCREEN_NOTIFICATION_HARNESS.replace("    // SCAN", method(events, "func scanDisplays(").replace(
            "NSScreen.screens", "ScreenLeaf.screens")).replace(
            "    // NOTIFICATION", method(controls, "@objc func handleScreenParametersChanged("))
        with tempfile.TemporaryDirectory(prefix="mwx-video-displays-") as directory:
            root = Path(directory)
            source = root / "Checks.swift"; source.write_text(harness)
            binary = root / "checks"
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source), "-o", str(binary)],
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("display-notification-checks-passed", result.stdout)

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
    struct Cohort { var isHeld = false }
    var initialPresentationCohort = Cohort()
    var awaitsInitialPresentation = false
    var isVisible = true
    var isOutputActive = true
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
        let heldHost = Host()
        heldHost.initialPresentationCohort.isHeld = true
        heldHost.startFrameDriver()
        precondition(heldHost.frames == 0 && heldHost.timers == 0,
            "An unadmitted presentation cohort must not draw or start a frame timer")
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
            method(driver, "func scheduleFrameDriver("),
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
        scene = (CORE / "SteamWorkshopScene/Runtime/IPC/SceneDaemonClient.swift").read_text()
        protocol = (CORE / "SteamWorkshopScene/Runtime/IPC/SceneDaemonProtocol.swift").read_text()
        harness = HARNESS.replace("// VIDEO_METHODS", "\n".join([
            method(video, "func applyPlaybackPaused("), method(video, "func sendPlaybackPaused("),
        ])).replace("// SCENE_METHODS", "\n".join([
            method(scene, "func handle("), method(scene, "func replayPendingIntent("),
            method(scene, "private func sendSimpleCommand("),
        ])).replace("// SOURCE_ENCODER", method(protocol, "static func sourceObject("))
        with tempfile.TemporaryDirectory(prefix="mwx-pause-delivery-") as directory:
            path = Path(directory)
            (path / "Harness.swift").write_text(harness)
            sources = [CORE / "Playback/DaemonProtocol.swift",
                CORE / "SteamWorkshopStorage/ScenePlaybackSource.swift",
                CORE / "SteamWorkshopScene/Runtime/IPC/SceneDaemonProtocol+UserShortcuts.swift",
                CORE / "PlaybackControl/PlaybackSurfaceVisibility.swift",
                CORE / "SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
                ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/VideoPlaybackCommandHandler.swift",
                *[CORE / "PlaybackControl" / name for name in ["ScenePlaybackShortcut.swift", "WallpaperEngineCommand.swift",
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
