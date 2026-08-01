import Foundation

/// Pure bounded evaluator. Wall time is sampled once by the shared frame clock.
nonisolated enum SceneTimeOfDayEffectScriptRuntime {
    nonisolated static func values(
        program: SceneTimeOfDayEffectScriptProgram,
        wallDate: Date,
        timeZone: TimeZone = .current
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        let daytime = normalizedTimeOfDay(wallDate, timeZone: timeZone)
        return program.bindings.reduce(into: [:]) { values, binding in
            var budget = 256
            guard let value = evaluate(
                binding.expression, timeOfDay: daytime, remainingSteps: &budget
            ), value.isFinite else { return }
            values[binding.definition.target] = .scalar(value)
        }
    }

    private nonisolated static func normalizedTimeOfDay(
        _ date: Date,
        timeZone: TimeZone
    ) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond], from: date
        )
        let seconds = Double(components.hour ?? 0) * 3_600
            + Double(components.minute ?? 0) * 60
            + Double(components.second ?? 0)
            + Double(components.nanosecond ?? 0) / 1_000_000_000
        return min(max(seconds / 86_400, 0), 1)
    }

    private nonisolated static func evaluate(
        _ expression: SceneTimeOfDayEffectScriptExpression,
        timeOfDay: Double,
        remainingSteps: inout Int
    ) -> Double? {
        remainingSteps -= 1
        guard remainingSteps >= 0 else { return nil }
        switch expression {
        case let .number(value): return value
        case .timeOfDay: return timeOfDay
        case let .add(left, right): return binary(left, right, timeOfDay, &remainingSteps, +)
        case let .subtract(left, right):
            return binary(left, right, timeOfDay, &remainingSteps, -)
        case let .multiply(left, right):
            return binary(left, right, timeOfDay, &remainingSteps, *)
        case let .divide(left, right):
            guard let divisor = evaluate(right, timeOfDay: timeOfDay, remainingSteps: &remainingSteps),
                  divisor != 0,
                  let dividend = evaluate(
                      left, timeOfDay: timeOfDay, remainingSteps: &remainingSteps
                  ) else { return nil }
            return dividend / divisor
        case let .negate(value):
            return evaluate(value, timeOfDay: timeOfDay, remainingSteps: &remainingSteps).map(-)
        case let .maximum(left, right):
            return binary(left, right, timeOfDay, &remainingSteps, max)
        case let .smoothStep(minimum, maximum, value):
            guard let lower = evaluate(
                      minimum, timeOfDay: timeOfDay, remainingSteps: &remainingSteps
                  ),
                  let upper = evaluate(
                      maximum, timeOfDay: timeOfDay, remainingSteps: &remainingSteps
                  ),
                  let input = evaluate(
                      value, timeOfDay: timeOfDay, remainingSteps: &remainingSteps
                  ), lower.isFinite, upper.isFinite, input.isFinite, lower != upper else {
                return nil
            }
            let normalized = min(max((input - lower) / (upper - lower), 0), 1)
            return normalized * normalized * (3 - 2 * normalized)
        }
    }

    private nonisolated static func binary(
        _ left: SceneTimeOfDayEffectScriptExpression,
        _ right: SceneTimeOfDayEffectScriptExpression,
        _ timeOfDay: Double,
        _ remainingSteps: inout Int,
        _ operation: (Double, Double) -> Double
    ) -> Double? {
        guard let lhs = evaluate(left, timeOfDay: timeOfDay, remainingSteps: &remainingSteps),
              let rhs = evaluate(right, timeOfDay: timeOfDay, remainingSteps: &remainingSteps) else {
            return nil
        }
        let result = operation(lhs, rhs)
        return result.isFinite ? result : nil
    }
}
