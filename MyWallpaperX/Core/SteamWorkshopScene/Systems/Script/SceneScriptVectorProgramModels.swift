import Foundation

nonisolated struct SceneScriptVectorFrameResult: Equatable, Sendable {
    let values: [SceneDynamicTarget: SceneDynamicValue]
    let timelineInputTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let puppetBoneMutations: [SceneScriptPuppetBoneMutation]
    let puppetAnimationCommands: [ScenePuppetAnimationCommand]
    let mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand]
    let videoCommandTargets: Set<SceneDynamicTarget>
    let ownerEffects: [SceneScriptOwnerEffects]

    init(
        values: [SceneDynamicTarget: SceneDynamicValue],
        failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure],
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation],
        animationMutations: [SceneTimelinePlaybackMutation],
        layerMutations: [SceneScriptLayerMutation],
        mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand],
        videoCommandTargets: Set<SceneDynamicTarget>,
        ownerEffects: [SceneScriptOwnerEffects] = [],
        puppetBoneMutations: [SceneScriptPuppetBoneMutation] = [],
        puppetAnimationCommands: [ScenePuppetAnimationCommand] = [],
        timelineInputTargets: Set<SceneDynamicTarget> = []
    ) {
        self.values = values
        self.timelineInputTargets = timelineInputTargets
        self.failures = failures
        self.materialFunctionMutations = materialFunctionMutations
        self.animationMutations = animationMutations
        self.layerMutations = layerMutations
        self.puppetBoneMutations = puppetBoneMutations
        self.puppetAnimationCommands = puppetAnimationCommands
        self.mediaPlaybackCommands = mediaPlaybackCommands
        self.videoCommandTargets = videoCommandTargets
        self.ownerEffects = ownerEffects
    }

    func valuesForAdmission(
        timelineValues: [SceneDynamicTarget: SceneDynamicValue],
        excluding rejected: Set<SceneDynamicTarget>
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        var admitted = values.filter { !rejected.contains($0.key) }
        for target in timelineInputTargets where admitted[target] != nil {
            guard let value = timelineValues[target] else { continue }
            admitted[target] = value
        }
        return admitted
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
    let requiresStatefulOwner: Bool
    let evaluatesAfterSharedProviders: Bool
    let owner: SceneScriptValueOwner
}

nonisolated struct SceneScriptCursorOwnerRegistration: @unchecked Sendable {
    let layerID: Int
    let authoredOrdinal: Int
    let target: SceneDynamicTarget
    let seedValue: SceneDynamicValue
    let owner: SceneScriptValueOwner
    let scriptProperties: [String: SceneScriptPropertyInput]
}
