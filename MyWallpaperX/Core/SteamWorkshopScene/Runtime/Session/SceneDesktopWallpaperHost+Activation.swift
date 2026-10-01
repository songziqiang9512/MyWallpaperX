import AppKit
import Foundation

extension SceneDesktopWallpaperHost {
    func beginCandidate(
        _ context: SceneDesktopWallpaperLaunchContext,
        firstPresentation: SceneFirstFramePresentationRegistration,
        completion: @escaping (Result<Void, Error>) -> Void
    ) throws {
        let session = SceneDesktopWallpaperSession(textureDecodeCacheBudget: textureDecodeCacheBudget)
        configure(session)
        candidateSession = session
        candidateCompletion = completion
        NSLog("MWX Scene: phase=session-candidate session=%@", session.lifecycleID.uuidString)
        var pendingScreens: Set<CGDirectDisplayID> = []
        session.onFirstFrameCompletion = { [weak self, weak session] screen, succeeded in
            guard let self, let session, self.candidateSession === session else { return }
            NSLog("MWX Scene: phase=session-first-frame session=%@ surface=%u gpu=%@",
                session.lifecycleID.uuidString, screen, succeeded ? "completed" : "failed")
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
            let previous = self.activeSession
            previous?.launchContext?.sceneScriptStorageSession?.retirePersistence()
            context.sceneScriptStorageSession?.activatePersistence(
                replacing: previous?.launchContext?.sceneScriptStorageSession
            )
            self.activeSession = session
            session.promote(firstPresentation: firstPresentation)
            NSLog("MWX Scene: phase=session-activated session=%@ previous=%@ surfaces=%d",
                session.lifecycleID.uuidString, previous?.lifecycleID.uuidString ?? "none", session.surfaces.count)
            if let previous { self.retire(previous) }
            self.finishCandidate(.success(()))
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
        NSLog("MWX Scene: phase=session-retiring session=%@", session.lifecycleID.uuidString)
        session.stopAndDrainGPU { [weak self] succeeded in
            self?.retiringSessions.removeValue(forKey: identity)
            if !succeeded { NSLog("MWX Scene: retired session GPU drain failed") }
        }
    }

    func reconcileAudioDemand() {
        let sessions = [activeSession, candidateSession].compactMap { $0 }
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
}
