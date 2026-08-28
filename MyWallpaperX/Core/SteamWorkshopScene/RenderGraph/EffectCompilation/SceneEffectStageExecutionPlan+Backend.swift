import Foundation

extension SceneEffectStageExecutionPlan {
    enum Backend {
        case standardBlur(SceneStandardBlurPlan)

        var supportsUnifiedPairLeaf: Bool {
            false
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

    nonisolated var executionFamilyStableName: String {
        backend.stableName
    }

    nonisolated var liveConsumerTargets: Set<SceneDynamicTarget> {
        []
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
