"""Execute the native parent Video/Web switch owners with controlled IPC peers."""
from pathlib import Path
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
    final class DisplayDaemonSession {
        let displayID: UInt32; let transport: DaemonProcessTransport
        var nextRequestID = 0
        var latestRequestedPlayRequestID: Int?, latestPreparedPlayRequestID: Int?
        var latestCommittedPlayRequestID: Int?, latestReadyPlayRequestID: Int?, latestFinalizedPlayRequestID: Int?
        var process: FakeProcess { transport.process }
        init(_ displayID: UInt32) { self.displayID = displayID; transport = .init(executableURL: URL(fileURLWithPath: "/unused"), arguments: []) }
    }
    struct ActiveVideoPlayback { let id = UUID(); let wallpaper: VideoWallpaper; let path: String; let multiDisplayEnabled: Bool }
    static let playbackReadyNotification = Notification.Name("ready")
    static let playbackFailedNotification = Notification.Name("failed")
    var switchPrepared: ((PlaybackSwitchTicket, PlaybackSwitchEndpoint)->Void)?
    var switchVisible: ((PlaybackSwitchTicket, UUID)->Void)?
    var switchFailed: ((PlaybackSwitchTicket, String)->Void)?
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
    func normalizedPath(_ path: String) -> String { path }
    func adoptIntentEpoch(_ epoch: UInt64) {}
    func scanDisplays() {}
    // REAL_VIDEO_PAUSE
    func refreshVideoSpectrumTargets() {}
    func replayDeferredVideoEndIfNeeded() {}
    func ensureSession(for display: UInt32) -> DisplayDaemonSession? {
        if let session = displaySessions[display] { return session }
        let session = DisplayDaemonSession(display); displaySessions[display] = session
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


HARNESS = r'''
import AppKit
import Foundation
@main enum Harness {
    @MainActor static func main() throws {
        func ticket(_ kind: WallpaperRuntimeKind) -> PlaybackSwitchTicket { .init(epoch: 1, id: UUID(), runtime: kind) }
        func evidence(display: UInt32, window: UInt32 = 10, pid: Int32) -> PlaybackSurfaceVisibility.Evidence {
            let rect = PlaybackSurfaceVisibility.Rect(CGRect(x: 0, y: 0, width: 200, height: 100))
            return .init(displayID: display, windowID: window, expectedPID: pid, expectedLevel: 2,
                displayExists: true, localFrame: rect, screenFrame: rect, displayFrame: rect,
                localLevel: 2, localAlpha: 1, visible: true, miniaturized: false, onActiveSpace: true,
                serverPID: pid, serverFrame: rect, serverLevel: 2, serverAlpha: 1, onscreen: true)
        }
        func videoEvent(_ type: String, _ execution: WallpaperEngine.VideoSwitchExecution,
                        _ session: WallpaperEngine.DisplayDaemonSession, prepared: Bool = true) -> DaemonEvent {
            var event = DaemonEvent(type: type, displayID: session.displayID,
                requestID: execution.requests[session.displayID], message: nil, videoPath: execution.path, contentKind: "video")
            event.cohortID = execution.id; event.activationID = execution.activationID
            event.preparationGeneration = prepared ? 1 : nil
            event.visibility = [evidence(display: session.displayID, pid: session.process.processIdentifier)]
            return event
        }
        let engine = WallpaperEngine()
        engine.playbackPaused = true
        var videoEndpoints: [UUID: PlaybackSwitchEndpoint] = [:], videoVisible: [UUID] = []
        engine.switchPrepared = { _, endpoint in videoEndpoints[endpoint.id] = endpoint }
        engine.switchVisible = { _, id in videoVisible.append(id) }
        engine.switchFailed = { _, _ in }
        func prepareVideo(_ path: String) -> WallpaperEngine.VideoSwitchExecution {
            engine.prepareVideoSwitch(.init(path: path), ticket: ticket(.video), multiDisplayEnabled: true,
                videoFillMode: "fill", shouldLoopCurrentItem: false)
            return engine.videoCandidate!
        }
        func preparedVideo(_ execution: WallpaperEngine.VideoSwitchExecution) {
            for session in execution.sessions.values { engine.videoDidPrepare(videoEvent("prepared", execution, session), session: session) }
        }
        func visibleVideo(_ execution: WallpaperEngine.VideoSwitchExecution) {
            for session in execution.sessions.values { engine.videoDidBecomeVisible(videoEvent("ready", execution, session), session: session) }
        }
        let a = prepareVideo("/A"); preparedVideo(a)
        for session in a.sessions.values {
            let command = try JSONDecoder().decode(DaemonCommand.self, from: Data(session.transport.sent.last!.dropLast()))
            precondition(command.action == "pause", "new Video request lost current user pause")
        }
        precondition(videoEndpoints.count == 1 && !a.activated && engine.currentContentPath == nil)
        let endpointA = videoEndpoints[a.id]!
        endpointA.activate(); visibleVideo(a)
        precondition(videoVisible == [a.id] && engine.currentContentPath == nil)
        endpointA.finalize(); precondition(engine.currentContentPath == "/A")
        let b = prepareVideo("/B"); preparedVideo(b)
        precondition(engine.currentContentPath == "/A", "preparation overwrote committed Video facts")
        let endpointB = videoEndpoints[b.id]!
        endpointB.activate(); visibleVideo(b)
        let queuedVideoTicket = ticket(.video)
        engine.prepareVideoSwitch(.init(path: "/queued"), ticket: queuedVideoTicket,
            multiDisplayEnabled: true, videoFillMode: "fill", shouldLoopCurrentItem: false)
        precondition(engine.videoCandidate === b && engine.deferredVideoPreparation?.ticket == queuedVideoTicket && !b.cancelling)
        var queueCancelled = false
        engine.cancelSwitch(ticket: queuedVideoTicket) { queueCancelled = true }
        precondition(queueCancelled && engine.deferredVideoPreparation == nil && engine.videoCandidate === b)
        var sameTypeRetired = false
        endpointA.retire(nil) { sameTypeRetired = true }
        precondition(sameTypeRetired)
        endpointB.finalize()
        precondition(engine.currentContentPath == "/B")
        precondition(engine.displaySessions.count == 2 && engine.displaySessions.values.allSatisfy { !$0.transport.stopRequested },
            "old same-kind retire stopped the successor's shared helper")
        let c = prepareVideo("/C"); var cancelled = false
        engine.cancelSwitch(ticket: c.ticket) { cancelled = true }
        precondition(!cancelled)
        let d = prepareVideo("/D")
        for session in c.sessions.values { engine.videoDidCancel(videoEvent("cancelled", c, session, prepared: false), session: session) }
        precondition(cancelled && engine.videoCandidate === d && engine.currentContentPath == "/B")
        visibleVideo(c); precondition(engine.currentContentPath == "/B")
        var videoActivity: Bool? = nil
        endpointB.setOutputActive(false) { videoActivity = $0 }
        for session in b.sessions.values {
            let command = try JSONDecoder().decode(DaemonCommand.self, from: Data(session.transport.sent.last!.dropLast()))
            var ack = videoEvent("outputActivityChanged", b, session)
            ack.activityID = command.activityID; ack.outputActive = false
            engine.videoDidChangeOutputActivity(ack, session: session)
        }
        precondition(videoActivity == true && engine.playbackPaused)

        func prepareEarlyVideo(_ owner: WallpaperEngine, _ path: String) -> WallpaperEngine.VideoSwitchExecution {
            owner.prepareVideoSwitch(.init(path: path), ticket: ticket(.video), multiDisplayEnabled: false,
                videoFillMode: "fill", shouldLoopCurrentItem: false)
            return owner.videoCandidate!
        }
        let orphanEngine = WallpaperEngine()
        orphanEngine.displayIDs = [1]
        let orphan = prepareEarlyVideo(orphanEngine, "/orphan")
        let orphanSession = orphan.sessions[1]!
        var orphanCancelled = false
        orphanEngine.cancelSwitch(ticket: orphan.ticket) { orphanCancelled = true }
        precondition(!orphanCancelled && !orphanSession.transport.stopRequested)
        orphanEngine.videoDidCancel(videoEvent("cancelled", orphan, orphanSession, prepared: false), session: orphanSession)
        precondition(orphanCancelled && orphanEngine.displaySessions.isEmpty && orphanSession.transport.stopRequested,
            "cancelled first candidate left an ownerless helper in the display table")
        precondition(orphanSession.process.isRunning, "cancellation ACK was mistaken for physical exit")
        orphanSession.transport.end()
        precondition(orphanEngine.displaySessions.isEmpty && orphanEngine.videoCandidate == nil)

        let retainedEngine = WallpaperEngine()
        retainedEngine.displayIDs = [1]
        var retainedEndpoint: PlaybackSwitchEndpoint?
        retainedEngine.switchPrepared = { _, endpoint in retainedEndpoint = endpoint }
        let retainedA = prepareEarlyVideo(retainedEngine, "/retained-A")
        let retainedSession = retainedA.sessions[1]!
        retainedEngine.videoDidPrepare(videoEvent("prepared", retainedA, retainedSession), session: retainedSession)
        retainedEndpoint!.activate()
        retainedEngine.videoDidBecomeVisible(videoEvent("ready", retainedA, retainedSession), session: retainedSession)
        retainedEndpoint!.finalize()
        let cancelledB = prepareEarlyVideo(retainedEngine, "/cancelled-B")
        retainedEngine.cancelSwitch(ticket: cancelledB.ticket) {}
        retainedEngine.videoDidCancel(videoEvent("cancelled", cancelledB, retainedSession, prepared: false), session: retainedSession)
        precondition(retainedEngine.activeVideoExecution === retainedA
            && retainedEngine.displaySessions[1] === retainedSession && !retainedSession.transport.stopRequested,
            "cancelling B stopped the helper still owned by committed A")

        let successorEngine = WallpaperEngine()
        successorEngine.displayIDs = [1]
        let obsoleteB = prepareEarlyVideo(successorEngine, "/obsolete-B")
        successorEngine.cancelSwitch(ticket: obsoleteB.ticket) {}
        let successorC = prepareEarlyVideo(successorEngine, "/successor-C")
        let successorSession = successorC.sessions[1]!
        successorEngine.videoDidCancel(videoEvent("cancelled", obsoleteB, successorSession, prepared: false), session: successorSession)
        precondition(successorEngine.videoCandidate === successorC
            && successorEngine.displaySessions[1] === successorSession && !successorSession.transport.stopRequested,
            "late B cancellation stopped the helper now owned by C")

        let adapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        var webEndpoints: [UUID: PlaybackSwitchEndpoint] = [:], webVisible: [UUID] = []
        var audioDemands: [Bool] = []
        adapter.eventHandler = { event in
            if case let .audioSpectrumDemandChanged(demand, _) = event { audioDemands.append(demand) }
        }
        adapter.switchPrepared = { _, endpoint in webEndpoints[endpoint.id] = endpoint }
        adapter.switchVisible = { _, id in webVisible.append(id) }
        func prepareWeb(_ name: String) -> WebDaemonHostAdapter.Session {
            let request = WallpaperEngine.WebWallpaperLaunchRequest(id: UUID(), entryURL: URL(fileURLWithPath: "/" + name),
                rootURL: URL(fileURLWithPath: "/"), propertiesJSON: "{}", source: .steamWorkshop,
                recordID: name, language: "zh", runtimeProfile: .standard, multiDisplayEnabled: false,
                allowedNetworkHosts: ["prepared-author.example"])
            adapter.prepareSwitch(ticket: ticket(.web), request: request,
                runtimeState: .init(paused: false, volume: 0.8, playbackRate: 1, spectrumLevels: nil))
            let session = adapter.candidate!
            adapter.receive(.hello, from: session)
            let launch = try! JSONDecoder().decode(WebDaemonEnvelope<WebDaemonCommand>.self, from: session.transport.sent[0])
            guard case let .launch(input) = launch.payload else { fatalError("expected launch command") }
            precondition(input.allowedNetworkHosts == ["prepared-author.example"]
                && session.executionRequest.allowedNetworkHosts == request.allowedNetworkHosts,
                "hello uses the prepared request hosts without a descriptor resolver")
            return session
        }
        func preparedWeb(_ session: WebDaemonHostAdapter.Session) {
            adapter.receive(.prepared(1), from: session)
            adapter.receive(.committed(1), from: session)
            precondition(webEndpoints[session.executionID] == nil, "legacy ready authorized a product switch")
            adapter.receive(.preparationCohort(.init(generation: 1, surfaces: [
                .init(displayID: 1, surfaceID: UUID(), navigationGeneration: 1, windowID: 10)
            ])), from: session)
        }
        func visibleWeb(_ session: WebDaemonHostAdapter.Session) {
            adapter.receive(.activationConfirmed(session.activationIdentity!, [evidence(display: 1, pid: session.transport.process.processIdentifier)]), from: session)
        }
        let abandoned = prepareWeb("abandoned")
        adapter.receive(.host(.audioSpectrumDemandChanged(true, requestID: abandoned.request.id)), from: abandoned)
        precondition(adapter.audioSpectrumRequested && audioDemands.last == true)
        adapter.cancelSwitch(ticket: abandoned.ticket) {}
        precondition(adapter.active == nil && adapter.candidate == nil
            && !adapter.audioSpectrumRequested && audioDemands.last == false,
            "last uncommitted Web cancellation retained shared audio capture")
        abandoned.transport.end()

        let wa = prepareWeb("WA"); preparedWeb(wa)
#if DEBUG
        let measuresStartup = ProcessInfo.processInfo.arguments.contains("--mwx-debug-web-startup-report")
        precondition((wa.startupTiming != nil) == measuresStartup)
        precondition(wa.transport.arguments.contains("--mwx-debug-web-startup-timing") == measuresStartup)
        precondition(wa.startupTiming?.preparedCohortAcceptedAt != nil || !measuresStartup)
        precondition(wa.startupTiming?.launchEnqueuedAt != nil || !measuresStartup)
        precondition(wa.startupTiming?.activationSentAt == nil)
#endif
        adapter.receive(.host(.audioSpectrumDemandChanged(true, requestID: wa.request.id)), from: wa)
        let webA = webEndpoints[wa.executionID]!
        precondition(adapter.active == nil)
        webA.activate()
#if DEBUG
        let sentAt = wa.startupTiming?.activationSentAt
        precondition((sentAt != nil) == measuresStartup)
        webA.activate()
        precondition(wa.startupTiming?.activationSentAt == sentAt, "duplicate activation rewrote its event time")
        func startupObservationData(_ timing: WebDaemonStartupTimingObservation, requestID: UUID) throws -> Data {
            let observation = WebDaemonHostObservation(phase: "ready", currentRequest: 1,
                loopbacks: 0, monitors: 0, observers: 0, pointerTimer: 0, surfaces: 1,
                watchTimer: 0, watchers: 0, startupTiming: timing)
            return try DaemonNewlineJSON.encode(WebDaemonEnvelope(
                requestID: requestID, payload: WebDaemonEvent.observation(observation)))
        }
        let identity = wa.activationIdentity!
        let surfaceIdentity = wa.preparedCohort!.surfaces.first!
        let observedSurface = WebDaemonStartupSurfaceTimingObservation(displayID: surfaceIdentity.displayID,
            creationStartedAt: 2.5, surfaceID: surfaceIdentity.surfaceID,
            navigationGeneration: surfaceIdentity.navigationGeneration,
            creationCompletedAt: 3, loadIssuedAt: 3.5, readyObservedAt: 4, readySource: "didFinish")
        precondition(observedSurface.matching(surfaceIdentity) != nil)
        precondition(observedSurface.matching(.init(displayID: surfaceIdentity.displayID,
            surfaceID: UUID(), navigationGeneration: surfaceIdentity.navigationGeneration, windowID: 10)) == nil,
            "replaced surface inherited old preparation telemetry")
        precondition(observedSurface.matching(.init(displayID: surfaceIdentity.displayID,
            surfaceID: surfaceIdentity.surfaceID, navigationGeneration: surfaceIdentity.navigationGeneration + 1, windowID: 10)) == nil,
            "replacement document inherited old load/ready telemetry")
        let wrongActivation = WebDaemonStartupTimingObservation(
            identity: .init(generation: identity.generation, activationID: UUID()), activateReceivedAt: 1)
        adapter.consume(try startupObservationData(wrongActivation, requestID: wa.request.id), from: wa)
        precondition(wa.matchingChildStartupTiming == nil, "stale activation telemetry became matching evidence")
        var preparation = WebDaemonPreparationTimingObservation(launchReceivedAt: 2,
            generation: identity.generation, surfaces: wa.preparedCohort!.surfaces,
            hostReadyAt: 4, snapshotRequestedAt: 5, snapshotCompletedAt: 7,
            policyWaitStartedAt: 7.5, policyAcceptedAt: 8,
            surfaceTimings: [observedSurface])
        let producerTiming = WebDaemonStartupTimingObservation(identity: identity, activateReceivedAt: 10,
            nativePolicyAcceptedAt: 30, visibilityFirstConfirmedAt: 20,
            firstVisibilityRetryAt: 15, firstVisibilityRetryReason: "window-not-onscreen",
            preparation: preparation)
        preparation.snapshotCompletedAt = 999
        adapter.consume(try startupObservationData(producerTiming, requestID: wa.request.id), from: wa)
        precondition(!wa.visibilityConfirmed && webVisible.isEmpty, "diagnostics authorized a product switch")
        if measuresStartup {
            precondition(wa.matchingChildStartupTiming?.activateReceivedAt == 10
                && wa.matchingChildStartupTiming?.nativePolicyAcceptedAt == 30
                && wa.matchingChildStartupTiming?.visibilityFirstConfirmedAt == 20
                && wa.matchingChildStartupTiming?.firstVisibilityRetryAt == 15
                && wa.matchingChildStartupTiming?.firstVisibilityRetryReason == "window-not-onscreen",
                "IPC replaced producer times with receive time or forced media/visibility order")
            let transported = wa.matchingChildStartupTiming!.preparation!
            precondition(transported.generation == identity.generation
                && transported.surfaces == wa.preparedCohort!.surfaces
                && transported.launchReceivedAt == 2 && transported.snapshotCompletedAt == 7
                && transported.policyWaitStartedAt == 7.5 && transported.policyAcceptedAt == 8
                && transported.surfaceTimings.first?.loadIssuedAt == 3.5
                && transported.surfaceTimings.first?.readySource == "didFinish",
                "preparation snapshot lost cohort, producer time or ready semantics in transport")
        } else { precondition(wa.matchingChildStartupTiming == nil) }
        // Execute the actual initial-load, recovery and page-navigation writers.
        let producer = DedicatedWebWallpaperHostPlaceholderAdapter()
        producer.currentRequest = wa.request
        let producerSurface = DedicatedWebWallpaperHostPlaceholderAdapter.HostSurface(screenID: 1, webView: WKWebView())
        producer.surfaces[1] = producerSurface
        func seedCreation() {
            producer.debugStartupSurfaceTimings?[1] = .init(displayID: 1, creationStartedAt: 1,
                surfaceID: producerSurface.id, creationCompletedAt: 2)
        }
        seedCreation()
        producer.loadTrackedNavigation(on: producerSurface, request: wa.request,
            localEntryURL: wa.request.entryURL, stopCurrent: false) { precondition($0) }
        let firstNavigationGeneration = producer.navigationOwnershipByScreen[1]!.generation
        let firstIdentity = WebDaemonSurfaceIdentity(displayID: 1, surfaceID: producerSurface.id,
            navigationGeneration: firstNavigationGeneration, windowID: 10)
        precondition(producer.debugStartupSurfaceTimings?[1]?.loadIssuedAt != nil
            && producer.debugStartupSurfaceTimings?[1]?.matching(firstIdentity) != nil)
        precondition(producer.reloadTrackedNavigation(on: producerSurface, requestID: wa.request.id))
        precondition(producer.debugStartupSurfaceTimings?[1] == nil,
            "WebContent recovery retained initial document preparation times")
        seedCreation()
        producer.loadTrackedNavigation(on: producerSurface, request: wa.request,
            localEntryURL: wa.request.entryURL, stopCurrent: false) { precondition($0) }
        producer.readyScreenIDs.insert(1)
        precondition(producer.screenIDForStartedNavigation(WKNavigation(), webView: producerSurface.webView) == 1)
        precondition(producer.debugStartupSurfaceTimings?[1] == nil,
            "page navigation retained initial document preparation times")
        let invalidTelemetryAdapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        invalidTelemetryAdapter.prepareSwitch(ticket: ticket(.web), request: wa.executionRequest, runtimeState: wa.state)
        let invalidTelemetrySession = invalidTelemetryAdapter.candidate!
        invalidTelemetryAdapter.consume(try startupObservationData(producerTiming, requestID: UUID()),
            from: invalidTelemetrySession)
        precondition(invalidTelemetrySession.observation == nil && invalidTelemetryAdapter.candidate == nil,
            "wrong request telemetry bypassed normal protocol rejection")
#endif
        visibleWeb(wa)
        precondition(webVisible == [wa.executionID] && adapter.active == nil)
        webA.finalize(); precondition(adapter.active === wa)
        let wb = prepareWeb("WB"); var earlyCancelled = false
        adapter.cancelSwitch(ticket: wb.ticket) { earlyCancelled = true }
        precondition(!earlyCancelled && wb.transport.stopRequested && adapter.active === wa)
        wb.transport.end(); precondition(earlyCancelled && adapter.active === wa)
        let wc = prepareWeb("WC"); preparedWeb(wc)
        let webC = webEndpoints[wc.executionID]!
        webC.activate(); var webCancelled = false
        webC.cancel { webCancelled = true }
        adapter.receive(.activationCancelled(.init(generation: 1, activationID: UUID())), from: wc)
        precondition(!webCancelled)
        adapter.receive(.activationCancelled(wc.activationIdentity!), from: wc)
        precondition(webCancelled && adapter.active === wa)
        let wd = prepareWeb("WD"); preparedWeb(wd)
        adapter.receive(.host(.audioSpectrumDemandChanged(true, requestID: wd.request.id)), from: wd)
        let webD = webEndpoints[wd.executionID]!
        webD.activate(); visibleWeb(wd)
        let queuedWebTicket = ticket(.web)
        adapter.prepareSwitch(ticket: queuedWebTicket, request: wd.executionRequest, runtimeState: wd.state)
        precondition(adapter.candidate === wd && !wd.isCancelling && adapter.deferredPreparation?.ticket == queuedWebTicket)
        var webQueueCancelled = false
        adapter.cancelSwitch(ticket: queuedWebTicket) { webQueueCancelled = true }
        precondition(webQueueCancelled && adapter.deferredPreparation == nil && adapter.candidate === wd)
        precondition(adapter.active === wa && !wa.transport.stopRequested)
        var webRetired = false
        webA.retire(nil) { webRetired = true }
        precondition(!webRetired && wa.transport.stopRequested && adapter.candidate === wd && !wd.transport.stopRequested)
        wa.transport.end(); precondition(webRetired)
        precondition(adapter.audioSpectrumRequested && audioDemands.last == true,
            "retiring old Web withdrew the successor's live audio demand")
        webD.finalize(); precondition(adapter.active === wd)
        var outputDone: Bool? = nil
        webD.setOutputActive(false) { outputDone = $0 }
        let activity = wd.outputActivityCompletions.keys.first!
        adapter.receive(.outputActivityChanged(activity, false), from: wd)
        precondition(outputDone == true && wd.state.volume == 0.8 && !wd.state.paused)
        outputDone = nil
        webD.setOutputActive(false) { outputDone = $0 }
        let deadline = Date().addingTimeInterval(2.2)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        precondition(wd.transport.stopRequested && outputDone == nil, "ACK timeout completed before actual exit")
        wd.transport.end(); precondition(outputDone == true)

        // A committed renderer can die while another page is preparing. Its
        // recovery input must survive that candidate and restart the same ticket
        // after cancellation; retiring the old endpoint revokes that recovery.
        let recoveryAdapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        let originalTicket = ticket(.web)
        let dead = WebDaemonHostAdapter.Session(request: wa.executionRequest, state: wa.state,
            transport: .init(executableURL: URL(fileURLWithPath: "/unused"), arguments: []),
            recoveryAttempt: 0, ticket: originalTicket)
        dead.committedAt = ProcessInfo.processInfo.systemUptime
        let selectedResource = WebWallpaperResourceGrant(kind: .file, url: URL(fileURLWithPath: "/external/selected.mp3"))
        dead.resourceGrants = [selectedResource]
        let propertyEngine = WallpaperEngine()
        propertyEngine.dedicatedWebHostAdapter = recoveryAdapter
        propertyEngine.currentPlaybackContentKind = .web
        propertyEngine.currentWebRequestID = dead.request.id
        propertyEngine.currentWebPropertiesJSON = "{}"
        recoveryAdapter.active = dead
        recoveryAdapter.prepareSwitch(ticket: ticket(.web), request: wd.executionRequest, runtimeState: wd.state)
        let preparing = recoveryAdapter.candidate!
        dead.transport.end(); recoveryAdapter.didExit(dead)
        precondition(recoveryAdapter.pendingRecovery?.session === dead && recoveryAdapter.candidate === preparing)
        precondition(propertyEngine.currentWebResourceGrants == [selectedResource], "committed recovery input lost its authority snapshot")
        let unrelatedProperties = preparing.propertiesJSON
        let unrelatedGrants = preparing.resourceGrants
        propertyEngine.updateCurrentWebWallpaperProperties("{\"image\":{\"value\":\"\"}}", resourceGrants: [], resourcesChanged: true)
        precondition(dead.resourceGrants.isEmpty && dead.resourceRevision == 1 && dead.propertyRevision == 1,
            "clear during didExit/pendingRecovery was discarded")
        precondition(preparing.propertiesJSON == unrelatedProperties && preparing.resourceGrants == unrelatedGrants,
            "committed clear modified a new user selection")
        var failedCandidateCancelled = false
        recoveryAdapter.cancelSwitch(ticket: preparing.ticket) { failedCandidateCancelled = true }
        preparing.transport.end(); precondition(failedCandidateCancelled)
        let recoveryDeadline = Date().addingTimeInterval(0.35)
        while Date() < recoveryDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        let restarted = recoveryAdapter.candidate!
        precondition(restarted.ticket == originalTicket && restarted.executionID != dead.executionID)
        precondition(restarted.executionRequest.allowedNetworkHosts == dead.executionRequest.allowedNetworkHosts,
            "recovery preserves the same author host snapshot")
        precondition(restarted.resourceGrants.isEmpty && restarted.resourceRevision == 1,
            "recovery resurrected an external grant cleared during its wait")
        propertyEngine.updateCurrentWebWallpaperProperties("{\"image\":{\"value\":\"Default\"}}", resourceGrants: [], resourcesChanged: true)
        precondition(restarted.resourceRevision == 2 && restarted.propertyRevision == 2,
            "reset while the committed request's recovery candidate prepared was discarded")
        recoveryAdapter.handle(.applyProperties(.init(requestID: dead.request.id, revision: 3, resourceRevision: 0,
            propertiesJSON: "{}", resourceGrants: [selectedResource])))
        precondition(restarted.resourceGrants.isEmpty && restarted.resourceRevision == 2,
            "stale recovery update expanded current authority")
        precondition(recoveryAdapter.propertyUpdateSession(for: preparing.request.id) == nil,
            "old uncommitted selection became a committed update target")
        var deadRetired = false
        recoveryAdapter.retireEndpoint(dead) { deadRetired = true }
        precondition(deadRetired && recoveryAdapter.pendingRecovery == nil && recoveryAdapter.candidate == nil
            && restarted.transport.stopRequested, "retired committed endpoint resurrected its recovery")

        // Delay all child processing after B.activate. A display toggle must
        // retain B's endpoint cancellation barrier while C becomes prepared.
        let toggleAdapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        var transaction = PlaybackSwitchTransaction()
        var toggleEndpoints: [UUID: PlaybackSwitchEndpoint] = [:]
        var executeEffects: (([PlaybackSwitchTransaction.Effect]) -> Void)!
        executeEffects = { effects in
            for effect in effects {
                switch effect {
                case let .activate(selection):
                    toggleEndpoints[selection.executionID!]?.activate()
                case let .output(operation):
                    toggleEndpoints[operation.executionID]?.setOutputActive(operation.active) { succeeded in
                        executeEffects(transaction.activityCompleted(operation, succeeded: succeeded))
                    }
                case let .finalize(selection):
                    toggleEndpoints[selection.executionID!]?.finalize()
                case let .cancel(barrier, selection):
                    let finish = { executeEffects(transaction.cancelled(barrier)) }
                    if let id = selection.executionID, let endpoint = toggleEndpoints[id] {
                        endpoint.cancel(finish)
                    } else {
                        toggleAdapter.cancelSwitch(ticket: selection.ticket, completion: finish)
                    }
                default: break
                }
            }
        }
        toggleAdapter.switchPrepared = { ticket, endpoint in
            toggleEndpoints[endpoint.id] = endpoint
            executeEffects(transaction.prepared(ticket, executionID: endpoint.id))
        }
        toggleAdapter.switchVisible = { ticket, executionID in
            executeEffects(transaction.visible(ticket, executionID: executionID))
        }
        func feedPrepared(_ adapter: WebDaemonHostAdapter, _ session: WebDaemonHostAdapter.Session) {
            adapter.receive(.hello, from: session)
            adapter.receive(.preparationCohort(.init(generation: 1, surfaces: [
                .init(displayID: 1, surfaceID: UUID(), navigationGeneration: 1, windowID: 10)
            ])), from: session)
        }
        let (committedTicket, committedEffects) = transaction.begin(.web)
        executeEffects(committedEffects)
        toggleAdapter.prepareSwitch(ticket: committedTicket, request: wa.executionRequest, runtimeState: wa.state)
        let committedA = toggleAdapter.candidate!
        feedPrepared(toggleAdapter, committedA)
        toggleAdapter.receive(.activationConfirmed(committedA.activationIdentity!,
            [evidence(display: 1, pid: committedA.transport.process.processIdentifier)]), from: committedA)
        precondition(toggleAdapter.active === committedA && transaction.committed?.ticket == committedTicket)
        let (toggleTicket, initialEffects) = transaction.begin(.web)
        executeEffects(initialEffects)
        toggleAdapter.prepareSwitch(ticket: toggleTicket, request: wb.executionRequest, runtimeState: wb.state)
        let oldToggle = toggleAdapter.candidate!
        feedPrepared(toggleAdapter, oldToggle)
        precondition(!oldToggle.activationSent)
#if DEBUG
        precondition(oldToggle.startupTiming?.activationSentAt == nil,
            "prepared telemetry skipped the old output barrier")
#endif
        let deactivateA = committedA.outputActivityCompletions.first!
        precondition(!deactivateA.value.desired)
        toggleAdapter.receive(.outputActivityChanged(deactivateA.key, false), from: committedA)
        precondition(oldToggle.activationSent)
#if DEBUG
        precondition((oldToggle.startupTiming?.activationSentAt != nil) == measuresStartup)
#endif
        let oldExecutionID = oldToggle.executionID, oldActivation = oldToggle.activationIdentity!
        toggleAdapter.updateDisplayConfiguration(multiDisplayEnabled: true)
        precondition(oldToggle.executionID == oldExecutionID && oldToggle.activationIdentity == oldActivation
            && oldToggle.isRetiring && oldToggle.transport.stopRequested,
            "display update replaced the endpoint identity before revoking the original process")
        let (cTicket, cEffects) = transaction.begin(.web)
        executeEffects(cEffects)
        toggleAdapter.prepareSwitch(ticket: cTicket, request: wd.executionRequest, runtimeState: wd.state)
        let nextC = toggleAdapter.candidate!
        feedPrepared(toggleAdapter, nextC)
        precondition(!transaction.cancellations.isEmpty && !nextC.activationSent,
            "C activated before delayed B acknowledged cancellation or exited")
        let delayedB = WebDaemonEvent.activationConfirmed(oldActivation,
            [evidence(display: 1, pid: oldToggle.transport.process.processIdentifier)])
        toggleAdapter.consume(try DaemonNewlineJSON.encode(WebDaemonEnvelope(
            requestID: oldToggle.request.id, payload: delayedB)), from: oldToggle)
        precondition(!transaction.cancellations.isEmpty && !nextC.activationSent)
        oldToggle.transport.end()
        precondition(transaction.cancellations.isEmpty && nextC.activationSent
            && toggleAdapter.candidate === nextC && toggleAdapter.displayRebuildSource == nil,
            "old display rebuild stole C after its cancellation barrier completed")

        // With no superseding intent, the same ticket is rebuilt only after
        // old physical exit, with the latest display and pause/volume policy.
        let rebuildAdapter = WebDaemonHostAdapter(spectrumDelivery: .init())
        let rebuildTicket = ticket(.web)
        rebuildAdapter.switchPrepared = { _, _ in }
        rebuildAdapter.prepareSwitch(ticket: rebuildTicket, request: wa.executionRequest, runtimeState: wa.state)
        let beforeRebuild = rebuildAdapter.candidate!
        feedPrepared(rebuildAdapter, beforeRebuild)
        rebuildAdapter.updateDisplayConfiguration(multiDisplayEnabled: true)
        precondition(rebuildAdapter.candidate == nil && rebuildAdapter.displayRebuildSource === beforeRebuild)
        rebuildAdapter.handle(.pause); rebuildAdapter.handle(.setVolume(0.3))
        beforeRebuild.transport.end()
        let afterRebuild = rebuildAdapter.candidate!
        precondition(afterRebuild.ticket == rebuildTicket && afterRebuild.executionID != beforeRebuild.executionID
            && afterRebuild.multiDisplayEnabled && afterRebuild.state.paused && afterRebuild.state.volume == 0.3)
        precondition(afterRebuild.executionRequest.allowedNetworkHosts == beforeRebuild.executionRequest.allowedNetworkHosts,
            "display-cohort rebuilding preserves prepared author hosts")

        let optional = WebDaemonHostAdapter(spectrumDelivery: .init())
        var mayPrewarm = true
        optional.mayPrepareIdleProcess = { mayPrewarm }
        optional.scheduleIdlePreparation()
        let scheduled = optional.idlePreparationWorkItem!
        optional.active = wa
        mayPrewarm = false
        scheduled.perform()
        precondition(optional.preparedProcess == nil,
            "optional timer must consult current Scene retention at actual admission")
        optional.prepareIdleProcess()
        precondition(optional.preparedProcess == nil)
        let explicitRequest = UUID()
        optional.prepareProcess(requestID: explicitRequest)
        let claimed = optional.preparedProcess!
        precondition(claimed.requestID == explicitRequest && !claimed.isIdle,
            "Scene optional-prewarm predicate cannot block a real Web request")
        optional.cancelIdlePreparation()
        precondition(optional.preparedProcess === claimed && !claimed.transport.stopRequested,
            "non-Web intent cleanup cannot cancel an already claimed real request")
        optional.cancelPreparedProcess(requestID: explicitRequest)
        claimed.transport.end()
        mayPrewarm = true
        optional.prepareIdleProcess()
        let unused = optional.preparedProcess!
        optional.scheduleIdlePreparation()
        optional.cancelIdlePreparation()
        precondition(optional.preparedProcess == nil && optional.idlePreparationWorkItem == nil
            && unused.transport.stopRequested && optional.retiringPrepared[ObjectIdentifier(unused)] === unused)
        unused.transport.end()
        precondition(optional.retiringPrepared.isEmpty)
        optional.active = nil

        print("playback-switch-endpoints-pass")
    }
}
'''


class PlaybackSwitchEndpointTests(unittest.TestCase):
    def test_product_intent_cancels_preparation_after_advancing_epoch(self):
        manager = (ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager.swift").read_text()
        assembly = (ROOT / "MyWallpaperX/App/MyWallpaperXApplication.swift").read_text()
        harness_source = r'''
import Foundation
protocol PlaybackResourceLifetime: AnyObject {}
@MainActor final class WallpaperManager {
    static let shared = WallpaperManager()
    var playbackSwitch = PlaybackSwitchTransaction()
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
            sources = ["WallpaperRuntimeSwitch.swift", "PlaybackSwitchTransaction.swift", "ImportedVideoAutoplayGate.swift"]
            compilation = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-default-isolation", "MainActor",
                *[str(ROOT / "MyWallpaperX/Core/PlaybackControl" / name) for name in sources],
                str(harness), "-module-cache-path", str(directory / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("product-intent-preparation-cancellation-pass", result.stdout)

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
