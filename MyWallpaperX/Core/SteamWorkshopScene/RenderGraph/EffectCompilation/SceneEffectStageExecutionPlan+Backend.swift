import Foundation

extension SceneEffectStageExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case localContrast(SceneLocalContrastPlan)
        case opacity(SceneOpacityExecutionPlan)
        case colorGrading(SceneColorGradingExecutionPlan)
        case workshopShiftHue(SceneWorkshopShiftHueExecutionPlan)
        case workshopAudioBars(SceneWorkshopAudioBarsExecutionPlan)
        case workshopGradient(SceneWorkshopGradientExecutionPlan)
        case workshopShadow(SceneWorkshopShadowExecutionPlan)
        case proceduralNoise(SceneProceduralNoiseExecutionPlan)
        case filmGrain(SceneFilmGrainExecutionPlan)
        case lightShafts(SceneLightShaftsExecutionPlan)
        case shake(SceneShakeExecutionPlan)
        case waterFlow(SceneWaterFlowExecutionPlan)
        case waterWaves(SceneWaterWavesExecutionPlan)
        case waterCaustics(SceneWaterCausticsExecutionPlan)
        case cursorRipple(SceneCursorRippleExecutionPlan)
        case waterRipple(SceneWaterRippleExecutionPlan)
        case depthParallax(SceneDepthParallaxExecutionPlan)
        case xRay(SceneXRayExecutionPlan)
        case blend(SceneBlendExecutionPlan)
        case tint(SceneTintExecutionPlan)
        case transform(SceneTransformExecutionPlan)
        case fisheyeZeroDistortion(SceneFisheyeZeroDistortionPlan)
        case pulse(ScenePulseExecutionPlan)
        case godrays(SceneGodraysPlan)
        case shine(SceneShineExecutionPlan)

        var supportsUnifiedPairLeaf: Bool {
            switch self {
            case .opacity, .colorGrading,
                 .workshopShiftHue, .workshopAudioBars, .workshopGradient,
                 .workshopShadow, .filmGrain, .shake, .waterFlow,
                 .waterWaves, .waterCaustics, .waterRipple,
                 .depthParallax, .xRay, .blend, .tint, .transform,
                 .fisheyeZeroDistortion, .pulse:
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
                && !supportsUnifiedFullFrameComposeStage
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

    nonisolated var supportsUnifiedFullFrameComposeStage: Bool {
        guard case .preciseGaussian = backend,
              logicalRenderTargetCount == 0,
              renderGraph.renderTargets.isEmpty,
              renderGraph.effects.count == 1,
              let effect = renderGraph.effects.first else { return false }
        let materialNodes = renderGraph.nodes.filter { $0.kind == .material }
        return materialNodes.count == 2
            && renderGraph.nodes.count == 2
            && SceneEffectStageExecutionPlanner.preciseBlurTopology(
                horizontalNode: materialNodes[0],
                verticalNode: materialNodes[1],
                effect: effect,
                commandNodeCount: 0
            ) == .fullFrameCompose
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

    nonisolated var opacity: SceneOpacityExecutionPlan? {
        guard case .opacity(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var colorGrading: SceneColorGradingExecutionPlan? {
        guard case .colorGrading(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var workshopShiftHue: SceneWorkshopShiftHueExecutionPlan? {
        guard case .workshopShiftHue(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var workshopAudioBars: SceneWorkshopAudioBarsExecutionPlan? {
        guard case .workshopAudioBars(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var workshopGradient: SceneWorkshopGradientExecutionPlan? {
        guard case .workshopGradient(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var workshopShadow: SceneWorkshopShadowExecutionPlan? {
        guard case .workshopShadow(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var proceduralNoise: SceneProceduralNoiseExecutionPlan? {
        guard case .proceduralNoise(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var filmGrain: SceneFilmGrainExecutionPlan? {
        guard case .filmGrain(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var lightShafts: SceneLightShaftsExecutionPlan? {
        guard case .lightShafts(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var shake: SceneShakeExecutionPlan? {
        guard case .shake(let plan) = backend else { return nil }
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

    nonisolated var waterRipple: SceneWaterRippleExecutionPlan? {
        guard case .waterRipple(let plan) = backend else { return nil }
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

    nonisolated var tint: SceneTintExecutionPlan? {
        guard case .tint(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var transform: SceneTransformExecutionPlan? {
        guard case .transform(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var fisheyeZeroDistortion: SceneFisheyeZeroDistortionPlan? {
        guard case .fisheyeZeroDistortion(let plan) = backend else { return nil }
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
        if let target = opacity?.liveAlphaTarget { targets.insert(target) }
        if let target = blend?.liveMultiplyTarget { targets.insert(target) }
        if let xRay { targets.formUnion(xRay.liveConsumerTargets) }
        if let tint { targets.formUnion(tint.liveConsumerTargets) }
        if let pulse { targets.formUnion(pulse.liveConsumerTargets) }
        if let workshopAudioBars {
            targets.formUnion(workshopAudioBars.liveConsumerTargets)
        }
        return targets
    }

    nonisolated var supportsUtilityCapture: Bool {
        switch backend {
        case .colorGrading:
            return true
        case .standardBlur:
            return true
        case .opacity:
            return true
        case .fisheyeZeroDistortion:
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

    func opacityAlpha(in snapshot: SceneDynamicSnapshot) -> Float? {
        opacity?.resolvedAlpha(in: snapshot)
    }

    var requiresExactInputExtent: Bool {
        if case .preciseGaussian = backend {
            return !supportsUnifiedFullFrameComposeStage
        }
        return false
    }
}
