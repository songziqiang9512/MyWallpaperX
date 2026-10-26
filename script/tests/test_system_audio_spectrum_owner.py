"""Exercise the real Engine initializer and factory at recording audio boundaries.

The service records construction and exposes the supplied callbacks; it never
opens an audio device. Web setup, demand observation and display scanning are
recording leaves. The production initializer, stored fields and callback factory
are inserted unchanged, so the former placeholder remains a two-constructor
counterexample when this gate is overlaid on the previous implementation.
The Manager gate uses real library request/Sequence/preparation admission;
provider availability and native IPC remain recording leaves. Workspace
startup restoration is outside this focused projection gate.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from script.tests.test_web_compat_parity import source_block
from script.tests.test_steam_library_interactions import method
from script.tests.test_imported_video_autoplay_gate import GATE_SOURCES


ROOT = Path(__file__).resolve().parents[2]
PLAYBACK = ROOT / "MyWallpaperX/Core/Playback"

SUPPORT = r'''
import AppKit
import Foundation

nonisolated final class OwnerProbe: @unchecked Sendable {
    static let shared = OwnerProbe()
    private let lock = NSLock()
    private var constructions: [ObjectIdentifier] = []
    private var eventCounts: [(String, Int)] = []
    private var serviceUses: [ObjectIdentifier] = []
    private var webDeliveries: [ObjectIdentifier] = []

    func constructed(_ service: SystemAudioSpectrumService) {
        lock.withLock { constructions.append(ObjectIdentifier(service)) }
    }
    func event(_ name: String) {
        lock.withLock { eventCounts.append((name, constructions.count)) }
    }
    func use(_ service: SystemAudioSpectrumService) {
        lock.withLock { serviceUses.append(ObjectIdentifier(service)) }
    }
    func webDelivery(_ delivery: PlaybackSpectrumDelivery) {
        lock.withLock { webDeliveries.append(ObjectIdentifier(delivery)) }
    }
    var snapshot: (constructors: Int, events: [(String, Int)],
                   services: [ObjectIdentifier], webDeliveries: [ObjectIdentifier]) {
        lock.withLock { (constructions.count, eventCounts, serviceUses, webDeliveries) }
    }
}

nonisolated final class PlaybackSpectrumDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var overlays: [[Float]] = []
    private var web: [[Float]] = []
    private var scene: [SceneAudioSpectrumRoutedFrame] = []
    func publishOverlay(_ levels: [Float]) { lock.withLock { overlays.append(levels) } }
    func publishWeb(_ levels: [Float]) { lock.withLock { web.append(levels) } }
    func publishScene(_ frame: SceneAudioSpectrumRoutedFrame) { lock.withLock { scene.append(frame) } }
    var snapshot: (overlays: [[Float]], web: [[Float]], scene: [SceneAudioSpectrumRoutedFrame]) {
        lock.withLock { (overlays, web, scene) }
    }
}

nonisolated final class SystemAudioSpectrumService: @unchecked Sendable {
    typealias LevelsHandler = @Sendable ([Float]) -> Void
    typealias SceneLevelsHandler = @Sendable (
        [Float], [Float], [Float], [Float], [Float], [Float], SceneAudioSpectrumCaptureToken
    ) -> Void
    let barCount: Int
    private let onLevels: LevelsHandler?
    private let onWebLevels: LevelsHandler?
    private let onSceneLevels: SceneLevelsHandler?
    init(barCount: Int, onLevels: LevelsHandler? = nil,
         onWebLevels: LevelsHandler? = nil, onSceneLevels: SceneLevelsHandler? = nil) {
        self.barCount = barCount
        self.onLevels = onLevels
        self.onWebLevels = onWebLevels
        self.onSceneLevels = onSceneLevels
        OwnerProbe.shared.constructed(self)
    }
    func emitOverlay(_ values: [Float]) { onLevels?(values) }
    func emitWeb(_ values: [Float]) { onWebLevels?(values) }
    func emitScene(left: [Float], right: [Float], left32: [Float], right32: [Float],
                   left64: [Float], right64: [Float], token: SceneAudioSpectrumCaptureToken) {
        onSceneLevels?(left, right, left32, right32, left64, right64, token)
    }
}

protocol WebWallpaperHostAdapter: AnyObject {
    var eventHandler: ((Int) -> Void)? { get set }
}
final class WebDaemonHostAdapter: WebWallpaperHostAdapter {
    var eventHandler: ((Int) -> Void)?
    init(spectrumDelivery: PlaybackSpectrumDelivery) {
        OwnerProbe.shared.webDelivery(spectrumDelivery)
        OwnerProbe.shared.event("web-host")
    }
}

// Keep the production registration expression without installing an observer.
final class NotificationCenter {
    static let `default` = NotificationCenter()
    func addObserver(_ observer: Any, selector: Selector,
                     name: NSNotification.Name?, object: Any?) {
        OwnerProbe.shared.event("screen-observer")
    }
}

// ENGINE_DECLARATION
    // ENGINE_FIELDS
    // ENGINE_INITIALIZER

    func handleWebHostEvent(_ event: Int) { OwnerProbe.shared.event("web-event") }
    func configureWebSwitchCallbacks() {
        OwnerProbe.shared.event("web-callbacks")
        OwnerProbe.shared.use(systemAudioSpectrumService)
    }
    func observeSceneAudioSpectrumDemand() {
        OwnerProbe.shared.event("scene-demand")
        OwnerProbe.shared.use(systemAudioSpectrumService)
    }
    @objc func handleScreenParametersChanged() {}
    func scanDisplays() {
        OwnerProbe.shared.event("display-scan")
        OwnerProbe.shared.use(systemAudioSpectrumService)
    }
}

extension WallpaperEngine {
    // ENGINE_FACTORY
}

@main enum Harness {
    @MainActor static func main() throws {
        let engine = WallpaperEngine()
        let initialized = OwnerProbe.shared.snapshot
        var checks: [String: Bool] = [:]
        checks["exactlyOneServiceConstructedBeforeInitializerReturns"] = initialized.constructors == 1
        checks["serviceExistsBeforeEveryExternalSetupLeaf"] = initialized.events.map { $0.0 }
            == ["web-host", "web-callbacks", "scene-demand", "screen-observer", "display-scan"]
            && initialized.events.allSatisfy { $0.1 == 1 }
        let service = engine.systemAudioSpectrumService
        let delivery = engine.spectrumDelivery
        checks["setupAndLaterReadsUseTheSameService"] = initialized.services.count == 3
            && initialized.services.allSatisfy { $0 == ObjectIdentifier(service) }
            && engine.systemAudioSpectrumService === service
        checks["webHostReceivesTheEngineDelivery"] = initialized.webDeliveries == [ObjectIdentifier(delivery)]
        checks["initialLevelsAndServiceUseTheConfiguredDefaultBandCount"] = service.barCount == WallpaperEngine.defaultSpectrumBarCount
            && engine.currentSpectrumLevels == Array(repeating: 0, count: service.barCount)

        let overlay: [Float] = [0.125, 0.875]
        let web = (0..<128).map { Float($0) / 128 }
        let left = (0..<16).map { Float($0 + 1) }
        let right = (0..<16).map { Float($0 + 21) }
        let left32 = (0..<32).map { Float($0 + 41) }
        let right32 = (0..<32).map { Float($0 + 81) }
        let left64 = (0..<64).map { Float($0 + 121) }
        let right64 = (0..<64).map { Float($0 + 201) }
        let token = SceneAudioSpectrumCaptureToken(scopeEpoch: 73, includesCurrentProcessOutput: true)
        service.emitOverlay(overlay)
        let afterOverlay = delivery.snapshot
        checks["overlayCallbackTargetsOnlyTheEngineOverlayDelivery"] = afterOverlay.overlays == [overlay]
            && afterOverlay.web.isEmpty && afterOverlay.scene.isEmpty
        service.emitWeb(web)
        let afterWeb = delivery.snapshot
        checks["webCallbackTargetsOnlyTheEngineWebDelivery"] = afterWeb.overlays == [overlay]
            && afterWeb.web == [web] && afterWeb.scene.isEmpty
        service.emitScene(left: left, right: right, left32: left32, right32: right32,
                          left64: left64, right64: right64, token: token)
        let afterScene = delivery.snapshot
        checks["sceneCallbackPreservesEveryBandArrayAndCaptureToken"] = afterScene.scene.count == 1
            && afterScene.scene.first?.left == left && afterScene.scene.first?.right == right
            && afterScene.scene.first?.left32 == left32 && afterScene.scene.first?.right32 == right32
            && afterScene.scene.first?.left64 == left64 && afterScene.scene.first?.right64 == right64
            && afterScene.scene.first?.captureToken == token
            && afterScene.overlays == [overlay] && afterScene.web == [web]
        let nextToken = SceneAudioSpectrumCaptureToken(scopeEpoch: 74, includesCurrentProcessOutput: false)
        service.emitScene(left: right, right: left, left32: right32, right32: left32,
                          left64: right64, right64: left64, token: nextToken)
        let final = delivery.snapshot
        checks["laterSceneCallbackUsesItsOwnArraysAndToken"] = final.scene.count == 2
            && final.scene.last?.left == right && final.scene.last?.right == left
            && final.scene.last?.left32 == right32 && final.scene.last?.right32 == left32
            && final.scene.last?.left64 == right64 && final.scene.last?.right64 == left64
            && final.scene.last?.captureToken == nextToken
        checks["callbackDeliveryDoesNotReplaceTheService"] = OwnerProbe.shared.snapshot.constructors == 1
            && engine.systemAudioSpectrumService === service
        let result: [String: Any] = ["checks": checks, "constructorCount": initialized.constructors,
            "constructionCountsAtSetup": initialized.events.map { ["leaf": $0.0, "count": $0.1] as [String: Any] }]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SystemAudioSpectrumOwnerTests(unittest.TestCase):
    def test_manager_seeds_spectrum_once_and_projects_real_changes_into_play_payloads(self):
        core = ROOT / 'MyWallpaperX/Modules/VideoLibrary/Core'
        settings = (core / 'WallpaperManager+PlaybackSettings.swift').read_text()
        manager = (core / 'WallpaperManager.swift').read_text()
        switching = (core / 'WallpaperManager+RuntimeSwitching.swift').read_text()
        application = (core / 'WallpaperManager+WallpaperApplication.swift').read_text()
        audio = (PLAYBACK / 'WallpaperEngine+SystemAudioSpectrum.swift').read_text()
        execution = (PLAYBACK / 'WallpaperEngine+SwitchExecution.swift').read_text()
        start = manager.index('        $settings\n')
        end = manager.index('        .store(in: &cancellables)', start) + len('        .store(in: &cancellables)')
        bindings = manager[start:end]
        start = execution.index('            var command = DaemonCommand(action: "play"')
        end = execution.index('            command.cohortID', start)
        play_command = execution[start:end] + '\n            return command'
        harness = r'''
import Foundation
import Combine
import QuartzCore
enum Runtime { case video, web, scene, other }
struct VideoWallpaper { let id: String; let path: String; var staticFramePath: String? = nil }
enum PlaybackSurfaceVisibility { struct Evidence: Codable {} }
struct HotkeySettingsSnapshot: Equatable { init(settings: WallpaperSettings) {} }
@MainActor final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager(); func update(with settings: WallpaperSettings) {}
}
@MainActor final class PlaybackVolumeState {
    static let shared = PlaybackVolumeState(); func setNormalizedVolume(_ value: Float) {}
}
@MainActor final class PlaybackPolicyController {
    static let shared = PlaybackPolicyController(); func updateSettings(_ value: WallpaperSettings) {}
}
@MainActor final class PlaybackCommandMultiplexer {
    enum Command { case setVolume(Float) }
    static let shared = PlaybackCommandMultiplexer(); func dispatch(_ value: Command) {}
}
@MainActor final class SceneDaemonClient {
    static let shared = SceneDaemonClient()
    var stopPlaybackRequested: (() -> Void)?
    var switchPrepared: ((PlaybackSwitchTicket, PlaybackSwitchEndpoint) -> Void)?
    var switchVisible: ((PlaybackSwitchTicket, UUID) -> Void)?
    var switchFailed: ((PlaybackSwitchTicket, String) -> Void)?, switchLost: ((PlaybackSwitchTicket, String) -> Void)?
    var multiDisplayEnabled = false
    func setMultiDisplayEnabled(_ value: Bool) { multiDisplayEnabled = value }
}
@MainActor final class RecordingAudioService {
    var changes: [(SystemAudioSpectrumStyle, SystemAudioSpectrumSensitivity, Int)] = []
    func updateConfiguration(style: SystemAudioSpectrumStyle, sensitivity: SystemAudioSpectrumSensitivity, barCount: Int) {
        changes.append((style, sensitivity, barCount))
    }
}
@MainActor final class WallpaperEngine {
    final class Process { var isRunning = true }
    final class Session { let process = Process(); var commands: [DaemonCommand] = [] }
    struct Delivery { var currentOverlayLevels: [Float] = [] }
    static let shared = WallpaperEngine()
    var videoEndDeliveryAdmission: (() -> Bool)?
    var switchPrepared: ((PlaybackSwitchTicket, PlaybackSwitchEndpoint) -> Void)?
    var switchVisible: ((PlaybackSwitchTicket, UUID) -> Void)?
    var switchFailed: ((PlaybackSwitchTicket, String) -> Void)?, switchLost: ((PlaybackSwitchTicket, String) -> Void)?
    var currentSystemAudioSpectrumEnabled = false
    var currentSystemAudioSpectrumBarCount = 28, currentSystemAudioSpectrumColorHex = "default"
    var currentSystemAudioSpectrumOffsetX: Float = 0, currentSystemAudioSpectrumOffsetY: Float = 0
    var currentSystemAudioSpectrumPeakCapsEnabled = true
    var currentSpectrumLevels: [Float] = [], currentPlaybackContentKind = Runtime.other
    var currentWebAudioSpectrumRequested = false
    var effectiveVolumeNormalized: Float = 0, targetPlaybackRate: Float = 1
    var displaySessions: [Int: Session] = [:]
    let systemAudioSpectrumService = RecordingAudioService()
    var spectrumDelivery = Delivery()
    func refreshSystemAudioSpectrumCapture() {}
    func currentWebSpectrumSnapshot() -> [Float]? { nil }
    func clearedWebSpectrumLevels() -> [Float] { [] }
    enum Command { case pushAudioSpectrum([Float]) }
    func dispatchWebRuntimeCommand(_ value: Command) {}
    func send(_ command: DaemonCommand, to session: Session) { session.commands.append(command) }
    func setVolume(_ value: Float) { effectiveVolumeNormalized = value / 100 }
    func setPlaybackRate(_ value: Float) { targetPlaybackRate = value }
    func setFillMode(_ value: String) {}
    func setLoopCurrentItem(_ value: Bool) {}
    func updateWebDisplayConfiguration(multiDisplayEnabled: Bool) {}
    // Native process/IPC is a recording leaf; the play payload below is real.
    func prepareVideoSwitch(_ wallpaper: VideoWallpaper, ticket: PlaybackSwitchTicket,
        multiDisplayEnabled: Bool, videoFillMode: String, shouldLoopCurrentItem: Bool) {
        precondition(ticket.runtime == .video)
        for session in displaySessions.values {
            send(playCommand(wallpaper, request: Int(ticket.epoch)), to: session)
        }
    }
    func playCommand(_ wallpaper: VideoWallpaper, request: Int) -> DaemonCommand {
        let path = wallpaper.path, videoFillMode = "aspectFill", shouldLoopCurrentItem = true
        struct Execution { let path: String }
        let execution = Execution(path: path)
        // PLAY_COMMAND
    }
    // CONFIGURE_SPECTRUM
}
extension Notification.Name {
    static let onlineDownloadsPlaybackPathDidChange = Notification.Name("audio-owner-playback-path")
}
@MainActor final class WallpaperManager {
    @Published var settings = WallpaperSettings()
    var cancellables = Set<AnyCancellable>()
    var lastEngineProjectionBaseline: WallpaperSettings?
    var lastAppliedHotkeySettings: HotkeySettingsSnapshot?
    var runtimeSwitchingConfigured = false
    var activeWallpaperRuntime = Runtime.other
    var currentWallpaper: VideoWallpaper?, pendingWallpaper: VideoWallpaper?
    var playbackSourceContext = 0, currentSelectionContext = 0
    var libraryPlaybackSequence = WallpaperPlaybackSequence()
    var libraryRotationDeadline = WallpaperRotationDeadline()
    var libraryPlaybackSnapshotProvider: ((WallpaperReference?, WallpaperPlaybackSequence.Source,
        WallpaperPlaybackCause) -> WallpaperPlaybackSequence.Snapshot?)?
    var libraryPlaybackDispatcher: ((WallpaperPlaybackSequence.Pending) -> Bool)?
    var playbackSwitch = PlaybackSwitchTransaction()
    var playbackIntentEpoch: UInt64 { playbackSwitch.epoch }
    var playbackIntentDidAdvance: ((WallpaperRuntimeKind?) -> Void)?
    var switchSelections: [UUID: RuntimeSwitchSelection] = [:]
    func bindSettings() {
        // SETTINGS_BINDINGS
    }
    func sanitizeSystemHotkeySettingsIfNeeded() {}
    func scheduleSettingsAutoPersist() {}
    func switchPrepared(_ ticket: PlaybackSwitchTicket, endpoint: PlaybackSwitchEndpoint) {}
    func switchVisible(_ ticket: PlaybackSwitchTicket, executionID: UUID) {}
    func switchFailed(_ ticket: PlaybackSwitchTicket, reason: String) { preconditionFailure(reason) }
    func switchLost(_ ticket: PlaybackSwitchTicket, reason: String) {}
    // This gate stops at preparation; endpoint effects/deadlines do not run.
    func runSwitchEffects(_ effects: [PlaybackSwitchTransaction.Effect]) {}
    func scheduleSwitchDeadline(_ ticket: PlaybackSwitchTicket) {}
    func stopCurrentPlayback() {}
    func admitsDeferredVideoEnd() -> Bool { true }
    func normalizedPath(_ value: String) -> String { value }
    func pathExists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    func handleMissingWallpaperDuringSwitch(_ wallpaper: VideoWallpaper, userInitiated: Bool) { preconditionFailure() }
    func recordInitialIndexUserSelection(_ wallpaper: VideoWallpaper) {}
    func recordPlaybackHistoryIfNeeded(current: VideoWallpaper?, targetNormalizedPath: String, enabled: Bool) {}
    func updateCurrentWallpaperIndex(for id: String) {}
    func updateRecentWallpapers(_ wallpaper: VideoWallpaper) {}
    func startAutoSwitchTimer() {}
    func stopAutoSwitchTimer() {}
    func shouldLoopCurrentItemInEngine(settings: WallpaperSettings? = nil) -> Bool { true }
    // MANAGER_METHODS
}
@main enum Harness {
    @MainActor static func main() throws {
        let engine = WallpaperEngine.shared
        let path = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("test.mov")
        try Data("fixture".utf8).write(to: path)
        let movie = VideoWallpaper(id: "video", path: path.path)
        func matches(_ command: DaemonCommand, _ settings: WallpaperSettings) -> Bool {
            command.spectrumEnabled == settings.systemAudioSpectrumEnabled
                && command.spectrumBarCount == settings.systemAudioSpectrumBarCount
                && command.spectrumColorHex == settings.systemAudioSpectrumColorHex
                && command.spectrumOffsetX == Float(settings.systemAudioSpectrumOffsetX)
                && command.spectrumOffsetY == Float(settings.systemAudioSpectrumOffsetY)
                && command.spectrumPeakCapsEnabled == settings.systemAudioSpectrumPeakCapsEnabled
        }
        for initial in [Runtime.video, .web, .scene] {
            for enabled in [false, true] {
                engine.displaySessions = [:]; engine.systemAudioSpectrumService.changes = []
                engine.currentPlaybackContentKind = initial
                let manager = WallpaperManager(); manager.activeWallpaperRuntime = initial
                let reference = WallpaperReference(provider: .videoLibrary, sourceID: movie.id)
                // Provider availability is supplied; original request/dispatch,
                // Sequence, pending admission and Manager prepare remain real.
                manager.libraryPlaybackSnapshotProvider = { requested, source, _ in
                    guard requested == reference, source == .single(reference) else { return nil }
                    return try! WallpaperPlaybackSequence.Snapshot(source: source, revision: 1,
                        entries: [.init(reference: reference, runtime: .video, isPlayable: true)])
                }
                manager.libraryPlaybackDispatcher = { [weak manager] pending in
                    guard let manager, pending.proposal.entry.reference == reference else { return false }
                    manager.setAsWallpaper(movie, libraryPending: pending)
                    return true
                }
                manager.settings.systemAudioSpectrumEnabled = enabled
                manager.settings.systemAudioSpectrumStyle = .banded
                manager.settings.systemAudioSpectrumSensitivity = .lively
                manager.settings.systemAudioSpectrumBarCount = 36
                manager.settings.systemAudioSpectrumColorHex = "#123456"
                manager.settings.systemAudioSpectrumOffsetX = 0.12
                manager.settings.systemAudioSpectrumOffsetY = -0.21
                manager.settings.systemAudioSpectrumPeakCapsEnabled = false
                manager.settings.multiDisplayEnabled = false
                manager.bindSettings()
                manager.configureRuntimeSwitching(); manager.configureRuntimeSwitching()
                // Capture the actual post-configuration play payload; this
                // does not exercise Workspace startup restoration.
                let seededPlayCommand = engine.playCommand(
                    .init(id: "seeded-play", path: "/not-read"), request: 0)
                precondition(engine.systemAudioSpectrumService.changes.count == 1,
                    "configuration must seed the engine once before play")
                precondition(matches(seededPlayCommand, manager.settings))
                precondition(SceneDaemonClient.shared.multiDisplayEnabled == false)
                let configured = engine.systemAudioSpectrumService.changes[0]
                precondition(configured.0 == .banded && configured.1 == .lively && configured.2 == 36)
                engine.displaySessions = [1: .init(), 2: .init()]
                manager.setAsWallpaper(movie); manager.setAsWallpaper(movie)
                precondition(engine.systemAudioSpectrumService.changes.count == 1,
                    "first and later video selection must not reset spectrum configuration")
                for session in engine.displaySessions.values {
                    precondition(session.commands.count == 2 && session.commands.allSatisfy {
                        $0.action == "play" && matches($0, manager.settings)
                    }, "each new display/helper gets the complete seed in its play payload")
                    session.commands = []
                }
                manager.settings.volume = 27
                manager.settings.pauseWhenIdle.toggle()
                manager.applyEngineSettings(reloadWallpaper: false)
                precondition(engine.systemAudioSpectrumService.changes.count == 1,
                    "unrelated settings and policy apply must not clear spectrum")
                var imported = manager.settings
                imported.systemAudioSpectrumColorHex = "#abcdef"
                imported.systemAudioSpectrumBarCount = 24
                imported.systemAudioSpectrumEnabled.toggle()
                manager.settings = imported // same published write used by preferences import
                manager.applyEngineSettings(reloadWallpaper: false)
                precondition(engine.systemAudioSpectrumService.changes.count == 2)
                for session in engine.displaySessions.values {
                    precondition(session.commands.count == 1 && session.commands[0].action == "setSpectrumEnabled"
                        && matches(session.commands[0], imported),
                        "willSet projection must use incoming values exactly once")
                    session.commands = []
                }
                manager.settings = .defaults // same published write used by fresh-install reset
                manager.applyEngineSettings(reloadWallpaper: false)
                precondition(engine.systemAudioSpectrumService.changes.count == 3)
                for session in engine.displaySessions.values {
                    precondition(session.commands.count == 1 && matches(session.commands[0], .defaults))
                }
                manager.setAsWallpaper(movie)
                precondition(engine.systemAudioSpectrumService.changes.count == 3)
                let restarted = WallpaperEngine.Session()
                engine.send(engine.playCommand(movie, request: 2), to: restarted)
                precondition(matches(restarted.commands[0], .defaults), "replacement helper must inherit current configuration")
            }
        }
        print("manager-spectrum-projection-pass")
    }
}
'''
        methods = '\n'.join(method(settings, signature) for signature in [
            '    func applyPlaybackRateToEngine(', '    func applySystemAudioSpectrumToEngine(',
            '    func seedEngineProjectionFromPersistedSettings(', '    func projectEngineSettingsIfChanged(',
            '    func projectLoopPolicyToEngine(', '    func applyEngineSettings(',
        ]) + '\n' + '\n'.join(method(switching, signature) for signature in [
            '    func configureRuntimeSwitching(', '    enum RuntimeSwitchSelection',
            '    func requestLibraryPlayback(reference: WallpaperReference, from snapshot:',
            '    func requestLibraryPlayback(reference: WallpaperReference, source:',
            '    func dispatchLibraryPlayback(', '    func acceptsLibraryPlayback(',
            '    func acceptsImportedVideoPlayback(', '    func prepareVideoSwitch(',
        ]) + '\n' + method(manager, '    func beginPlaybackIntent(') \
            + '\n' + method(application, '    func setAsWallpaper(')
        for marker, fragment in [
            ('// SETTINGS_BINDINGS', bindings), ('// MANAGER_METHODS', methods),
            ('// CONFIGURE_SPECTRUM', method(audio, '    public func configureSystemAudioSpectrum(')),
            ('// PLAY_COMMAND', play_command),
        ]:
            harness = harness.replace(marker, fragment)
        with tempfile.TemporaryDirectory(prefix='mwx-manager-audio-projection-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Harness.swift'; source.write_text(harness)
            binary = work / 'projection'
            compiled = subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                *map(str, GATE_SOURCES),
                str(ROOT / 'MyWallpaperX/Models/WallpaperSettings.swift'),
                str(ROOT / 'MyWallpaperX/Models/WallpaperControls.swift'),
                str(PLAYBACK / 'DaemonProtocol.swift'), str(source),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('manager-spectrum-projection-pass', run.stdout)

    def test_initializer_owns_one_eager_service_with_all_callbacks(self):
        engine = (PLAYBACK / "WallpaperEngine.swift").read_text()
        audio = (PLAYBACK / "WallpaperEngine+SystemAudioSpectrum.swift").read_text()
        delivery = (PLAYBACK / "PlaybackSpectrumDelivery.swift").read_text()
        scene = (ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneAudioSpectrum.swift").read_text()
        fields = []
        for name in ["dedicatedWebHostAdapter", "currentSpectrumLevels", "systemAudioSpectrumService",
                     "spectrumDelivery", "defaultSpectrumBarCount"]:
            matches = re.findall(r"^    (?:(?:lazy|static) )*(?:let|var) " + re.escape(name)
                                 + r"(?:\s*[:=]).*$", engine, re.MULTILINE)
            self.assertEqual(len(matches), 1, f"one production field declaration required: {name}")
            fields.append(matches[0])
        header = re.search(r"^public final class WallpaperEngine: NSObject \{$", engine, re.MULTILINE)
        self.assertIsNotNone(header)
        source = SUPPORT.replace("// ENGINE_DECLARATION", header.group(0))
        source = source.replace("// ENGINE_FIELDS", "\n".join(fields))
        source = source.replace("// ENGINE_INITIALIZER", source_block(engine, "override init()"))
        source = source.replace("// ENGINE_FACTORY", source_block(audio, "makeSystemAudioSpectrumService("))
        source = source_block(scene, "struct SceneAudioSpectrumCaptureToken:") + "\n" + source
        source = source_block(delivery, "struct SceneAudioSpectrumRoutedFrame:") + "\n" + source
        with tempfile.TemporaryDirectory(prefix="mwx-audio-owner-", dir="/private/tmp") as folder:
            work = Path(folder)
            swift = work / "Harness.swift"
            swift.write_text(source)
            binary = work / "audio-owner"
            build = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                                    "-parse-as-library", str(swift), "-module-cache-path", str(work / "modules"),
                                    "-o", str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                                 capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            result = json.loads(run.stdout)
            if proof := os.environ.get("MWX_SYSTEM_AUDIO_OWNER_PROOF_DIR"):
                output = Path(proof)
                output.mkdir(parents=True, exist_ok=True)
                (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
                (output / "runtime.log").write_text(run.stderr)
            self.assertTrue(result["checks"])
            for name, passed in result["checks"].items():
                with self.subTest(name=name, constructorCount=result["constructorCount"]):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
