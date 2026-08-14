import Foundation

/// Advances every admitted binding once per host frame. The authored script uses
/// a fixed WEMath.mix factor, so frame time is intentionally not an input.
nonisolated struct SceneLaunchOriginTransitionRuntime {
    private let program: SceneLaunchOriginTransitionProgram
    private var states: [SceneDynamicTarget: SIMD3<Double>]

    nonisolated init(program: SceneLaunchOriginTransitionProgram) {
        self.program = program
        states = Dictionary(uniqueKeysWithValues: program.bindings.map {
            ($0.definition.target, $0.plan.authoredOrigin)
        })
    }

    /// Live properties are resolved on every frame. A bad value freezes the
    /// complete cohort; no surface can observe a partially advanced group.
    nonisolated mutating func values(
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        var claimedTargets: Set<SceneDynamicTarget> = []
        for cohort in program.cohorts {
            guard cohort.bindings.allSatisfy({ binding in
                effectivePropertyValues.keys.contains(binding.plan.triggerPropertyKey)
            }) else { continue }
            claimedTargets.formUnion(cohort.bindings.map(\.definition.target))
            guard let next = nextStates(
                for: cohort,
                effectivePropertyValues: effectivePropertyValues
            ) else { continue }
            for (target, value) in next { states[target] = value }
        }
        return currentValues(for: claimedTargets)
    }

    private func nextStates(
        for cohort: SceneLaunchOriginTransitionCohort,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> [SceneDynamicTarget: SIMD3<Double>]? {
        var result: [SceneDynamicTarget: SIMD3<Double>] = [:]
        for binding in cohort.bindings {
            let target = binding.definition.target
            guard let current = states[target],
                  let speed = resolve(
                      binding.plan.speed,
                      effectivePropertyValues: effectivePropertyValues
                  ),
                  binding.plan.speedDivisor.isFinite,
                  binding.plan.speedDivisor > 0 else { return nil }
            let factor = speed / binding.plan.speedDivisor
            guard factor.isFinite, (0...1).contains(factor),
                  let destination = destination(
                      binding.plan,
                      effectivePropertyValues: effectivePropertyValues
                  ) else { return nil }
            let value = current + (destination - current) * factor
            guard finite(value) else { return nil }
            result[target] = value
        }
        return result.count == cohort.bindings.count ? result : nil
    }

    private func destination(
        _ plan: SceneLaunchOriginTransitionPlan,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> SIMD3<Double>? {
        switch plan.initialFalseTarget {
        case let .base(offset):
            guard let base = resolve(
                plan.base,
                effectivePropertyValues: effectivePropertyValues
            ) else { return nil }
            let result = base + offset
            return finite(result) ? result : nil
        case .endpoint:
            return resolve(
                plan.endpoint,
                effectivePropertyValues: effectivePropertyValues
            )
        }
    }

    private func resolve(
        _ input: SceneLaunchOriginTransitionVectorInput,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> SIMD3<Double>? {
        guard let x = resolve(input.x, effectivePropertyValues: effectivePropertyValues),
              let y = resolve(input.y, effectivePropertyValues: effectivePropertyValues),
              let z = resolve(input.z, effectivePropertyValues: effectivePropertyValues) else {
            return nil
        }
        let result = SIMD3(x, y, z)
        return finite(result) ? result : nil
    }

    private func resolve(
        _ input: SceneLaunchOriginTransitionScalarInput,
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

    private func currentValues(
        for claimedTargets: Set<SceneDynamicTarget>
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        program.bindings.reduce(into: [:]) { result, binding in
            let target = binding.definition.target
            guard claimedTargets.contains(target),
                  let value = states[target], finite(value) else { return }
            result[target] = .vector3(value.x, value.y, value.z)
        }
    }

    private func finite(_ value: SIMD3<Double>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
