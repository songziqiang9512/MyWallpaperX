import Foundation

extension SceneEffectStageExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case xRay(SceneXRayExecutionPlan)
        case blend(SceneBlendExecutionPlan)
        case transform(SceneTransformExecutionPlan)
        case pulse(ScenePulseExecutionPlan)

        var supportsUnifiedPairLeaf: Bool {
            switch self {
            case .xRay, .blend, .transform, .pulse:
                return true
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
        default:
            return false
        }
    }

    var gaussianBlur: SceneGaussianBlurPlan? {
        guard case .preciseGaussian(let plan) = backend else { return nil }
        return plan
    }

    nonisolated var standardBlur: SceneStandardBlurPlan? {
        guard case .standardBlur(let plan) = backend else { return nil }
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

    nonisolated var executionFamilyStableName: String {
        backend.stableName
    }

    nonisolated var liveConsumerTargets: Set<SceneDynamicTarget> {
        var targets = Set<SceneDynamicTarget>()
        if let target = blend?.liveMultiplyTarget { targets.insert(target) }
        if let xRay { targets.formUnion(xRay.liveConsumerTargets) }
        if let pulse { targets.formUnion(pulse.liveConsumerTargets) }
        return targets
    }

    nonisolated var supportsUtilityCapture: Bool {
        switch backend {
        case .standardBlur:
            return true
        default:
            return false
        }
    }

    var requiresExactInputExtent: Bool {
        if case .preciseGaussian = backend {
            return true
        }
        return false
    }
}
