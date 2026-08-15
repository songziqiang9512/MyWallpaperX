import Foundation

/// Scene-lifetime shared state and alpha counters. It advances once per host
/// frame before the surface loop so every surface observes the same generation.
nonisolated struct SceneSharedLayerAlphaRuntime {
    private let program: SceneSharedLayerAlphaProgram
    private var flags: [String: Bool]
    private var states: [SceneDynamicTarget: Double]

    nonisolated init(program: SceneSharedLayerAlphaProgram) {
        self.program = program
        flags = program.initialFlags
        states = Dictionary(uniqueKeysWithValues: program.bindings.compactMap {
            guard case let .scalar(value) = $0.definition.authoredValue else {
                return nil
            }
            return ($0.definition.target, value)
        })
    }

    nonisolated mutating func values(
        effectivePropertyValues: [String: SceneUserPropertyValue],
        frameTime: TimeInterval
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        guard frameTime.isFinite, frameTime >= 0 else { return currentValues() }
        for binding in program.bindings {
            let target = binding.definition.target
            let plan = binding.plan
            guard let current = states[target], current.isFinite,
                  let flag = flags[plan.sharedFlag],
                  let upper = resolve(
                      plan.upperBound,
                      effectivePropertyValues: effectivePropertyValues
                  ), upper > plan.lowerBound else { continue }
            let active = flag == plan.activeFlagValue
            let delta = (active ? plan.riseRate : plan.fallRate) * frameTime
            guard delta.isFinite else { continue }
            let candidate = active ? current + delta : current - delta
            guard candidate.isFinite else { continue }
            states[target] = active
                ? min(candidate, upper)
                : max(candidate, plan.lowerBound)
        }
        return currentValues()
    }

    private func resolve(
        _ input: SceneSharedLayerAlphaScalarInput,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> Double? {
        let value: Double
        if let key = input.userPropertyKey,
           let live = effectivePropertyValues[key] {
            guard case let .number(number) = live else { return nil }
            value = number
        } else {
            value = input.fallback
        }
        return value.isFinite ? value : nil
    }

    private func currentValues() -> [SceneDynamicTarget: SceneDynamicValue] {
        program.bindings.reduce(into: [:]) { result, binding in
            guard let value = states[binding.definition.target], value.isFinite else {
                return
            }
            result[binding.definition.target] = .scalar(value)
        }
    }
}
