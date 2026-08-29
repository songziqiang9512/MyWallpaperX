import Foundation

nonisolated struct SceneScriptOwnerLifecycleSnapshot: Equatable, Sendable {
    let destroyCallbackCount: Int
    let activeTimerCount: Int
    let pendingLayerMutationCount: Int
    let activeDynamicLayerCount: Int
    let hasJobResidue: Bool
    let callbackActive: Bool

    var isQuiescent: Bool {
        activeTimerCount == 0 && pendingLayerMutationCount == 0
            && activeDynamicLayerCount == 0 && !hasJobResidue && !callbackActive
    }
}

nonisolated struct SceneScriptOwnerTeardownOutcome: Equatable, Sendable {
    let destroyCallbackInvoked: Bool
    let snapshot: SceneScriptOwnerLifecycleSnapshot
    let failure: SceneScriptScalarRuntimeFailure?
}

nonisolated enum SceneScriptOwnerLifecycleBridge {
    static func teardown(
        owner: OpaquePointer,
        generation: UInt64,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String,
        userPropertiesJSON: String
    ) -> SceneScriptOwnerTeardownOutcome {
        var diagnostic = [CChar](repeating: 0, count: 512)
        var invoked: UInt32 = 0
        var rawFrame = MWXSceneQuickJSFrameInput(
            time_of_day: frame.timeOfDay,
            frame_time: frame.frameTime,
            runtime: frame.runtime
        )
        let raw = scriptPropertiesJSON.withCString { scriptProperties in
            userPropertiesJSON.withCString { userProperties in
                mwx_scene_quickjs_owner_teardown(
                    owner,
                    generation,
                    &rawFrame,
                    scriptProperties,
                    scriptPropertiesJSON.utf8.count,
                    userProperties,
                    userPropertiesJSON.utf8.count,
                    &invoked,
                    &diagnostic,
                    diagnostic.count
                )
            }
        }
        var lifecycle = MWXSceneQuickJSLifecycleSnapshot()
        let snapshotResult = mwx_scene_quickjs_owner_lifecycle_snapshot(
            owner, &lifecycle
        )
        let snapshot = SceneScriptOwnerLifecycleSnapshot(
            destroyCallbackCount: Int(lifecycle.destroy_callback_count),
            activeTimerCount: Int(lifecycle.active_timer_count),
            pendingLayerMutationCount: Int(lifecycle.pending_layer_mutation_count),
            activeDynamicLayerCount: Int(lifecycle.active_dynamic_layer_count),
            hasJobResidue: lifecycle.has_job_residue != 0,
            callbackActive: lifecycle.callback_active != 0
        )
        let failure = raw == MWX_SCENE_QUICKJS_OK
            && snapshotResult == MWX_SCENE_QUICKJS_OK && snapshot.isQuiescent
            ? nil
            : mapFailure(
                raw == MWX_SCENE_QUICKJS_OK
                    ? (snapshotResult == MWX_SCENE_QUICKJS_OK
                        ? MWX_SCENE_QUICKJS_INVALID_ARGUMENT : snapshotResult)
                    : raw,
                diagnostic: String(cString: diagnostic)
            )
        return .init(
            destroyCallbackInvoked: invoked != 0,
            snapshot: snapshot,
            failure: failure
        )
    }

    private static func mapFailure(
        _ raw: MWXSceneQuickJSResult,
        diagnostic: String
    ) -> SceneScriptScalarRuntimeFailure {
        switch raw {
        case MWX_SCENE_QUICKJS_EXCEPTION: .exception(diagnostic)
        case MWX_SCENE_QUICKJS_BUDGET_EXCEEDED: .budgetExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_MEMORY_EXCEEDED: .memoryExceeded(diagnostic)
        case MWX_SCENE_QUICKJS_DISABLED: .disabled(diagnostic)
        case MWX_SCENE_QUICKJS_STALE_OWNER: .staleOwner
        case MWX_SCENE_QUICKJS_MUTATION_OVERFLOW: .mutationOverflow(diagnostic)
        default: .invalidArgument(
            diagnostic.isEmpty ? "SceneScript teardown did not quiesce" : diagnostic
        )
        }
    }
}
