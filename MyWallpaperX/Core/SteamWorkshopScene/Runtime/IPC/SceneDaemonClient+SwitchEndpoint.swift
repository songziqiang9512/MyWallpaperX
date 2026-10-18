import Foundation

@MainActor
extension SceneDaemonClient {
    struct QueuedSwitchPreparation {
        let request: ScenePlaybackLoadRequest
        let ticket: PlaybackSwitchTicket
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
        let completion: (Bool) -> Void
        var deadline: DispatchWorkItem?

        init(generation: UInt64, requestID: UUID?, transport: DaemonProcessTransport,
             requiresCancellation: Bool, completion: @escaping (Bool) -> Void) {
            self.generation = generation
            self.requestID = requestID
            self.transport = transport
            self.requiresCancellation = requiresCancellation
            self.completion = completion
        }
    }

    func prepareSwitch(_ request: ScenePlaybackLoadRequest, ticket: PlaybackSwitchTicket,
                       resourceLifetime: PlaybackResourceLifetime?) {
        if pendingSwitchExecution?.presented == true {
            // The product already committed this visible candidate; retiring its
            // previous output may still be in flight. A newer prepare must not
            // cancel it before the product's finalize arrives.
            queuedSwitchPreparation = .init(request: request, ticket: ticket,
                                             resourceLifetime: resourceLifetime)
            return
        }
        flushDeferredDisplayConfigurationUpdate()
        retainResourceLifetime(resourceLifetime, rootURL: request.rootURL, recordID: request.recordID)
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
            retire: { [weak self] completion in
                guard let self else { completion(); return }
                self.retireSwitch(execution, completion: completion)
            })
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
        resumeDeferredTextureUpdates(recordID: activeIntent?.recordID, requestID: execution.requestID)
        flushDeferredDisplayConfigurationUpdate()
        startQueuedSwitchIfPossible()
    }

    private func startQueuedSwitchIfPossible() {
        guard pendingSwitchExecution?.presented != true, let queued = queuedSwitchPreparation else { return }
        queuedSwitchPreparation = nil
        prepareSwitch(queued.request, ticket: queued.ticket, resourceLifetime: queued.resourceLifetime)
    }

    private func retireSwitch(_ execution: SwitchExecution, completion: @escaping () -> Void) {
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
                               recordID: queued.request.recordID)
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
                                      completion: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        let control = SwitchControl(generation: generation, requestID: requestID, transport: child,
                                    requiresCancellation: requiresCancellation, completion: completion)
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
              UUID(uuidString: requestRaw) == control.requestID,
              let accepted = payload["accepted"] as? Bool else { return }
        if !accepted, control.requiresCancellation {
            control.transport.terminate()
            return
        }
        switchControls.removeValue(forKey: id)
        control.deadline?.cancel()
        control.completion(accepted)
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
           accepted.rootURL.standardizedFileURL == fallback.rootURL.standardizedFileURL {
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
