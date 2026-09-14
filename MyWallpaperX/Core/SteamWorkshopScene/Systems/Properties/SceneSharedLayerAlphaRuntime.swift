import Foundation

/// Scene-lifetime shared state and alpha counters. One candidate is prepared
/// per host frame before the surface loop so every surface observes the same
/// values; the host commits it only after the shared submission barrier.
nonisolated struct SceneSharedLayerAlphaRuntime {
    /// A frame-local value candidate. Preparing a candidate never advances
    /// the scene-lifetime state; the host publishes it only after the shared
    /// surface submission barrier accepts the frame.
    nonisolated struct PendingValues: Sendable {
        let values: [SceneDynamicTarget: SceneDynamicValue]
        fileprivate let states: [SceneDynamicTarget: Double]
    }

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
        let pending = prepareValues(
            effectivePropertyValues: effectivePropertyValues,
            frameTime: frameTime
        )
        commitValues(pending)
        return pending.values
    }

    /// Advances a copy of the shared-alpha state for the current frame.
    /// Callers must explicitly commit the returned candidate after the frame
    /// has been accepted by the common compositor path.
    nonisolated func prepareValues(
        effectivePropertyValues: [String: SceneUserPropertyValue],
        frameTime: TimeInterval
    ) -> PendingValues {
        var candidate = self
        let values = candidate.advanceValues(
            effectivePropertyValues: effectivePropertyValues,
            frameTime: frameTime
        )
        return PendingValues(values: values, states: candidate.states)
    }

    /// Publishes one previously prepared candidate. The candidate is a value
    /// copy, so discarding it leaves the prior frame's state untouched.
    nonisolated mutating func commitValues(_ pending: PendingValues) {
        states = pending.states
    }

    private nonisolated mutating func advanceValues(
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
