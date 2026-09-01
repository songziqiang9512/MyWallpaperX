import Foundation

nonisolated struct SceneScriptVectorFrameResult: Equatable, Sendable {
    let values: [SceneDynamicTarget: SceneDynamicValue]
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let videoCommands: [SceneScriptVideoCommand]
    let videoCommandTargets: Set<SceneDynamicTarget>
    let ownerEffects: [SceneScriptOwnerEffects]

    init(
        values: [SceneDynamicTarget: SceneDynamicValue],
        failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure],
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation],
        animationMutations: [SceneTimelinePlaybackMutation],
        layerMutations: [SceneScriptLayerMutation],
        videoCommands: [SceneScriptVideoCommand],
        videoCommandTargets: Set<SceneDynamicTarget>,
        ownerEffects: [SceneScriptOwnerEffects] = []
    ) {
        self.values = values
        self.failures = failures
        self.materialFunctionMutations = materialFunctionMutations
        self.animationMutations = animationMutations
        self.layerMutations = layerMutations
        self.videoCommands = videoCommands
        self.videoCommandTargets = videoCommandTargets
        self.ownerEffects = ownerEffects
    }
}

nonisolated struct SceneScriptVectorBinding: @unchecked Sendable {
    let authoredOrdinal: Int
    let definition: SceneDynamicTargetDefinition
    let properties: [String: SceneScriptPropertyInput]
    let livePropertyInputTargets: Set<SceneDynamicTarget>
    let hasCurrentAnimation: Bool
    let handlesMediaThumbnail: Bool
    let handlesMediaPlayback: Bool
    let handlesMediaProperties: Bool
    let handlesMediaTimeline: Bool
    let dynamicImageReferences: [SceneScriptDynamicImageReference]
    let owner: SceneScriptVectorOwner
}

nonisolated struct SceneScriptCursorOwnerRegistration: @unchecked Sendable {
    let layerID: Int
    let authoredOrder: Int
    let owner: SceneScriptVectorOwner
}
