import Foundation

nonisolated struct SceneBlendExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let shaderProfile: SceneBlendShaderProfile
    let blendMode: Int
    let multiply: Float
    let alphaMultiply: Float
    let writesAlpha: Bool
    let dynamicMultiplyBinding: SceneTimeOfDayEffectScriptBinding?
    let assetTexturePath: String
    let userPropertyKey: String?

    nonisolated var executedUserPropertyKeys: Set<String> {
        Set([userPropertyKey].compactMap { $0 })
    }

    nonisolated var liveMultiplyTarget: SceneDynamicTarget? {
        dynamicMultiplyBinding?.definition.target
    }

    nonisolated func resolvedMultiply(in snapshot: SceneDynamicSnapshot) -> Float {
        guard let target = liveMultiplyTarget,
              let resolved = snapshot[target],
              case let .scalar(value) = resolved.value,
              value.isFinite,
              (0...2).contains(value) else {
            return multiply
        }
        return Float(value)
    }
}
