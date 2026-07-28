import Foundation

extension SceneAuthoredEffectExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case localContrast(SceneLocalContrastPlan)
        case opacity(SceneOpacityExecutionPlan)
        case colorKey(SceneColorKeyExecutionPlan)
        case workshopShiftHue(SceneWorkshopShiftHueExecutionPlan)
        case workshopAudioBars(SceneWorkshopAudioBarsExecutionPlan)
        case workshopGradient(SceneWorkshopGradientExecutionPlan)
        case workshopAudioHueShift(SceneWorkshopAudioHueShiftExecutionPlan)
        case workshopShadow(SceneWorkshopShadowExecutionPlan)
        case spin(SceneSpinExecutionPlan)
        case proceduralNoise(SceneProceduralNoiseExecutionPlan)
        case filmGrain(SceneFilmGrainExecutionPlan)
        case shake(SceneShakeExecutionPlan)
        case waterFlow(SceneWaterFlowExecutionPlan)
        case waterWaves(SceneWaterWavesExecutionPlan)
        case foliageSway(SceneFoliageSwayExecutionPlan)
        case waterRipple(SceneWaterRippleExecutionPlan)
        case xRay(SceneXRayExecutionPlan)
        case blend(SceneBlendExecutionPlan)
        case tint(SceneTintExecutionPlan)
        case transform(SceneTransformExecutionPlan)
        case pulse(ScenePulseExecutionPlan)
        case godrays(SceneGodraysPlan)
        case authoredShader(SceneAuthoredShaderExecutionPlan)
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

    nonisolated var colorKey: SceneColorKeyExecutionPlan? {
        guard case .colorKey(let plan) = backend else { return nil }
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

    nonisolated var workshopAudioHueShift: SceneWorkshopAudioHueShiftExecutionPlan? {
        guard case .workshopAudioHueShift(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var workshopShadow: SceneWorkshopShadowExecutionPlan? {
        guard case .workshopShadow(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var spin: SceneSpinExecutionPlan? {
        guard case .spin(let plan) = backend else { return nil }
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

    nonisolated var foliageSway: SceneFoliageSwayExecutionPlan? {
        guard case .foliageSway(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var waterRipple: SceneWaterRippleExecutionPlan? {
        guard case .waterRipple(let plan) = backend else { return nil }
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

    nonisolated var pulse: ScenePulseExecutionPlan? {
        guard case .pulse(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var godrays: SceneGodraysPlan? {
        guard case .godrays(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var authoredShader: SceneAuthoredShaderExecutionPlan? {
        guard case .authoredShader(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var liveConsumerTargets: Set<SceneDynamicTarget> {
        var targets = Set<SceneDynamicTarget>()
        if let target = localContrast?.liveStrengthTarget { targets.insert(target) }
        if let target = opacity?.liveAlphaTarget { targets.insert(target) }
        if let xRay { targets.formUnion(xRay.liveConsumerTargets) }
        if let tint { targets.formUnion(tint.liveConsumerTargets) }
        if let pulse { targets.formUnion(pulse.liveConsumerTargets) }
        if let workshopAudioBars {
            targets.formUnion(workshopAudioBars.liveConsumerTargets)
        }
        return targets
    }

    nonisolated var supportsUtilityCapture: Bool {
        guard case .workshopAudioBars(let plan) = backend,
              case .simple = plan.profile else {
            return false
        }
        return true
    }

    func localContrastStrength(in snapshot: SceneDynamicSnapshot) -> Float? {
        localContrast?.resolvedStrength(in: snapshot)
    }

    func opacityAlpha(in snapshot: SceneDynamicSnapshot) -> Float? {
        opacity?.resolvedAlpha(in: snapshot)
    }

    var requiresExactInputExtent: Bool {
        if case .preciseGaussian = backend { return !usesLegacyComposeNormalization }
        return false
    }
}
