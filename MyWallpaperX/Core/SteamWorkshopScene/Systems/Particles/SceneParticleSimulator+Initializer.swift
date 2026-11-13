import Foundation

nonisolated struct SceneParticleRandomScalarPlan: Sendable {
    let minimum: Double
    let maximum: Double
    let exponent: Double?

    nonisolated init(
        _ value: SceneParticleInitializer,
        defaults: (minimum: Double, maximum: Double)
    ) {
        minimum = SceneParticleSimulationMath.scalar(value.minimum, fallback: defaults.minimum)
        maximum = SceneParticleSimulationMath.scalar(value.maximum, fallback: defaults.maximum)
        exponent = value.exponent
    }
}

nonisolated struct SceneParticleRandomVectorPlan: Sendable {
    let minimum: SIMD3<Double>
    let maximum: SIMD3<Double>
    let exponent: Double?

    nonisolated init(
        _ value: SceneParticleInitializer,
        defaults: (minimum: SIMD3<Double>, maximum: SIMD3<Double>)
    ) {
        minimum = SceneParticleSimulationMath.vector(value.minimum, fallback: defaults.minimum)
        maximum = SceneParticleSimulationMath.vector(value.maximum, fallback: defaults.maximum)
        exponent = value.exponent
    }
}

nonisolated struct SceneParticleRandomColorPlan: Sendable {
    let minimum: SIMD3<Double>
    let maximum: SIMD3<Double>
    let exponent: Double?

    nonisolated init(
        _ value: SceneParticleInitializer,
        defaults: (minimum: SIMD3<Double>, maximum: SIMD3<Double>)
    ) {
        minimum = SceneParticleSimulationMath.vector(value.minimum, fallback: defaults.minimum)
        maximum = SceneParticleSimulationMath.vector(value.maximum, fallback: defaults.maximum)
        exponent = value.exponent
    }
}

/// Launch-stable authored projections used by the particle initializer hot path.
/// Turbulent velocity and event values remain live because they consume position/time,
/// audio or frame-local event state.
nonisolated enum SceneParticleInitializerExecutionPlan: Sendable {
    case lifetime(SceneParticleRandomScalarPlan)
    case size(SceneParticleRandomScalarPlan)
    case alpha(SceneParticleRandomScalarPlan)
    case velocity(SceneParticleRandomVectorPlan)
    case rotation(SceneParticleRandomVectorPlan)
    case angularVelocity(SceneParticleRandomVectorPlan)
    case color(SceneParticleRandomColorPlan)
    case hsvColor(SceneParticleHSVColorPlan?)
    case colorList([SIMD3<Double>]?)
    case turbulentVelocity(SceneParticleTurbulentVelocityPlan?)
    case positionOffset(SceneParticlePositionOffsetPlan?)
    case positionAroundControlPoint(SceneParticlePositionAroundControlPointPlan?)
    case positionBetweenControlPoints(SceneParticlePositionBetweenControlPointsPlan?)
    case inheritEventValue(SceneParticleEventValueOperation?)
    case unsupported

    nonisolated init(_ value: SceneParticleInitializer, definition: SceneParticleDefinition) {
        switch value.kind {
        case .lifetime:
            self = .lifetime(.init(value, defaults: (0, 1)))
        case .size:
            self = .size(.init(value, defaults: (0, 20)))
        case .velocity:
            self = .velocity(.init(value, defaults: (.zero, .zero)))
        case .color:
            self = .color(.init(value, defaults: (.zero, SIMD3(repeating: 255))))
        case .hsvColor:
            self = .hsvColor(value.boundedHSVColor)
        case .colorList:
            self = .colorList(value.boundedColorList)
        case .turbulentVelocity:
            self = .turbulentVelocity(value.turbulentVelocity.map(
                SceneParticleTurbulentVelocityPlan.init
            ))
        case .alpha:
            self = .alpha(.init(value, defaults: (0.05, 1)))
        case .rotation:
            self = .rotation(.init(value, defaults: (.zero, SIMD3(0, 0, 2 * .pi))))
        case .angularVelocity:
            self = .angularVelocity(.init(
                value,
                defaults: (SIMD3(0, 0, -5), SIMD3(0, 0, 5))
            ))
        case .positionOffset:
            self = .positionOffset(value.boundedPositionOffset)
        case .positionAroundControlPoint:
            self = .positionAroundControlPoint(definition.positionAroundControlPointPlan(for: value))
        case .positionBetweenControlPoints:
            self = .positionBetweenControlPoints(value.positionBetweenControlPointsPlan)
        case let .inheritEventValue(operation):
            self = .inheritEventValue(operation)
        case .unsupported:
            self = .unsupported
        }
    }
}

extension SceneParticleSimulator {
    nonisolated func applyInitializers(
        to particle: inout SceneParticleState, strict: Bool = false,
        emitterControlPointOrigin: SIMD3<Double> = .zero
    ) -> Bool {
        for (initializerIndex, executionPlan) in initializerExecutionPlans.enumerated() {
#if DEBUG
            componentObservation?.record("initializer", initializerIndex, "attempted", reason: "birth-initializer-dispatch", time: simulationTime, particleID: particle.id)
#endif
            switch executionPlan {
            case let .lifetime(plan):
                particle.lifetime = randomScalar(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "lifetime-assigned", time: simulationTime, particleID: particle.id)
#endif
            case let .size(plan):
                particle.size *= randomScalar(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "size-multiplied", time: simulationTime, particleID: particle.id)
#endif
            case let .velocity(plan):
                // Wallpaper Engine initializes both authored velocity vectors to zero before
                // reading the optional `min` and `max` fields. Keep a missing endpoint at that
                // public engine default; inventing a symmetric range changes one-sided authored
                // profiles such as `max: "0 100 0"` into bidirectional motion.
                particle.velocity += randomVector(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "velocity-assigned", time: simulationTime, particleID: particle.id)
#endif
            case let .color(plan):
                particle.color = randomColor(plan) / 255
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "color-assigned", time: simulationTime, particleID: particle.id)
#endif
            case let .hsvColor(plan):
                if let plan,
                   let color = randomHSVColor(plan) {
                    particle.color = color
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "hsv-color-assigned", time: simulationTime, particleID: particle.id)
#endif
                }
            case let .colorList(colors):
                if let colors,
                   let color = randomColorFromList(colors) {
                    particle.color = color
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "list-color-assigned", time: simulationTime, particleID: particle.id)
#endif
                }
            case let .alpha(plan):
                particle.alpha *= randomScalar(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "alpha-multiplied", time: simulationTime, particleID: particle.id)
#endif
            case let .rotation(plan):
                particle.rotation += randomVector(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "rotation-assigned", time: simulationTime, particleID: particle.id)
#endif
            case let .angularVelocity(plan):
                particle.angularVelocity += randomVector(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "angular-velocity-assigned", time: simulationTime, particleID: particle.id)
#endif
            case let .turbulentVelocity(plan):
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime, particleID: particle.id)
#endif
                let audioFactor = plan?.audioResponsePlan.map {
                    1 + evaluateAudioResponse(
                        $0,
                        componentKind: .initializer,
                        componentIndex: initializerIndex
                    )
                }
                particle.velocity += SceneParticleSimulationMath.turbulentVelocity(
                    plan, particle.position, simulationTime,
                    &random, audioInput: audioInput,
                    preparedAudioFactor: audioFactor, strict: strict
                )
            case let .positionOffset(plan):
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime, particleID: particle.id)
#endif
                if let plan {
                    let delta = SceneParticleSimulationMath.positionOffset(
                            plan, position: particle.position, time: simulationTime,
                            particleID: particle.id, simulationSeed: simulationSeed, strict: strict
                        )
                    if strict { particle.position += delta }
                    else { SceneParticleSimulationMath.addFinite(delta, to: &particle.position) }
                }
            case let .positionAroundControlPoint(plan):
                guard let plan else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                let applied = applyPositionAroundControlPoint(plan, to: &particle)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, applied ? "evaluated" : "unavailable",
                    reason: applied ? "control-point-position-applied" : "control-point-position-unavailable", time: simulationTime, particleID: particle.id)
#endif
                if !applied, strict { return false }
            case let .positionBetweenControlPoints(plan):
                guard let plan else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                let applied = applyPositionBetweenControlPoints(
                    plan, to: &particle, emitterControlPointOrigin: emitterControlPointOrigin
                )
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, applied ? "evaluated" : "unavailable",
                    reason: applied ? "between-control-points-applied" : "control-point-position-unavailable", time: simulationTime, particleID: particle.id)
                if plan.hasUnconsumedOptions {
                    componentObservation?.record("initializer", initializerIndex, "partial", reason: "between-options-unconsumed", time: simulationTime, particleID: particle.id)
                }
#endif
                if !applied, strict { return false }
            case let .inheritEventValue(operation):
                guard let operation,
                      let values = eventValueContext.initializerValues,
                      operation.canConsume(values) else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "event-value-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                switch operation {
                case .setColor:
                    particle.color = values.color
                case .multiplySize:
                    particle.size *= values.size * 0.5
                case .setOpacity:
                    particle.alpha = values.alpha
                }
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "event-value-applied", time: simulationTime, particleID: particle.id)
#endif
            case .unsupported:
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "unsupported", reason: "unknown-initializer-kind", time: simulationTime, particleID: particle.id)
#endif
                break
            }
        }
        return true
    }

}
