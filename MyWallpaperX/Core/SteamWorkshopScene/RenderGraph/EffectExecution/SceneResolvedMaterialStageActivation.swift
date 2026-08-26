import Foundation

/// Frame-local activation for one already-admitted authored effect stage.
/// It consumes the shared dynamic snapshot and pointer provider; it does not
/// own graph topology, property state, or a second render route.
nonisolated struct SceneResolvedMaterialStageActivationPolicy:
    Equatable, Sendable
{
    enum Decision: Equatable, Sendable {
        case active
        case inactive(reasonCode: String)
        case rejected(reasonCode: String)
    }

    struct ScalarMinimum: Equatable, Sendable {
        let target: SceneDynamicTarget?
        let authoredFallback: Double
        let authoredRange: ClosedRange<Double>?
        let minimum: Double
    }

    let effectVisibilityTarget: SceneDynamicTarget?
    let requiresPointerPositionProvider: Bool
    let scalarMinimum: ScalarMinimum?

    var liveConsumerTargets: Set<SceneDynamicTarget> {
        effectVisibilityTarget.map { [$0] } ?? []
    }

    func evaluate(
        dynamicValues: SceneDynamicSnapshot,
        pointerIsInside: Bool
    ) -> Decision {
        if let target = effectVisibilityTarget,
           let resolved = dynamicValues[target] {
            guard case let .bool(visible) = resolved.value else {
                return .rejected(
                    reasonCode: "effect-activation-visibility-type-invalid"
                )
            }
            guard visible else {
                return .inactive(
                    reasonCode: "effect-activation-visibility-disabled"
                )
            }
        }
        guard !requiresPointerPositionProvider || pointerIsInside else {
            return .inactive(
                reasonCode: "effect-activation-pointer-provider-unavailable"
            )
        }
        if let condition = scalarMinimum {
            let value: Double
            if let target = condition.target,
               let resolved = dynamicValues[target] {
                guard case let .scalar(current) = resolved.value,
                      current.isFinite else {
                    return .rejected(
                        reasonCode: "effect-activation-scalar-type-invalid"
                    )
                }
                if let range = condition.authoredRange,
                   !range.contains(current) {
                    guard resolved.source == .userProperty,
                          case let .scalar(authored)? =
                            dynamicValues.authoredValue(for: target),
                          authored.isFinite,
                          range.contains(authored) else {
                        return .rejected(
                            reasonCode: "effect-activation-scalar-range-invalid"
                        )
                    }
                    value = authored
                } else {
                    value = current
                }
            } else {
                value = condition.authoredFallback
            }
            guard value >= condition.minimum else {
                return .inactive(
                    reasonCode: "effect-activation-scalar-below-minimum"
                )
            }
        }
        return .active
    }
}
