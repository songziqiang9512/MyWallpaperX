import simd

nonisolated struct SceneTintExecutionPlan {
    nonisolated struct ConstantBinding: Equatable {
        /// Non-nil for a user-property producer. Timeline producers write the same typed
        /// dynamic target and therefore do not need a property key.
        let propertyKey: String?
        let layerID: Int
        let effectIndex: Int
        let constantName: String

        nonisolated var dynamicTarget: SceneDynamicTarget {
            .effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: 0,
                name: constantName
            )
        }
    }

    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    /// 遮罩语义按指纹分流（stock 与 `g_BlendAlpha` 相乘、directional-v1 覆盖）。
    let shaderProfile: SceneTintShaderProfile
    let blendMode: Int
    let staticOrFallbackColor: SIMD3<Float>
    let staticOrFallbackAlpha: Float
    let colorBinding: ConstantBinding?
    let alphaBinding: ConstantBinding?
    /// 槽位 1（`g_Texture1`）遮罩；nil 表示实例未绑图（`ApplyBlending` 权重只有 alpha）。
    let maskTexturePath: String?

    nonisolated var liveConsumerTargets: Set<SceneDynamicTarget> {
        Set([colorBinding?.dynamicTarget, alphaBinding?.dynamicTarget].compactMap { $0 })
    }

    nonisolated func resolvedColor(in snapshot: SceneDynamicSnapshot) -> SIMD3<Float> {
        guard let target = colorBinding?.dynamicTarget,
              case let .vector3(red, green, blue) = snapshot[target]?.value
        else {
            return staticOrFallbackColor
        }
        guard [red, green, blue].allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else {
            return staticOrFallbackColor
        }
        return SIMD3<Float>(Float(red), Float(green), Float(blue))
    }

    nonisolated func resolvedAlpha(in snapshot: SceneDynamicSnapshot) -> Float {
        guard let binding = alphaBinding,
              case let .scalar(rawValue) = snapshot[binding.dynamicTarget]?.value
        else {
            return staticOrFallbackAlpha
        }
        let value = Float(rawValue)
        guard value.isFinite else { return staticOrFallbackAlpha }
        // Bézier handles may intentionally overshoot an endpoint by a small amount. Timeline
        // values follow shader saturation semantics so a continuous curve cannot turn into a
        // one-frame static fallback. User-property injections retain the strict range check.
        if binding.propertyKey == nil {
            return min(max(value, 0), 1)
        }
        return (0 ... 1).contains(value) ? value : staticOrFallbackAlpha
    }
}
