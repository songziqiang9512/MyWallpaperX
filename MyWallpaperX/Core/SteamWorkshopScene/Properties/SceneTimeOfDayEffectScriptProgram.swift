import Foundation

/// Data-only scalar program for the official Blend time-of-day scripting family.
/// It contains no general JavaScript objects, statements, loops, or callbacks.
nonisolated struct SceneTimeOfDayEffectScriptProgram: Equatable, Sendable {
    let bindings: [SceneTimeOfDayEffectScriptBinding]

    nonisolated static let empty = SceneTimeOfDayEffectScriptProgram(bindings: [])

    /// Consumer ownership is resolved after MaterialProgram admission. A
    /// source candidate that never becomes a consumer must not reserve its
    /// target or conflict with another live producer.
    nonisolated static func validatedConsumers(
        candidates: [SceneTimeOfDayEffectScriptBinding],
        consumerTargets: Set<SceneDynamicTarget>,
        conflictingTargets: Set<SceneDynamicTarget>
    ) -> Self? {
        let bindings = candidates.filter {
            consumerTargets.contains($0.definition.target)
        }
        let targets = bindings.map(\.definition.target)
        guard Set(targets).count == targets.count,
              Set(targets).isDisjoint(with: conflictingTargets) else {
            return nil
        }
        return .init(bindings: bindings.sorted { lhs, rhs in
            guard case let .effectConstant(
                lhsLayer, lhsEffect, lhsPass, lhsName
            ) = lhs.definition.target,
                case let .effectConstant(
                    rhsLayer, rhsEffect, rhsPass, rhsName
                ) = rhs.definition.target else { return false }
            if lhsLayer != rhsLayer { return lhsLayer < rhsLayer }
            if lhsEffect != rhsEffect { return lhsEffect < rhsEffect }
            if lhsPass != rhsPass { return lhsPass < rhsPass }
            return lhsName < rhsName
        })
    }
}

nonisolated struct SceneTimeOfDayEffectScriptBinding: Equatable, Sendable {
    let definition: SceneDynamicTargetDefinition
    let expression: SceneTimeOfDayEffectScriptExpression
}

indirect nonisolated enum SceneTimeOfDayEffectScriptExpression: Equatable, Sendable {
    case number(Double)
    case timeOfDay
    case add(Self, Self)
    case subtract(Self, Self)
    case multiply(Self, Self)
    case divide(Self, Self)
    case negate(Self)
    case smoothStep(Self, Self, Self)
    case maximum(Self, Self)
}
