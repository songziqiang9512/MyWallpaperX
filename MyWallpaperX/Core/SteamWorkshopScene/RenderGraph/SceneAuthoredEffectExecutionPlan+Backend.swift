import Foundation

extension SceneAuthoredEffectExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case localContrast(SceneLocalContrastPlan)
        case opacity(SceneOpacityExecutionPlan)
        case workshopShadow(SceneWorkshopShadowExecutionPlan)
        case shake(SceneShakeExecutionPlan)
        case waterFlow(SceneWaterFlowExecutionPlan)
        case waterWaves(SceneWaterWavesExecutionPlan)
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

    nonisolated var workshopShadow: SceneWorkshopShadowExecutionPlan? {
        guard case .workshopShadow(let plan) = backend else { return nil }
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

    nonisolated var liveConsumerTarget: SceneDynamicTarget? {
        localContrast?.liveStrengthTarget ?? opacity?.liveAlphaTarget
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
