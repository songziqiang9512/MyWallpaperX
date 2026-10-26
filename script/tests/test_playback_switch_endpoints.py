"""Execute the native parent Video/Web switch owners with controlled IPC peers."""
from pathlib import Path
import fcntl
import hashlib
import json
import subprocess
import tempfile
import unittest

from script.tests.test_playback_process_isolation import source_block

ROOT = Path(__file__).resolve().parents[2]

SUPPORT = r'''
import AppKit
import Foundation
nonisolated enum WallpaperRuntimeKind: Hashable, Sendable { case video, web, scene, image }
protocol PlaybackResourceLifetime: AnyObject {}
struct VideoWallpaper { let path: String; var staticFramePath: String? = nil }
final class DaemonPlaybackProcessRegistry { static let shared = DaemonPlaybackProcessRegistry(); var acceptsNewProcesses = true }
final class FakeProcess { var isRunning = true; let processIdentifier: Int32; init(_ pid: Int32) { processIdentifier = pid } }
typealias Process = FakeProcess
final class DaemonProcessTransport {
    static var nextPID: Int32 = 1000
    let process: FakeProcess
    let arguments: [String]
    let inputPipe = Pipe(), outputPipe = Pipe(), errorPipe = Pipe()
    var onOutput: ((Data)->Void)?, onError: ((String)->Void)?, onTermination: ((Int32)->Void)?
    var sent: [Data] = []; var stopRequested = false
    var isRunning: Bool { process.isRunning }
    init(executableURL: URL, arguments: [String], playbackRenderer: Bool = false) {
        self.arguments = arguments
        Self.nextPID += 1; process = FakeProcess(Self.nextPID)
    }
    func start() throws {}
    @discardableResult func sendRequired(_ data: Data) -> Bool { sent.append(data); return isRunning }
    @discardableResult func sendLatest(_ data: Data) -> Bool { sendRequired(data) }
    func requestGracefulStop(_ command: Data? = nil, gracePeriod: TimeInterval = 2) {
        if let command { sent.append(command) }; stopRequested = true
    }
    func closeIO() {}
    func end() { process.isRunning = false; onTermination?(0) }
}
struct DaemonRestartBackoff { static func delay(forConsecutiveFailureCount: Int) -> TimeInterval { 0 } }
final class PlaybackPolicyController { static let shared = PlaybackPolicyController(); func refresh() {} }
final class PlaybackSpectrumDelivery {
    struct Target { let requestID: UUID; let transport: DaemonProcessTransport }
    var currentOverlayLevels: [Float] { [] }
    func setWebTargets(_ values: [Target]) {}
}
final class SystemMediaService {
    static let shared = SystemMediaService(); let currentSnapshot = SystemMediaSnapshot.empty
    func unsubscribe(_ id: UUID) {}
    func subscribe(_ id: UUID, needsMedia: Bool, needsWebArtwork: Bool = false,
                   handler: @escaping (SystemMediaSnapshot)->Void) {}
}
final class WebRuntimeDiagnosticsStore {
    enum Severity: String { case warning }
    static let shared = WebRuntimeDiagnosticsStore()
    func record(type: String, severity: Severity, message: String, recordID: String?, screenID: UInt32?, url: String?) {}
}
@MainActor final class WallpaperEngine {
    enum PlaybackContentKind { case video, web }
    // REAL_VIDEO_SESSION
    struct ActiveVideoPlayback { let id = UUID(); let wallpaper: VideoWallpaper; let path: String; let multiDisplayEnabled: Bool }
    static let playbackReadyNotification = Notification.Name("ready")
    static let playbackFailedNotification = Notification.Name("failed")
    var switchPrepared: ((PlaybackSwitchTicket, PlaybackSwitchEndpoint)->Void)?
    var switchVisible: ((PlaybackSwitchTicket, UUID)->Void)?
    var switchFailed: ((PlaybackSwitchTicket, String)->Void)?
    var switchLost: ((PlaybackSwitchTicket, String)->Void)?
    var pendingVideoRecovery: VideoSwitchExecution?
    var deferredVideoPreparation: DeferredVideoSwitchPreparation?
    var videoCandidate: VideoSwitchExecution?, activeVideoExecution: VideoSwitchExecution?
    var videoExecutions: [UUID: VideoSwitchExecution] = [:]
    var videoOutputAcknowledgements: [UUID: VideoOutputAcknowledgement] = [:]
    var activeVideoPlayback: ActiveVideoPlayback?
    var videoEndState: (playbackID: UUID, delivered: Bool)?
    var displaySessions: [UInt32: DisplayDaemonSession] = [:], displayIDs: [UInt32] = [1, 2]
    var displayCrashCounts: [UInt32: Int] = [:]
    var currentWallpaper: VideoWallpaper?, currentContentPath: String?, currentPlaybackContentKind: PlaybackContentKind?
    var currentVideoFillMode = "fill", currentMultiDisplayEnabled = true, currentShouldLoopCurrentItem = false
    var effectiveVolumeNormalized: Float = 0.7, targetPlaybackRate: Float = 1
    var currentSystemAudioSpectrumEnabled = false
    var currentSystemAudioSpectrumBarCount = 28, currentSystemAudioSpectrumColorHex = "#ffffff"
    var currentSystemAudioSpectrumOffsetX: Float = 0, currentSystemAudioSpectrumOffsetY: Float = 0
    var currentSystemAudioSpectrumPeakCapsEnabled = false, playbackPaused = false
    var lastFailureVideoPath: String?, lastFailureAt: TimeInterval = 0
    let spectrumDelivery = PlaybackSpectrumDelivery()
    lazy var dedicatedWebHostAdapter: WebWallpaperHostAdapter = WebDaemonHostAdapter(spectrumDelivery: spectrumDelivery)
    var currentWebRequestID: UUID?
    var currentWebPropertiesJSON: String?
    func dispatchWebRuntimeCommand(_ command: WebWallpaperRuntimeCommand) { dedicatedWebHostAdapter.handle(command) }
    // REAL_WEB_PROPERTIES
    var normalizedPathCalls = 0
    // REAL_NORMALIZED_PATH
    func adoptIntentEpoch(_ epoch: UInt64) {}
    func scanDisplays() {}
    // REAL_VIDEO_PAUSE
    func refreshVideoSpectrumTargets() {}
    func replayDeferredVideoEndIfNeeded() {}
    // REAL_VIDEO_EVENTS
    func ensureSession(for display: UInt32) -> DisplayDaemonSession? {
        if let session = displaySessions[display] { return session }
        let session = DisplayDaemonSession(displayID: display,
            transport: .init(executableURL: URL(fileURLWithPath: "/unused"), arguments: []))
        displaySessions[display] = session
        session.transport.onTermination = { [weak self, weak session] _ in
            guard let self, let session else { return }
            let current = self.displaySessions[display] === session
            if current { self.displaySessions.removeValue(forKey: display) }
            self.videoSessionDidExit(session, wasCurrent: current)
        }
        return session
    }
    func send(_ command: DaemonCommand, to session: DisplayDaemonSession) {
        session.transport.sendRequired(try! DaemonNewlineJSON.encode(command))
    }
    func terminateSession(for display: UInt32) { displaySessions.removeValue(forKey: display)?.transport.requestGracefulStop() }
}
'''

# Keep diagnostic storage and event dispatch from the actual parent owner in both configurations.
SUPPORT = SUPPORT.replace("// REAL_VIDEO_SESSION", source_block(
    (ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine.swift").read_text(), "final class DisplayDaemonSession"))
NORMALIZER = source_block((ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine.swift").read_text(), "func normalizedPath(")
NORMALIZE_LEAF = "        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path"
assert NORMALIZER.count(NORMALIZE_LEAF) == 1
SUPPORT = SUPPORT.replace("// REAL_NORMALIZED_PATH", NORMALIZER.replace(NORMALIZE_LEAF,
    "        normalizedPathCalls += 1\n        return " + NORMALIZE_LEAF.strip()))
EVENT_SOURCE = (ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+DaemonEvents.swift").read_text()
SUPPORT = SUPPORT.replace("// REAL_VIDEO_EVENTS", "\n".join(source_block(EVENT_SOURCE, marker) for marker in (
    "func consumeDaemonEvents(", "private func handleDaemonEvent(", "private func handlePlaybackEndedEvent(")))

ASSEMBLY_SUPPORT = r'''
enum VideoFillMode: String { case aspectFill }
final class PlaybackMuteState { static let shared = PlaybackMuteState(); var isMuted = false }
final class PlaybackCommandMultiplexer {
    enum Command { case pause, resume }
    static let shared = PlaybackCommandMultiplexer()
    func dispatch(_ value: Command) {}
}
struct PlaybackIntentEpoch {
    static func adopted(mirror: UInt64, product: UInt64) -> UInt64 { max(mirror, product) }
}
final class SystemAudioSpectrumService {
    init(barCount: Int) {}
    func setConsumers(overlayEnabled: Bool, webEnabled: Bool) {}
}
struct SceneAudioSpectrumCaptureDemand { static let none = SceneAudioSpectrumCaptureDemand() }
struct SceneAudioSpectrumCaptureRoutingState {}
extension PlaybackSpectrumDelivery { func setVideoTargets(_ values: [DaemonProcessTransport]) {} }
extension WallpaperEngine {
    func refreshSystemAudioSpectrumCapture() {}
    static func makeSystemAudioSpectrumService(barCount: Int, delivery: PlaybackSpectrumDelivery) -> SystemAudioSpectrumService { .init(barCount: barCount) }
    func observeSceneAudioSpectrumDemand() {}
    func currentWebSpectrumSnapshot() -> [Float]? { nil }
    func setWebAudioSpectrumRequested(_ active: Bool) { currentWebAudioSpectrumRequested = active }
}
'''

PREPARATION_PRODUCER_SUPPORT = r'''
#if DEBUG
final class WKNavigation {}
final class WKWebView {
    func load(_ request: URLRequest) -> WKNavigation? { WKNavigation() }
    func reload() -> WKNavigation? { WKNavigation() }
    func stopLoading() {}
}
final class DedicatedWebWallpaperHostPlaceholderAdapter {
    struct HostSurface { let id = UUID(); let screenID: UInt32; let webView: WKWebView }
    struct NavigationOwnership { let requestID: UUID; let navigation: WKNavigation; let generation: UInt64 }
    enum Phase { case ready, launching }
    var phase = Phase.ready
    var surfaces: [UInt32: HostSurface] = [:]
    var currentRequest: WallpaperEngine.WebWallpaperLaunchRequest?
    var navigationOwnershipByScreen: [UInt32: NavigationOwnership] = [:]
    var recoveringWebContentScreenIDs = Set<UInt32>()
    var readyScreenIDs = Set<UInt32>()
    var debugStartupSurfaceTimings: [UInt32: WebDaemonStartupSurfaceTimingObservation]? = [:]
    var generation: UInt64 = 0
    func advanceNavigationGeneration() -> UInt64 { generation += 1; return generation }
    func invalidatePresentation(on surface: HostSurface) {}
    func screenID(for view: WKWebView) -> UInt32? { surfaces.first { $0.value.webView === view }?.key }
    func runtimeEntryURL(for request: WallpaperEngine.WebWallpaperLaunchRequest, localEntryURL: URL,
                         surface: HostSurface, completion: (URL) -> Void) { completion(localEntryURL) }
}
extension DedicatedWebWallpaperHostPlaceholderAdapter {
    // REAL_NAVIGATION_PRODUCERS
}
#endif
'''


HARNESS_PATH = ROOT / "script/tests/fixtures/PlaybackSwitchEndpointChecks.swift"
HARNESS = HARNESS_PATH.read_text()


class PlaybackSwitchEndpointTests(unittest.TestCase):
    def test_product_intent_cancels_preparation_after_advancing_epoch(self):
        manager = (ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager.swift").read_text()
        assembly = (ROOT / "MyWallpaperX/App/MyWallpaperXApplication.swift").read_text()
        harness_source = r'''
import Foundation
import QuartzCore
protocol PlaybackResourceLifetime: AnyObject {}
@MainActor final class WallpaperManager {
    static let shared = WallpaperManager()
    var playbackSwitch = PlaybackSwitchTransaction()
    var libraryPlaybackSequence = WallpaperPlaybackSequence()
    var libraryRotationDeadline = WallpaperRotationDeadline()
    var playbackIntentDidAdvance: ((WallpaperRuntimeKind?) -> Void)?
    var playbackIntentEpoch: UInt64 { playbackSwitch.epoch }
    var pendingWallpaper: Int?
    var timerStops = 0
    var onEffects: (() -> Void)?
    func runSwitchEffects(_ effects: [PlaybackSwitchTransaction.Effect]) { onEffects?() }
    func scheduleSwitchDeadline(_ ticket: PlaybackSwitchTicket) {}
    func stopAutoSwitchTimer() { timerStops += 1 }
    // REAL_BEGIN
}
@MainActor final class WebDaemonHostAdapter {
    var mayPrepareIdleProcess: (() -> Bool)?
    var cancellations = 0
    func cancelIdlePreparation() { cancellations += 1 }
}
@MainActor final class WallpaperEngine {
    static let shared = WallpaperEngine()
    let dedicatedWebHostAdapter: Any = WebDaemonHostAdapter()
}
@MainActor final class SceneDaemonClient {
    static let shared = SceneDaemonClient()
    var hasRetainedOrRetiringTransport = false
    var intents: [WallpaperRuntimeKind?] = []
    func invalidateRetainedTransport(for runtime: WallpaperRuntimeKind?) { intents.append(runtime) }
}
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    var cancelledEpochs: [UInt64] = []
    var cancelledRuntimes: [WallpaperRuntimeKind?] = []
    @discardableResult func advanceWebLaunchIntentGeneration() -> UInt64 {
        cancelledEpochs.append(WallpaperManager.shared.playbackIntentEpoch)
        cancelledRuntimes.append(WallpaperManager.shared.playbackSwitch.requestedRuntime)
        return UInt64(cancelledEpochs.count)
    }
}
@main enum Harness {
    @MainActor static func main() {
        let manager = WallpaperManager.shared
        let service = SteamWorkshopService.shared
        let adapter = WallpaperEngine.shared.dedicatedWebHostAdapter as! WebDaemonHostAdapter
        let scene = SceneDaemonClient.shared
        // REAL_IDLE_ASSEMBLY
        precondition(adapter.mayPrepareIdleProcess?() == true)
        scene.hasRetainedOrRetiringTransport = true
        precondition(adapter.mayPrepareIdleProcess?() == false)
        scene.hasRetainedOrRetiringTransport = false
        precondition(manager.beginPlaybackIntent(runtime: .web) == 1)
        precondition(service.cancelledEpochs.isEmpty)
        // REAL_ASSEMBLY
        for runtime in [WallpaperRuntimeKind.video, .web, .scene, .systemStill] {
            let old = manager.playbackIntentEpoch
            let autoplay = ImportedVideoAutoplayGate.shared.claim()
            let cancellations = adapter.cancellations
            manager.pendingWallpaper = 1
            let epoch = manager.beginPlaybackIntent(runtime: runtime)
            precondition(epoch == old + 1)
            precondition(service.cancelledEpochs.last == epoch, "cancel before product epoch advanced")
            precondition(service.cancelledRuntimes.last! == runtime)
            precondition(scene.intents.last! == runtime)
            precondition(adapter.cancellations == cancellations + (runtime == .web ? 0 : 1))
            precondition(manager.pendingWallpaper == (runtime == .video ? 1 : nil))
            precondition(!ImportedVideoAutoplayGate.shared.isCurrent(autoplay))
        }
        let stopped = manager.beginPlaybackIntent()
        precondition(service.cancelledEpochs == [2, 3, 4, 5, 6])
        precondition(service.cancelledRuntimes.last! == nil && stopped == 6)
        precondition(manager.playbackSwitch.pending == nil && manager.playbackSwitch.committed == nil)
        let notifications = service.cancelledEpochs.count
        manager.onEffects = {
            manager.onEffects = nil
            _ = manager.beginPlaybackIntent(runtime: .scene)
        }
        let superseded = manager.beginPlaybackIntent(runtime: .web)
        precondition(manager.playbackIntentEpoch == superseded + 1)
        precondition(service.cancelledEpochs.count == notifications + 1
            && service.cancelledEpochs.last == superseded + 1
            && scene.intents.last! == .scene,
            "outer stale notification must not revoke the reentrant Scene intent")
        print("product-intent-preparation-cancellation-pass")
    }
}
'''
        harness_source = harness_source.replace("// REAL_BEGIN", source_block(manager, "func beginPlaybackIntent("))
        harness_source = harness_source.replace("// REAL_ASSEMBLY", source_block(assembly,
            "WallpaperManager.shared.playbackIntentDidAdvance ="))
        harness_source = harness_source.replace("// REAL_IDLE_ASSEMBLY", source_block(assembly,
            "adapter.mayPrepareIdleProcess ="))
        with tempfile.TemporaryDirectory(prefix="mwx-intent-cancellation-") as raw:
            directory = Path(raw)
            harness = directory / "Harness.swift"
            harness.write_text(harness_source)
            binary = directory / "harness"
            sources = ["WallpaperRuntimeSwitch.swift", "PlaybackSwitchTransaction.swift", "ImportedVideoAutoplayGate.swift",
                       "WallpaperPlaybackSequence.swift", "WallpaperRotationDeadline.swift", "ImportedVideoPlaybackAdmission.swift"]
            compilation = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-default-isolation", "MainActor",
                *[str(ROOT / "MyWallpaperX/Core/PlaybackControl" / name) for name in sources],
                str(ROOT / "MyWallpaperX/Models/WallpaperReference.swift"),
                str(ROOT / "MyWallpaperX/Models/WallpaperLibraryPage.swift"),
                str(harness), "-module-cache-path", str(directory / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("product-intent-preparation-cancellation-pass", result.stdout)

    def test_explicit_library_stop_preserves_video_retirement_until_physical_exit(self):
        """Actual action/Manager/Engine Stop, with only IPC peers controlled.

        No NSApplication, window, renderer, media, or child Process is used.
        The negative build removes the guard in a temporary source copy.
        """
        from script.tests.test_imported_video_autoplay_gate import GATE_SOURCES, MANAGER, product_harness
        from script.tests.test_ui_library_algorithms import declaration

        engine_path = ROOT / 'MyWallpaperX/Core/Playback/WallpaperEngine.swift'
        removal_path = MANAGER / 'WallpaperManager+Removal.swift'
        commands_path = ROOT / 'MyWallpaperX/App/WallpaperLibraryCommands.swift'
        fixture_path = ROOT / 'script/tests/fixtures/PlaybackExplicitStopHarness.swift'
        event_path = ROOT / 'MyWallpaperX/Core/Playback/WallpaperEngine+DaemonEvents.swift'
        pause_path = ROOT / 'MyWallpaperX/Core/Playback/WallpaperEngine+PlaybackControl.swift'
        types_path = ROOT / 'MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift'
        engine_text, removal = engine_path.read_text(), removal_path.read_text()
        commands = commands_path.read_text()
        shell = SUPPORT.replace('nonisolated enum WallpaperRuntimeKind: Hashable, Sendable { case video, web, scene, image }', '')
        shell = shell.replace('protocol PlaybackResourceLifetime: AnyObject {}', '')
        shell = shell.replace('struct VideoWallpaper { let path: String; var staticFramePath: String? = nil }',
            'struct VideoWallpaper { let path:String; var id:String{path}; var staticFramePath:String?=nil }')
        shell = shell.replace('@MainActor final class WallpaperEngine {',
            '@MainActor final class WallpaperEngine {\n    static var shared=WallpaperEngine()\n'
            '    static let playbackEndedNotification=Notification.Name("ended")\n'
            '    var playbackIntentEpoch:UInt64=0\n    var videoEndDeliveryAdmission:(()->Bool)?\n'
            '    var currentWebRecordID:String?\n    func setWebAudioSpectrumRequested(_ value:Bool){}')
        shell = shell.replace('func adoptIntentEpoch(_ epoch: UInt64) {}', declaration(engine_text, '    public func adoptIntentEpoch('))
        shell = shell.replace('func replayDeferredVideoEndIfNeeded() {}',
            declaration(event_path.read_text(), '    func replayDeferredVideoEndIfNeeded('))
        shell = shell.replace('// REAL_VIDEO_PAUSE', declaration(pause_path.read_text(), '    func sendPlaybackPaused('))
        shell = shell.replace('// REAL_WEB_PROPERTIES', '')
        types = types_path.read_text()
        shell += '\n' + '\n'.join(source_block(types, signature) for signature in (
            'struct WebWallpaperResourceGrant', 'struct WebWallpaperPropertyUpdate', 'extension WallpaperEngine'))
        owner = source_block(product_harness(), '@MainActor final class WallpaperManager: ObservableObject')
        owner = owner.replace('func stopCurrentPlayback(){_ = beginPlaybackIntent();currentWallpaper=nil;pendingWallpaper=nil;isPlaying=false;stopAutoSwitchTimer()}', '')
        owner = owner.replace('var autoSwitchTimer:Timer?',
            'var pendingManualNavigationWorkItem:DispatchWorkItem?\n    var pendingManualNavigationDirection:Int?\n'
            '    var autoSwitchTimer:Timer?')
        owner += '\nextension WallpaperManager {\n' + '\n'.join(declaration(removal, signature) for signature in (
            '    func clearCurrentWallpaperReference(', '    func stopCurrentPlayback(')) + '\n}\n'
        fixture = fixture_path.read_text().replace('// ACTUAL_PRIMARY_ACTIONS', '\n'.join(declaration(commands, signature) for signature in (
            '    func makePrimaryAction(', '    func makeApplyAction(', '    func stop(')))
        relative = [
            'Core/PlaybackControl/PlaybackIntentEpoch.swift', 'Models/WallpaperContent.swift',
            'Core/PlaybackControl/PlaybackSurfaceVisibility.swift', 'Core/Playback/DaemonProtocol.swift',
            'Core/DaemonKit/DaemonNewlineJSON.swift', 'Core/Playback/WallpaperEngine+SwitchExecution.swift',
            'Core/Playback/SystemMedia/SystemMediaSnapshot.swift', 'Core/Playback/SystemMedia/SystemMediaSnapshotStore.swift',
            'Core/SteamWorkshopWeb/Process/WebDaemonProtocol.swift',
            'Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift',
            'Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter+SwitchExecution.swift',
        ]
        originals = list(dict.fromkeys([*GATE_SOURCES, *[ROOT / 'MyWallpaperX' / name for name in relative]]))
        observed = list(dict.fromkeys([*originals, engine_path, removal_path, commands_path, fixture_path, event_path,
            pause_path, types_path, Path(__file__), ROOT / 'script/tests/test_imported_video_autoplay_gate.py',
            *MANAGER.glob('WallpaperManager*.swift')]))
        hashes = {str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        stop = declaration(engine_text, '    public func stopPlayback(')
        self.assertEqual(stop.count('guard !execution.retired else { continue }'), 1)
        reports = {}
        with tempfile.TemporaryDirectory(prefix='mwx-explicit-video-stop-', dir='/private/tmp') as raw:
            folder=Path(raw)
            copied=[]
            for path in originals:
                target=folder / path.name;target.write_bytes(path.read_bytes());copied.append(str(target))
            for label,body in [('before',stop.replace('guard !execution.retired else { continue }','')),('fixed',stop)]:
                source=folder / ('Harness-'+label+'.swift')
                source.write_text(shell+'\n'+owner+'\nextension WallpaperEngine {\n'
                    +declaration(engine_text,'    func beginPlaybackIntent(')+'\n'+body+'\n}\n'+fixture)
                binary=folder / ('checks-'+label)
                with open('/private/tmp/mywallpaperx-checkpoint-build.flock','a') as lock:
                    fcntl.flock(lock,fcntl.LOCK_EX)
                    built=subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',
                        *copied,str(source),'-module-cache-path',str(folder / 'modules'),'-o',str(binary)],
                        capture_output=True,text=True,timeout=150)
                self.assertEqual(built.returncode,0,built.stdout+built.stderr)
                ran=subprocess.run([str(binary)],capture_output=True,text=True,timeout=20)
                self.assertEqual(ran.returncode,0,ran.stdout+ran.stderr)
                reports[label]=json.loads(ran.stdout)
            failed={name for name,passed in reports['before'].items() if not passed}
            self.assertEqual(failed,{'explicit-stop-keeps-original-execution-owned-before-physical-exit',
                'repeated-generic-stop-keeps-one-live-retirement-owner',
                'explicit-stop-last-display-exit-settles-transaction-and-endpoint-once',
                'old-stop-retirement-callback-does-not-clear-new-pending'},reports['before'])
            self.assertTrue(all(reports['fixed'].values()),reports['fixed'])
            print(json.dumps({'negativeControlFailedChecks':sorted(failed),'fixed':reports['fixed']},sort_keys=True))
        self.assertEqual(hashes,{str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})

    def test_parent_endpoints_prepare_activate_finalize_cancel_and_exact_retirement(self):
        with tempfile.TemporaryDirectory(prefix="mwx-switch-endpoints-") as raw:
            directory = Path(raw)
            types = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift").read_text()
            support = directory / "Support.swift"
            pause = (ROOT / "MyWallpaperX/Core/Playback/WallpaperEngine+PlaybackControl.swift").read_text()
            web = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift").read_text()
            properties = "\n".join(source_block(web, marker) for marker in (
                "var currentWebResourceRootURL:", "var currentWebResourceGrants:",
                "func updateCurrentWebWallpaperProperties(", "private func mergedWebPropertiesJSON(",
                "private func jsonObjectDictionary("))
            shell = SUPPORT.replace("// REAL_VIDEO_PAUSE", source_block(pause, "func sendPlaybackPaused(")).replace("// REAL_WEB_PROPERTIES", properties)
            navigation = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+NavigationIdentity.swift").read_text()
            producers = "\n".join(source_block(navigation, marker) for marker in (
                "func loadTrackedNavigation(\n", "func reloadTrackedNavigation(on surface:",
                "func screenIDForStartedNavigation("))
            shell += PREPARATION_PRODUCER_SUPPORT.replace("// REAL_NAVIGATION_PRODUCERS", producers)
            support.write_text(shell + "\n" + source_block(types, "struct WebWallpaperResourceGrant")
                + "\n" + source_block(types, "struct WebWallpaperPropertyUpdate")
                + "\n" + source_block(types, "extension WallpaperEngine"))
            harness = directory / "Harness.swift"; harness.write_text(HARNESS)
            sources = [
                "Core/PlaybackControl/PlaybackSwitchTransaction.swift",
                "Core/PlaybackControl/PlaybackSurfaceVisibility.swift",
                "Core/Playback/DaemonProtocol.swift",
                "Core/DaemonKit/DaemonNewlineJSON.swift",
                "Core/Playback/WallpaperEngine+SwitchExecution.swift",
                "Core/Playback/SystemMedia/SystemMediaSnapshot.swift",
                "Core/Playback/SystemMedia/SystemMediaSnapshotStore.swift",
                "Core/SteamWorkshopWeb/Process/WebDaemonProtocol.swift",
                "Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift",
                "Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter+SwitchExecution.swift",
            ]
            for debug in (False, True):
                with self.subTest(debug=debug):
                    binary = directory / ("harness-debug" if debug else "harness-release")
                    compilation = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-default-isolation", "MainActor",
                        *(["-D", "DEBUG"] if debug else []),
                        *[str(ROOT / "MyWallpaperX" / item) for item in sources], str(support), str(harness), "-o", str(binary)],
                        capture_output=True, text=True, timeout=60)
                    self.assertEqual(compilation.returncode, 0, compilation.stderr)
                    modes = ([], ["--mwx-debug-web-startup-report"]) if debug else ([],)
                    for arguments in modes:
                        result = subprocess.run([str(binary), *arguments], capture_output=True, text=True, timeout=10)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertIn("playback-switch-endpoints-pass", result.stdout)

    def test_actual_engine_assembly_typechecks_against_endpoint_contract(self):
        with tempfile.TemporaryDirectory(prefix="mwx-engine-assembly-") as raw:
            directory = Path(raw)
            prefix = SUPPORT.split("@MainActor final class WallpaperEngine {", 1)[0]
            prefix = prefix.replace("struct VideoWallpaper {", "public struct VideoWallpaper {")
            prefix = (prefix[:prefix.index("final class DaemonPlaybackProcessRegistry")]
                      + prefix[prefix.index("final class PlaybackPolicyController"):])
            types = (ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift").read_text()
            support = directory / "Support.swift"
            support.write_text(prefix + ASSEMBLY_SUPPORT + source_block(types, "struct WebWallpaperResourceGrant")
                + "\n" + source_block(types, "struct WebWallpaperPropertyUpdate")
                + "\n" + source_block(types, "extension WallpaperEngine"))
            sources = [
                "Core/PlaybackControl/PlaybackSwitchTransaction.swift",
                "Core/PlaybackControl/PlaybackSurfaceVisibility.swift",
                "Core/Playback/DaemonProtocol.swift", "Core/DaemonKit/DaemonNewlineJSON.swift",
                "Core/DaemonKit/DaemonProcessTransport.swift",
                "Core/Playback/WallpaperEngine.swift", "Core/Playback/WallpaperEngine+SwitchExecution.swift",
                "Core/Playback/WallpaperEngine+DaemonEvents.swift",
                "Core/Playback/WallpaperEngine+DaemonSessionLifecycle.swift",
                "Core/Playback/WallpaperEngine+PlaybackControl.swift",
                "Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift",
                "Core/Playback/SystemMedia/SystemMediaSnapshot.swift",
                "Core/Playback/SystemMedia/SystemMediaSnapshotStore.swift",
                "Core/SteamWorkshopWeb/Process/WebDaemonProtocol.swift",
                "Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter.swift",
                "Core/SteamWorkshopWeb/Process/WebDaemonHostAdapter+SwitchExecution.swift",
            ]
            result = subprocess.run(["xcrun", "swiftc", "-typecheck", "-default-isolation", "MainActor",
                *[str(ROOT / "MyWallpaperX" / item) for item in sources], str(support)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
