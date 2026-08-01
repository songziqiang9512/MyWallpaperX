import Foundation

/// Data-only scalar program for the official Blend time-of-day scripting family.
/// It contains no general JavaScript objects, statements, loops, or callbacks.
nonisolated struct SceneTimeOfDayEffectScriptProgram: Equatable, Sendable {
    let bindings: [SceneTimeOfDayEffectScriptBinding]

    nonisolated static let empty = SceneTimeOfDayEffectScriptProgram(bindings: [])
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
