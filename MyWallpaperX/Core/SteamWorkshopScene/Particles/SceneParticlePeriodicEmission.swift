import Foundation

nonisolated enum SceneParticlePeriodicEmissionAdmission {
    case disabled
    case supported(SceneParticlePeriodicEmissionPlan)
    case unsupported
}

nonisolated struct SceneParticlePeriodicEmissionPlan: Sendable {
    let minimumDuration: Double
    let maximumDuration: Double
    let minimumDelay: Double
    let maximumDelay: Double
}

nonisolated struct SceneParticleEmitterState: Sendable {
    var elapsed = 0.0
    var remainder = 0.0
    var emittedInstantaneous = false

    private var periodicIsEmitting = true
    private var periodicRemaining: Double?
    private var periodicRandom: SceneParticleRandomGenerator

    nonisolated init(seed: UInt64, emitterIndex: Int) {
        periodicRandom = SceneParticleRandomGenerator(
            state: seed &+ UInt64(emitterIndex) &* 0x9E3779B97F4A7C15
        )
    }

    nonisolated mutating func activeDuration(
        for emitter: SceneParticleEmitter,
        stepDuration: Double
    ) -> Double {
        switch emitter.periodicEmissionAdmission {
        case .disabled:
            return stepDuration
        case .unsupported:
            return 0
        case let .supported(configuration):
            var remainingStep = stepDuration
            var active = 0.0
            while remainingStep > 1e-12 {
                if periodicRemaining == nil {
                    let range = periodicIsEmitting
                        ? (configuration.minimumDuration, configuration.maximumDuration)
                        : (configuration.minimumDelay, configuration.maximumDelay)
                    periodicRemaining = periodicRandom.value(range.0, range.1)
                }
                let slice = min(remainingStep, periodicRemaining ?? 0)
                if periodicIsEmitting { active += slice }
                remainingStep -= slice
                periodicRemaining = max((periodicRemaining ?? 0) - slice, 0)
                if periodicRemaining ?? 0 <= 1e-12 {
                    periodicIsEmitting.toggle()
                    periodicRemaining = nil
                }
            }
            return active
        }
    }
}

nonisolated extension SceneParticleEmitter {
    var periodicEmissionAdmission: SceneParticlePeriodicEmissionAdmission {
        guard usesRandomPeriodicEmission else { return .disabled }
        let value = periodicEmission
        let minimumInterval = 1.0 / 240.0
        let maximumInterval = 3_600.0
        guard rawFlags & ~4 == 0,
              !value.hasMalformedFields,
              value.initialDelay == nil || value.initialDelay == 0,
              value.maximumEmissionCount == nil,
              (instantaneousCount ?? 0) == 0,
              (duration ?? 0) == 0,
              !audioResponse.isEnabled,
              let minimumDuration = value.minimumDuration,
              let maximumDuration = value.maximumDuration,
              let minimumDelay = value.minimumDelay,
              let maximumDelay = value.maximumDelay,
              minimumDuration.isFinite, maximumDuration.isFinite,
              minimumDelay.isFinite, maximumDelay.isFinite,
              (minimumInterval...maximumInterval).contains(minimumDuration),
              (minimumInterval...maximumInterval).contains(minimumDelay),
              minimumDuration <= maximumDuration,
              minimumDelay <= maximumDelay,
              maximumDuration <= maximumInterval,
              maximumDelay <= maximumInterval else { return .unsupported }
        return .supported(.init(
            minimumDuration: minimumDuration,
            maximumDuration: maximumDuration,
            minimumDelay: minimumDelay,
            maximumDelay: maximumDelay
        ))
    }
}
