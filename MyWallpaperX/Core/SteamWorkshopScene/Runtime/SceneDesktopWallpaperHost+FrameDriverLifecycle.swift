import AppKit
import QuartzCore

extension SceneDesktopWallpaperHost {
    func teardownSceneScriptOwners(
        _ context: SceneDesktopWallpaperLaunchContext,
        reason: SceneGraphExecutionResetReason
    ) {
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
            .userPropertiesJSON(effectiveValues: context.liveState.effectiveValues)
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
