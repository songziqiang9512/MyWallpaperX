import Foundation

/// Advances every admitted binding once per host frame. The authored script uses
/// a fixed WEMath.mix factor, so frame time is intentionally not an input.
nonisolated struct SceneLaunchOriginTransitionRuntime {
    private let program: SceneLaunchOriginTransitionProgram
    private var states: [SceneDynamicTarget: SIMD3<Double>]
    private var flagStates: [String: Bool]
    private var previousPrimaryButtonIsDown = false

    nonisolated init(program: SceneLaunchOriginTransitionProgram) {
        self.program = program
        states = Dictionary(uniqueKeysWithValues: program.bindings.map {
            ($0.definition.target, $0.plan.authoredOrigin)
        })
        flagStates = Dictionary(uniqueKeysWithValues: program.cohorts.map {
            ($0.sharedFlag, false)
        })
    }

    /// Returns the current surface-local state without consuming a pointer
    /// edge or advancing authored fixed-factor mixes. This is used for the
    /// hit-test snapshot that precedes the same frame's cursorClick dispatch.
    nonisolated func currentValues(
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        program.cohorts.reduce(into: [:]) { result, cohort in
            guard cohortCanRun(
                cohort,
                effectivePropertyValues: effectivePropertyValues
            ) else { return }
            appendCurrentValues(for: cohort, to: &result)
        }
    }

    /// Live properties are resolved on every frame. A bad value freezes the
    /// complete cohort; no surface can observe a partially advanced group.
    nonisolated mutating func values(
        clickedOwnerLayerIDs: Set<Int> = [],
        primaryButtonIsDown: Bool = false,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        let clickEdge = primaryButtonIsDown && !previousPrimaryButtonIsDown
        previousPrimaryButtonIsDown = primaryButtonIsDown
        var result: [SceneDynamicTarget: SceneDynamicValue] = [:]
        for cohort in program.cohorts {
            guard cohortCanRun(
                cohort,
                effectivePropertyValues: effectivePropertyValues
            ) else { continue }
            if clickEdge,
               let masterLayerID = masterLayerID(cohort),
               clickedOwnerLayerIDs.contains(masterLayerID) {
                flagStates[cohort.sharedFlag, default: false].toggle()
            }
            guard let next = nextStates(
                for: cohort,
                isActive: flagStates[cohort.sharedFlag, default: false],
                effectivePropertyValues: effectivePropertyValues
            ) else {
                appendCurrentValues(for: cohort, to: &result)
                continue
            }
            for (target, value) in next { states[target] = value }
            appendCurrentValues(for: cohort, to: &result)
        }
        return result
    }

    private func nextStates(
        for cohort: SceneLaunchOriginTransitionCohort,
        isActive: Bool,
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
                      isActive: isActive,
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
        isActive: Bool,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> SIMD3<Double>? {
        switch (isActive, plan.initialFalseTarget) {
        case (true, .base):
            return resolve(
                plan.endpoint,
                effectivePropertyValues: effectivePropertyValues
            )
        case (true, .endpoint):
            return resolve(
                plan.base,
                effectivePropertyValues: effectivePropertyValues
            )
        case let (false, .base(offset)):
            guard let base = resolve(
                plan.base,
                effectivePropertyValues: effectivePropertyValues
            ) else { return nil }
            let result = base + offset
            return finite(result) ? result : nil
        case (false, .endpoint):
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

    private func appendCurrentValues(
        for cohort: SceneLaunchOriginTransitionCohort,
        to result: inout [SceneDynamicTarget: SceneDynamicValue]
    ) {
        for binding in cohort.bindings {
            let target = binding.definition.target
            guard let value = states[target], finite(value) else { continue }
            result[target] = .vector3(value.x, value.y, value.z)
        }
        let isActive = flagStates[cohort.sharedFlag, default: false]
        for binding in cohort.scalarBindings {
            let value = isActive ? binding.trueValue : binding.falseValue
            guard value.isFinite, (0...1).contains(value) else { continue }
            result[binding.definition.target] = .scalar(value)
        }
    }

    private func cohortCanRun(
        _ cohort: SceneLaunchOriginTransitionCohort,
        effectivePropertyValues: [String: SceneUserPropertyValue]
    ) -> Bool {
        cohort.bindings.allSatisfy { binding in
            effectivePropertyValues.keys.contains(binding.plan.triggerPropertyKey)
        }
    }

    private func masterLayerID(
        _ cohort: SceneLaunchOriginTransitionCohort
    ) -> Int? {
        guard case let .layer(layerID, .origin) = cohort.masterTarget else {
            return nil
        }
        return layerID
    }

    private func finite(_ value: SIMD3<Double>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
