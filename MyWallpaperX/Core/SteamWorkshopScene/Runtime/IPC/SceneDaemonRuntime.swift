import AppKit
import Darwin
import Foundation

/// Serializes daemon output away from the Scene main thread. At most one
/// frame-stats payload waits behind a blocked write; newer samples replace it.
private final class SceneDaemonEventWriter: @unchecked Sendable {
    private let output: FileHandle
    private let queue = DispatchQueue(
        label: "com.mywallpaperx.scene-daemon-events",
        qos: .utility
    )
    private let lock = NSLock()
    private var latestStats: Data?
    private var statsWriteScheduled = false

    init(output: FileHandle) {
        self.output = output
    }

    func sendCritical(_ data: Data, completion: (() -> Void)? = nil) {
        queue.async { [output] in
            output.write(data)
            completion?()
        }
    }

    func sendLatestStats(_ data: Data) {
        lock.lock()
        latestStats = data
        let shouldSchedule = !statsWriteScheduled
        statsWriteScheduled = true
        lock.unlock()
        guard shouldSchedule else { return }
        queue.async { [weak self] in
            self?.writeLatestStatsUntilEmpty()
        }
    }

    private func writeLatestStatsUntilEmpty() {
        while true {
            lock.lock()
            guard let data = latestStats else {
                statsWriteScheduled = false
                lock.unlock()
                return
            }
            latestStats = nil
            lock.unlock()
            output.write(data)
        }
    }
}

/// One bounded handoff from the stdin reader to the daemon main thread.
/// Adjacent audio commands coalesce, while every ordinary command is a barrier
/// that prevents values from opposite sides from replacing or overtaking.
private final class SceneDaemonCommandInbox: @unchecked Sendable {
    typealias DecodedCommand = Result<
        SceneDaemonCommand,
        SceneDaemonProtocolFailure
    >

    private let lock = NSLock()
    private var commands = DaemonCommandBuffer<
        DecodedCommand,
        SceneDaemonAudioSpectrumFrame
    >()
    private var drainScheduled = false
    private var acceptingCommands = true

    @discardableResult
    func submit(
        _ command: DecodedCommand,
        byteCount: Int,
        scheduleDrain: () -> Void
    ) -> Bool {
        lock.lock()
        guard acceptingCommands,
              byteCount <= DaemonCommandBufferLimits
                .maximumPendingControlBytes else {
            acceptingCommands = false
            lock.unlock()
            return false
        }
        let accepted: Bool
        if case let .success(.publishAudioSpectrum(frame)) = command {
            commands.enqueueDroppable(frame)
            accepted = true
        } else {
            accepted = commands.enqueueControl(
                command,
                byteCount: byteCount,
                maximumCount:
                    DaemonCommandBufferLimits.maximumPendingControlCount,
                maximumBytes:
                    DaemonCommandBufferLimits.maximumPendingControlBytes
            )
        }
        guard accepted else {
            acceptingCommands = false
            lock.unlock()
            return false
        }
        let shouldSchedule = !drainScheduled
        drainScheduled = true
        lock.unlock()
        if shouldSchedule {
            scheduleDrain()
        }
        return true
    }

    func takeNext() -> DaemonCommandBuffer<
        DecodedCommand,
        SceneDaemonAudioSpectrumFrame
    >.Entry? {
        lock.lock()
        let command = commands.takeFirst()
        if command == nil {
            drainScheduled = false
        }
        lock.unlock()
        return command
    }

    func clear() {
        lock.lock()
        acceptingCommands = false
        commands.removeAll()
        lock.unlock()
    }
}

/// Scene-specific daemon endpoint. Generic process spawning and retry policy
/// live in DaemonKit; this type owns only the Scene command/event projection.
@MainActor
final class SceneDaemonRuntime {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(
            SceneDaemonProtocol.commandFlag
        )
    }

    private let writer = SceneDaemonEventWriter(output: .standardOutput)
    private let commands = SceneDaemonCommandInbox()
    private let host = SceneDesktopWallpaperHost()
    private var observers: [NSObjectProtocol] = []
    private var statsTimer: DispatchSourceTimer?
    private var currentRequestID: UUID?
    private var lastPropertyRevision: UInt64 = 0
    private var shouldPausePlayback = false
    private var isShuttingDown = false
    private var audioDemand = SceneAudioSpectrumCaptureDemand.none
    private var systemAudioSpectrumPublicationGate = SceneAudioSpectrumPublicationGate()
    private var didReportNonSilentAudioPublication = false

    deinit {
        statsTimer?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func configure() {
        NSApplication.shared.setActivationPolicy(.accessory)
        emit([
            "v": SceneDaemonProtocol.version,
            "role": "scene-daemon"
        ])
        installAudioSpectrumDemandBridge()
        installObservers()
        installStatsTimer()
        startCommandLoop()
    }

    func loadSceneFromArgumentsIfPresent() {
        guard let rootPath = Self.argumentValue(
            after: SceneDaemonProtocol.sceneRootFlag
        ) else { return }
        handle(.loadScene(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL,
            propertyOverrides: [:],
            userPropertyTextures: [:],
            profile: .current,
            recordID: nil
        ))
    }

    private func startCommandLoop() {
        let commands = self.commands
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let line = readLine(strippingNewline: true) {
                guard !line.isEmpty else { continue }
                let byteCount = line.lengthOfBytes(using: .utf8)
                let result = SceneDaemonProtocol.decodeCommand(Data(line.utf8))
                guard commands.submit(
                    result,
                    byteCount: byteCount,
                    scheduleDrain: {
                        DispatchQueue.main.async { [weak self] in
                            self?.drainPendingCommands()
                        }
                    }
                ) else {
                    DispatchQueue.main.async { [weak self] in
                        self?.handleCommandAdmissionOverflow()
                    }
                    break
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.shutdown(exitCode: 0)
            }
        }
    }

    private func drainPendingCommands() {
        guard !isShuttingDown else { return }
        while !isShuttingDown, let pending = commands.takeNext() {
            switch pending {
            case let .droppable(frame):
                handle(.publishAudioSpectrum(frame))
            case let .control(result, _):
                switch result {
                case let .success(command): handle(command)
                case let .failure(failure):
                    emitError(
                        code: failure.code,
                        message: String(describing: failure)
                    )
                }
            }
        }
    }

    private func handleCommandAdmissionOverflow() {
        guard !isShuttingDown else { return }
        emitError(
            code: "command-backpressure-overflow",
            message: "Scene daemon command backlog exceeded its bounded budget"
        )
        shutdown(exitCode: 70)
    }

    private func handle(_ command: SceneDaemonCommand) {
        switch command {
        case let .loadScene(
            rootURL, overrides, textureReferences, profile, recordID
        ):
            lastPropertyRevision = 0
            host.applyPerformanceProfile(profile)
            host.requestLaunch(
                rootURL: rootURL,
                propertyOverrides: overrides,
                userPropertyTextureURLs: Self.resolveTextureURLs(
                    textureReferences
                ),
                recordID: recordID
            ) { _ in }
        case let .setProperty(values, revision, recordID):
            let accepted = revision > lastPropertyRevision
                && host.applyUserPropertyValues(
                    values,
                    changedPropertyKeys: Set(values.keys),
                    recordID: recordID
                )
            if accepted {
                lastPropertyRevision = revision
            }
            emit([
                "v": SceneDaemonProtocol.version,
                "event": "propertyUpdateResult",
                "revision": revision,
                "recordID": recordID,
                "accepted": accepted
            ])
        case let .cancelLaunch(recordID):
            host.cancelPendingLaunch(
                recordID: recordID
            )
        case let .setDisplayConfiguration(topology):
            NSLog(
                "MWX SCENE DAEMON: phase=display-configuration screens=%d",
                topology.count
            )
            host.applyDisplayConfiguration(topology)
        case let .setPerformanceProfile(profile):
            host.applyPerformanceProfile(profile)
        case let .setVolume(volume):
            PlaybackVolumeState.shared.setNormalizedVolume(volume)
            host.soundPlaybackRegistry?.setMasterVolume(Double(volume))
        case let .setMuted(muted):
            PlaybackMuteState.shared.setMuted(muted)
            host.soundPlaybackRegistry?.setMuted(muted)
        case let .setSpectrumEnabled(enabled):
            systemAudioSpectrumPublicationGate.setEnabled(enabled)
            if !enabled {
                SceneAudioSpectrumInbox.shared.clearSnapshot()
            }
        case let .publishAudioSpectrum(frame):
            guard systemAudioSpectrumPublicationGate.allowsPublication else {
                return
            }
            let accepted = SceneAudioSpectrumInbox.shared.publishSystemCapture(
                left: frame.left,
                right: frame.right,
                left32: frame.left32,
                right32: frame.right32,
                left64: frame.left64,
                right64: frame.right64,
                token: frame.captureToken
            )
            if accepted, !didReportNonSilentAudioPublication {
                let peak = (
                    frame.left64 + frame.right64
                ).max() ?? 0
                guard peak > 0 else { return }
                didReportNonSilentAudioPublication = true
                emit([
                    "v": SceneDaemonProtocol.version,
                    "event": "audioSpectrumPublished",
                    "scopeEpoch": frame.captureToken.scopeEpoch,
                    "includesDaemonProcessOutput": frame.captureToken
                        .includesCurrentProcessOutput,
                    "peak": peak
                ])
            }
        case .pause:
            shouldPausePlayback = true
            host.setPlaybackPaused(true)
        case .resume:
            shouldPausePlayback = false
            host.setPlaybackPaused(false)
        case .shutdown:
            shutdown(exitCode: 0)
        }
    }

    private func installAudioSpectrumDemandBridge() {
        SceneAudioSpectrumInbox.shared.setDemandObserver { [weak self] demand in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isShuttingDown else { return }
                self.publishAudioSpectrumDemand(demand)
            }
        }
        publishAudioSpectrumDemand(
            SceneAudioSpectrumInbox.shared.captureDemand
        )
    }

    private func publishAudioSpectrumDemand(
        _ demand: SceneAudioSpectrumCaptureDemand
    ) {
        guard demand != audioDemand else { return }
        audioDemand = demand
        didReportNonSilentAudioPublication = false
        emit([
            "v": SceneDaemonProtocol.version,
            "event": "audioSpectrumDemandChanged",
            "requiresSpectrum": demand.requiresSpectrum,
            "includesDaemonProcessOutput": demand.includesCurrentProcessOutput,
            "scopeEpoch": demand.scopeEpoch
        ])
    }

    private func installObservers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneWallpaperLaunchStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let state = notification.object
                        as? SceneWallpaperLaunchState else { return }
                if state.phase == .accepted {
                    self.currentRequestID = state.requestID
                } else if state.phase == .launched, self.shouldPausePlayback {
                    self.host.setPlaybackPaused(true)
                }
                self.emit([
                    "v": SceneDaemonProtocol.version,
                    "event": "launchStateChanged",
                    "phase": state.phase.rawValue,
                    "message": state.message,
                    "requestID": state.requestID.uuidString,
                    "recordID": state.recordID ?? NSNull()
                ])
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneWallpaperFirstFrameDidPresent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let presentation = notification.object
                        as? SceneFramePresentation,
                      presentation.requestID == self.currentRequestID else { return }
                self.emit([
                    "v": SceneDaemonProtocol.version,
                    "event": "firstFramePresented",
                    "requestID": presentation.requestID.uuidString,
                    "recordID": presentation.recordID ?? NSNull(),
                    "uptimeMs": Double(presentation.uptimeMicros) / 1_000
                ])
#if DEBUG
                self.captureFirstPresentedFrameIfRequested()
#endif
            }
        })
    }

#if DEBUG
    private func captureFirstPresentedFrameIfRequested() {
        guard let outputPath = Self.argumentValue(
            after: "--mwx-debug-scene-evidence-dir"
        ) else { return }
        let outputDirectory = URL(
            fileURLWithPath: outputPath,
            isDirectory: true
        ).standardizedFileURL
        guard let windowNumber = host.debugSnapshot().windowNumbers.first else {
            return
        }
        _ = host.requestDebugSnapshot(
            windowNumber: windowNumber,
            reason: "daemon-\(getpid())-first-present",
            outputDirectory: outputDirectory
        )
    }
#endif

    private func installStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            self.host.refreshPerformanceResourceGauges()
            let counters = ScenePerformanceCounterHub.shared.snapshot()
            let rendered = counters[.framesRendered] ?? 0
            var event: [String: Any] = [
                "v": SceneDaemonProtocol.version,
                "event": "frameStats",
                "rendered": rendered,
                "busy": counters[.framesBusy] ?? 0,
                "dropped": counters[.framesDropped] ?? 0,
                "drawCalls": counters[.drawCalls] ?? 0,
                "pipelineStateBinds": counters[.pipelineStateBinds] ?? 0,
                "geometryDrawCalls": counters[.geometryDrawCalls] ?? 0,
                "fallbackBranches": counters[.fallbackBranches] ?? 0,
                "gpuAllocatedBytes": counters[.gpuAllocatedBytes] ?? 0,
                "renderTargetPoolBytes": counters[.renderTargetPoolBytes] ?? 0
            ]
            if rendered > 0 {
                event["cpuFrameMs"] = Double(
                    counters[.cpuFrameMicros] ?? 0
                ) / Double(rendered) / 1_000
            }
            guard let data = Self.encode(event) else { return }
            writer.sendLatestStats(data)
        }
        timer.resume()
        statsTimer = timer
    }

    private func shutdown(exitCode: Int32) {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        SceneAudioSpectrumInbox.shared.setDemandObserver(nil)
        commands.clear()
        statsTimer?.cancel()
        statsTimer = nil
        host.stopAndDrainGPU { [writer] drained in
            let resolvedCode: Int32 = drained ? exitCode : 70
            guard let data = Self.encode([
                "v": SceneDaemonProtocol.version,
                "event": "exited",
                "code": resolvedCode,
                "gpuDrained": drained
            ]) else {
                Darwin.exit(resolvedCode)
            }
            writer.sendCritical(data) {
                Darwin.exit(resolvedCode)
            }
        }
    }

    private func emitError(code: String, message: String) {
        emit([
            "v": SceneDaemonProtocol.version,
            "event": "error",
            "code": code,
            "message": message
        ])
    }

    private func emit(_ payload: [String: Any]) {
        guard let data = Self.encode(payload) else { return }
        writer.sendCritical(data)
    }

    private static func encode(_ payload: [String: Any]) -> Data? {
        try? DaemonNewlineJSON.encodeJSONObject(
            payload,
            options: [.sortedKeys]
        )
    }

    private static func resolveTextureURLs(
        _ references: [String: ScenePlaybackTextureReference]
    ) -> [String: URL] {
        references.mapValues { reference in
            guard let bookmarkData = reference.bookmarkData else {
                return reference.url
            }
            var isStale = false
            if let scopedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return scopedURL.resolvingSymlinksInPath().standardizedFileURL
            }
            if let unscopedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return unscopedURL.resolvingSymlinksInPath().standardizedFileURL
            }
            return reference.url
        }
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
