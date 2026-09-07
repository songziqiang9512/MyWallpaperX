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
/// Turbulent velocity and event color remain live because they consume position/time,
/// audio or frame-local event state.
nonisolated struct SceneParticleInitializerExecutionPlan: Sendable {
    let scalar: SceneParticleRandomScalarPlan?
    let vector: SceneParticleRandomVectorPlan?
    let color: SceneParticleRandomColorPlan?
    let hsvColor: SceneParticleHSVColorPlan?
    let colorList: [SIMD3<Double>]?
    let turbulentVelocity: SceneParticleTurbulentVelocityPlan?
    let positionOffset: SceneParticlePositionOffsetPlan?
    let inheritsEventColor: Bool

    nonisolated init(_ value: SceneParticleInitializer) {
        var scalar: SceneParticleRandomScalarPlan?
        var vector: SceneParticleRandomVectorPlan?
        var color: SceneParticleRandomColorPlan?
        var hsvColor: SceneParticleHSVColorPlan?
        var colorList: [SIMD3<Double>]?
        var turbulentVelocity: SceneParticleTurbulentVelocityPlan?
        var positionOffset: SceneParticlePositionOffsetPlan?
        var inheritsEventColor = false

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
        case let .inheritEventColor(declaration):
            inheritsEventColor = declaration.isBoundedSetColor
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
        self.inheritsEventColor = inheritsEventColor
    }
}

extension SceneParticleSimulator {
    nonisolated func applyInitializers(to particle: inout SceneParticleState) {
        for (initializerIndex, initializer) in definition.initializers.enumerated() {
            let executionPlan = initializerExecutionPlans[initializerIndex]
            switch initializer.kind {
            case .lifetime:
                guard let plan = executionPlan.scalar else { break }
                particle.lifetime = randomScalar(plan)
            case .size:
                guard let plan = executionPlan.scalar else { break }
                particle.size = randomScalar(plan)
            case .velocity:
                // Wallpaper Engine initializes both authored velocity vectors to zero before
                // reading the optional `min` and `max` fields. Keep a missing endpoint at that
                // public engine default; inventing a symmetric range changes one-sided authored
                // profiles such as `max: "0 100 0"` into bidirectional motion.
                guard let plan = executionPlan.vector else { break }
                particle.velocity += randomVector(plan)
            case .color:
                guard let plan = executionPlan.color else { break }
                particle.color = randomColor(plan) / 255
            case .hsvColor:
                if let plan = executionPlan.hsvColor,
                   let color = randomHSVColor(plan) { particle.color = color }
            case .colorList:
                if let colors = executionPlan.colorList,
                   let color = randomColorFromList(colors) { particle.color = color }
            case .alpha:
                guard let plan = executionPlan.scalar else { break }
                particle.alpha = randomScalar(plan)
            case .rotation:
                guard let plan = executionPlan.vector else { break }
                particle.rotation += randomVector(plan)
            case .angularVelocity:
                guard let plan = executionPlan.vector else { break }
                particle.angularVelocity += randomVector(plan)
            case .turbulentVelocity:
                particle.velocity += SceneParticleSimulationMath.turbulentVelocity(
                    executionPlan.turbulentVelocity, particle.position, simulationTime,
                    &random, audioInput: audioInput
                )
            case .positionOffset:
                if let plan = executionPlan.positionOffset {
                    SceneParticleSimulationMath.addFinite(
                        SceneParticleSimulationMath.positionOffset(
                            plan, position: particle.position, time: simulationTime,
                            particleID: particle.id, simulationSeed: simulationSeed
                        ),
                        to: &particle.position
                    )
                }
            case .positionAroundControlPoint:
                guard let plan = positionAroundControlPointPlans[initializerIndex]
                else { break }
                applyPositionAroundControlPoint(plan, to: &particle)
            case .inheritEventColor:
                if executionPlan.inheritsEventColor,
                   let color = eventColorContext.initializerColor {
                    particle.color = color
                }
            case .unsupported:
                break
            }
        }
    }

}
