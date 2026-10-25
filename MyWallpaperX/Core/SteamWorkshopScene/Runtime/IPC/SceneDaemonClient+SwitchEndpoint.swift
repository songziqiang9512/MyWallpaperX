import Foundation

#if DEBUG
nonisolated struct SceneDaemonStartupObservation: Sendable {
    enum Phase: String, Sendable { case prepared, parentFinalized }
    let phase: Phase
    let ticketID: UUID
    let intentEpoch: UInt64
    let requestID: UUID
    let executionID: UUID
    let transportGeneration: UInt64
    let daemonPID: Int32?
    let uptimeMicros: UInt64
}

/// Parent call boundaries plus optional values from this transport's hello.
nonisolated struct SceneDaemonStartupPrefixObservation: Sendable {
    enum Phase: String, Sendable {
        case preparationReceived, processStartBegan, processStartReturned
        case helloObserved, loadEnqueueAttempted
    }
    let phase: Phase
    let ticketID: UUID
    let intentEpoch: UInt64
    let requestID: UUID?
    let transportGeneration: UInt64
    let daemonPID: Int32?
    let uptimeMicros: UInt64
    var childStartupUptimes: [String: UInt64]? = nil
}
#endif

@MainActor
extension SceneDaemonClient {
    struct QueuedSwitchPreparation {
        let request: ScenePlaybackLoadRequest
        let ticket: PlaybackSwitchTicket?
        let resourceLifetime: PlaybackResourceLifetime?
    }
    struct CommittedSwitchRecovery {
        let request: ScenePlaybackLoadRequest
        let ticket: PlaybackSwitchTicket
        let resourceLifetime: PlaybackResourceLifetime?
    }
    /// Execution identity only. The product transaction owns selection and the
    /// decision to activate/finalize; this object scopes closures to one child.
    final class SwitchExecution {
        let ticket: PlaybackSwitchTicket
        let id = UUID()
        let requestID: UUID
        let generation: UInt64
        let transport: DaemonProcessTransport
        var activated = false
        var presented = false
        var outputActive = true

        init(ticket: PlaybackSwitchTicket, requestID: UUID, generation: UInt64,
             transport: DaemonProcessTransport) {
            self.ticket = ticket
            self.requestID = requestID
            self.generation = generation
            self.transport = transport
        }
    }

    final class SwitchControl {
        let generation: UInt64
        let requestID: UUID?
        let transport: DaemonProcessTransport
        let requiresCancellation: Bool
        let requiresRequestRetired: Bool
        let resourceLifetimes: [PlaybackResourceLifetime]
        let completion: (Bool) -> Void
        var deadline: DispatchWorkItem?

        init(generation: UInt64, requestID: UUID?, transport: DaemonProcessTransport,
             requiresCancellation: Bool, requiresRequestRetired: Bool = false,
             resourceLifetimes: [PlaybackResourceLifetime] = [], completion: @escaping (Bool) -> Void) {
            self.generation = generation
            self.requestID = requestID
            self.transport = transport
            self.requiresCancellation = requiresCancellation
            self.requiresRequestRetired = requiresRequestRetired
            self.resourceLifetimes = resourceLifetimes
            self.completion = completion
        }
    }

    /// One deadline for the existing transport, never a second process slot.
    final class IdleTransport {
        let generation: UInt64
        let transport: DaemonProcessTransport
        var deadline: DispatchWorkItem?

        init(generation: UInt64, transport: DaemonProcessTransport) {
            self.generation = generation
            self.transport = transport
        }
    }

    var hasRequestRetirementControl: Bool {
        switchControls.values.contains {
            $0.requiresRequestRetired && $0.generation == sessionGeneration && $0.transport === transport
        }
    }

    var hasRetainedOrRetiringTransport: Bool {
        idleTransport != nil || hasRequestRetirementControl || !retiringTransports.isEmpty
    }

    /// A new Scene may adopt this transport. Other intents revoke only empty
    /// retention; the committed Scene remains available for failed-switch rollback.
    func invalidateRetainedTransport(for runtime: WallpaperRuntimeKind?) {
        guard runtime != .scene, idleTransport != nil || hasRequestRetirementControl else { return }
        stop()
    }

    func discardIdleTransport() {
        idleTransport?.deadline?.cancel()
        idleTransport = nil
    }

    func prepareSwitch(_ request: ScenePlaybackLoadRequest, ticket: PlaybackSwitchTicket,
                       resourceLifetime: PlaybackResourceLifetime?) {
        if hasRequestRetirementControl || pendingSwitchExecution?.presented == true {
            // The product already committed this visible candidate; retiring its
            // previous output may still be in flight. A newer prepare must not
            // cancel it before the product's finalize arrives.
            queuedSwitchPreparation = .init(request: request, ticket: ticket,
                                             resourceLifetime: resourceLifetime)
            return
        }
        // A control completion may synchronously admit a newer selection before
        // it returns to the old queued continuation.
        queuedSwitchPreparation = nil
#if DEBUG
        observeDebugStartupPrefix(.preparationReceived, ticket: ticket)
#endif
        flushDeferredDisplayConfigurationUpdate()
        retainResourceLifetime(resourceLifetime, rootURL: request.rootURL, recordID: request.recordID,
                               source: request.source)
        startLaunch(request, ticket: ticket)
    }

    /// Also works before hello/prepared. Clearing the pending wire identity
    /// prevents replay; completion still waits for child rollback or real exit.
    func cancelSwitch(ticket: PlaybackSwitchTicket, completion: @escaping () -> Void) {
        if queuedSwitchPreparation?.ticket == ticket {
            queuedSwitchPreparation = nil
            completion()
            return
        }
        guard pendingSwitchTicket == ticket else { completion(); return }
        let requestID = pendingRequestID
        let pending = pendingIntent
        let generation = sessionGeneration
        let child = transport
        let recovery = committedSwitchRecovery
        let finish = { [weak self] in
            completion()
            self?.resumeCommittedSwitchRecoveryIfPossible(after: ticket)
        }
        finishPendingShortcutUpdates(.superseded)
        finishPendingTextureUpdates(.superseded)
        pendingIntent = nil
        pendingResourceLifetime = nil
        pendingRequestID = nil
        pendingPresentationRequestID = nil
        pendingPresentationReachability = nil
        pendingPropertyRevisions.removeAll(keepingCapacity: true)
        pendingSwitchTicket = nil
        pendingSwitchExecution = nil
        if activeIntent == nil {
            stop()
            committedSwitchRecovery = recovery
            waitForSwitchExit(child, generation: generation) { _ in finish() }
        } else if endpointReady, let requestID, let child {
            sendSwitchControl("cancelCandidate", requestID: requestID, child: child,
                              requiresCancellation: true) { _ in finish() }
        } else {
            // No load command was sent before hello, so no candidate can exist.
            finish()
        }
        if let pending {
            let state = SceneWallpaperLaunchState(requestID: requestID ?? UUID(),
                recordID: pending.recordID, phase: .cancelled, message: "已取消 Scene 壁纸准备")
            launchState = state
            NotificationCenter.default.post(name: .sceneWallpaperLaunchStateDidChange, object: state)
        }
    }

    func reportPreparedSwitch(requestID: UUID) -> Bool {
        guard let ticket = pendingSwitchTicket, let prepared = switchPrepared,
              let transport else { return false }
        guard pendingSwitchExecution == nil else { return true }
        let execution = SwitchExecution(ticket: ticket, requestID: requestID,
                                        generation: sessionGeneration, transport: transport)
        pendingSwitchExecution = execution
        let endpoint = PlaybackSwitchEndpoint(id: execution.id,
            activate: { [weak self] in self?.activateSwitch(execution) },
            finalize: { [weak self] in self?.finalizeSwitch(execution) },
            cancel: { [weak self] completion in
                guard let self else { completion(); return }
                self.cancelSwitchExecution(execution, completion: completion)
            },
            setOutputActive: { [weak self] active, completion in
                guard let self else { completion(false); return }
                self.setSwitchOutputActive(execution, active: active, completion: completion)
            },
            retire: { [weak self] replacement, completion in
                guard let self else { completion(); return }
                self.retireSwitch(execution, replacement: replacement, completion: completion)
            })
#if DEBUG
        observeDebugStartup(.prepared, execution: execution)
#endif
        prepared(ticket, endpoint)
        return true
    }

    private func acceptsSwitch(_ execution: SwitchExecution) -> Bool {
        execution.generation == sessionGeneration && transport?.isRunning == true
            && (pendingSwitchExecution === execution || activeSwitchExecution === execution)
    }

    private func activateSwitch(_ execution: SwitchExecution) {
        guard acceptsSwitch(execution), pendingSwitchExecution === execution,
              pendingRequestID == execution.requestID, !execution.activated else { return }
        execution.activated = true
        send(["v": SceneDaemonProtocol.version, "cmd": "commitCandidate",
              "requestID": execution.requestID.uuidString])
    }

    private func cancelSwitchExecution(_ execution: SwitchExecution, completion: @escaping () -> Void) {
        if pendingSwitchExecution === execution {
            cancelSwitch(ticket: execution.ticket, completion: completion)
        } else if activeSwitchExecution === execution {
            retireSwitch(execution, completion: completion)
        } else if execution.generation == sessionGeneration, transport === execution.transport,
                  activeSwitchExecution !== execution {
            // A same-ticket reprepare may already own the pending slot. Cancel
            // only the captured old wire request, never that replacement.
            sendSwitchControl("cancelCandidate", requestID: execution.requestID,
                              child: execution.transport, requiresCancellation: true) { _ in completion() }
        } else {
            waitForSwitchExit(execution.transport, generation: execution.generation) { _ in completion() }
        }
    }

    private func finalizeSwitch(_ execution: SwitchExecution) {
        guard acceptsSwitch(execution), pendingSwitchExecution === execution,
              execution.presented, pendingRequestID == execution.requestID else { return }
        commitPresentedScene(requestID: execution.requestID)
        activeSwitchTicket = execution.ticket
        activeSwitchExecution = execution
        pendingSwitchTicket = nil
        pendingSwitchExecution = nil
        committedSwitchRecovery = nil
#if DEBUG
        observeDebugStartup(.parentFinalized, execution: execution)
#endif
        resumeDeferredTextureUpdates(recordID: activeIntent?.recordID, requestID: execution.requestID)
        flushDeferredDisplayConfigurationUpdate()
        startQueuedSwitchIfPossible()
    }

#if DEBUG
    func observeDebugStartupPrefix(
        _ phase: SceneDaemonStartupPrefixObservation.Phase, ticket: PlaybackSwitchTicket? = nil,
        childStartupUptimes: [String: UInt64]? = nil
    ) {
        guard let observer = debugStartupPrefixObserver,
              let ticket = ticket ?? pendingSwitchTicket else { return }
        observer(.init(phase: phase, ticketID: ticket.id, intentEpoch: ticket.epoch,
            requestID: phase == .loadEnqueueAttempted ? pendingRequestID : nil,
            transportGeneration: sessionGeneration, daemonPID: debugProcessIdentifier,
            uptimeMicros: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000),
            childStartupUptimes: childStartupUptimes))
    }

    private func observeDebugStartup(
        _ phase: SceneDaemonStartupObservation.Phase, execution: SwitchExecution
    ) {
        guard let observer = debugStartupObserver else { return }
        observer(.init(phase: phase, ticketID: execution.ticket.id,
            intentEpoch: execution.ticket.epoch, requestID: execution.requestID,
            executionID: execution.id, transportGeneration: execution.generation,
            daemonPID: debugProcessIdentifier,
            uptimeMicros: UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)))
    }
#endif

    private func startQueuedSwitchIfPossible() {
        guard !hasRequestRetirementControl, pendingSwitchExecution?.presented != true,
              let queued = queuedSwitchPreparation else { return }
        queuedSwitchPreparation = nil
        if let ticket = queued.ticket {
            prepareSwitch(queued.request, ticket: ticket, resourceLifetime: queued.resourceLifetime)
        } else {
            retainResourceLifetime(queued.resourceLifetime, rootURL: queued.request.rootURL,
                                   recordID: queued.request.recordID, source: queued.request.source)
            startLaunch(queued.request, ticket: nil)
        }
    }

    private func retireSwitch(_ execution: SwitchExecution, replacement: PlaybackSwitchTicket? = nil,
                              completion: @escaping () -> Void) {
        let revokesRecovery = committedSwitchRecovery?.ticket == execution.ticket
        if revokesRecovery { committedSwitchRecovery = nil }
        if revokesRecovery, pendingSwitchTicket == execution.ticket,
           pendingSwitchExecution !== execution, pendingSwitchExecution?.presented != true {
            // A stale endpoint still represents the retired product selection.
            // Revoke that selection's in-flight recovery before admitting exit.
            cancelSwitch(ticket: execution.ticket, completion: completion)
            return
        }
        guard acceptsSwitch(execution) else {
            if execution.generation == sessionGeneration, transport === execution.transport {
                // A finalized same-engine replacement already owns this child;
                // the old standby was retired by its exact finalize command.
                completion()
            } else {
                waitForSwitchExit(execution.transport, generation: execution.generation) { _ in completion() }
            }
            return
        }
        if pendingSwitchExecution === execution {
            if execution.presented {
                let queued = queuedSwitchPreparation
                stop()
                queuedSwitchPreparation = queued
                waitForSwitchExit(execution.transport, generation: execution.generation) { [weak self] _ in
                    self?.startQueuedSwitchIfPossible()
                    completion()
                }
            } else {
                cancelSwitch(ticket: execution.ticket, completion: completion)
            }
        } else if pendingIntent == nil, activeSwitchExecution === execution {
            if let replacement, replacement.id != execution.ticket.id,
               replacement.runtime == .web || replacement.runtime == .video,
               endpointReady, requestRetirementSchemaVersion == 1,
               DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses {
                retireForIdleReuse(execution, completion: completion)
                return
            }
            let child = execution.transport
            stop()
            waitForSwitchExit(child, generation: execution.generation) { _ in completion() }
        } else if pendingSwitchExecution?.presented == true, activeSwitchExecution === execution {
            // The visible successor needs finalize to retire the GPU standby.
            // Confirm only old activity revocation, retaining rollback resources.
            sendSwitchControl("setOutputActive", requestID: execution.requestID,
                              child: execution.transport, active: false,
                              requiresCancellation: true) { _ in completion() }
        } else if activeSwitchExecution === execution {
            activeIntent = nil
            activeRequestID = nil
            activeRecordID = nil
            activeResourceLifetime = nil
            activeCallbackPropertyFacts = nil
            activeSwitchTicket = nil
            activeSwitchExecution = nil
            sendSwitchControl("retireOutput", requestID: execution.requestID,
                              child: execution.transport, requiresCancellation: true) { _ in completion() }
        } else { completion() }
    }

    private func retireForIdleReuse(_ execution: SwitchExecution, completion: @escaping () -> Void) {
        let child = execution.transport
        let generation = execution.generation
        let lifetimes = [activeResourceLifetime?.lifetime,
            requestResourceLifetimes[execution.requestID]].compactMap { $0 }
        let operationID = installSwitchControl(child, generation: generation, requestID: execution.requestID,
            requiresCancellation: true, requiresRequestRetired: true, resourceLifetimes: lifetimes) { [weak self] success in
                guard let self else { completion(); return }
                if success, self.transport === child, self.sessionGeneration == generation,
                   child.isRunning, self.activeIntent == nil, self.pendingIntent == nil,
                   DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses {
                    self.requestResourceLifetimes.removeValue(forKey: execution.requestID)
                    let idle = IdleTransport(generation: generation, transport: child)
                    self.idleTransport = idle
                    let deadline = DispatchWorkItem { [weak self, weak idle] in
                        guard let self, let idle, self.idleTransport === idle,
                              self.transport === idle.transport, self.sessionGeneration == idle.generation,
                              self.activeIntent == nil, self.pendingIntent == nil,
                              self.queuedSwitchPreparation == nil else { return }
                        self.stop()
                    }
                    idle.deadline = deadline
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: deadline)
                } else if success, self.transport === child, self.sessionGeneration == generation,
                          !DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses {
                    self.stop()
                }
                completion()
                self.startQueuedSwitchIfPossible()
            }
        // Install the existing control before invoking any reentrant callbacks.
        activeIntent = nil
        activeRequestID = nil
        activeRecordID = nil
        activeResourceLifetime = nil
        activeCallbackPropertyFacts = nil
        activeSwitchTicket = nil
        activeSwitchExecution = nil
        committedSwitchRecovery = nil
        latestFrameStats = nil
        finishPendingShortcutUpdates(.superseded)
        finishPendingTextureUpdates(.superseded)
        failPendingFrameCaptures()
        revokeAudioSpectrumDemand(generation: generation)
        revokeSystemMediaDemand(generation: generation)
        guard transport === child, sessionGeneration == generation,
              switchControls[operationID] != nil else { return }
        send(["v": SceneDaemonProtocol.version, "cmd": "retireOutput",
              "requestID": execution.requestID.uuidString, "operationID": operationID.uuidString,
              "requireRequestRetirement": true])
    }

    func rememberCommittedSwitchForRecovery() {
        if pendingSwitchExecution?.presented == true,
           let request = pendingIntent, let ticket = pendingSwitchTicket {
            committedSwitchRecovery = .init(request: request, ticket: ticket,
                resourceLifetime: pendingResourceLifetime?.lifetime)
        } else if let request = activeIntent, let ticket = activeSwitchTicket {
            committedSwitchRecovery = .init(request: request, ticket: ticket,
                resourceLifetime: activeResourceLifetime?.lifetime)
        }
    }

    func adoptQueuedSwitchPreparationForRecovery() {
        guard let queued = queuedSwitchPreparation else { return }
        queuedSwitchPreparation = nil
        pendingIntent = queued.request
        pendingSwitchTicket = queued.ticket
        retainResourceLifetime(queued.resourceLifetime, rootURL: queued.request.rootURL,
                               recordID: queued.request.recordID, source: queued.request.source)
    }

    func resumeCommittedSwitchRecoveryIfPossible(after failedTicket: PlaybackSwitchTicket?) {
        guard pendingIntent == nil, activeIntent == nil, queuedSwitchPreparation == nil,
              let recovery = committedSwitchRecovery, recovery.ticket != failedTicket else { return }
        restartBackoff.reset()
        prepareSwitch(recovery.request, ticket: recovery.ticket, resourceLifetime: recovery.resourceLifetime)
    }

    private func setSwitchOutputActive(_ execution: SwitchExecution, active: Bool,
                                      completion: @escaping (Bool) -> Void) {
        guard acceptsSwitch(execution), let child = transport else {
            // A crashed old child has physically relinquished output. This is
            // sufficient for deactivation, but cannot restore that execution.
            completion(!active && !execution.transport.isRunning)
            return
        }
        sendSwitchControl("setOutputActive", requestID: execution.requestID, child: child,
                          active: active) { success in
            if success { execution.outputActive = active }
            completion(success)
        }
    }

    private func sendSwitchControl(_ command: String, requestID: UUID,
                                   child: DaemonProcessTransport, active: Bool? = nil,
                                   requiresCancellation: Bool = false,
                                   completion: @escaping (Bool) -> Void) {
        let id = installSwitchControl(child, generation: sessionGeneration, requestID: requestID,
                                      requiresCancellation: requiresCancellation, completion: completion)
        var payload: [String: Any] = ["v": SceneDaemonProtocol.version, "cmd": command,
            "requestID": requestID.uuidString, "operationID": id.uuidString]
        if let active { payload["active"] = active }
        send(payload)
    }

    private func waitForSwitchExit(_ child: DaemonProcessTransport?, generation: UInt64,
                                  completion: @escaping (Bool) -> Void) {
        guard let child, child.isRunning else { completion(false); return }
        _ = installSwitchControl(child, generation: generation, requestID: nil,
                                 requiresCancellation: true, completion: completion)
    }

    private func installSwitchControl(_ child: DaemonProcessTransport, generation: UInt64,
                                      requestID: UUID?, requiresCancellation: Bool,
                                      requiresRequestRetired: Bool = false,
                                      resourceLifetimes: [PlaybackResourceLifetime] = [],
                                      completion: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        let control = SwitchControl(generation: generation, requestID: requestID, transport: child,
                                    requiresCancellation: requiresCancellation,
                                    requiresRequestRetired: requiresRequestRetired,
                                    resourceLifetimes: resourceLifetimes, completion: completion)
        switchControls[id] = control
        let deadline = DispatchWorkItem { [weak self, weak control] in
            guard let self, let control, self.switchControls[id] === control else { return }
            // No ACK is not permission to overlap outputs. The independent
            // transport deadline escalates to KILL and termination settles it.
            control.transport.terminate()
        }
        control.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: deadline)
        return id
    }

    func handleSwitchControlResult(_ payload: [String: Any], generation: UInt64) {
        guard let raw = payload["operationID"] as? String, let id = UUID(uuidString: raw),
              let control = switchControls[id], control.generation == generation,
              let requestRaw = payload["requestID"] as? String,
              UUID(uuidString: requestRaw) == control.requestID else { return }
        let accepted = control.requiresRequestRetired
            ? SceneDaemonProtocol.boolean(payload["accepted"]) : payload["accepted"] as? Bool
        guard let accepted else { return }
        if control.requiresRequestRetired,
           (transport !== control.transport || generation != sessionGeneration
            || expectedTerminationGenerations.contains(generation)) { return }
        let succeeded = accepted && (!control.requiresRequestRetired
            || SceneDaemonProtocol.boolean(payload["requestRetired"]) == true)
        if !succeeded, control.requiresCancellation {
            control.transport.terminate()
            return
        }
        switchControls.removeValue(forKey: id)
        control.deadline?.cancel()
        control.completion(succeeded)
    }

    func finishSwitchControlsAfterExit(generation: UInt64) {
        let completed = switchControls.filter { $0.value.generation == generation }
        for (id, control) in completed {
            switchControls.removeValue(forKey: id)
            control.deadline?.cancel()
        }
        completed.values.forEach { $0.completion(false) }
    }

    /// Executing this method requires an actual drawable-presented event.
    /// Product-managed calls reach it only through endpoint.finalize.
    func commitPresentedScene(requestID: UUID) {
        let fallback = fallbackReplayIntent(requestID: requestID)
        if let fallback, let accepted = activeIntent, accepted.recordID == fallback.recordID,
           accepted.rootURL.standardizedFileURL == fallback.rootURL.standardizedFileURL,
           accepted.source == fallback.source {
            activeIntent = accepted
        } else { activeIntent = fallback ?? pendingIntent }
        activeResourceLifetime = pendingResourceLifetime
        activeRecordID = pendingIntent?.recordID
        activeRequestID = requestID
        pendingIntent = nil
        pendingResourceLifetime = nil
        pendingRequestID = nil
        activeCallbackPropertyFacts = pendingPresentationReachability.map {
            .init(transportGeneration: sessionGeneration, requestID: requestID,
                  recordID: activeRecordID, reachability: $0)
        }
        pendingPresentationRequestID = nil
        pendingPresentationReachability = nil
        send(["v": SceneDaemonProtocol.version, "cmd": "finalizeCandidate",
              "requestID": requestID.uuidString])
    }
}
