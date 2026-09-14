import AppKit
import QuartzCore

extension SceneDesktopWallpaperHost {
    func teardownSurfaces(
        clearContext: Bool,
        reason: SceneGraphExecutionResetReason
    ) {
#if DEBUG
        let shouldLogSurfaceTeardown =
            Self.usesDebugEvidenceWindow && launchContext != nil
        let timerWasActive = frameTimer?.isValid == true
#endif
        if clearContext {
            screenReconciliationWorkItem?.cancel()
            screenReconciliationWorkItem = nil
            screenTopology = []
            removePointerEventMonitors()
        }
        frameTimer?.invalidate()
        frameTimer = nil
        frameDriverDeadline = nil
        for surface in surfaces.values {
            surface.metalView.invalidateResolvedMaterialRuntime(reason: reason)
            surface.metalView.teardownParticlePlayback(reason: reason)
            surface.window.orderOut(nil)
            surface.window.close()
        }
        surfaces.removeAll()
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
            SceneAudioSpectrumInbox.shared.setDemand(false)
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
            launchContext = nil
#if DEBUG
            debugPointerOverride = nil
#endif
        }
    }
}
