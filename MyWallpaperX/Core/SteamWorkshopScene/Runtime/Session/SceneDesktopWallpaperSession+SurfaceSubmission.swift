import AppKit
import QuartzCore

// Session owns submission transactions and its startup-only surface cohort.
extension SceneDesktopWallpaperSession {
    func renderSurfaces() -> SceneFrameDriverAttempt {
        let attempt = awaitsInitialPresentation ? initialPresentationCohort.beginAttempt(
            members: Set(surfaces.keys) == preparedSurfaceIDs
                ? surfaces.mapValues { ObjectIdentifier($0) } : [:]
        ) : nil
        var qualifiedSubmitted: [UInt32: ObjectIdentifier] = [:]
#if DEBUG
        var pendingVideoLayerIDs: Set<Int> = []
#endif
        var frameOutcomes: [SceneMetalRenderer.FrameOutcome] = []
        frameOutcomes.reserveCapacity(surfaces.count)
        for (displayID, surface) in surfaces {
            if sceneClock.isPaused && surface.didSubmitSimulationFrame && !awaitsInitialPresentation { continue }
#if DEBUG
            let mainFrameStart = ProcessInfo.processInfo.systemUptime
#endif
            let frameOutcome = surface.metalView.renderFrame(
                collectsInitialVideoReadiness: awaitsInitialPresentation,
                performanceTelemetry: SceneDesktopWallpaperHost.usesDebugEvidenceWindow
                    ? SceneFramePerformanceTelemetry.debugEvidence : nil
            )
            if case let .prepared(candidate) = frameOutcome {
#if DEBUG
                if let readiness = candidate.initialVideoPresentation {
                    pendingVideoLayerIDs.formUnion(readiness.pendingLayerIDs)
                }
#endif
                observeSurfaceCompletion(candidate, surface: surface, displayID: displayID, attempt: attempt)
            }
            frameOutcomes.append(frameOutcome)
#if DEBUG
            if case let .prepared(candidate) = frameOutcome {
                candidate.observeGPUStageSurface(frameIndex: surface.metalView.simulationFrameIndex, surfaceID: displayID)
            }
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
               surface.metalView.simulationFrameIndex <= 2,
               case let .prepared(candidate) = frameOutcome {
                candidate.observeCompletion(frameIndex: surface.metalView.simulationFrameIndex, surfaceID: displayID)
            }
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
               debugRejectPreparedFrameOnce == surface.metalView.simulationFrameIndex,
               frameOutcomes.count == surfaces.count {
                debugRejectPreparedFrameOnce = nil
                if case let .prepared(candidate) = frameOutcome { candidate.cancel() }
                frameOutcomes[frameOutcomes.count - 1] = .dropped(
                    reasonCode: "debug-evidence-prepared-surface-rejected"
                )
                NSLog("MWX DEBUG SCENE: phase=surface-submission state=rejected frame=%llu surface=%u totalSurfaces=%d", surface.metalView.simulationFrameIndex, displayID, surfaces.count)
            }
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                SceneFramePerformanceTelemetry.debugEvidence.recordMainFrame(
                    duration: ProcessInfo.processInfo.systemUptime - mainFrameStart
                )
            }
#endif
            let outcomeIndex = frameOutcomes.count - 1
            let submitted = SceneMetalRenderer.submitPreparedFrame(frameOutcomes[outcomeIndex])
            frameOutcomes[outcomeIndex] = submitted
            if submitted.isSubmitted {
                if case let .prepared(candidate) = frameOutcome,
                   candidate.initialVideoPresentation?.isComplete == true {
                    qualifiedSubmitted[displayID] = ObjectIdentifier(surface)
                }
                surface.didSubmitSimulationFrame = true
                surface.metalView.commitPreparedMaterialAssetFrame()
                surface.metalView.commitPreparedFrameTexturePublication()
                surface.metalView.commitPreparedMediaThumbnailUpdate()
                surface.metalView.commitPreparedDynamicTextUpdate()
            } else {
                if frameOutcome.isPrepared { surface.pendingPausedFrame = nil }
                surface.metalView.discardPreparedMaterialAssetFrame()
                surface.metalView.discardPreparedFrameTexturePublication()
                surface.metalView.discardPreparedMediaThumbnailUpdate()
                surface.metalView.discardPreparedDynamicTextUpdate()
            }
        }
        // The shared provider version is resolved once. A failed surface may
        // not roll back a source already referenced by another submitted GPU.
        if frameOutcomes.contains(where: \.isSubmitted) {
            videoTextureSourceRegistry?.commitPreparedFrame()
        } else {
            videoTextureSourceRegistry?.discardPreparedFrame()
        }
        if let attempt {
            initialPresentationCohort.finishAttempt(token: attempt, qualifiedSubmitted: qualifiedSubmitted)
#if DEBUG
            if SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                NSLog("MWX DEBUG SCENE: phase=initial-video-presentation attempt=%llu frame=%llu surfaces=%d qualified=%d held=%@ pending=%@",
                    attempt.rawValue, surfaces.values.first?.metalView.simulationFrameIndex ?? 0,
                    surfaces.count, qualifiedSubmitted.count, initialPresentationCohort.isHeld ? "true" : "false",
                    pendingVideoLayerIDs.sorted().prefix(8).map(String.init).joined(separator: ","))
            }
#endif
            deliverInitialPresentationCohort(initialPresentationCohort.takeCompletedCohort())
        }
        if sceneClock.isPaused && !surfaces.values.allSatisfy(\.didSubmitSimulationFrame) {
            return frameOutcomes.contains(where: \.isDeferred) ? .busy : .dropped
        }
        return frameOutcomes.contains(where: \.isSubmitted) ? .rendered : .dropped
    }
    var awaitsInitialPresentation: Bool { !isVisible && onFirstFrameCompletion != nil }

    private func observeSurfaceCompletion(
        _ candidate: SceneMetalRenderer.PreparedFrame,
        surface: Surface, displayID: CGDirectDisplayID,
        attempt: SceneInitialPresentationCohort.AttemptToken?
    ) {
        guard awaitsInitialPresentation || sceneClock.isPaused else { return }
        if sceneClock.isPaused { surface.pendingPausedFrame = candidate }
        candidate.whenCompleted { [weak self, weak surface, weak candidate] succeeded in
            DispatchQueue.main.async {
                guard let self, let surface, self.surfaces[displayID] === surface else { return }
                if self.awaitsInitialPresentation {
                    if !succeeded {
                        // A live candidate's old/pending attempt may still fail.
                        // Success tokens must never suppress that GPU failure.
                        self.onFirstFrameCompletion?(displayID, false)
                    } else if let attempt {
                        self.deliverInitialPresentationCohort(self.initialPresentationCohort.complete(
                            token: attempt, surface: displayID, identity: ObjectIdentifier(surface)
                        ))
                    }
                }
                guard self.surfaces[displayID] === surface,
                      let candidate, surface.pendingPausedFrame === candidate else { return }
                surface.pendingPausedFrame = nil
                guard self.sceneClock.isPaused, !succeeded else { return }
                surface.didSubmitSimulationFrame = false
                self.scheduleFrameDriver(after: .dropped, scheduledDeadline: CACurrentMediaTime())
            }
        }
    }

    private func deliverInitialPresentationCohort(_ screens: [CGDirectDisplayID]?) {
        guard let screens else { return }
        for screen in screens {
            guard awaitsInitialPresentation, initialPresentationCohort.isHeld else { return }
            onFirstFrameCompletion?(screen, true)
        }
    }
}
