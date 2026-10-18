import AppKit
import CoreFoundation
import Darwin
import Foundation

nonisolated struct SceneDaemonFrameStats: Equatable, Sendable {
    let rendered: UInt64
    let busy: UInt64
    let dropped: UInt64
    let drawCalls: UInt64
    let pipelineStateBinds: UInt64
    let geometryDrawCalls: UInt64
    let fallbackBranches: UInt64
    let gpuAllocatedBytes: UInt64
    let renderTargetPoolBytes: UInt64
    let cpuFrameMs: Double?
}

nonisolated struct SceneDaemonClientFailure: Equatable, Sendable {
    let code: String
    let message: String
    let recordID: String?
}

nonisolated struct SceneDaemonAudioSpectrumPublication: Equatable, Sendable {
    let scopeEpoch: UInt64
    let includesDaemonProcessOutput: Bool
    let peak: Float
}

nonisolated struct SceneDaemonActiveSessionFactsChange: Sendable {
    let recordIDs: Set<String>
}

extension Notification.Name {
    static let sceneDaemonActiveSessionFactsDidChange = Notification.Name(
        "SceneDaemonActiveSessionFactsDidChange"
    )
    static let sceneDaemonFrameStatsDidChange = Notification.Name(
        "SceneDaemonFrameStatsDidChange"
    )
    static let sceneDaemonClientDidFail = Notification.Name(
        "SceneDaemonClientDidFail"
    )
    static let sceneDaemonAudioSpectrumDemandDidChange = Notification.Name(
        "SceneDaemonAudioSpectrumDemandDidChange"
    )
    static let sceneDaemonAudioSpectrumDidPublish = Notification.Name(
        "SceneDaemonAudioSpectrumDidPublish"
    )
}

/// Main-App control-plane owner for the out-of-process Scene runtime. The
/// daemon remains the sole owner of prepared products, Metal state, and
/// surfaces; this client retains only restartable authored intent and light
/// endpoint observations.
@MainActor
final class SceneDaemonClient: PlaybackEngineControlling {
    static let shared = SceneDaemonClient()

    let engineKind: PlaybackEngineKind = .scene

    var transport: DaemonProcessTransport?
    var retiringTransports: [UInt64: DaemonProcessTransport] = [:]
    var outputFrames = DaemonNewlineFrameBuffer()
    var sessionGeneration: UInt64 = 0
    var expectedTerminationGenerations: Set<UInt64> = []
    var handshakeWorkItem: DispatchWorkItem?
    var restartWorkItem: DispatchWorkItem?
    var restartBackoff = DaemonRestartBackoff()
    let maximumRestartAttempts = 6
    var endpointReady = false

    var launchState: SceneWallpaperLaunchState?
    var latestFrameStats: SceneDaemonFrameStats?
    var activeRecordID: String?
    var audioSpectrumDemand = SceneAudioSpectrumCaptureDemand.none
    var audioSpectrumDemandGeneration: UInt64?
    let systemMedia = SceneDaemonMediaClientState()
    /// 自截帧请求的在途回调（requestID → 主线程回调）。daemon 停止/重启
    /// 时统一以 nil 结清，避免同步系统壁纸的等待方悬挂。
    var pendingFrameCaptureCompletions: [String: (URL?) -> Void] = [:]

    var activeIntent: ScenePlaybackLoadRequest?
    var pendingIntent: ScenePlaybackLoadRequest?
    var switchPrepared: ((PlaybackSwitchTicket, PlaybackSwitchEndpoint) -> Void)?
    var switchVisible: ((PlaybackSwitchTicket, UUID) -> Void)?
    var switchFailed: ((PlaybackSwitchTicket, String) -> Void)?
    var switchLost: ((PlaybackSwitchTicket, String) -> Void)?
    var stopPlaybackRequested: (() -> Void)?
    var activeSwitchTicket: PlaybackSwitchTicket?
    var pendingSwitchTicket: PlaybackSwitchTicket?
    var activeSwitchExecution: SwitchExecution?
    var pendingSwitchExecution: SwitchExecution?
    var switchControls: [UUID: SwitchControl] = [:]
    var queuedSwitchPreparation: QueuedSwitchPreparation?
    var committedSwitchRecovery: CommittedSwitchRecovery?
    var deferredDisplayConfigurationUpdate = false
    var activeRequestID: UUID?
    struct ActiveCallbackPropertyFacts: Equatable {
        let transportGeneration: UInt64
        let requestID: UUID
        let recordID: String?
        let reachability: ScenePreparedCallbackPropertyReachability
    }
    var activeCallbackPropertyFacts: ActiveCallbackPropertyFacts? {
        didSet {
            guard oldValue != activeCallbackPropertyFacts else { return }
            NotificationCenter.default.post(name: .sceneDaemonActiveSessionFactsDidChange,
                object: SceneDaemonActiveSessionFactsChange(recordIDs: Set(
                    [oldValue?.recordID, activeCallbackPropertyFacts?.recordID].compactMap { $0 })))
        }
    }
    var pendingRequestID: UUID?
    var pendingPresentationRequestID: UUID?
    var pendingPresentationReachability: ScenePreparedCallbackPropertyReachability?
    /// Sent launches retain their immutable versions through CPU preparation,
    /// candidate rollback and GPU drain, independently of mutable UI intent.
    var requestResourceLifetimes: [UUID: PlaybackResourceLifetime] = [:]
    var pendingPropertyRevisions: [UInt64: String] = [:]
    var pendingTextureUpdates: [UInt64: PendingTextureUpdate] = [:]
    var latestTextureRevisions: [String: UInt64] = [:]
    /// Synchronous drain callbacks may not admit work into the departing session.
    var textureUpdateAdmissionClosed = false
    /// Set by `warmSession()` while its silent spawn is in flight; cleared by
    /// any real intent, a handshake timeout, or spawn failure. A completed
    /// handshake leaves it set until the next intent/reuse — harmless, since
    /// every non-silent spawn entry clears it before spawning.
    var warmSessionPending = false
    struct RetainedResourceLifetime {
        let rootURL: URL
        let recordID: String?
        let lifetime: PlaybackResourceLifetime
    }
    var pendingResourceLifetime: RetainedResourceLifetime?
    var activeResourceLifetime: RetainedResourceLifetime?
    var retiringResourceLifetimes: [UInt64: [PlaybackResourceLifetime]] = [:]
    private var lastPropertyRevision: UInt64 = 0
    private var performanceProfile = PlaybackPerformanceProfile.current
    private var isPaused = false
    private var screenParametersObserver: NSObjectProtocol?
    var shutdownCompletions: [(generations: Set<UInt64>, completion: () -> Void)] = []
    var displayConfiguration = SceneScreenTopology.capture() {
        didSet {
            // A topology rebuild has not yet proven a complete prepared cohort.
            // Wait for a new launched observation before advertising its rows.
            if oldValue != displayConfiguration { activeCallbackPropertyFacts = nil }
        }
    }
    /// 多屏语义与 video/web 对齐：开=全部显示器，关=仅首屏。主 App 是
    /// 显示集的唯一裁决者，daemon 按收到的拓扑建表面。
    var multiDisplayEnabled = true

    var isPlaying: Bool {
        activeIntent != nil && activeRequestID != nil && transport?.isRunning == true
            && !isPaused && activeSwitchExecution?.outputActive != false
    }

    private init() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDisplayConfiguration(
                    multiDisplayEnabled: self?.multiDisplayEnabled ?? true
                )
            }
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    @discardableResult
    func handle(_ command: WallpaperEngineCommand) -> Bool {
        switch command {
        case let .loadScene(request):
            requestLaunch(request)
            return true
        case let .setProperty(values, revision, recordID):
            return applyPropertyValues(
                values,
                revision: revision,
                recordID: recordID
            )
        case let .cancelSceneLaunch(recordID):
            return cancelPendingLaunch(recordID: recordID)
        case let .setPerformanceProfile(maxFPS):
            guard let profile = PlaybackPerformanceProfile(rawValue: maxFPS) else {
                return false
            }
            performanceProfile = profile
            if endpointReady {
                send([
                    "v": SceneDaemonProtocol.version,
                    "cmd": "setPerformanceProfile",
                    "maxFPS": profile.maxFPS
                ])
            }
            return activeIntent != nil || pendingIntent != nil
        case let .setVolume(volume):
            let normalized = volume.isFinite
                ? min(max(volume, 0), 100) / 100
                : PlaybackVolumeState.shared.normalizedVolume
            PlaybackVolumeState.shared.setNormalizedVolume(normalized)
            if endpointReady {
                send([
                    "v": SceneDaemonProtocol.version,
                    "cmd": "setVolume",
                    "volume": normalized
                ])
            }
            return activeIntent != nil || pendingIntent != nil
        case let .setMuted(muted):
            PlaybackMuteState.shared.setMuted(muted)
            if endpointReady {
                send([
                    "v": SceneDaemonProtocol.version,
                    "cmd": "setMuted",
                    "muted": muted
                ])
            }
            return activeIntent != nil || pendingIntent != nil
        case let .setPlaybackPaused(paused):
            let hasPlaybackIntent = activeIntent != nil || pendingIntent != nil
            guard isPaused != paused else { return hasPlaybackIntent }
            isPaused = paused
            if endpointReady { sendSimpleCommand(paused ? "pause" : "resume") }
            return hasPlaybackIntent
        case .pause, .resume:
            return false // User intent is resolved by the multiplexer.
        case .stop:
            // E2a-2: user-requested stop reports completion so the
            // selection authority recycles its truth.
            if let stopPlaybackRequested { stopPlaybackRequested() }
            else { stop(postsLaunchState: true) }
            return true
        case .switchNext:
            return false
        }
    }

    func hasIntent(for recordID: String) -> Bool {
        activeIntent?.recordID == recordID || pendingIntent?.recordID == recordID
    }

    func preparedCallbackPropertyKeys(
        for recordID: String,
        source: ScenePreparedCallbackPropertyReachability.Source?
    ) -> Set<String> {
        guard endpointReady, transport?.isRunning == true,
              let facts = activeCallbackPropertyFacts,
              facts.transportGeneration == sessionGeneration,
              facts.requestID == activeRequestID, facts.recordID == recordID,
              activeRecordID == recordID, activeIntent?.recordID == recordID,
              facts.reachability.source == source,
              facts.reachability.source.rootPath == activeIntent?.rootURL
                .resolvingSymlinksInPath().standardizedFileURL.path else { return [] }
        return facts.reachability.propertyKeys
    }

    func retainResourceLifetime(
        _ lifetime: PlaybackResourceLifetime?,
        rootURL: URL,
        recordID: String?
    ) {
        pendingResourceLifetime = lifetime.map {
            RetainedResourceLifetime(
                rootURL: rootURL.resolvingSymlinksInPath().standardizedFileURL,
                recordID: recordID,
                lifetime: $0
            )
        }
    }
#if DEBUG
    var debugProcessIdentifier: Int32? {
        guard let transport, transport.isRunning else { return nil }
        return transport.process.processIdentifier
    }

    @discardableResult
    func debugForceTerminateDaemon() -> Bool {
        guard let processIdentifier = debugProcessIdentifier else { return false }
        return Darwin.kill(processIdentifier, SIGKILL) == 0
    }
#endif
    @discardableResult
    func cancelPendingLaunch(recordID: String) -> Bool {
        guard pendingIntent?.recordID == recordID else { return false }
        cancelPreparationForRuntimeSwitch()
        return true
    }

    /// New product intent revokes an uncommitted Scene before another engine
    /// starts preparing. Keep a committed Scene, including its version lease.
    func cancelPreparationForRuntimeSwitch() {
        guard let pending = pendingIntent else { return }
        if let ticket = pendingSwitchTicket {
            cancelSwitch(ticket: ticket, completion: {})
            return
        }
        let requestID = pendingRequestID
        finishPendingTextureUpdates(.superseded)
        if activeIntent == nil {
            // In particular, a hello still queued on stdout must not replay it.
            stop()
        } else {
            pendingIntent = nil
            pendingResourceLifetime = nil
            pendingRequestID = nil
            pendingPresentationRequestID = nil
            pendingPresentationReachability = nil
            pendingPropertyRevisions.removeAll(keepingCapacity: true)
            if endpointReady, let requestID {
                send(["v": SceneDaemonProtocol.version, "cmd": "cancelCandidate",
                      "requestID": requestID.uuidString])
            }
        }
        // Before hello no wire UUID exists yet, but the product still needs a
        // terminal record observation to clear its loading state.
        let state = SceneWallpaperLaunchState(requestID: requestID ?? UUID(),
            recordID: pending.recordID, phase: .cancelled, message: "已取消 Scene 壁纸准备")
        launchState = state
        NotificationCenter.default.post(name: .sceneWallpaperLaunchStateDidChange, object: state)
    }

    func shutdown(postsLaunchState: Bool = false, completion: (() -> Void)? = nil) {
        stop(postsLaunchState: postsLaunchState)
        if let completion {
            shutdownCompletions.append((Set(retiringTransports.keys), completion))
        }
        finishShutdownIfPossible()
    }

    func stop() {
        stop(postsLaunchState: false)
    }

    /// 请求 daemon 自截壁纸表面一帧（免屏幕录制权限），JPEG 路径经
    /// frameCaptured 事件回传；失败/未就绪回调 nil。
    func captureSurfaceFrame(completion: @escaping (URL?) -> Void) {
        guard endpointReady else {
            completion(nil)
            return
        }
        let requestID = UUID().uuidString
        pendingFrameCaptureCompletions[requestID] = completion
        send([
            "v": SceneDaemonProtocol.version,
            "cmd": "captureFrame",
            "requestID": requestID
        ])
    }

    func failPendingFrameCaptures() {
        let completions = pendingFrameCaptureCompletions.values
        pendingFrameCaptureCompletions.removeAll()
        completions.forEach { $0(nil) }
    }

    /// Internal execution teardown stays silent. A standalone command stop may
    /// publish its state; product command stops first enter stopPlaybackRequested.
    func stop(postsLaunchState: Bool) {
        finishPendingTextureUpdates(.superseded)
        let stoppedRequestID = activeRequestID ?? pendingRequestID
            ?? (activeIntent != nil || pendingIntent != nil ? UUID() : nil)
        let stoppedRecordID = activeRecordID ?? pendingIntent?.recordID
        restartWorkItem?.cancel()
        restartWorkItem = nil
        handshakeWorkItem?.cancel()
        handshakeWorkItem = nil
        let resourceLifetimes = [pendingResourceLifetime?.lifetime, activeResourceLifetime?.lifetime]
            .compactMap { $0 } + Array(requestResourceLifetimes.values)
        requestResourceLifetimes.removeAll()
        pendingResourceLifetime = nil
        activeResourceLifetime = nil
        pendingIntent = nil
        activeIntent = nil
        pendingSwitchTicket = nil
        activeSwitchTicket = nil
        pendingSwitchExecution = nil
        activeSwitchExecution = nil
        queuedSwitchPreparation = nil
        committedSwitchRecovery = nil
        pendingRequestID = nil
        pendingPresentationRequestID = nil
        pendingPresentationReachability = nil
        activeRequestID = nil
        activeCallbackPropertyFacts = nil
        pendingPropertyRevisions.removeAll(keepingCapacity: true)
        activeRecordID = nil
        endpointReady = false
        failPendingFrameCaptures()
        revokeAudioSpectrumDemand(generation: sessionGeneration)
        revokeSystemMediaDemand(generation: sessionGeneration)
        latestFrameStats = nil
        restartBackoff.reset()
        if postsLaunchState, let stoppedRequestID {
            // Posted before transport teardown so the recycle lands even if
            // the daemon outlives the notification consumer's run loop turn.
            NotificationCenter.default.post(
                name: .sceneWallpaperLaunchStateDidChange,
                object: SceneWallpaperLaunchState(
                    requestID: stoppedRequestID,
                    recordID: stoppedRecordID,
                    phase: .stopped,
                    message: "Scene 壁纸已停止"
                )
            )
        }
        guard let transport else { return }
        let generation = sessionGeneration
        if !resourceLifetimes.isEmpty {
            retiringResourceLifetimes[generation, default: []].append(contentsOf: resourceLifetimes)
        }
        expectedTerminationGenerations.insert(generation)
        retiringTransports[generation] = transport
        self.transport = nil
        let shutdownData = try? DaemonNewlineJSON.encodeJSONObject([
            "v": SceneDaemonProtocol.version, "cmd": "shutdown"
        ], options: [.sortedKeys])
        transport.requestGracefulStop(shutdownData)
    }

    func requestLaunch(_ request: ScenePlaybackLoadRequest) {
        let sameVersion: (ScenePlaybackLoadRequest?) -> Bool = {
            $0?.recordID == request.recordID
                && $0?.rootURL.standardizedFileURL == request.rootURL.standardizedFileURL
        }
        // A property fallback for the committed version cannot replace a newer
        // product selection. Internal rebuilds retain the accepted product ticket.
        if pendingSwitchTicket != nil, pendingSwitchTicket != activeSwitchTicket,
           sameVersion(activeIntent), !sameVersion(pendingIntent) { return }
        let ticket = sameVersion(pendingIntent) ? pendingSwitchTicket
            : (sameVersion(activeIntent) ? activeSwitchTicket : nil)
        if let queued = queuedSwitchPreparation, queued.ticket != ticket { return }
        startLaunch(request, ticket: ticket)
    }

    func startLaunch(_ request: ScenePlaybackLoadRequest, ticket: PlaybackSwitchTicket?) {
        // retainResourceLifetime already installed this incoming request's token.
        // Property/texture rebuilds of the active immutable version reuse its
        // lease; releasing the previous session must not unpin the replacement.
        let normalizedRoot = request.rootURL.resolvingSymlinksInPath().standardizedFileURL
        let incomingLifetime = [pendingResourceLifetime, activeResourceLifetime].compactMap { $0 }.first {
            $0.rootURL == normalizedRoot && $0.recordID == request.recordID
        }
        if let ticket, pendingSwitchExecution?.presented == true {
            queuedSwitchPreparation = .init(request: request, ticket: ticket,
                                             resourceLifetime: incomingLifetime?.lifetime)
            return
        }
        cancelPreparationForRuntimeSwitch()
        pendingResourceLifetime = incomingLifetime
        finishPendingTextureUpdates(.superseded)
        latestTextureRevisions.removeAll(keepingCapacity: true)
        warmSessionPending = false
        pendingIntent = request
        pendingSwitchTicket = ticket
        pendingSwitchExecution = nil
        pendingRequestID = nil
        pendingPresentationRequestID = nil
        pendingPresentationReachability = nil
        pendingPropertyRevisions.removeAll(keepingCapacity: true)
        lastPropertyRevision = 0
        restartWorkItem?.cancel()
        restartWorkItem = nil
        if ensureSession(), endpointReady {
            replayPendingIntent()
        }
    }

    private func applyPropertyValues(
        _ values: [String: SceneUserPropertyValue],
        revision: UInt64,
        recordID: String
    ) -> Bool {
        guard !values.isEmpty,
              revision > lastPropertyRevision,
              activeIntent?.recordID == recordID else { return false }
        activeIntent?.propertyOverrides.merge(values) { _, new in new }
        if pendingIntent?.recordID == recordID {
            pendingIntent?.propertyOverrides.merge(values) { _, new in new }
            for revision in Array(pendingTextureUpdates.keys) {
                guard var pending = pendingTextureUpdates[revision],
                      pending.generation == sessionGeneration,
                      pending.waitsForFirstPresent, pending.isLaunchRetry,
                      pending.update.recordID == recordID,
                      pending.fallbackBaseIntent?.recordID == recordID,
                      pending.requestID == pendingRequestID else { continue }
                pending.fallbackBaseIntent?.propertyOverrides.merge(values) { _, new in new }
                pendingTextureUpdates[revision] = pending
            }
        }
        lastPropertyRevision = revision
        guard endpointReady else { return true }
        pendingPropertyRevisions[revision] = recordID
        send([
            "v": SceneDaemonProtocol.version,
            "cmd": "setProperty",
            "values": values.mapValues(\.foundationValue),
            "revision": revision,
            "recordID": recordID
        ])
        return true
    }

    @discardableResult
    func ensureSession() -> Bool {
        if transport?.isRunning == true { return true }
        warmSessionPending = false
        return spawnSession(silentHandshakeFailure: false)
    }

    /// Best-effort daemon prewarm: spawns the daemon and completes the role
    /// handshake without any launch intent, so a later real `requestLaunch`
    /// reuses the hot transport. A failed warm spawn stays silent (no user
    /// visible failure state) and is not retried — the restart scheduler
    /// keeps its intent gate.
    func warmSession() {
        guard transport?.isRunning != true else { return }
        guard pendingIntent == nil else { return }
        warmSessionPending = true
        _ = spawnSession(silentHandshakeFailure: true)
    }

    private func spawnSession(silentHandshakeFailure: Bool) -> Bool {
        guard DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses else { return false }
        guard let executableURL = Bundle.main.executableURL else {
            guard !silentHandshakeFailure else { return false }
            scheduleRestart(reason: "missing-main-executable")
            return false
        }

        sessionGeneration &+= 1
        activeCallbackPropertyFacts = nil
        let generation = sessionGeneration
        expectedTerminationGenerations.remove(generation)
        endpointReady = false
        outputFrames = DaemonNewlineFrameBuffer()
        var daemonArguments = [SceneDaemonProtocol.commandFlag]
#if DEBUG
        if let evidenceDirectory = Self.argumentValue(
            after: "--mwx-debug-scene-evidence-dir"
        ) {
            daemonArguments.append(contentsOf: [
                "--mwx-debug-scene-evidence-dir", evidenceDirectory
            ])
        }
#endif
        let transport = DaemonProcessTransport(
            executableURL: executableURL,
            arguments: daemonArguments,
            playbackRenderer: true
        )
        transport.onOutput = { [weak self] data in
            self?.consumeOutput(data, generation: generation)
        }
        transport.onError = { [weak self] text in
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }
            guard self != nil else { return }
#if DEBUG
            NSLog("MWX SCENE DAEMON STDERR: %@", message)
#endif
        }
        transport.onTermination = { [weak self] status in
            self?.handleTermination(status: status, generation: generation)
        }
        do {
            try transport.start()
            self.transport = transport
            let handshake = DispatchWorkItem { [weak self] in
                guard let self,
                      generation == self.sessionGeneration,
                      !self.endpointReady else { return }
                if silentHandshakeFailure || self.warmSessionPending {
                    // Silent prewarm: a missed handshake leaves no user
                    // visible state; the next real launch spawns fresh.
                    warmSessionPending = false
                    self.transport?.terminate()
                    return
                }
                self.publishFailure(
                    code: "handshake-timeout",
                    message: "Scene daemon did not publish its role in time"
                )
                self.transport?.terminate()
            }
            handshakeWorkItem = handshake
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 2,
                execute: handshake
            )
            return true
        } catch {
            transport.closeIO()
            self.transport = nil
            warmSessionPending = false
            guard !silentHandshakeFailure else { return false }
            scheduleRestart(reason: "spawn-failed: \(error.localizedDescription)")
            return false
        }
    }

    func replayPendingIntent() {
        guard let request = pendingIntent else { return }
        let requestID = UUID()
        pendingRequestID = requestID
        if let lifetime = pendingResourceLifetime?.lifetime {
            requestResourceLifetimes[requestID] = lifetime
        }
        sendDisplayConfiguration()
        var textures: [String: [String: Any]] = [:]
        textures.reserveCapacity(request.userPropertyTextures.count)
        for (key, reference) in request.userPropertyTextures {
            var encoded: [String: Any] = ["path": reference.url.path]
            if let bookmarkData = reference.bookmarkData {
                encoded["bookmark"] = bookmarkData.base64EncodedString()
            }
            textures[key] = encoded
        }
        var payload: [String: Any] = [
            "v": SceneDaemonProtocol.version,
            "cmd": "loadScene",
            "requestID": requestID.uuidString,
            "rootURL": request.rootURL.path,
            "propertyOverrides": request.propertyOverrides.mapValues(
                \.foundationValue
            ),
            "userPropertyTextures": textures,
            "requiredUserTextureKeys": request.requiredUserTextureKeys.sorted(),
            "profile": performanceProfile.maxFPS
        ]
        if let recordID = request.recordID {
            payload["recordID"] = recordID
        }
        send(payload)
        send([
            "v": SceneDaemonProtocol.version,
            "cmd": "setVolume",
            "volume": PlaybackVolumeState.shared.normalizedVolume
        ])
        send([
            "v": SceneDaemonProtocol.version,
            "cmd": "setMuted",
            "muted": PlaybackMuteState.shared.isMuted
        ])
        sendSimpleCommand(isPaused ? "pause" : "resume")
    }

    private func sendSimpleCommand(_ command: String) {
        send(["v": SceneDaemonProtocol.version, "cmd": command])
    }

    func send(_ payload: [String: Any]) {
        guard let data = try? DaemonNewlineJSON.encodeJSONObject(
            payload,
            options: [.sortedKeys]
        ), transport?.send(data) == true else {
            transport?.terminate()
            return
        }
    }

    var spectrumDeliveryTarget: PlaybackSpectrumDelivery.SceneTarget? {
        guard endpointReady, let transport,
              audioSpectrumDemandGeneration == sessionGeneration,
              audioSpectrumDemand.requiresSpectrum else { return nil }
        return .init(generation: sessionGeneration, demand: audioSpectrumDemand,
                     transport: transport)
    }
#if DEBUG
    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
#endif
}
