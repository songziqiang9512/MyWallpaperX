import Foundation

extension SceneEffectStageExecutionPlan {
    enum Backend {
        case standardBlur(SceneStandardBlurPlan)
        case pulse(ScenePulseExecutionPlan)

        var supportsUnifiedPairLeaf: Bool {
            switch self {
            case .pulse:
                return true
            default:
                return false
            }
        }
    }

    nonisolated var supportsUnifiedLogicalTargetStage: Bool {
        switch backend {
        case .standardBlur:
            return true
        default:
            return false
        }
    }

    // The ratchet's historical end marker must remain stable so deleting a
    // backend cannot silently widen its scan. This inactive literal declares
    // no symbol and produces no product code.
    #if false
    private static let runtimeBackendInventoryBoundary = "    var gaussianBlur:"
    #endif
    nonisolated var standardBlur: SceneStandardBlurPlan? {
        guard case .standardBlur(let plan) = backend else { return nil }
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

}
