import Foundation

nonisolated enum SceneParticleInitialDelayAdmission {
    case disabled
    case supported(Double)
    case unsupported
}

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

    private var initialDelayElapsed = 0.0
    private var emittedRateThisFrame = false
    private var periodicIsEmitting = true
    private var periodicRemaining: Double?
    private var periodicRandom: SceneParticleRandomGenerator

    nonisolated init(seed: UInt64, emitterIndex: Int) {
        periodicRandom = SceneParticleRandomGenerator(
            state: seed &+ UInt64(emitterIndex) &* 0x9E3779B97F4A7C15
        )
    }

    nonisolated mutating func beginFrame() {
        emittedRateThisFrame = false
    }

    nonisolated mutating func boundedRateEmissionCount(
        _ count: Int,
        limitsToOnePerFrame: Bool
    ) -> Int {
        guard limitsToOnePerFrame else { return count }
        guard count > 0, !emittedRateThisFrame else { return 0 }
        emittedRateThisFrame = true
        return 1
    }

    nonisolated mutating func scheduledActiveDuration(
        for emitter: SceneParticleEmitter,
        stepDuration: Double,
        rateScale: Double
    ) -> Double? {
        let scheduled = activeDurationAfterInitialDelay(
            for: emitter, stepDuration: stepDuration
        )
        guard scheduled > 0 else { return nil }
        elapsed += scheduled * rateScale
        if let limit = emitter.duration,
           limit > 0, elapsed > limit + 1e-12 { return nil }
        let active = periodicActiveDuration(for: emitter, stepDuration: scheduled)
        return active > 0 ? active : nil
    }

    private nonisolated mutating func activeDurationAfterInitialDelay(
        for emitter: SceneParticleEmitter,
        stepDuration: Double
    ) -> Double {
        switch emitter.initialDelayAdmission {
        case .disabled:
            return stepDuration
        case .unsupported:
            return 0
        case let .supported(delay):
            let remaining = max(delay - initialDelayElapsed, 0)
            guard remaining > 1e-12 else { return stepDuration }
            let waiting = min(stepDuration, remaining)
            initialDelayElapsed = min(delay, initialDelayElapsed + waiting)
            let active = stepDuration - waiting
            return active > 1e-12 ? active : 0
        }
    }

    private nonisolated mutating func periodicActiveDuration(
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
    var initialDelayAdmission: SceneParticleInitialDelayAdmission {
        let value = periodicEmission
        guard !value.hasMalformedInitialDelay else { return .unsupported }
        guard let delay = value.initialDelay else { return .disabled }
        guard delay.isFinite, delay >= 0, delay <= 3_600 else {
            return .unsupported
        }
        return delay > 1e-12 ? .supported(delay) : .disabled
    }

    var periodicEmissionAdmission: SceneParticlePeriodicEmissionAdmission {
        guard usesRandomPeriodicEmission else { return .disabled }
        let value = periodicEmission
        let minimumInterval = 1.0 / 240.0
        let maximumInterval = 3_600.0
        if case .unsupported = initialDelayAdmission { return .unsupported }
        guard rawFlags & ~4 == 0,
              !value.hasMalformedFields,
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
