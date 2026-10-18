import AppKit
import Foundation

extension SceneDesktopWallpaperHost {
    func beginCandidate(
        _ context: SceneDesktopWallpaperLaunchContext,
        firstPresentation: SceneFirstFramePresentationRegistration,
        completion: @escaping (Result<Void, Error>) -> Void
    ) throws {
        let session = SceneDesktopWallpaperSession(textureDecodeCacheBudget: textureDecodeCacheBudget)
        session.launchRequestID = firstPresentation.requestID
        configure(session)
        candidateSession = session
        candidateCompletion = completion
#if DEBUG
        NSLog("MWX Scene: phase=session-candidate session=%@", session.lifecycleID.uuidString)
#endif
        var pendingScreens: Set<CGDirectDisplayID> = []
        session.onFirstFrameCompletion = { [weak self, weak session] screen, succeeded in
            guard let self, let session, self.candidateSession === session else { return }
#if DEBUG
            NSLog("MWX Scene: phase=session-first-frame session=%@ surface=%u gpu=%@",
                session.lifecycleID.uuidString, screen, succeeded ? "completed" : "failed")
#endif
            guard succeeded else {
                self.finishCandidate(.failure(SceneDesktopWallpaperHostLaunchError.firstFrameFailed))
                return
            }
#if DEBUG
            if Self.usesDebugEvidenceWindow,
               ProcessInfo.processInfo.environment["MWX_SCENE_DEBUG_REJECT_CANDIDATE_GENERATION"] == String(self.nextLaunchRequestGeneration) {
                NSLog("MWX DEBUG SCENE: phase=candidate-rejected-after-gpu session=%@", session.lifecycleID.uuidString)
                self.finishCandidate(.failure(SceneDesktopWallpaperHostLaunchError.firstFrameFailed))
                return
            }
#endif
            pendingScreens.remove(screen)
            guard pendingScreens.isEmpty else { return }
            session.onFirstFrameCompletion = nil
            let promote = { [weak self, weak session] in
                guard let self, let session, self.candidateSession === session else { return }
                let previous = self.activeSession
                if self.candidatePreparedHandler != nil {
                    previous?.soundPlaybackRegistry?.setMuted(true)
                    self.unconfirmedPromotion = (firstPresentation.requestID, previous)
                } else {
                    previous?.launchContext?.sceneScriptStorageSession?.retirePersistence()
                    context.sceneScriptStorageSession?.activatePersistence(
                        replacing: previous?.launchContext?.sceneScriptStorageSession)
                }
                self.activeSession = session
                session.promote(firstPresentation: firstPresentation)
                if self.candidatePreparedHandler != nil { previous?.suspendPresentationForHandoff() }
#if DEBUG
                NSLog("MWX Scene: phase=session-activated session=%@ previous=%@ surfaces=%d",
                    session.lifecycleID.uuidString, previous?.lifecycleID.uuidString ?? "none", session.surfaces.count)
#endif
                if self.candidatePreparedHandler == nil, let previous { self.retire(previous) }
                self.finishCandidate(.success(()))
            }
            if let handler = self.candidatePreparedHandler {
                self.candidatePromotion = (firstPresentation.requestID, promote)
                handler(firstPresentation.requestID)
            } else { promote() }
        }
        do {
            try session.activate(context)
        } catch {
            discardCandidate()
            throw error
        }
        pendingScreens = Set(session.surfaces.keys)
        let deadline = DispatchWorkItem { [weak self, weak session] in
            guard let self, let session, self.candidateSession === session else { return }
            self.finishCandidate(.failure(SceneDesktopWallpaperHostLaunchError.firstFrameTimeout))
        }
        candidateDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: deadline)
    }

    private func finishCandidate(_ result: Result<Void, Error>) {
        let completion = candidateCompletion
        candidateCompletion = nil
        if case .success = result {
            candidateDeadline?.cancel()
            candidateDeadline = nil
            candidateSession?.onFirstFrameCompletion = nil
            candidateSession = nil
            reconcileAudioDemand()
        } else {
            discardCandidate()
        }
        completion?(result)
    }

    func discardCandidate() {
        candidatePromotion = nil
        candidateDeadline?.cancel()
        candidateDeadline = nil
        candidateCompletion = nil
        if let session = candidateSession {
            candidateSession = nil
            session.onFirstFrameCompletion = nil
            retire(session)
        }
        reconcileAudioDemand()
    }

    func retire(_ session: SceneDesktopWallpaperSession) {
        let identity = ObjectIdentifier(session)
        retiringSessions[identity] = session
#if DEBUG
        NSLog("MWX Scene: phase=session-retiring session=%@", session.lifecycleID.uuidString)
#endif
        session.stopAndDrainGPU { [weak self] succeeded in
            self?.retiringSessions.removeValue(forKey: identity)
            if let requestID = session.launchRequestID {
                self?.requestResourcesReleasedHandler?(requestID)
            }
            if !succeeded {
#if DEBUG
            NSLog("MWX Scene: retired session GPU drain failed")
#endif
 }
        }
    }

    func commitCandidate(requestID: UUID) {
        guard let promotion = candidatePromotion, promotion.requestID == requestID else { return }
        candidatePromotion = nil
        promotion.promote()
        guard unconfirmedPromotion?.requestID == requestID else { return }
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.presentationDeadline != nil,
                  self.unconfirmedPromotion?.requestID == requestID else { return }
            let recordID = self.activeSession?.activeRecordID
            self.rollbackUnconfirmedPromotion()
            self.publishLaunchState(.init(requestID: requestID, recordID: recordID,
                phase: .failed, message: "Scene 首帧未能显示，已恢复之前的壁纸"))
        }
        presentationDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: deadline)
    }

    /// Physical presentation stops the local watchdog. The parent's finalize
    /// still owns retirement, so a stalled parent cannot cause a false timeout.
    func noteCandidatePresentation(requestID: UUID) {
        guard unconfirmedPromotion?.requestID == requestID else { return }
        presentationDeadline?.cancel()
        presentationDeadline = nil
    }

    func finalizeCandidate(requestID: UUID) {
        guard let promotion = unconfirmedPromotion, promotion.requestID == requestID else { return }
        presentationDeadline?.cancel()
        presentationDeadline = nil
        unconfirmedPromotion = nil
        promotion.previous?.launchContext?.sceneScriptStorageSession?.retirePersistence()
        activeSession?.launchContext?.sceneScriptStorageSession?.activatePersistence(
            replacing: promotion.previous?.launchContext?.sceneScriptStorageSession)
        if let previous = promotion.previous { retire(previous) }
    }

    func retireOutput(requestID: UUID) -> Bool {
        if let previous = unconfirmedPromotion?.previous, previous.launchRequestID == requestID {
            unconfirmedPromotion?.previous = nil
            retire(previous)
        } else if let activeSession, activeSession.launchRequestID == requestID {
            self.activeSession = nil
            retire(activeSession)
        }
        reconcileAudioDemand()
        return activeSession?.launchRequestID != requestID
            && unconfirmedPromotion?.previous?.launchRequestID != requestID
    }

    @discardableResult
    func cancelCandidate(requestID: UUID) -> Bool {
        if unconfirmedPromotion?.requestID == requestID {
            let recordID = activeSession?.activeRecordID
            rollbackUnconfirmedPromotion()
            publishLaunchState(.init(requestID: requestID, recordID: recordID,
                phase: .cancelled, message: "已取消 Scene 壁纸准备"))
        } else if launchState?.requestID == requestID {
            cancelPendingLaunch()
        }
        return activeSession?.launchRequestID != requestID
            && candidateSession?.launchRequestID != requestID
            && candidatePromotion?.requestID != requestID
    }

    func rollbackUnconfirmedPromotion() {
        guard let promotion = unconfirmedPromotion else { return }
        presentationDeadline?.cancel()
        presentationDeadline = nil
        unconfirmedPromotion = nil
        let replacement = activeSession
        replacement?.soundPlaybackRegistry?.setMuted(true)
        activeSession = promotion.previous
        if let previous = promotion.previous {
            // A pause/performance change may have arrived while this session
            // was standby. Restore from the same Host policy before revealing.
            configure(previous)
            previous.promote(firstPresentation: nil)
        }
        replacement?.suspendPresentationForHandoff()
        if let replacement { retire(replacement) }
        reconcileAudioDemand()
    }

    /// A cancelled preparation may still be unwinding on the worker queue.
    /// Release its parent's immutable-version lease only after CPU and GPU use.
    func whenRequestResourcesReleased(requestID: UUID, completion: @escaping @MainActor () -> Void) {
        launchPreparationQueue.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.activeSession?.launchRequestID != requestID,
                      self.candidateSession?.launchRequestID != requestID else { return }
                let sessions = self.retiringSessions.values.filter { $0.launchRequestID == requestID }
                guard !sessions.isEmpty else { completion(); return }
                var remaining = sessions.count
                for session in sessions {
                    session.stopAndDrainGPU { _ in
                        remaining -= 1
                        if remaining == 0 { completion() }
                    }
                }
            }
        }
    }

    func reconcileAudioDemand() {
        let sessions = [activeSession, candidateSession].compactMap { $0 }.filter(\.isOutputActive)
        SceneAudioSpectrumInbox.shared.setDemand(
            sessions.contains { $0.audioDemand.spectrum },
            requiresCurrentProcessAudioCapture: sessions.contains { $0.audioDemand.currentProcess }
        )
    }

    func stopAndDrainGPU(completion: @escaping @MainActor (Bool) -> Void) {
        stop()
        let sessions = Array(retiringSessions.values)
        guard !sessions.isEmpty else { completion(true); return }
        var remaining = sessions.count
        var succeeded = true
        for session in sessions {
            session.stopAndDrainGPU { result in
                succeeded = succeeded && result
                remaining -= 1
                if remaining == 0 { completion(succeeded) }
            }
        }
    }
    /// M3.2：launch 阶段 → M1 计数器 hub 的统一映射（同步/异步两条
    /// launch 路径共用，保证 TTFVF 归因口径一致）。
#if DEBUG
    static func recordLaunchPhase(_ phase: SceneWallpaperLaunchState.Phase) {
        let hubPhase: SceneLaunchPhase?
        switch phase {
        case .accepted: hubPhase = .accepted
        case .preparingModel: hubPhase = .preparingModel
        case .preparingPrograms: hubPhase = .preparingPrograms
        case .preparingResources: hubPhase = .preparingResources
        case .preparingSurfaces: hubPhase = .preparingSurfaces
        case .launched: hubPhase = .launched
        case .cancelled, .failed, .stopped: hubPhase = nil
        }
        guard let hubPhase else { return }
        ScenePerformanceCounterHub.shared.recordLaunchPhase(
            hubPhase,
            uptimeMicros: ScenePerformanceCounterHub.nowUptimeMicros()
        )
    }
#endif
    func publishLaunchState(_ state: SceneWallpaperLaunchState) {
        launchState = state
#if DEBUG
        NSLog(
            "MWX SCENE STARTUP: request=%@ record=%@ phase=%@ message=%@",
            state.requestID.uuidString,
            state.recordID ?? "-",
            state.phase.rawValue,
            state.message
        )
        Self.recordLaunchPhase(state.phase)
        SceneSignpost.emitEvent("launch-state", state.phase.rawValue)
#endif
        NotificationCenter.default.post(
            name: .sceneWallpaperLaunchStateDidChange,
            object: state
        )
    }

}
