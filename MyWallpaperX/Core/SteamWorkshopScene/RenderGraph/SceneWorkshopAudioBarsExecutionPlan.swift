nonisolated struct SceneWorkshopAudioBarsExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    /// Exact authored `SHAPE`: 4 = inner circle, 5 = outer circle.
    let shape: Int
}
