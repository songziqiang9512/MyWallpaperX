import Foundation

nonisolated struct SceneScriptOwnerLifecycleSnapshot: Equatable, Sendable {
    let teardownStarted: Bool
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
    let destroyCallbackThrew: Bool
    let snapshot: SceneScriptOwnerLifecycleSnapshot
    let failure: SceneScriptScalarRuntimeFailure?
}

/// Scalar and String Programs share the same value-owner storage and cleanup
/// contract; retirement runs once through this existing lifecycle boundary.
nonisolated protocol SceneScriptValueOwnerProgramRetirement: AnyObject {
    var bindings: [SceneScriptValueOwner] { get }
    var propertyInputsByTarget: [SceneDynamicTarget: [String: SceneScriptPropertyInput]] { get }
    var disabledTargets: Set<SceneDynamicTarget> { get set }
    var retiredTargets: Set<SceneDynamicTarget> { get set }
}

extension SceneScriptValueOwnerProgramRetirement {
    /// Called after the topology commit and every peer journal is finalized.
    func retire(
        layerIDs: Set<Int>, frame: SceneScriptFrameInput,
        effectivePropertyValues: [String: SceneUserPropertyValue] = [:],
        userPropertiesJSON: String
    ) -> [SceneScriptOwnerTeardownOutcome] {
        SceneScriptOwnerLifecycleBridge.retire(
            owners: bindings, layerIDs: layerIDs, frame: frame,
            propertiesByTarget: propertyInputsByTarget,
            effectivePropertyValues: effectivePropertyValues,
            userPropertiesJSON: userPropertiesJSON,
            disabledTargets: &disabledTargets, retiredTargets: &retiredTargets
        )
    }
}

nonisolated enum SceneScriptOwnerLifecycleBridge {
    /// A permanent topology commit retires each target without changing the
    /// Program binding indexes retained by pending frame snapshots.
    static func retire(
        owners: [SceneScriptValueOwner], layerIDs: Set<Int>,
        frame: SceneScriptFrameInput,
        propertiesByTarget: [SceneDynamicTarget: [String: SceneScriptPropertyInput]],
        effectivePropertyValues: [String: SceneUserPropertyValue],
        userPropertiesJSON: String,
        disabledTargets: inout Set<SceneDynamicTarget>,
        retiredTargets: inout Set<SceneDynamicTarget>
    ) -> [SceneScriptOwnerTeardownOutcome] {
        owners.compactMap { owner in
            guard layerIDs.contains(owner.layerID), !retiredTargets.contains(owner.target) else { return nil }
            disabledTargets.insert(owner.target)
            let properties = propertiesByTarget[owner.target] ?? [:]
            let outcome = owner.teardown(
                frame: frame,
                scriptPropertiesJSON: SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                    properties, effectiveValues: effectivePropertyValues
                ) ?? SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                    properties, effectiveValues: [:]
                ) ?? "{}",
                userPropertiesJSON: userPropertiesJSON
            )
            if outcome.snapshot.isQuiescent { retiredTargets.insert(owner.target) }
            return outcome
        }
    }

    static func teardown(
        owner: OpaquePointer,
        generation: UInt64,
        frame: SceneScriptFrameInput,
        scriptPropertiesJSON: String,
        userPropertiesJSON: String
    ) -> SceneScriptOwnerTeardownOutcome {
        var diagnostic = [CChar](repeating: 0, count: 512)
        var invoked: UInt32 = 0
        var threw: UInt32 = 0
        var rawFrame = frame.quickJSValue
        let raw = scriptPropertiesJSON.withCString { scriptProperties in
            userPropertiesJSON.withCString { userProperties in
                mwx_scene_quickjs_owner_teardown_with_provenance(
                    owner,
                    generation,
                    &rawFrame,
                    scriptProperties,
                    scriptPropertiesJSON.utf8.count,
                    userProperties,
                    userPropertiesJSON.utf8.count,
                    &invoked,
                    &threw,
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
            teardownStarted: lifecycle.teardown_started != 0,
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
            destroyCallbackThrew: threw != 0,
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
