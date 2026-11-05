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
nonisolated struct SceneParticleInitializerExecutionPlan: Sendable {
    let scalar: SceneParticleRandomScalarPlan?
    let vector: SceneParticleRandomVectorPlan?
    let color: SceneParticleRandomColorPlan?
    let hsvColor: SceneParticleHSVColorPlan?
    let colorList: [SIMD3<Double>]?
    let turbulentVelocity: SceneParticleTurbulentVelocityPlan?
    let positionOffset: SceneParticlePositionOffsetPlan?
    let positionAroundControlPoint: SceneParticlePositionAroundControlPointPlan?
    let positionBetweenControlPoints: SceneParticlePositionBetweenControlPointsPlan?

    nonisolated init(_ value: SceneParticleInitializer, definition: SceneParticleDefinition) {
        var scalar: SceneParticleRandomScalarPlan?
        var vector: SceneParticleRandomVectorPlan?
        var color: SceneParticleRandomColorPlan?
        var hsvColor: SceneParticleHSVColorPlan?
        var colorList: [SIMD3<Double>]?
        var turbulentVelocity: SceneParticleTurbulentVelocityPlan?
        var positionOffset: SceneParticlePositionOffsetPlan?
        var positionAroundControlPoint: SceneParticlePositionAroundControlPointPlan?
        var positionBetweenControlPoints: SceneParticlePositionBetweenControlPointsPlan?

        switch value.kind {
        case .lifetime:
            scalar = .init(value, defaults: (0, 1))
        case .size:
            scalar = .init(value, defaults: (0, 20))
        case .velocity:
            vector = .init(value, defaults: (.zero, .zero))
        case .color:
            color = .init(value, defaults: (.zero, SIMD3(repeating: 255)))
        case .hsvColor:
            hsvColor = value.boundedHSVColor
        case .colorList:
            colorList = value.boundedColorList
        case .turbulentVelocity:
            turbulentVelocity = value.turbulentVelocity.map(
                SceneParticleTurbulentVelocityPlan.init
            )
        case .alpha:
            scalar = .init(value, defaults: (0.05, 1))
        case .rotation:
            vector = .init(value, defaults: (.zero, SIMD3(0, 0, 2 * .pi)))
        case .angularVelocity:
            vector = .init(
                value,
                defaults: (SIMD3(0, 0, -5), SIMD3(0, 0, 5))
            )
        case .positionOffset:
            positionOffset = value.boundedPositionOffset
        case .positionAroundControlPoint:
            if definition.supportsBoundedPositionAroundControlPoint(value) {
                positionAroundControlPoint = value.positionAroundControlPointPlan
            }
        case .positionBetweenControlPoints:
            positionBetweenControlPoints = value.positionBetweenControlPointsPlan
        default:
            break
        }

        self.scalar = scalar
        self.vector = vector
        self.color = color
        self.hsvColor = hsvColor
        self.colorList = colorList
        self.turbulentVelocity = turbulentVelocity
        self.positionOffset = positionOffset
        self.positionAroundControlPoint = positionAroundControlPoint
        self.positionBetweenControlPoints = positionBetweenControlPoints
    }
}

extension SceneParticleSimulator {
    nonisolated func applyInitializers(
        to particle: inout SceneParticleState, strict: Bool = false,
        emitterControlPointOrigin: SIMD3<Double> = .zero
    ) -> Bool {
        for (initializerIndex, initializer) in definition.initializers.enumerated() {
            let executionPlan = initializerExecutionPlans[initializerIndex]
#if DEBUG
            componentObservation?.record("initializer", initializerIndex, "attempted", reason: "birth-initializer-dispatch", time: simulationTime, particleID: particle.id)
#endif
            switch initializer.kind {
            case .lifetime:
                guard let plan = executionPlan.scalar else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                particle.lifetime = randomScalar(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "lifetime-assigned", time: simulationTime, particleID: particle.id)
#endif
            case .size:
                guard let plan = executionPlan.scalar else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                particle.size *= randomScalar(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "size-multiplied", time: simulationTime, particleID: particle.id)
#endif
            case .velocity:
                // Wallpaper Engine initializes both authored velocity vectors to zero before
                // reading the optional `min` and `max` fields. Keep a missing endpoint at that
                // public engine default; inventing a symmetric range changes one-sided authored
                // profiles such as `max: "0 100 0"` into bidirectional motion.
                guard let plan = executionPlan.vector else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                particle.velocity += randomVector(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "velocity-assigned", time: simulationTime, particleID: particle.id)
#endif
            case .color:
                guard let plan = executionPlan.color else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                particle.color = randomColor(plan) / 255
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "color-assigned", time: simulationTime, particleID: particle.id)
#endif
            case .hsvColor:
                if let plan = executionPlan.hsvColor,
                   let color = randomHSVColor(plan) {
                    particle.color = color
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "hsv-color-assigned", time: simulationTime, particleID: particle.id)
#endif
                }
            case .colorList:
                if let colors = executionPlan.colorList,
                   let color = randomColorFromList(colors) {
                    particle.color = color
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "list-color-assigned", time: simulationTime, particleID: particle.id)
#endif
                }
            case .alpha:
                guard let plan = executionPlan.scalar else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                particle.alpha *= randomScalar(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "alpha-multiplied", time: simulationTime, particleID: particle.id)
#endif
            case .rotation:
                guard let plan = executionPlan.vector else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                particle.rotation += randomVector(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "rotation-assigned", time: simulationTime, particleID: particle.id)
#endif
            case .angularVelocity:
                guard let plan = executionPlan.vector else {
#if DEBUG
                    componentObservation?.record("initializer", initializerIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime, particleID: particle.id)
#endif
                    break
                }
                particle.angularVelocity += randomVector(plan)
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "evaluated", reason: "angular-velocity-assigned", time: simulationTime, particleID: particle.id)
#endif
            case .turbulentVelocity:
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime, particleID: particle.id)
#endif
                let audioFactor = executionPlan.turbulentVelocity?.audioResponsePlan.map {
                    1 + evaluateAudioResponse(
                        $0,
                        componentKind: .initializer,
                        componentIndex: initializerIndex
                    )
                }
                particle.velocity += SceneParticleSimulationMath.turbulentVelocity(
                    executionPlan.turbulentVelocity, particle.position, simulationTime,
                    &random, audioInput: audioInput,
                    preparedAudioFactor: audioFactor, strict: strict
                )
            case .positionOffset:
#if DEBUG
                componentObservation?.record("initializer", initializerIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime, particleID: particle.id)
#endif
                if let plan = executionPlan.positionOffset {
                    let delta = SceneParticleSimulationMath.positionOffset(
                            plan, position: particle.position, time: simulationTime,
                            particleID: particle.id, simulationSeed: simulationSeed, strict: strict
                        )
                    if strict { particle.position += delta }
                    else { SceneParticleSimulationMath.addFinite(delta, to: &particle.position) }
                }
            case .positionAroundControlPoint:
                guard let plan = executionPlan.positionAroundControlPoint
                else {
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
            case .positionBetweenControlPoints:
                guard let plan = executionPlan.positionBetweenControlPoints else {
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
