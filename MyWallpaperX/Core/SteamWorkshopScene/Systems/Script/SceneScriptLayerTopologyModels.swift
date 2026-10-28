import Foundation

nonisolated struct SceneScriptLayerTopologySnapshot: Sendable {
    /// Changes only when layer admission, retirement or ordering changes topology.
    /// Authored value publication stays frame-varying and does not invalidate the
    /// renderer's prepared topology projection.
    var particlePlayback: [Int: SceneParticlePlaybackSnapshot] = [:]
    let topologyRevision: UInt64
    let dynamicLayers: [SceneRenderDescriptor.Layer]
    let renderOrderLayerIDs: [Int]
    let destroyedAuthoredLayerIDs: Set<Int>
    let authoredLayerValues: [SceneDynamicTarget: SceneDynamicValue]
}

nonisolated struct SceneScriptPreparedResourceLayerTemplate: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case image, composition }
    let modelPath: String
    let renderSizeWH: [Float]
    var autosize: Bool = false
    var puppetMeshPath: String? = nil
    var kind: Kind = .image
    var imageMaterialRenderState: SceneMaterialRenderState? = nil

    var defaultRenderSizeWH: [Float] { autosize ? renderSizeWH : [1, 1] }
}

nonisolated struct SceneScriptLayerMutationOwnerFailure: Sendable {
    let ownerTarget: SceneDynamicTarget?
    let failure: SceneScriptScalarRuntimeFailure
}

nonisolated struct SceneScriptLayerMutationApplyOutcome: Sendable {
    let committedMutationCount: Int
    let committedDynamicMutationCount: Int
    let failures: [SceneScriptLayerMutationOwnerFailure]
}

/// Opaque, side-effect-free candidate state. Rendering keeps using the snapshot
/// captured before this plan for topology and non-visibility authored setters.
/// Accepted visibility and particle transitions share the current cadence's
/// typed snapshot and simulation; commit retains their values and final intent.
nonisolated struct SceneScriptLayerMutationPlan: Sendable {
    var particlePlayback: [Int: SceneParticlePlaybackSnapshot] = [:]
    var particleTransitions: [SceneParticlePlaybackTransition] = []
    var outcome: SceneScriptLayerMutationApplyOutcome
    let order: [Int]
    let dynamicLayersByID: [Int: SceneRenderDescriptor.Layer]
    let dynamicLayerCreatorTargetsByID: [Int: SceneDynamicTarget]
    let destroyedAuthoredLayerIDs: Set<Int>
    var authoredLayerValues: [SceneDynamicTarget: SceneDynamicValue]
    let authoredDefinitionOrder: [SceneDynamicTarget]
    let authoredDefinitionsByTarget:
        [SceneDynamicTarget: SceneDynamicTargetDefinition]
    let dynamicTopologyChanged: Bool
    var textTemplateIdentitiesByLayerID: [Int: UInt64] = [:]
    var retiredDynamicLayerIDs: Set<Int> = []
    var createdPreparedTextValues: [SceneDynamicTarget: SceneDynamicValue] = [:]

    /// Camera setters join this frame without advancing ordinary layer setters.
    func overlayCameraValues(into values: inout [SceneDynamicTarget: SceneDynamicValue]) {
        for field in SceneDynamicCameraField.staticTransformFields {
            let target = SceneDynamicTarget.camera(field)
            if let value = authoredLayerValues[target] { values[target] = value }
        }
    }
}

nonisolated struct SceneScriptOwnerEffectsAdmission: Sendable {
    let admittedEffects: [SceneScriptOwnerEffects]
    let rejectedOwners: [SceneScriptLayerMutationOwnerFailure]
    let layerPlan: SceneScriptLayerMutationPlan
}

nonisolated struct SceneScriptOwnerEffectsFixedPointAdmission: Sendable {
    let admission: SceneScriptOwnerEffectsAdmission
    let externallyRejectedOwners: Set<SceneDynamicTarget>
}
