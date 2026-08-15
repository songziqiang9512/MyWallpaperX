import Foundation

/// Surface-local event state followed by the authored fixed-factor WEMath.mix
/// update. A malformed live value freezes its complete flag cohort.
nonisolated struct SceneHoverOriginTransitionRuntime {
    private let program: SceneHoverOriginTransitionProgram
    private var states: [SceneDynamicTarget: SIMD3<Double>]

    nonisolated init(program: SceneHoverOriginTransitionProgram) {
        self.program = program
        states = Dictionary(uniqueKeysWithValues: program.bindings.map {
            ($0.definition.target, $0.plan.authoredOrigin)
        })
    }

    nonisolated mutating func values(
        hoveredOwnerLayerIDs: Set<Int>,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        var claimedTargets: Set<SceneDynamicTarget> = []
        for cohort in program.cohorts {
            guard cohort.bindings.allSatisfy({
                effectivePropertyValues.keys.contains($0.plan.triggerPropertyKey)
            }) else { continue }
            claimedTargets.formUnion(cohort.bindings.map(\.definition.target))
            guard let next = nextStates(
                for: cohort,
                active: hoveredOwnerLayerIDs.contains(cohort.ownerLayerID),
                effectivePropertyValues: effectivePropertyValues
            ) else { continue }
            states.merge(next) { _, new in new }
        }
        return currentValues(for: claimedTargets)
    }

    private func nextStates(
        for cohort: SceneHoverOriginTransitionCohort,
        active: Bool,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> [SceneDynamicTarget: SIMD3<Double>]? {
        var result: [SceneDynamicTarget: SIMD3<Double>] = [:]
        for binding in cohort.bindings {
            let target = binding.definition.target
            let plan = binding.plan
            guard let current = states[target],
                  let speed = resolve(
                      plan.speed, effectivePropertyValues: effectivePropertyValues
                  ), plan.speedDivisor.isFinite, plan.speedDivisor > 0 else {
                return nil
            }
            let factor = speed / plan.speedDivisor
            guard factor.isFinite, (0...1).contains(factor),
                  let destination = destination(
                      plan, active: active,
                      effectivePropertyValues: effectivePropertyValues
                  ) else { return nil }
            let value = current + (destination - current) * factor
            guard finite(value) else { return nil }
            result[target] = value
        }
        return result.count == cohort.bindings.count ? result : nil
    }

    private func destination(
        _ plan: SceneHoverOriginTransitionPlan,
        active: Bool,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> SIMD3<Double>? {
        let useEndpoint = active ? !plan.falseUsesEndpoint : plan.falseUsesEndpoint
        if useEndpoint {
            return resolve(
                plan.endpoint, effectivePropertyValues: effectivePropertyValues
            )
        }
        guard let base = resolve(
            plan.base, effectivePropertyValues: effectivePropertyValues
        ) else { return nil }
        let value = base + plan.baseOffset
        return finite(value) ? value : nil
    }

    private func resolve(
        _ input: SceneLaunchOriginTransitionVectorInput,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> SIMD3<Double>? {
        guard let x = resolve(input.x, effectivePropertyValues: effectivePropertyValues),
              let y = resolve(input.y, effectivePropertyValues: effectivePropertyValues),
              let z = resolve(input.z, effectivePropertyValues: effectivePropertyValues)
        else { return nil }
        let value = SIMD3(x, y, z)
        return finite(value) ? value : nil
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
            guard claimedTargets.contains(binding.definition.target),
                  let value = states[binding.definition.target], finite(value) else {
                return
            }
            result[binding.definition.target] = .vector3(value.x, value.y, value.z)
        }
    }

    private func finite(_ value: SIMD3<Double>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
