import Metal

extension SceneMetalRenderer {
    /// The only frame result that the host scheduler may use to advance a
    /// frame plan. A drawable may be acquired and CPU/GPU work may be prepared
    /// without producing a presented frame, so `submitted` is kept distinct
    /// from deferred and rejected work.
    enum FrameOutcome: Equatable {
        case submitted
        case deferred(reasonCode: String)
        case dropped(reasonCode: String)

        var isSubmitted: Bool {
            if case .submitted = self { return true }
            return false
        }

        var reasonCode: String? {
            switch self {
            case .submitted:
                return nil
            case let .deferred(reasonCode), let .dropped(reasonCode):
                return reasonCode
            }
        }

        var isDeferred: Bool {
            if case .deferred = self { return true }
            return false
        }
    }

    enum ResolvedMaterialFrameAdmission {
        case ready(plans: [Int: SceneResolvedMaterialFrameTargetPlan])
        case deferred(reasonCode: String)
        case rejected(reasonCode: String)
    }
}
