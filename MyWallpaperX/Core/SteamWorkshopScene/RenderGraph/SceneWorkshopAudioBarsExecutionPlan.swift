import simd

nonisolated struct SceneWorkshopAudioBarsExecutionPlan {
    nonisolated struct ConstantBinding: Equatable, Sendable {
        let propertyKey: String
        let layerID: Int
        let effectIndex: Int
        let passIndex: Int
        let constantName: String

        nonisolated var dynamicTarget: SceneDynamicTarget {
            .effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: constantName
            )
        }
    }

    nonisolated struct SimpleParameters: Equatable, Sendable {
        enum Profile: Equatable, Sendable {
            case bottomReplace32ClipLow
            case bottomReplace64ClipHigh

            nonisolated var resolution: Int {
                switch self {
                case .bottomReplace32ClipLow: 32
                case .bottomReplace64ClipHigh: 64
                }
            }

            nonisolated var clipsLow: Bool {
                self == .bottomReplace32ClipLow
            }

            nonisolated var clipsHigh: Bool {
                self == .bottomReplace64ClipHigh
            }
        }

        let profile: Profile
        let barCount: Int
        let staticOrFallbackColor: SIMD3<Float>
        let colorBinding: ConstantBinding?
        let barSpacing: Float
        let lowerBound: Float
        let upperBound: Float
        let opacity: Float

        nonisolated var liveConsumerTargets: Set<SceneDynamicTarget> {
            Set([colorBinding?.dynamicTarget].compactMap { $0 })
        }

        nonisolated func resolvedColor(in snapshot: SceneDynamicSnapshot) -> SIMD3<Float> {
            guard let target = colorBinding?.dynamicTarget,
                  case let .vector3(red, green, blue) = snapshot[target]?.value,
                  [red, green, blue].allSatisfy({
                      $0.isFinite && (0 ... 1).contains($0)
                  }) else {
                return staticOrFallbackColor
            }
            return SIMD3(Float(red), Float(green), Float(blue))
        }
    }

    nonisolated enum Profile {
        case enhancedSegmented(shape: Int)
        case simple(SimpleParameters)
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

    nonisolated init(
        layerID: Int,
        effectKey: SceneAuthoredEffectRenderPlan.EffectKey,
        renderGraph: SceneAuthoredEffectRenderPlan,
        simpleParameters: SimpleParameters
    ) {
        self.layerID = layerID
        self.effectKey = effectKey
        self.renderGraph = renderGraph
        profile = .simple(simpleParameters)
    }

    nonisolated var shape: Int {
        switch profile {
        case .enhancedSegmented(let shape): shape
        case .simple: 0
        }
    }

    nonisolated var liveConsumerTargets: Set<SceneDynamicTarget> {
        guard case .simple(let parameters) = profile else { return [] }
        return parameters.liveConsumerTargets
    }

    nonisolated func resolvedSimpleParameters(
        in snapshot: SceneDynamicSnapshot
    ) -> (parameters: SimpleParameters, color: SIMD3<Float>)? {
        guard case .simple(let parameters) = profile else { return nil }
        return (parameters, parameters.resolvedColor(in: snapshot))
    }
}
