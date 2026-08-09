nonisolated struct SceneWorkshopAudioBarsExecutionPlan {
    nonisolated enum Profile {
        case enhancedSegmented(shape: Int)
    }

    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let profile: Profile

    nonisolated init(
        layerID: Int,
        effectKey: SceneAuthoredEffectRenderPlan.EffectKey,
        renderGraph: SceneAuthoredEffectRenderPlan,
        shape: Int
    ) {
        self.layerID = layerID
        self.effectKey = effectKey
        self.renderGraph = renderGraph
        profile = .enhancedSegmented(shape: shape)
    }

    nonisolated var shape: Int {
        switch profile {
        case .enhancedSegmented(let shape): shape
        }
    }

    nonisolated var liveConsumerTargets: Set<SceneDynamicTarget> {
        []
    }
}
