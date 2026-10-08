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
        if clearContext {
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
            SceneSystemMediaProvider.shared.release(lifecycleID)
            if let launchContext {
                teardownSceneScriptOwners(launchContext, reason: reason)
                launchContext.preparedDeviceResources.baseImages
                    .cancelDeferredPreparation()
            }
            if let pending = pendingDeferredLayerVisibilityUpdate {
                logDeferredLayerVisibilityTransition(
                    generation: pending.generation,
                    layerIDs: pending.layerIDs,
                    state: "cancelled:surface-stop"
                )
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
