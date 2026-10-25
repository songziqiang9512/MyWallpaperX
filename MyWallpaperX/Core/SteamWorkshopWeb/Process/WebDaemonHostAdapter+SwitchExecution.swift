import Foundation

extension WebDaemonHostAdapter {
    struct DeferredWebSwitchPreparation {
        let request: WallpaperEngine.WebWallpaperLaunchRequest
        let state: WallpaperEngine.WebWallpaperRuntimeState
        let recoveryAttempt: Int
        let ticket: PlaybackSwitchTicket
    }

    func runDeferredPreparationIfPossible() {
        guard candidate == nil, let deferred = deferredPreparation else { return }
        deferredPreparation = nil
        launch(deferred.request, state: deferred.state,
            recoveryAttempt: deferred.recoveryAttempt, ticket: deferred.ticket)
    }

    func schedulePendingRecoveryIfPossible() {
        guard active == nil, candidate == nil, deferredPreparation == nil,
              recoveryWorkItem == nil, let recovery = pendingRecovery,
              DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses else { return }
        let session = recovery.session
        let work = DispatchWorkItem { [weak self, weak session] in
            guard let self else { return }
            self.recoveryWorkItem = nil
            guard let session, self.pendingRecovery?.session === session,
                  self.active == nil, self.candidate == nil, self.deferredPreparation == nil else { return }
            self.pendingRecovery = nil
            self.launch(session.executionRequest, state: session.state,
                recoveryAttempt: recovery.attempt, ticket: session.ticket)
        }
        recoveryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(recovery.attempt), execute: work)
    }

    func rebuildCandidateSession(_ session: Session) {
        guard candidate === session, !session.isCancelling, !session.didObserveExit else { return }
        displayRebuildSource = session
        // Keep the old execution/activation identities intact: a Manager that
        // still holds that endpoint must wait for this exact renderer's exit.
        cancelSession(session, preservingDisplayRebuild: true, completion: {})
        retireEndpoint(session, preservingDisplayRebuild: true) { [weak self, weak session] in
            guard let self, let session, self.displayRebuildSource === session else { return }
            self.displayRebuildSource = nil
            guard self.candidate == nil, self.deferredPreparation == nil else { return }
            self.launch(session.executionRequest, state: session.state,
                recoveryAttempt: session.recoveryAttempt, ticket: session.ticket)
        }
    }

    func receivePreparedCohort(_ cohort: WebDaemonPreparedCohort, from session: Session) {
        guard candidate === session, !session.isCancelling, !cohort.surfaces.isEmpty,
              cohort.generation >= session.minimumPreparationGeneration,
              cohort.generation > (session.preparedCohort?.generation ?? 0),
              Set(cohort.surfaces.map(\.displayID)).count == cohort.surfaces.count else { return }
        if session.preparedCohort != nil {
            rebuildCandidateSession(session)
            return
        }
#if DEBUG
        session.startupTiming?.preparedCohortAcceptedAt = ProcessInfo.processInfo.systemUptime
#endif
        session.visibilityConfirmed = false
        session.activationSent = false
        session.preparedCohort = cohort
        session.preparationGeneration = cohort.generation
        let identity = WebDaemonActivationIdentity(generation: cohort.generation, activationID: UUID())
        session.activationIdentity = identity
        let endpoint = switchEndpoint(session, identity: identity, executionID: session.executionID)
        if let switchPrepared { switchPrepared(session.ticket, endpoint) }
        else { endpoint.activate() }
    }

    func switchEndpoint(_ session: Session, identity: WebDaemonActivationIdentity,
                        executionID: UUID) -> PlaybackSwitchEndpoint {
        .init(id: executionID,
            activate: { [weak self, weak session] in
                guard let self, let session, self.candidate === session,
                      session.executionID == executionID, !session.isCancelling, !session.activationSent,
                      session.activationIdentity == identity, let cohort = session.preparedCohort else { return }
                session.activationSent = true
                self.armSessionTimeout(session, after: 8, message: "Web 可见确认超时")
#if DEBUG
                session.startupTiming?.activationSentAt = ProcessInfo.processInfo.systemUptime
#endif
                self.send(.activate(.init(identity: identity, surfaces: cohort.surfaces)), to: session)
            },
            finalize: { [weak self, weak session] in
                guard let self, let session, session.executionID == executionID else { return }
                self.finalizeSession(session, identity: identity)
            },
            cancel: { [weak self, weak session] completion in
                guard let self, let session else { completion(); return }
                self.cancelSession(session, completion: completion)
            },
            setOutputActive: { [weak self, weak session] active, completion in
                guard let self, let session, session.executionID == executionID else { completion(!active); return }
                self.setOutputActivity(active, session: session, completion: completion)
            },
            retire: { [weak self, weak session] _, completion in
                guard let self, let session else { completion(); return }
                self.retireEndpoint(session, completion: completion)
            })
    }

    func finalizeSession(_ session: Session, identity: WebDaemonActivationIdentity) {
        guard candidate === session, !session.isCancelling, session.visibilityConfirmed,
              session.activationIdentity == identity else { return }
        displayRebuildSource = nil
        pendingRecovery = nil; recoveryWorkItem?.cancel(); recoveryWorkItem = nil
        let previous = active
        if let previous { standby[ObjectIdentifier(previous)] = previous }
        active = session; candidate = nil
        session.committedAt = ProcessInfo.processInfo.systemUptime
        session.timeout?.cancel(); session.timeout = nil
        send(.finalize(identity), to: session)
        eventHandler?(.ready(requestID: session.request.id))
        if switchPrepared == nil, let previous { retireEndpoint(previous, completion: {}) }
        if active === session { scheduleIdlePreparation() }
        publishAudioDemand(force: true)
        runDeferredPreparationIfPossible()
    }

    func setOutputActivity(_ desired: Bool, session: Session, completion: @escaping (Bool) -> Void) {
        guard !session.isRetiring, session.transport.isRunning else { completion(!desired); return }
        let id = UUID()
        session.outputActivityCompletions[id] = (desired, completion)
        send(.setOutputActivity(desired, id), to: session)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak session] in
            guard let session, session.outputActivityCompletions[id] != nil else { return }
            session.outputActivityAwaitingExit.insert(id)
            session.transport.requestGracefulStop(gracePeriod: 0)
        }
    }

    func cancelSwitch(ticket: PlaybackSwitchTicket, completion: @escaping () -> Void) {
        if deferredPreparation?.ticket == ticket { deferredPreparation = nil }
        if displayRebuildSource?.ticket == ticket { displayRebuildSource = nil }
        var seen: Set<ObjectIdentifier> = []
        let sessions = ([candidate].compactMap { $0 } + Array(cancelling.values)
            + retiring.values.filter { $0.isCancelling })
            .filter { $0.ticket == ticket && seen.insert(ObjectIdentifier($0)).inserted }
        guard !sessions.isEmpty else { completion(); return }
        var remaining = sessions.count
        for session in sessions {
            cancelSession(session) { remaining -= 1; if remaining == 0 { completion() } }
        }
    }

    func cancelSession(_ session: Session, preservingDisplayRebuild: Bool = false,
                       completion: @escaping () -> Void) {
        if !preservingDisplayRebuild, displayRebuildSource === session { displayRebuildSource = nil }
        guard active !== session, standby[ObjectIdentifier(session)] == nil else { completion(); return }
        if !session.transport.isRunning { completion(); return }
        session.cancelCompletions.append(completion)
        guard !session.isCancelling else { return }
        session.isCancelling = true
        if candidate === session { candidate = nil }
        cancelling[ObjectIdentifier(session)] = session
        session.timeout?.cancel(); session.timeout = nil
        if let identity = session.activationIdentity {
            send(.cancelActivation(identity), to: session)
            let timeout = DispatchWorkItem { [weak self, weak session] in
                guard let self, let session, session.isCancelling else { return }
                self.retire(session) // completion waits for physical exit.
            }
            session.timeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
        } else {
            // Before a prepared identity exists, teardown plus actual exit is
            // the only evidence strong enough to acknowledge cancellation.
            retire(session)
        }
        publishAudioDemand(force: true)
    }

    func finishSessionCancellation(_ session: Session) {
        let callbacks = session.cancelCompletions
        session.cancelCompletions.removeAll()
        cancelling.removeValue(forKey: ObjectIdentifier(session))
        callbacks.forEach { $0() }
        runDeferredPreparationIfPossible()
        schedulePendingRecoveryIfPossible()
    }

    func retireEndpoint(_ session: Session, preservingDisplayRebuild: Bool = false,
                        completion: @escaping () -> Void) {
        if !preservingDisplayRebuild, displayRebuildSource === session { displayRebuildSource = nil }
        if pendingRecovery?.session.ticket == session.ticket {
            pendingRecovery = nil; recoveryWorkItem?.cancel(); recoveryWorkItem = nil
        }
        session.shouldRecoverOnExit = false
        if let recovery = candidate, recovery !== session, recovery.ticket == session.ticket,
           !recovery.visibilityConfirmed { cancelSession(recovery, completion: {}) }
        guard !session.didObserveExit else { completion(); return }
        session.retirementCompletions.append(completion)
        retiring[ObjectIdentifier(session)] = session
        if candidate === session { candidate = nil }
        if active === session { active = nil }
        standby.removeValue(forKey: ObjectIdentifier(session))
        retire(session)
        updateSpectrumTargets()
        publishAudioDemand(force: true)
    }

    func armSessionTimeout(_ session: Session, after delay: TimeInterval, message: String) {
        session.timeout?.cancel()
        let timeout = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session, self.candidate === session else { return }
            self.fail(session, message: message)
        }
        session.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: timeout)
    }
}
