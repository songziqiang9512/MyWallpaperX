import AppKit
import QuartzCore

/// A frame may execute VM callbacks before every surface has admitted its
/// command buffer. Keep the callback watermarks and live-property edge state
/// provisional until the host barrier succeeds.
struct SceneScriptProgramFrameStates {
    let scalar: SceneScriptProgramFrameState
    let string: SceneScriptProgramFrameState
    let vector: SceneScriptProgramFrameState
}

extension SceneDesktopWallpaperHost {
    func sceneScriptProgramFrameState(
        _ context: SceneDesktopWallpaperLaunchContext
    ) -> SceneScriptProgramFrameStates {
        .init(
            scalar: context.sceneScriptScalarProgram.frameStateSnapshot(),
            string: context.sceneScriptStringProgram.frameStateSnapshot(),
            vector: context.propertyVectorScriptProgram.frameStateSnapshot()
        )
    }

    func restoreSceneScriptProgramFrameState(
        _ context: SceneDesktopWallpaperLaunchContext,
        _ state: SceneScriptProgramFrameStates
    ) {
        context.sceneScriptScalarProgram.restoreFrameState(state.scalar)
        context.sceneScriptStringProgram.restoreFrameState(state.string)
        context.propertyVectorScriptProgram.restoreFrameState(state.vector)
    }

    func finalizeSceneScriptLayerMutations(
        _ context: SceneDesktopWallpaperLaunchContext,
        committing: Bool,
        rejectedOwnerTargets: Set<SceneDynamicTarget> = []
    ) {
        context.sceneScriptScalarProgram.finalizeLayerMutations(
            committing: committing,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        context.sceneScriptStringProgram.finalizeLayerMutations(
            committing: committing,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        context.sceneScriptCursorProgram.finalizeLayerMutations(
            committing: committing,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        context.propertyVectorScriptProgram.finalizeLayerMutations(
            committing: committing,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
    }

    func discardSceneScriptLayerMutations(
        _ context: SceneDesktopWallpaperLaunchContext
    ) {
        finalizeSceneScriptLayerMutations(context, committing: false)
    }

    func commitSceneScriptLayerMutations(
        _ context: SceneDesktopWallpaperLaunchContext,
        rejectedOwnerTargets: Set<SceneDynamicTarget>
    ) {
        finalizeSceneScriptLayerMutations(
            context, committing: true,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
    }

    func commitSceneScriptLayerPlan(
        _ context: SceneDesktopWallpaperLaunchContext,
        plan: SceneScriptLayerMutationPlan,
        rejectedOwnerTargets: Set<SceneDynamicTarget>
    ) {
        context.sceneScriptDynamicLayerRuntime.commit(plan)
        commitSceneScriptLayerMutations(
            context, rejectedOwnerTargets: rejectedOwnerTargets
        )
    }

    func commitSubmittedSceneFrame(
        _ context: SceneDesktopWallpaperLaunchContext,
        pendingSurfaceEvaluations:
            [(Surface, SceneSurfaceEvaluationTransaction.PendingEvaluation)],
        pendingSharedLayerAlpha: SceneSharedLayerAlphaRuntime.PendingValues,
        animationMutations: [SceneTimelinePlaybackMutation],
        videoCommands: [SceneScriptVideoCommand],
        timing: SceneFrameTiming,
        layerPlan: SceneScriptLayerMutationPlan,
        rejectedOwnerTargets: Set<SceneDynamicTarget>
    ) {
        pendingSurfaceEvaluations.forEach {
            $0.0.evaluationTransaction.commit($0.1)
        }
        sharedLayerAlphaRuntime.commitValues(pendingSharedLayerAlpha)
        if !animationMutations.isEmpty,
           case .success = context.timelinePlaybackRuntime.apply(
               animationMutations, sceneTime: timing.sceneTime
           ) {
            NSLog(
                "MWX SceneScript VM: animationCommands=%d callback=committed nextFrame=true route=generic-only",
                animationMutations.count
            )
        }
        if !videoCommands.isEmpty,
           case .success? = videoTextureSourceRegistry?.apply(
               videoCommands, timing: timing
           ) {
            NSLog(
                "MWX SceneScript VM: videoCommands=%d callback=committed frame=%llu route=generic-only",
                videoCommands.count,
                timing.frameIndex
            )
        }
        commitSceneScriptLayerPlan(
            context, plan: layerPlan,
            rejectedOwnerTargets: rejectedOwnerTargets
        )
        context.sceneScriptStorageSession?.commitFrameTransaction()
    }

    func teardownSceneScriptOwners(
        _ context: SceneDesktopWallpaperLaunchContext,
        reason: SceneGraphExecutionResetReason
    ) {
        // Stop/switch is a scene-wide barrier.  Release every owner journal
        // before destroy callbacks so dynamic topology removal cannot be
        // blocked by a provisional owner from the last frame.
        discardSceneScriptLayerMutations(context)
        context.sceneScriptStorageSession?.discardFrameTransaction()
        let hostTime = CACurrentMediaTime()
#if DEBUG
        let wallDate = Self.debugWallDateOverride ?? Date()
#else
        let wallDate = Date()
#endif
        let frame = SceneScriptFrameInput(timing: .init(
            frameIndex: 0,
            hostTime: hostTime,
            sceneTime: sceneClock.currentSceneTime(hostTime: hostTime),
            rawFrameTime: 0,
            simulationFrameTime: 0,
            droppedFrameTime: 0,
            wallDate: wallDate
        ))
        let userPropertiesJSON = context.propertyVectorScriptProgram
            .userPropertiesJSON(
                effectiveValues: context.liveState.effectiveValues,
                revision: context.liveState.revision
            )
        let outcomes = context.sceneScriptScalarProgram.teardown(
            frame: frame,
            effectivePropertyValues: context.liveState.effectiveValues,
            userPropertiesJSON: userPropertiesJSON
        ) + context.sceneScriptStringProgram.teardown(
            frame: frame,
            effectivePropertyValues: context.liveState.effectiveValues,
            userPropertiesJSON: userPropertiesJSON
        ) + context.sceneScriptCursorProgram.teardown(
            frame: frame,
            userPropertiesJSON: userPropertiesJSON
        ) + context.propertyVectorScriptProgram.teardown(
            frame: frame,
            effectivePropertyValues: context.liveState.effectiveValues,
            userPropertiesJSON: userPropertiesJSON
        )
        let destroyCallbacks = outcomes.filter(\.destroyCallbackInvoked).count
        let quiescent = outcomes.filter(\.snapshot.isQuiescent).count
        let failures = outcomes.compactMap(\.failure)
        NSLog(
            "MWX SceneScript VM: lifecycle=teardown reason=%@ owners=%d destroyCallbacks=%d quiescent=%d failures=%d timers=%d jobs=%d mutations=%d dynamicLayers=%d route=generic-only",
            String(describing: reason), outcomes.count, destroyCallbacks,
            quiescent, failures.count,
            outcomes.reduce(0) { $0 + $1.snapshot.activeTimerCount },
            outcomes.filter(\.snapshot.hasJobResidue).count,
            outcomes.reduce(0) { $0 + $1.snapshot.pendingLayerMutationCount },
            outcomes.reduce(0) { $0 + $1.snapshot.activeDynamicLayerCount }
        )
    }
}
