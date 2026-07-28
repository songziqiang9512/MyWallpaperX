nonisolated struct SceneTransformStaticFallbackDiagnostic: Equatable, Sendable {
    let effectIndex: Int
    let passIndex: Int
    let constantName: String

    nonisolated var reportValue: String {
        "effect=\(effectIndex),pass=\(passIndex),constant=\(constantName),"
            + "reason=unsupported-dynamic-binding-static-fallback"
    }
}

nonisolated struct SceneTransformExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let staticFallbackDiagnostics: [SceneTransformStaticFallbackDiagnostic]
}
