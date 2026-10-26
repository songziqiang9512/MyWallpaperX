import AppKit
import Foundation

extension WallpaperEngine {
    /// One Video execution cohort. The product ticket is immutable; each
    /// helper request and its prepared generation remain separate identities.
    final class VideoSwitchExecution {
        let id = UUID()
        let activationID = UUID()
        let ticket: PlaybackSwitchTicket
        let wallpaper: VideoWallpaper
        let path: String
        let multiDisplayEnabled: Bool
        var fillMode: String
        var shouldLoop: Bool
        var sessions: [UInt32: DisplayDaemonSession] = [:]
        var requests: [UInt32: Int] = [:]
        var generations: [UInt32: UInt64] = [:]
        var visibleDisplays: Set<UInt32> = []
        var cancellationDisplays: Set<UInt32> = []
        var cancellationCompletions: [() -> Void] = []
        var retirementDisplays: Set<UInt32> = []
        var retirementCompletions: [() -> Void] = []
        var didReportPrepared = false
        var activated = false
        var ended = false
        var finalized = false
        var cancelling = false
        var retired = false
        var timeout: DispatchWorkItem?
        init(ticket: PlaybackSwitchTicket, wallpaper: VideoWallpaper,
             path: String, multiDisplayEnabled: Bool, fillMode: String, shouldLoop: Bool) {
            self.ticket = ticket; self.wallpaper = wallpaper; self.path = path
            self.multiDisplayEnabled = multiDisplayEnabled
            self.fillMode = fillMode; self.shouldLoop = shouldLoop
        }
    }

    struct DeferredVideoSwitchPreparation {
        let wallpaper: VideoWallpaper
        let ticket: PlaybackSwitchTicket
        let multiDisplayEnabled: Bool
        let fillMode: String
        let shouldLoop: Bool
    }

    struct VideoOutputAcknowledgement {
        let executionID: UUID
        let desired: Bool
        var pendingDisplays: Set<UInt32>
        let sessions: [UInt32: DisplayDaemonSession]
        let requests: [UInt32: Int]
        var awaitingExit: Set<UInt32> = []
        var succeeded = true
        let completion: (Bool) -> Void
    }

    func updateVideoExecutionPolicies(fillMode: String? = nil, shouldLoop: Bool? = nil) {
        for execution in videoExecutions.values where !execution.retired {
            if let fillMode { execution.fillMode = fillMode }
            if let shouldLoop { execution.shouldLoop = shouldLoop }
        }
        if let deferred = deferredVideoPreparation {
            deferredVideoPreparation = .init(wallpaper: deferred.wallpaper, ticket: deferred.ticket,
                multiDisplayEnabled: deferred.multiDisplayEnabled,
                fillMode: fillMode ?? deferred.fillMode, shouldLoop: shouldLoop ?? deferred.shouldLoop)
        }
    }

    func prepareVideoSwitch(_ wallpaper: VideoWallpaper, ticket: PlaybackSwitchTicket,
                            multiDisplayEnabled: Bool, videoFillMode: String,
                            shouldLoopCurrentItem: Bool) {
        guard ticket.runtime == .video, DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses else {
            switchFailed?(ticket, "Video process admission is closed"); return
        }
        if let pending = videoCandidate, pending.ticket.epoch > ticket.epoch { return }
        if let active = activeVideoExecution, active.ticket.epoch > ticket.epoch { return }
        if let visible = videoCandidate, visible.activated, !visible.cancelling,
           !visible.sessions.isEmpty, visible.visibleDisplays.count == visible.sessions.count {
            deferredVideoPreparation = .init(wallpaper: wallpaper, ticket: ticket,
                multiDisplayEnabled: multiDisplayEnabled, fillMode: videoFillMode,
                shouldLoop: shouldLoopCurrentItem)
            return
        }
        if let previous = videoCandidate { cancelVideoExecution(previous, completion: {}) }
        adoptIntentEpoch(ticket.epoch)
        scanDisplays()
        let displays = multiDisplayEnabled ? displayIDs : Array(displayIDs.prefix(1))
        let execution = VideoSwitchExecution(ticket: ticket, wallpaper: wallpaper,
            path: normalizedPath(wallpaper.path), multiDisplayEnabled: multiDisplayEnabled,
            fillMode: videoFillMode, shouldLoop: shouldLoopCurrentItem)
        videoExecutions[execution.id] = execution
        videoCandidate = execution
        guard !displays.isEmpty else { failVideoExecution(execution, message: "No target display"); return }
        for display in displays {
            guard let session = ensureSession(for: display) else {
                failVideoExecution(execution, message: "无法启动视频播放进程"); return
            }
            execution.sessions[display] = session
            session.nextRequestID += 1
            let request = session.nextRequestID
            execution.requests[display] = request
#if DEBUG
            session.latestRequestedPlayRequestID = request
            session.latestReadyPlayRequestID = nil
#endif
            var command = DaemonCommand(action: "play", videoPath: execution.path,
                framePath: wallpaper.staticFramePath, propertiesJSON: nil,
                fillMode: videoFillMode, shouldLoopCurrentItem: shouldLoopCurrentItem,
                volume: effectiveVolumeNormalized, playbackRate: targetPlaybackRate,
                spectrumEnabled: currentSystemAudioSpectrumEnabled,
                spectrumLevels: spectrumDelivery.currentOverlayLevels,
                spectrumBarCount: currentSystemAudioSpectrumBarCount,
                spectrumColorHex: currentSystemAudioSpectrumColorHex,
                spectrumOffsetX: currentSystemAudioSpectrumOffsetX,
                spectrumOffsetY: currentSystemAudioSpectrumOffsetY,
                spectrumPeakCapsEnabled: currentSystemAudioSpectrumPeakCapsEnabled, requestID: request)
            command.cohortID = execution.id
            send(command, to: session)
            sendPlaybackPaused(playbackPaused, to: session)
        }
        armVideoTimeout(execution, seconds: 45)
        PlaybackPolicyController.shared.refresh()
    }

    func cancelSwitch(ticket: PlaybackSwitchTicket, completion: @escaping () -> Void) {
        if ticket.runtime == .web {
            guard let adapter = dedicatedWebHostAdapter as? WebDaemonHostAdapter else { completion(); return }
            adapter.cancelSwitch(ticket: ticket) { [weak self] in
                completion()
                self?.replayDeferredVideoEndIfNeeded()
            }
            return
        }
        if deferredVideoPreparation?.ticket == ticket { deferredVideoPreparation = nil }
        let pending = videoExecutions.values.filter { $0.ticket == ticket && !$0.finalized && !$0.retired }
        guard !pending.isEmpty else { completion(); return }
        var remaining = pending.count
        for execution in pending {
            cancelVideoExecution(execution) { remaining -= 1; if remaining == 0 { completion() } }
        }
    }

    func videoExecution(for event: DaemonEvent, session: DisplayDaemonSession) -> VideoSwitchExecution? {
        guard let id = event.cohortID, let execution = videoExecutions[id],
              execution.sessions[session.displayID] === session,
              execution.requests[session.displayID] == event.requestID else { return nil }
        return execution
    }

    func videoDidPrepare(_ event: DaemonEvent, session: DisplayDaemonSession) {
        guard let execution = videoExecution(for: event, session: session),
              videoCandidate === execution, !execution.cancelling,
              let generation = event.preparationGeneration else { return }
        execution.generations[session.displayID] = generation
        guard execution.generations.count == execution.sessions.count,
              !execution.didReportPrepared else { return }
        execution.didReportPrepared = true
        let endpoint = videoEndpoint(execution)
        if let switchPrepared { switchPrepared(execution.ticket, endpoint) }
        else { endpoint.activate() }
    }

    private func videoEndpoint(_ execution: VideoSwitchExecution) -> PlaybackSwitchEndpoint {
        .init(id: execution.id,
            activate: { [weak self, weak execution] in
                guard let self, let execution, self.videoCandidate === execution,
                      !execution.cancelling, !execution.activated else { return }
                execution.activated = true
                self.armVideoTimeout(execution, seconds: 8)
                for session in execution.sessions.values {
                    self.sendVideoExecutionControl("commitVideo", execution: execution, session: session)
                }
            },
            finalize: { [weak self, weak execution] in
                guard let self, let execution else { return }
                self.finalizeVideoExecution(execution)
            },
            cancel: { [weak self, weak execution] completion in
                guard let self, let execution else { completion(); return }
                self.cancelVideoExecution(execution, completion: completion)
            },
            setOutputActive: { [weak self, weak execution] active, completion in
                guard let self, let execution else { completion(false); return }
                self.setVideoOutputActive(execution, active: active, completion: completion)
            },
            retire: { [weak self, weak execution] _, completion in
                guard let self, let execution else { completion(); return }
                self.retireVideoExecution(execution, completion: completion)
            })
    }

    func videoDidBecomeVisible(_ event: DaemonEvent, session: DisplayDaemonSession) {
        guard let execution = videoExecution(for: event, session: session),
              videoCandidate === execution, execution.activated, !execution.cancelling,
              event.activationID == execution.activationID,
              event.preparationGeneration == execution.generations[session.displayID],
              let evidence = event.visibility, evidence.count == 1,
              evidence[0].displayID == session.displayID,
              evidence[0].expectedPID == session.process.processIdentifier,
              PlaybackSurfaceVisibility.evaluate(evidence[0]) == .confirmed else { return }
        execution.visibleDisplays.insert(session.displayID)
#if DEBUG
        session.latestReadyPlayRequestID = event.requestID
#endif
        guard execution.visibleDisplays.count == execution.sessions.count else { return }
        execution.timeout?.cancel(); execution.timeout = nil
        if let switchVisible { switchVisible(execution.ticket, execution.id) }
        else { finalizeVideoExecution(execution) }
    }

    private func finalizeVideoExecution(_ execution: VideoSwitchExecution) {
        guard videoCandidate === execution, !execution.cancelling, !execution.finalized,
              execution.visibleDisplays.count == execution.sessions.count else { return }
        let previous = activeVideoExecution
        pendingVideoRecovery = nil
        execution.finalized = true
        videoCandidate = nil
        activeVideoExecution = execution
        for (display, session) in execution.sessions {
            session.latestFinalizedPlayRequestID = execution.requests[display]
            sendVideoExecutionControl("finalizeVideo", execution: execution, session: session)
            displayCrashCounts[display] = 0
        }
        activeVideoPlayback = .init(wallpaper: execution.wallpaper, path: execution.path,
            multiDisplayEnabled: execution.multiDisplayEnabled)
        if execution.ended, let activeVideoPlayback {
            videoEndState = (activeVideoPlayback.id, false)
        }
        currentWallpaper = execution.wallpaper
        currentContentPath = execution.path
        currentPlaybackContentKind = .video
        currentVideoFillMode = execution.fillMode
        currentMultiDisplayEnabled = execution.multiDisplayEnabled
        currentShouldLoopCurrentItem = execution.shouldLoop
        lastFailureVideoPath = nil; lastFailureAt = 0
        if switchPrepared == nil, let previous { retireVideoExecution(previous, completion: {}) }
        NotificationCenter.default.post(name: Self.playbackReadyNotification,
            object: self, userInfo: ["videoPath": execution.path])
        replayDeferredVideoEndIfNeeded()
        runDeferredVideoPreparationIfPossible()
    }

    private func runDeferredVideoPreparationIfPossible() {
        guard videoCandidate == nil, let deferred = deferredVideoPreparation else { return }
        deferredVideoPreparation = nil
        prepareVideoSwitch(deferred.wallpaper, ticket: deferred.ticket,
            multiDisplayEnabled: deferred.multiDisplayEnabled, videoFillMode: deferred.fillMode,
            shouldLoopCurrentItem: deferred.shouldLoop)
    }

    private func sendVideoExecutionControl(_ action: String, execution: VideoSwitchExecution,
                                          session: DisplayDaemonSession) {
        var command = DaemonCommand(action: action, videoPath: nil, framePath: nil,
            propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil,
            playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil,
            spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil,
            spectrumPeakCapsEnabled: nil, requestID: execution.requests[session.displayID])
        command.cohortID = execution.id
        command.activationID = execution.activationID
        command.preparationGeneration = execution.generations[session.displayID]
        send(command, to: session)
    }

    func cancelVideoExecution(_ execution: VideoSwitchExecution, completion: @escaping () -> Void) {
        guard !execution.finalized, !execution.retired else { completion(); return }
        execution.cancellationCompletions.append(completion)
        guard !execution.cancelling else { return }
        execution.cancelling = true
        execution.timeout?.cancel()
        if videoCandidate === execution { videoCandidate = nil }
        execution.cancellationDisplays = Set(execution.sessions.keys)
        for (display, session) in execution.sessions {
            if !session.process.isRunning { execution.cancellationDisplays.remove(display) }
            else { sendVideoExecutionControl("cancelVideoPreparation", execution: execution, session: session) }
        }
        finishVideoCancellationIfPossible(execution)
        let timeout = DispatchWorkItem { [weak self, weak execution] in
            guard let self, let execution, !execution.cancellationDisplays.isEmpty else { return }
            for display in execution.cancellationDisplays {
                guard let session = execution.sessions[display] else { continue }
                // No ACK means silence/visibility is unproved. Reclaim the exact
                // helper; actual exit supplies the cancellation acknowledgement.
                session.transport.requestGracefulStop(gracePeriod: 0)
                self.refreshVideoSpectrumTargets()
            }
        }
        execution.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
    }

    func videoDidCancel(_ event: DaemonEvent, session: DisplayDaemonSession) {
        guard let execution = videoExecution(for: event, session: session), execution.cancelling,
              event.activationID == execution.activationID,
              event.preparationGeneration == execution.generations[session.displayID] else { return }
        execution.cancellationDisplays.remove(session.displayID)
        finishVideoCancellationIfPossible(execution)
    }

    private func finishVideoCancellationIfPossible(_ execution: VideoSwitchExecution) {
        guard execution.cancelling, execution.cancellationDisplays.isEmpty else { return }
        execution.timeout?.cancel(); execution.timeout = nil
        execution.retired = true
        videoExecutions.removeValue(forKey: execution.id)
        for (display, session) in execution.sessions {
            let hasExecutionOwner = videoExecutions.values.contains {
                !$0.retired && !$0.cancelling && $0.sessions[display] === session
            }
            let hasActiveOwner = activeVideoExecution.map {
                $0.finalized && !$0.retired && !$0.cancelling && $0.sessions[display] === session
            } == true
            guard !hasExecutionOwner, !hasActiveOwner else { continue }
            // A cancellation ACK proves the candidate withdrew its media and
            // window. An otherwise ownerless helper must also leave the live
            // display table; physical retention stays with its transport.
            if displaySessions[display] === session { terminateSession(for: display) }
            else { session.transport.requestGracefulStop() }
        }
        let callbacks = execution.cancellationCompletions
        execution.cancellationCompletions.removeAll()
        callbacks.forEach { $0() }
        replayDeferredVideoEndIfNeeded()
        runDeferredVideoPreparationIfPossible()
        schedulePendingVideoRecoveryIfPossible()
    }

    private func setVideoOutputActive(_ execution: VideoSwitchExecution, active: Bool,
                                      completion: @escaping (Bool) -> Void) {
        guard !execution.retired else { completion(!active); return }
        let live = execution.sessions.filter { $0.value.process.isRunning }
        if active, live.count != execution.sessions.count { completion(false); return }
        guard !live.isEmpty else { completion(!active); return }
        let id = UUID()
        videoOutputAcknowledgements[id] = .init(executionID: execution.id, desired: active,
            pendingDisplays: Set(live.keys), sessions: live, requests: execution.requests, completion: completion)
        for (display, session) in live {
            var command = DaemonCommand(action: "setOutputActivity", videoPath: nil, framePath: nil,
                propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil,
                playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil,
                spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil,
                spectrumPeakCapsEnabled: nil, requestID: execution.requests[display])
            command.cohortID = execution.id; command.outputActive = active; command.activityID = id
            send(command, to: session)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, var acknowledgement = self.videoOutputAcknowledgements[id] else { return }
            acknowledgement.awaitingExit = acknowledgement.pendingDisplays
            self.videoOutputAcknowledgements[id] = acknowledgement
            for display in acknowledgement.pendingDisplays {
                acknowledgement.sessions[display]?.transport.requestGracefulStop(gracePeriod: 0)
            }
        }
    }

    func videoDidChangeOutputActivity(_ event: DaemonEvent, session: DisplayDaemonSession) {
        guard let id = event.activityID, var acknowledgement = videoOutputAcknowledgements[id],
              acknowledgement.sessions[session.displayID] === session,
              acknowledgement.requests[session.displayID] == event.requestID,
              !acknowledgement.awaitingExit.contains(session.displayID),
              event.cohortID == acknowledgement.executionID else { return }
        acknowledgement.succeeded = acknowledgement.succeeded && event.outputActive == acknowledgement.desired
        acknowledgement.pendingDisplays.remove(session.displayID)
        if acknowledgement.pendingDisplays.isEmpty {
            videoOutputAcknowledgements.removeValue(forKey: id)
            acknowledgement.completion(acknowledgement.succeeded)
            if acknowledgement.desired, acknowledgement.succeeded { replayDeferredVideoEndIfNeeded() }
        } else { videoOutputAcknowledgements[id] = acknowledgement }
    }

    private func retireVideoExecution(_ execution: VideoSwitchExecution, completion: @escaping () -> Void) {
        if pendingVideoRecovery === execution { pendingVideoRecovery = nil }
        if let recovery = videoCandidate, recovery !== execution, recovery.ticket == execution.ticket,
           recovery.visibleDisplays.count != recovery.sessions.count {
            cancelVideoExecution(recovery, completion: {})
        }
        if execution.retired {
            if execution.retirementDisplays.isEmpty { completion() }
            else { execution.retirementCompletions.append(completion) }
            return
        }
        if !execution.finalized { cancelVideoExecution(execution, completion: completion); return }
        execution.retired = true
        execution.retirementCompletions.append(completion)
        for (display, session) in execution.sessions {
            let sharesVisibleSuccessor = videoCandidate.map { successor in
                successor !== execution && successor.sessions[display] === session
                    && successor.visibleDisplays.contains(display) && !successor.cancelling
            } == true
            // The candidate already occupies this helper's visible slot. Its
            // later finalize releases the retained old slot without killing it.
            if sharesVisibleSuccessor || session.latestFinalizedPlayRequestID != execution.requests[display] { continue }
            guard session.process.isRunning else { continue }
            execution.retirementDisplays.insert(display)
            if displaySessions[display] === session { terminateSession(for: display) }
            else { session.transport.requestGracefulStop() }
        }
        finishVideoRetirementIfPossible(execution)
    }

    private func finishVideoRetirementIfPossible(_ execution: VideoSwitchExecution) {
        guard execution.retired, execution.retirementDisplays.isEmpty else { return }
        videoExecutions.removeValue(forKey: execution.id)
        if activeVideoExecution === execution, videoCandidate == nil {
            activeVideoExecution = nil; activeVideoPlayback = nil
            if currentPlaybackContentKind == .video {
                currentWallpaper = nil; currentContentPath = nil; currentPlaybackContentKind = nil
            }
        }
        let callbacks = execution.retirementCompletions
        execution.retirementCompletions.removeAll()
        callbacks.forEach { $0() }
    }

    private func failVideoExecution(_ execution: VideoSwitchExecution, message: String) {
        guard !execution.retired, !execution.cancelling else { return }
        switchFailed?(execution.ticket, message)
        if switchFailed == nil {
            NotificationCenter.default.post(name: Self.playbackFailedNotification, object: self,
                userInfo: ["videoPath": execution.path, "message": message, "contentKind": "video"])
        }
        cancelVideoExecution(execution, completion: {})
    }

    private func armVideoTimeout(_ execution: VideoSwitchExecution, seconds: TimeInterval) {
        execution.timeout?.cancel()
        let timeout = DispatchWorkItem { [weak self, weak execution] in
            guard let self, let execution, self.videoCandidate === execution else { return }
            self.failVideoExecution(execution, message: "Video preparation or visibility confirmation timed out")
        }
        execution.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    func videoSessionDidExit(_ session: DisplayDaemonSession, wasCurrent: Bool) {
        for execution in Array(videoExecutions.values) where execution.sessions[session.displayID] === session {
            if execution.retired {
                execution.retirementDisplays.remove(session.displayID)
                finishVideoRetirementIfPossible(execution)
            } else if execution.cancelling {
                execution.cancellationDisplays.remove(session.displayID)
                finishVideoCancellationIfPossible(execution)
            } else if !execution.finalized {
                failVideoExecution(execution, message: "Video playback process exited during preparation")
            }
        }
        for id in Array(videoOutputAcknowledgements.keys) {
            guard var acknowledgement = videoOutputAcknowledgements[id],
                  acknowledgement.sessions[session.displayID] === session,
                  acknowledgement.pendingDisplays.contains(session.displayID) else { continue }
            acknowledgement.pendingDisplays.remove(session.displayID)
            acknowledgement.awaitingExit.remove(session.displayID)
            acknowledgement.succeeded = acknowledgement.succeeded && !acknowledgement.desired
            if acknowledgement.pendingDisplays.isEmpty {
                videoOutputAcknowledgements.removeValue(forKey: id)
                acknowledgement.completion(acknowledgement.succeeded)
            } else { videoOutputAcknowledgements[id] = acknowledgement }
        }
        guard wasCurrent, let active = activeVideoExecution, !active.retired,
              active.sessions[session.displayID] === session,
              DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses else { return }
        pendingVideoRecovery = active
        schedulePendingVideoRecoveryIfPossible()
    }

    private func schedulePendingVideoRecoveryIfPossible() {
        guard let active = pendingVideoRecovery, activeVideoExecution === active,
              !active.retired, videoCandidate == nil, deferredVideoPreparation == nil,
              DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses else { return }
        let failures = active.sessions.keys.map { displayCrashCounts[$0, default: 0] }.max() ?? 0
        let delay = DaemonRestartBackoff.delay(forConsecutiveFailureCount: failures)
        for display in active.sessions.keys { displayCrashCounts[display, default: 0] += 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak active] in
            guard let self, let active, self.pendingVideoRecovery === active,
                  self.activeVideoExecution === active, self.videoCandidate == nil,
                  self.deferredVideoPreparation == nil, !active.retired else { return }
            self.pendingVideoRecovery = nil
            self.prepareVideoSwitch(active.wallpaper, ticket: active.ticket,
                multiDisplayEnabled: active.multiDisplayEnabled, videoFillMode: self.currentVideoFillMode,
                shouldLoopCurrentItem: self.currentShouldLoopCurrentItem)
        }
    }
}
