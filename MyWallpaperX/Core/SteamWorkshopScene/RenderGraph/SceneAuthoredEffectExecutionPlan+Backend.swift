import Foundation

extension SceneAuthoredEffectExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case localContrast(SceneLocalContrastPlan)
        case opacity(SceneOpacityExecutionPlan)
        case colorGrading(SceneColorGradingExecutionPlan)
        case workshopShiftHue(SceneWorkshopShiftHueExecutionPlan)
        case workshopAudioBars(SceneWorkshopAudioBarsExecutionPlan)
        case workshopGradient(SceneWorkshopGradientExecutionPlan)
        case workshopAudioHueShift(SceneWorkshopAudioHueShiftExecutionPlan)
        case workshopShadow(SceneWorkshopShadowExecutionPlan)
        case spin(SceneSpinExecutionPlan)
        case proceduralNoise(SceneProceduralNoiseExecutionPlan)
        case filmGrain(SceneFilmGrainExecutionPlan)
        case lightShafts(SceneLightShaftsExecutionPlan)
        case shake(SceneShakeExecutionPlan)
        case waterFlow(SceneWaterFlowExecutionPlan)
        case waterWaves(SceneWaterWavesExecutionPlan)
        case waterCaustics(SceneWaterCausticsExecutionPlan)
        case cursorRipple(SceneCursorRippleExecutionPlan)
        case foliageSway(SceneFoliageSwayExecutionPlan)
        case waterRipple(SceneWaterRippleExecutionPlan)
        case depthParallax(SceneDepthParallaxExecutionPlan)
        case xRay(SceneXRayExecutionPlan)
        case clippingMask(SceneClippingMaskExecutionPlan)
        case blend(SceneBlendExecutionPlan)
        case tint(SceneTintExecutionPlan)
        case transform(SceneTransformExecutionPlan)
        case fisheyeZeroDistortion(SceneFisheyeZeroDistortionPlan)
        case pulse(ScenePulseExecutionPlan)
        case godrays(SceneGodraysPlan)
        case shine(SceneShineExecutionPlan)

        var supportsUnifiedPairLeaf: Bool {
            switch self {
            case .workshopShiftHue, .workshopAudioBars, .workshopGradient,
                 .workshopAudioHueShift, .workshopShadow, .spin,
                 .proceduralNoise, .filmGrain, .shake:
                return true
            default:
                return false
            }
        }
    }

    /// A migrated dedicated profile may remain as a bounded fallback, while
    /// yielding product ownership whenever the shared Program path can fully
    /// compile the authored stage.
    nonisolated var yieldsToResolvedMaterialProgram: Bool {
        switch backend {
        case .opacity, .tint:
            return true
        default:
            return false
        }
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

    nonisolated var foliageSway: SceneFoliageSwayExecutionPlan? {
        guard case .foliageSway(let plan) = backend else { return nil }
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

    nonisolated var clippingMask: SceneClippingMaskExecutionPlan? {
        guard case .clippingMask(let plan) = backend else { return nil }
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
        case .foliageSway:
            return true
        case .clippingMask, .opacity:
            return true
        case .fisheyeZeroDistortion:
            return true
        case .workshopAudioBars(let plan):
            guard case .simple = plan.profile else { return false }
            return true
        case .proceduralNoise(let plan):
            return plan.variant == .legacyWorleyColor
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
        if case .preciseGaussian = backend { return !usesLegacyComposeNormalization }
        return false
    }
}
