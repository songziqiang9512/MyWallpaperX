import Foundation

extension SceneEffectStageExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case localContrast(SceneLocalContrastPlan)
        case colorGrading(SceneColorGradingExecutionPlan)
        case proceduralNoise(SceneProceduralNoiseExecutionPlan)
        case waterFlow(SceneWaterFlowExecutionPlan)
        case waterWaves(SceneWaterWavesExecutionPlan)
        case waterCaustics(SceneWaterCausticsExecutionPlan)
        case cursorRipple(SceneCursorRippleExecutionPlan)
        case depthParallax(SceneDepthParallaxExecutionPlan)
        case xRay(SceneXRayExecutionPlan)
        case blend(SceneBlendExecutionPlan)
        case transform(SceneTransformExecutionPlan)
        case pulse(ScenePulseExecutionPlan)
        case godrays(SceneGodraysPlan)
        case shine(SceneShineExecutionPlan)

        var supportsUnifiedPairLeaf: Bool {
            switch self {
            case .colorGrading,
                 .waterFlow,
                 .waterWaves, .waterCaustics,
                 .depthParallax, .xRay, .blend, .transform, .pulse:
                return true
            case .proceduralNoise(let plan):
                return plan.variant == .worleyColorV1
                    && plan.dependencyProviderLayerID != nil
                    && plan.dependencySlotIndex == 3
            default:
                return false
            }
        }
    }

    nonisolated var supportsUnifiedLogicalTargetStage: Bool {
        switch backend {
        case .preciseGaussian:
            return logicalRenderTargetCount > 0
        case .standardBlur:
            return true
        case .localContrast:
            return true
        case .godrays(let plan):
            return (plan.direction == nil && !plan.usesDirectionalGaussianKernel)
                || (plan.direction?.isFinite == true && plan.usesDirectionalGaussianKernel)
        case .shine:
            return true
        default:
            return false
        }
    }

    /// A dedicated authored stage whose typed planner is the sole authority
    /// allowed to opt a non-unique framebuffer into persistent history.  Keep
    /// this separate from ordinary logical-target stages so generic graphs can
    /// never acquire history merely by resembling the topology.
    nonisolated var supportsUnifiedHistoryTargetStage: Bool {
        guard case let .cursorRipple(plan) = backend,
              logicalRenderTargetCount == 2,
              renderGraph.nodes.count == 3,
              renderGraph.renderTargets.count == 2,
              renderGraph.renderTargets.allSatisfy({ !$0.declaredUnique }) else {
            return false
        }
        return plan.layerID == layerID
            && plan.effectKey == renderGraph.effects.first?.key
            && plan.renderGraph.layerID == renderGraph.layerID
            && plan.renderGraph.finalOutput == renderGraph.finalOutput
            && plan.renderGraph.nodes.map(\.nodeIndex)
                == renderGraph.nodes.map(\.nodeIndex)
            && plan.renderGraph.renderTargets.map(\.texture)
                == renderGraph.renderTargets.map(\.texture)
    }

    var gaussianBlur: SceneGaussianBlurPlan? {
        guard case .preciseGaussian(let plan) = backend else { return nil }
        return plan
    }

    var standardBlur: SceneStandardBlurPlan? {
        guard case .standardBlur(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var localContrast: SceneLocalContrastPlan? {
        guard case .localContrast(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var colorGrading: SceneColorGradingExecutionPlan? {
        guard case .colorGrading(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var proceduralNoise: SceneProceduralNoiseExecutionPlan? {
        guard case .proceduralNoise(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var waterFlow: SceneWaterFlowExecutionPlan? {
        guard case .waterFlow(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var waterWaves: SceneWaterWavesExecutionPlan? {
        guard case .waterWaves(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var waterCaustics: SceneWaterCausticsExecutionPlan? {
        guard case .waterCaustics(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var cursorRipple: SceneCursorRippleExecutionPlan? {
        guard case .cursorRipple(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var depthParallax: SceneDepthParallaxExecutionPlan? {
        guard case .depthParallax(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var xRay: SceneXRayExecutionPlan? {
        guard case .xRay(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var blend: SceneBlendExecutionPlan? {
        guard case .blend(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var transform: SceneTransformExecutionPlan? {
        guard case .transform(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var pulse: ScenePulseExecutionPlan? {
        guard case .pulse(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var godrays: SceneGodraysPlan? {
        guard case .godrays(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var shine: SceneShineExecutionPlan? {
        guard case .shine(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var executionFamilyStableName: String {
        backend.stableName
    }

    nonisolated var liveConsumerTargets: Set<SceneDynamicTarget> {
        var targets = Set<SceneDynamicTarget>()
        if let target = localContrast?.liveStrengthTarget { targets.insert(target) }
        if let target = blend?.liveMultiplyTarget { targets.insert(target) }
        if let xRay { targets.formUnion(xRay.liveConsumerTargets) }
        if let pulse { targets.formUnion(pulse.liveConsumerTargets) }
        return targets
    }

    nonisolated var supportsUtilityCapture: Bool {
        switch backend {
        case .colorGrading:
            return true
        case .standardBlur:
            return true
        case .proceduralNoise(let plan):
            return plan.variant == .worleyColorV1
                && plan.dependencyProviderLayerID != nil
                && plan.dependencySlotIndex == 3
        default:
            return false
        }
    }

    func localContrastStrength(in snapshot: SceneDynamicSnapshot) -> Float? {
        localContrast?.resolvedStrength(in: snapshot)
    }

    var requiresExactInputExtent: Bool {
        if case .preciseGaussian = backend {
            return true
        }
        return false
    }
}
