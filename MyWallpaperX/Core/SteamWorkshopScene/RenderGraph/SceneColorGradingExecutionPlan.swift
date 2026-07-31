import simd

/// Exact fullscreen Color Grading profile for the authored `TOOLS=2` branch.
nonisolated struct SceneColorGradingExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let luminance: Float
    let saturation: Float
    let vibrance: Float
    let opacity: Float
    let channelInfluence: SIMD3<Float>
}
