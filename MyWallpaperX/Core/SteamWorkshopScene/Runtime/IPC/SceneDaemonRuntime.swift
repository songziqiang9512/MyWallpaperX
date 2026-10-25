import AppKit
import Darwin
import Foundation
import ScreenCaptureKit

/// Serializes daemon output away from the Scene main thread. At most one
/// frame-stats payload waits behind a blocked write; newer samples replace it.
private final class SceneDaemonEventWriter: @unchecked Sendable {
    private let output: FileHandle
    private let queue = DispatchQueue(
        label: "com.mywallpaperx.scene-daemon-events",
        qos: .utility
    )
#if DEBUG
    private let lock = NSLock()
    private var latestStats: Data?
    private var statsWriteScheduled = false
#endif
    init(output: FileHandle) {
        self.output = output
    }

    func sendCritical(_ data: Data, completion: (() -> Void)? = nil) {
        queue.async { [output] in
            output.write(data)
            completion?()
        }
    }
#if DEBUG
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
#endif
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
#if DEBUG
    var debugStartupPrefixUptimes: [String: UInt64]?
    private var statsTimer: DispatchSourceTimer?
#endif
    private var currentRequestID: UUID?
    private var lastPropertyRevision: UInt64 = 0
    private var shouldPausePlayback = false
    private var isShuttingDown = false
    private var pendingRequestRetirement: (requestID: UUID, operationID: UUID)?
    private var audioDemand = SceneAudioSpectrumCaptureDemand.none
#if DEBUG
    private var didReportNonSilentAudioPublication = false
#endif
    private var systemMediaReceiver = SceneDaemonMediaReceiver()
    private var systemMediaLease: DispatchWorkItem?

    deinit {
#if DEBUG
        statsTimer?.cancel()
#endif
        systemMediaLease?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func configure() {
        DaemonParentLifetime.shared.setShutdownHandler { [weak self] in
            MainActor.assumeIsolated { self?.shutdown(exitCode: 0) }
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        host.requestResourcesReleasedHandler = { [weak self] requestID, succeeded in
            guard let self else { return }
            if succeeded { self.emitRequestResourcesReleased(requestID) }
            else { self.shutdown(exitCode: 70) }
        }
#if DEBUG
        var hello: [String: Any] = [
            "v": SceneDaemonProtocol.version,
            "role": "scene-daemon",
            "sourceSchemaVersion": ScenePlaybackSource.supportedSchemaVersion,
            "requestRetirementSchemaVersion": 1
        ]
        if var uptimes = debugStartupPrefixUptimes {
            uptimes["schemaVersion"] = 1
            uptimes["pid"] = UInt64(getpid())
            uptimes["helloSnapshotCaptured"] = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
            debugStartupPrefixUptimes = uptimes
            hello["debugStartupPrefixUptimes"] = uptimes
        }
        emit(hello)
#else
        emit([
            "v": SceneDaemonProtocol.version,
            "role": "scene-daemon",
            "sourceSchemaVersion": ScenePlaybackSource.supportedSchemaVersion,
            "requestRetirementSchemaVersion": 1
        ])
#endif
        installAudioSpectrumDemandBridge()
        installSystemMediaDemandBridge()
        installObservers()
#if DEBUG
        installStatsTimer()
#endif
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
            DaemonParentLifetime.shared.requestShutdown()
        }
    }

    private func drainPendingCommands() {
        guard !isShuttingDown, pendingRequestRetirement == nil else { return }
        while !isShuttingDown, pendingRequestRetirement == nil, let pending = commands.takeNext() {
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
            rootURL, overrides, textureReferences, shortcuts, profile, recordID, requiredTextureKeys, requestID, source
        ):
            lastPropertyRevision = 0
            // Explicit parent identities use a cancellable prepare/commit/
            // first-present transaction. Standalone legacy diagnostics retain
            // the direct Host behavior when no request identity was supplied.
            host.candidatePreparedHandler = requestID.map { _ in
                { [weak self] preparedID in
                    self?.emit(["v": SceneDaemonProtocol.version,
                        "event": "candidatePrepared", "requestID": preparedID.uuidString])
                }
            }
            host.applyPerformanceProfile(profile)
            host.requestLaunch(
                rootURL: rootURL,
                source: source,
                propertyOverrides: overrides,
                userPropertyTextureURLs: Self.resolveTextureURLs(
                    textureReferences
                ),
                userShortcuts: shortcuts,
                requiredUserTextureKeys: requiredTextureKeys,
                recordID: recordID,
                requestID: requestID ?? UUID()
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
        case let .setUserShortcuts(update, requestID):
            let accepted = host.applyUserShortcutUpdate(update, requestID: requestID)
            emit(["v": SceneDaemonProtocol.version, "event": "shortcutUpdateResult",
                "recordID": update.recordID, "requestID": requestID.uuidString,
                "revision": update.configuration.revision, "accepted": accepted])
        case let .setUserTextures(update):
            let urls = Self.resolveTextureURLs(update.references)
            let scopes = urls.values.filter { $0.startAccessingSecurityScopedResource() }
            host.applyUserTextureUpdate(update, resolvedURLs: urls) { [weak self] outcome in
                scopes.forEach { $0.stopAccessingSecurityScopedResource() }
                var response: [String: Any] = [
                    "v": SceneDaemonProtocol.version, "event": "textureUpdateResult",
                    "revision": update.revision, "recordID": update.recordID,
                ]
                switch outcome {
                case .applied: response["outcome"] = "applied"
                case .superseded: response["outcome"] = "superseded"
                case .unavailable: response["outcome"] = "unavailable"
                case let .failed(message):
                    response["outcome"] = "failed"
                    response["message"] = message
                }
                self?.emit(response)
#if DEBUG
                self?.capturePresentedFrameIfRequested(reason: "user-texture-\(update.revision)")
#endif
            }
        case let .cancelLaunch(recordID):
            host.cancelPendingLaunch(
                recordID: recordID
            )
        case let .commitCandidate(requestID):
            host.commitCandidate(requestID: requestID)
        case let .finalizeCandidate(requestID):
            host.finalizeCandidate(requestID: requestID)
        case let .cancelCandidate(requestID, operationID):
            let windows = host.outputWindows(requestID: requestID)
            let accepted = host.cancelCandidate(requestID: requestID)
            if let operationID {
                confirmOutputWithdrawal(windows: windows) { [weak self] hidden in
                    self?.emitSwitchControlResult(requestID: requestID, operationID: operationID,
                                                  accepted: accepted && hidden)
                }
            }
        case let .setOutputActive(requestID, operationID, active):
            let accepted = host.setOutputActive(active, requestID: requestID)
            emitSwitchControlResult(requestID: requestID, operationID: operationID, accepted: accepted)
        case let .retireOutput(requestID, operationID, requireRequestRetirement):
            let windows = host.outputWindows(requestID: requestID)
            let knownRequest = host.hasRequestOutput(requestID: requestID)
            if requireRequestRetirement {
                pendingRequestRetirement = (requestID, operationID)
            }
            let accepted = host.retireOutput(requestID: requestID)
            if requireRequestRetirement {
                host.whenRequestResourcesReleased(requestID: requestID) { [weak self] succeeded in
                    guard let self, !self.isShuttingDown else { return }
                    self.confirmOutputWithdrawal(windows: windows) { [weak self] hidden in
                        self?.finishRequestRetirement(requestID: requestID, operationID: operationID,
                            accepted: accepted && hidden, knownRequest: knownRequest, succeeded: succeeded)
                    }
                }
            } else {
                confirmOutputWithdrawal(windows: windows) { [weak self] hidden in
                    self?.emitSwitchControlResult(requestID: requestID, operationID: operationID,
                                                  accepted: accepted && hidden)
                }
            }
        case let .setDisplayConfiguration(topology):
#if DEBUG
            NSLog(
                "MWX SCENE DAEMON: phase=display-configuration screens=%d",
                topology.count
            )
#endif
            host.applyDisplayConfiguration(topology)
        case let .setPerformanceProfile(profile):
            host.applyPerformanceProfile(profile)
        case let .setVolume(volume):
            PlaybackVolumeState.shared.setNormalizedVolume(volume)
            host.setMasterVolume(Double(volume))
        case let .setMuted(muted):
            PlaybackMuteState.shared.setMuted(muted)
            host.setMuted(muted)
        case let .captureFrame(requestID):
            captureWallpaperFrame(requestID: requestID)
        case let .publishAudioSpectrum(frame):
            let accepted = SceneAudioSpectrumInbox.shared.publishSystemCapture(
                left: frame.left,
                right: frame.right,
                left32: frame.left32,
                right32: frame.right32,
                left64: frame.left64,
                right64: frame.right64,
                token: frame.captureToken
            )
#if DEBUG
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
#endif
        case let .publishSystemMedia(frame):
            acknowledgeSystemMedia(systemMediaReceiver.receive(frame))
        case let .publishSystemMediaArtwork(chunk):
            acknowledgeSystemMedia(systemMediaReceiver.receive(chunk))
        case let .controlSystemMedia(control):
            guard systemMediaReceiver.control(control) else {
                if systemMediaReceiver.requiresReplay(after: control) {
                    emitSystemMediaEvent("systemMediaReplayRequested", frame: control.scope)
                }
                return
            }
            if control.operation == .clear {
                systemMediaLease?.cancel()
                systemMediaLease = nil
                SceneMediaThumbnailInbox.shared.clearMediaSession()
            } else {
                renewSystemMediaLease()
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

    private func installSystemMediaDemandBridge() {
        SceneSystemMediaDemandRegistry.shared.didChange = { [weak self] demand in
            guard let self, !self.isShuttingDown else { return }
            self.systemMediaReceiver.setDemand(demand)
            self.systemMediaLease?.cancel()
            self.systemMediaLease = nil
            if demand.requiresMedia { self.renewSystemMediaLease() }
            self.emitSystemMediaEvent("systemMediaDemandChanged", frame: demand)
        }
        let demand = SceneSystemMediaDemandRegistry.shared.demand
        systemMediaReceiver.setDemand(demand)
        emitSystemMediaEvent("systemMediaDemandChanged", frame: demand)
    }

    private func finishRequestRetirement(requestID: UUID, operationID: UUID,
                                         accepted: Bool, knownRequest: Bool, succeeded: Bool) {
        guard !isShuttingDown, let pending = pendingRequestRetirement,
              pending.requestID == requestID, pending.operationID == operationID else { return }
        let demand = SceneAudioSpectrumInbox.shared.captureDemand
        let requestRetired = accepted && knownRequest && succeeded
            && host.isEmptyForRequestRetirement && !demand.requiresSpectrum
        if requestRetired {
            if currentRequestID == requestID { currentRequestID = nil }
            // Both events use the original FIFO writer; no-demand precedes ACK.
            publishAudioSpectrumDemand(demand)
        }
        emitSwitchControlResult(requestID: requestID, operationID: operationID,
                                accepted: accepted, requestRetired: requestRetired)
        guard requestRetired else { shutdown(exitCode: 70); return }
        pendingRequestRetirement = nil
        drainPendingCommands()
    }

    private func emitSwitchControlResult(requestID: UUID, operationID: UUID, accepted: Bool,
                                         requestRetired: Bool? = nil) {
        var payload: [String: Any] = ["v": SceneDaemonProtocol.version, "event": "switchControlResult",
            "requestID": requestID.uuidString, "operationID": operationID.uuidString,
            "accepted": accepted]
        if let requestRetired { payload["requestRetired"] = requestRetired }
        emit(payload)
    }

    /// The accepted field confirms exact window withdrawal; strong retirement
    /// separately qualifies request CPU/GPU terminal. Failure makes the parent
    /// terminate this child and wait for physical exit before releasing its barrier.
    private func confirmOutputWithdrawal(windows: [NSWindow], completion: @escaping (Bool) -> Void) {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        let outputs = windows.map { (window: $0, number: UInt32(exactly: $0.windowNumber) ?? 0) }
        func check() {
            guard !isShuttingDown else { return }
            let hidden = outputs.allSatisfy { output in
                guard !output.window.isVisible || output.window.alphaValue <= 0.01 else { return false }
                guard output.number > 0,
                      let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, output.number)
                        as? [[String: Any]])?.first else { return true }
                return (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == false
                    || ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) <= 0.01
            }
            if hidden { completion(true) }
            else if ProcessInfo.processInfo.systemUptime >= deadline { completion(false) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: check) }
        }
        check()
    }

    private func acknowledgeSystemMedia(_ result: SceneDaemonMediaReceiver.Result) {
        var ack = result.acknowledgement
        if let publication = result.publication,
           !SceneMediaThumbnailInbox.shared.replaceSystemSnapshot(publication) {
            ack = .init(scope: ack.scope, kind: ack.kind, epoch: ack.epoch,
                revision: ack.revision, transferID: ack.transferID, index: ack.index,
                accepted: false)
        }
        emitSystemMediaEvent("systemMediaAcknowledged", frame: ack)
        if ack.accepted { renewSystemMediaLease() }
    }

    private func renewSystemMediaLease() {
        systemMediaLease?.cancel()
        let lease = DispatchWorkItem { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            self.systemMediaLease = nil
            self.systemMediaReceiver.expireLease()
            SceneMediaThumbnailInbox.shared.clearMediaSession()
        }
        systemMediaLease = lease
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: lease)
    }

    private func emitSystemMediaEvent<T: Encodable>(_ event: String, frame: T) {
        do {
            let data = try JSONEncoder().encode(frame)
            let object = try JSONSerialization.jsonObject(with: data)
            emit(["v": SceneDaemonProtocol.version, "event": event, "frame": object])
        } catch {
            emitError(code: "system-media-event-encoding", message: String(describing: error))
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
        guard demand == SceneAudioSpectrumInbox.shared.captureDemand,
              demand != audioDemand else { return }
        audioDemand = demand
#if DEBUG
        didReportNonSilentAudioPublication = false
#endif
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
                var payload: [String: Any] = [
                    "v": SceneDaemonProtocol.version,
                    "event": "launchStateChanged",
                    "phase": state.phase.rawValue,
                    "message": state.message,
                    "requestID": state.requestID.uuidString,
                    "recordID": state.recordID ?? NSNull()
                ]
                if let facts = state.callbackPropertyReachability,
                   let data = try? JSONEncoder().encode(facts),
                   let encoded = try? JSONSerialization.jsonObject(with: data) {
                    payload["callbackPropertyReachability"] = encoded
                }
                self.emit(payload)
                if state.phase == .failed || state.phase == .cancelled {
                    self.host.whenRequestResourcesReleased(requestID: state.requestID) { [weak self] succeeded in
                        guard let self else { return }
                        if succeeded { self.emitRequestResourcesReleased(state.requestID) }
                        else { self.shutdown(exitCode: 70) }
                    }
                }
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
                self.host.noteCandidatePresentation(requestID: presentation.requestID)
                self.emit([
                    "v": SceneDaemonProtocol.version,
                    "event": "firstFramePresented",
                    "requestID": presentation.requestID.uuidString,
                    "recordID": presentation.recordID ?? NSNull(),
                    "uptimeMs": Double(presentation.uptimeMicros) / 1_000
                ])
#if DEBUG
                self.capturePresentedFrameIfRequested(reason: "daemon-\(getpid())-first-present")
#endif
            }
        })
    }

    private func emitRequestResourcesReleased(_ requestID: UUID) {
        emit(["v": SceneDaemonProtocol.version, "event": "launchResourcesReleased",
              "requestID": requestID.uuidString, "resourcesRetired": true])
    }
#if DEBUG
    private func capturePresentedFrameIfRequested(reason: String) {
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
            reason: reason,
            outputDirectory: outputDirectory
        )
    }
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
#endif
    private func shutdown(exitCode: Int32) {
        DaemonParentLifetime.shared.requestShutdown()
        guard !isShuttingDown else { return }
        isShuttingDown = true
        SceneAudioSpectrumInbox.shared.setDemandObserver(nil)
        SceneSystemMediaDemandRegistry.shared.didChange = nil
        systemMediaLease?.cancel()
        systemMediaLease = nil
        commands.clear()
#if DEBUG
        statsTimer?.cancel()
        statsTimer = nil
#endif
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

    /// 自截壁纸表面一帧供主 App 同步系统壁纸。SCK 的 current-process
    /// 变体只枚举本进程窗口，daemon 捕获自己的表面无需屏幕录制权限；
    /// 候选过滤与捕获流程与主 App 侧共用 WallpaperRuntimeFrameCapture
    /// 的单一实现；JPEG 写入临时文件后经 frameCaptured 事件回传路径。
    private func captureWallpaperFrame(requestID: String) {
        WallpaperRuntimeFrameCapture.captureWallpaperWindowCGImage { image in
            DispatchQueue.main.async {
                self.finishWallpaperFrameCapture(
                    image: image,
                    requestID: requestID
                )
            }
        }
    }

    private func finishWallpaperFrameCapture(
        image: CGImage?,
        requestID: String
    ) {
        guard let image,
              let representation = NSBitmapImageRep(cgImage: image)
                  .representation(
                      using: .jpeg,
                      properties: [.compressionFactor: 0.9]
                  ) else {
            emit([
                "v": SceneDaemonProtocol.version,
                "event": "frameCaptureFailed",
                "requestID": requestID
            ])
            return
        }
        let url = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("mwx-scene-frame-\(requestID).jpg")
        do {
            try representation.write(to: url)
        } catch {
            emit([
                "v": SceneDaemonProtocol.version,
                "event": "frameCaptureFailed",
                "requestID": requestID
            ])
            return
        }
        emit([
            "v": SceneDaemonProtocol.version,
            "event": "frameCaptured",
            "requestID": requestID,
            "path": url.path
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
