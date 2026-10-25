import AppKit
import QuartzCore

extension SceneDesktopWallpaperSession {
    func teardownSurfaces(
        clearContext: Bool,
        reason: SceneGraphExecutionResetReason
    ) {
#if DEBUG
        let shouldLogSurfaceTeardown =
            SceneDesktopWallpaperHost.usesDebugEvidenceWindow && launchContext != nil
        let timerWasActive = frameTimer?.isValid == true
#endif
        initialPresentationCohort.reset()
        userShortcutInput.revoke()
        if clearContext {
            releaseUserShortcutScopes()
            initialUserVideoPreparation?.cancel()
            initialUserVideoPreparation = nil
            cancelPendingUserTextureUpdates()
            screenReconciliationWorkItem?.cancel()
            screenReconciliationWorkItem = nil
            screenTopology = []
            rebuiltTopology = []
            removePointerEventMonitors()
        }
        frameTimer?.invalidate()
        frameTimer = nil
        frameDriverDeadline = nil
        pausedFrameRetryDeadline = nil
        for surface in surfaces.values {
            surface.metalView.dynamicTextTextures?.close()
            surface.metalView.invalidateResolvedMaterialRuntime(reason: reason)
            surface.metalView.teardownParticlePlayback(reason: reason)
            surface.window.orderOut(nil)
            surface.window.close()
            if !drainStarted { retireSurface(surface) }
        }
        surfaces.removeAll()
        // A display ID can be reused by a new view. Cancel input tied to the
        // removed surfaces even when the Scene VM survives reconstruction.
        launchContext?.sceneScriptCursorProgram.restoreEdgeState(.empty)
#if DEBUG
        debugSurfaceReferenceFrames.removeAll(keepingCapacity: false)
        if shouldLogSurfaceTeardown {
            NSLog(
                "MWX DEBUG SCENE: phase=surface-teardown clearContext=%@ timer=%@ surfaces=%d",
                clearContext ? "true" : "false",
                timerWasActive ? "active" : "inactive",
                surfaces.count
            )
        }
#endif
        if clearContext {
            SceneSystemMediaDemandRegistry.shared.release(lifecycleID)
            if let launchContext {
                teardownSceneScriptOwners(launchContext, reason: reason)
                // stop() can clear this context before a later request drain.
                // Keep its shared worker on the Session's existing release fence.
                let retirementDrain = retiringSurfaceDrain
                retirementDrain.enter()
                launchContext.preparedDeviceResources.baseImages
                    .cancelAndDrainDeferredPreparation { retirementDrain.leave() }
            }
            if let pending = pendingDeferredLayerVisibilityUpdate {
#if DEBUG
                logDeferredLayerVisibilityTransition(
                    generation: pending.generation,
                    layerIDs: pending.layerIDs,
                    state: "cancelled:surface-stop"
                )
#endif
            }
            pendingDeferredLayerVisibilityUpdate = nil
            audioDemand = (false, false)
            onAudioDemandChanged?()
            sharedLayerAlphaRuntime = .init(program: .empty)
#if DEBUG
            debugDropDynamicValuesFrameIndex = nil
            debugDidDropDynamicValues = false
            debugDidLogDynamicValuesRecovery = false
#endif
            videoTextureSourceRegistry?.stop()
            videoTextureSourceRegistry = nil
            soundPlaybackRegistry?.stop()
            soundPlaybackRegistry = nil
            firstFramePresentationRegistration = nil
            userPropertyTextureLoad = .empty
            launchContext = nil
#if DEBUG
            debugPointerOverride = nil
#endif
        }
    }
}
