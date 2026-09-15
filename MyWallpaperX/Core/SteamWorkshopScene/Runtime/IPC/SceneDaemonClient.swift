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

extension Notification.Name {
    static let sceneDaemonFrameStatsDidChange = Notification.Name(
        "SceneDaemonFrameStatsDidChange"
    )
    static let sceneDaemonClientDidFail = Notification.Name(
        "SceneDaemonClientDidFail"
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

    var activeIntent: ScenePlaybackLoadRequest?
    var pendingIntent: ScenePlaybackLoadRequest?
    var activeRequestID: UUID?
    var pendingRequestID: UUID?
    var pendingPropertyRevisions: [UInt64: String] = [:]
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
    private var runtimeSwitchObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    var shutdownCompletions: [() -> Void] = []
    var displayConfiguration = SceneScreenTopology.capture()

    var isPlaying: Bool {
        activeIntent != nil && transport?.isRunning == true && !isPaused
    }

    private init() {
        runtimeSwitchObserver = NotificationCenter.default.addObserver(
            forName: .wallpaperRuntimeWillSwitch,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard notification.userInfo?["kind"] as? String
                        != WallpaperRuntimeKind.scene.rawValue else { return }
                self?.stop()
            }
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDisplayConfiguration()
            }
        }
    }

    deinit {
        if let runtimeSwitchObserver {
            NotificationCenter.default.removeObserver(runtimeSwitchObserver)
        }
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
        case .pause:
            let hasPlaybackIntent = activeIntent != nil || pendingIntent != nil
            guard !isPaused else { return hasPlaybackIntent }
            isPaused = true
            if endpointReady { sendSimpleCommand("pause") }
            return hasPlaybackIntent
        case .resume:
            let hasPlaybackIntent = activeIntent != nil || pendingIntent != nil
            guard isPaused else { return hasPlaybackIntent }
            isPaused = false
            if endpointReady { sendSimpleCommand("resume") }
            return hasPlaybackIntent
        case .stop:
            stop()
            return true
        case .switchNext:
            return false
        }
    }

    func hasIntent(for recordID: String) -> Bool {
        activeIntent?.recordID == recordID || pendingIntent?.recordID == recordID
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

    func discardPendingResourceLifetime(rootURL: URL, recordID: String?) {
        guard pendingResourceLifetime?.recordID == recordID,
              pendingResourceLifetime?.rootURL
                == rootURL.resolvingSymlinksInPath().standardizedFileURL else { return }
        pendingResourceLifetime = nil
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
        if endpointReady {
            send([
                "v": SceneDaemonProtocol.version,
                "cmd": "cancelLaunch",
                "recordID": recordID
            ])
        }
        return true
    }

    func shutdown(completion: (() -> Void)? = nil) {
        if let completion {
            shutdownCompletions.append(completion)
        }
        stop()
        finishShutdownIfPossible()
    }

    func stop() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
        handshakeWorkItem?.cancel()
        handshakeWorkItem = nil
        let resourceLifetimes = [pendingResourceLifetime?.lifetime, activeResourceLifetime?.lifetime]
            .compactMap { $0 }
        pendingResourceLifetime = nil
        activeResourceLifetime = nil
        pendingIntent = nil
        activeIntent = nil
        pendingRequestID = nil
        activeRequestID = nil
        pendingPropertyRevisions.removeAll(keepingCapacity: true)
        activeRecordID = nil
        endpointReady = false
        latestFrameStats = nil
        restartBackoff.reset()
        guard let transport else { return }
        let generation = sessionGeneration
        if !resourceLifetimes.isEmpty {
            retiringResourceLifetimes[generation, default: []].append(contentsOf: resourceLifetimes)
        }
        expectedTerminationGenerations.insert(generation)
        retiringTransports[generation] = transport
        self.transport = nil
        if transport.isRunning,
           let data = try? DaemonNewlineJSON.encodeJSONObject([
                "v": SceneDaemonProtocol.version,
                "cmd": "shutdown"
           ], options: [.sortedKeys]) {
            transport.send(data)
            transport.closeInput()
        } else {
            transport.terminate()
        }
        transport.scheduleForcedTermination(after: 2)
    }

    func requestLaunch(_ request: ScenePlaybackLoadRequest) {
        let normalizedRoot = request.rootURL.resolvingSymlinksInPath().standardizedFileURL
        if pendingResourceLifetime?.rootURL != normalizedRoot
            || pendingResourceLifetime?.recordID != request.recordID {
            pendingResourceLifetime = nil
        }
        pendingIntent = request
        pendingRequestID = nil
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
        guard let executableURL = Bundle.main.executableURL else {
            scheduleRestart(reason: "missing-main-executable")
            return false
        }

        sessionGeneration &+= 1
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
            arguments: daemonArguments
        )
        transport.onOutput = { [weak self] data in
            self?.consumeOutput(data, generation: generation)
        }
        transport.onError = { [weak self] text in
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }
            guard self != nil else { return }
            NSLog("MWX SCENE DAEMON STDERR: %@", message)
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
            scheduleRestart(reason: "spawn-failed: \(error.localizedDescription)")
            return false
        }
    }

    func replayPendingIntent() {
        guard let request = pendingIntent else { return }
        pendingRequestID = nil
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
            "rootURL": request.rootURL.path,
            "propertyOverrides": request.propertyOverrides.mapValues(
                \.foundationValue
            ),
            "userPropertyTextures": textures,
            "profile": performanceProfile.maxFPS
        ]
        if let recordID = request.recordID {
            payload["recordID"] = recordID
        }
        send(payload)
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

#if DEBUG
    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
#endif
}
