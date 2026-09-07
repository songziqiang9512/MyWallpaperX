import Foundation

nonisolated struct SceneParticleOscillationCacheKey: Hashable, Sendable {
    let particleID: UInt64
    let operatorIndex: Int
}

nonisolated struct SceneParticlePositionOscillation: Sendable {
    let frequency: SIMD3<Double>
    let scale: SIMD3<Double>
    let phase: SIMD3<Double>
}

nonisolated struct SceneParticleOperatorBlendPlan: Sendable {
    let hasBlendIn: Bool
    let blendInStart: Double
    let blendInEnd: Double
    let hasBlendOut: Bool
    let blendOutStart: Double
    let blendOutEnd: Double

    nonisolated init(_ value: SceneParticleOperator) {
        hasBlendIn = value.blendInStart != nil || value.blendInEnd != nil
        blendInStart = value.blendInStart ?? 0
        blendInEnd = value.blendInEnd ?? 0
        hasBlendOut = value.blendOutStart != nil || value.blendOutEnd != nil
        blendOutStart = value.blendOutStart ?? 1
        blendOutEnd = value.blendOutEnd ?? 1
    }
}

nonisolated struct SceneParticlePositionOscillationPlan: Sendable {
    let frequencyMinimum: Double
    let frequencyMaximum: Double
    let scaleMinimum: SIMD3<Double>
    let scaleMaximum: SIMD3<Double>
    let phaseMinimum: Double
    let phaseMaximum: Double

    nonisolated init(_ value: SceneParticleOperator) {
        frequencyMinimum = value.frequencyMinimum ?? 0
        frequencyMaximum = value.frequencyMaximum ?? 5
        scaleMinimum = SceneParticleSimulationMath.vector(
            value.scaleMinimum, fallback: .zero
        )
        scaleMaximum = SceneParticleSimulationMath.vector(
            value.scaleMaximum, fallback: SIMD3(repeating: 1)
        )
        phaseMinimum = value.phaseMinimum ?? 0
        phaseMaximum = value.phaseMaximum ?? 2 * .pi
    }
}

/// Launch-stable scalar oscillation inputs. The particle age and the random
/// seed remain frame/particle-local; only authored ranges and their defaults
/// are prepared once so the fixed-step loop does not repeatedly normalize
/// optional numeric values.
nonisolated struct SceneParticleScalarOscillationPlan: Sendable {
    let minimum: Double
    let maximum: Double
    let frequencyMinimum: Double
    let frequencyMaximum: Double
    let phaseMinimum: Double
    let phaseMaximum: Double

    nonisolated init(_ value: SceneParticleOperator, sizeDefaults: Bool) {
        minimum = SceneParticleSimulationMath.scalar(
            value.scaleMinimum,
            fallback: sizeDefaults ? 0.8 : 0
        )
        maximum = SceneParticleSimulationMath.scalar(
            value.scaleMaximum,
            fallback: sizeDefaults ? 1.2 : 1
        )
        frequencyMinimum = value.frequencyMinimum ?? 0
        frequencyMaximum = value.frequencyMaximum ?? 10
        phaseMinimum = value.phaseMinimum ?? 0
        phaseMaximum = value.phaseMaximum ?? 2 * .pi
    }
}

/// Launch-stable inputs for the linear movement operator. The world-space
/// frame is itself a prepared simulator dependency; particle velocity,
/// position and duration remain live in the fixed-step loop.
nonisolated struct SceneParticleMovementPlan: Sendable {
    let gravity: SIMD3<Double>
    let drag: Double

    nonisolated init(
        _ value: SceneParticleOperator,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?
    ) {
        let authoredGravity = SceneParticleSimulationMath.vector(
            value.gravity,
            fallback: .zero
        )
        gravity = value.isWorldSpaceMovement
            ? worldSpaceFrame?.localDirection(authoredGravity) ?? authoredGravity
            : authoredGravity
        drag = max(0, value.drag ?? 0)
    }
}

/// Launch-stable inputs for angular movement. Angular velocity, rotation and
/// duration are particle/frame-local and are intentionally not cached here.
nonisolated struct SceneParticleAngularMovementPlan: Sendable {
    let force: SIMD3<Double>
    let drag: Double

    nonisolated init(_ value: SceneParticleOperator) {
        force = SceneParticleSimulationMath.vector(value.force, fallback: .zero)
        drag = max(0, value.drag ?? 0)
    }
}

/// Launch-stable execution values shared by the operator hot path.
///
/// The authored operator itself remains available to the simulator for
/// dynamic inputs and capability checks, while these immutable plans keep
/// scalar/vector normalization and audio declaration parsing out of every
/// fixed step.
nonisolated struct SceneParticleOperatorExecutionPlan: Sendable {
    let blend: SceneParticleOperatorBlendPlan
    let scalarOscillation: SceneParticleScalarOscillationPlan?
    let movement: SceneParticleMovementPlan?
    let angularMovement: SceneParticleAngularMovementPlan?
    let alphaFade: SceneParticleAlphaFadePlan?
    let scalarChange: SceneParticleScalarChangePlan?
    let colorChange: SceneParticleColorChangePlan?
    let positionOscillation: SceneParticlePositionOscillationPlan?
    let positionMask: SIMD3<Double>
    let audioResponse: SceneParticleAudioResponsePlan?
    let boids: SceneParticleBoidsPlan?
    let vortex: SceneParticleVortexPlan?
    let capVelocity: SceneParticleCapVelocityPlan?
    let velocityRemap: SceneParticleVelocityRemapPlan?
    let collisionPlane: SceneParticleCollisionPlanePlan?
    let controlPointForce: SceneParticleControlPointForcePlan?
    let reduceMovement: SceneParticleReduceMovementPlan?

    nonisolated init(
        _ value: SceneParticleOperator,
        definition: SceneParticleDefinition,
        worldSpaceFrame: SceneParticleWorldSpaceFrame?
    ) {
        blend = SceneParticleOperatorBlendPlan(value)
        switch value.kind {
        case .oscillateAlpha:
            scalarOscillation = SceneParticleScalarOscillationPlan(
                value, sizeDefaults: false
            )
        case .oscillateSize:
            scalarOscillation = SceneParticleScalarOscillationPlan(
                value, sizeDefaults: true
            )
        default:
            scalarOscillation = nil
        }
        switch value.kind {
        case .movement:
            movement = SceneParticleMovementPlan(
                value, worldSpaceFrame: worldSpaceFrame
            )
            angularMovement = nil
        case .angularMovement:
            movement = nil
            angularMovement = SceneParticleAngularMovementPlan(value)
        default:
            movement = nil
            angularMovement = nil
        }
        alphaFade = value.kind == .alphaFade
            ? SceneParticleAlphaFadePlan(value)
            : nil
        switch value.kind {
        case .alphaChange, .sizeChange:
            scalarChange = SceneParticleScalarChangePlan(value)
            colorChange = nil
        case .colorChange:
            scalarChange = nil
            colorChange = SceneParticleColorChangePlan(value)
        default:
            scalarChange = nil
            colorChange = nil
        }
        positionOscillation = value.kind == .oscillatePosition
            ? SceneParticlePositionOscillationPlan(value)
            : nil
        positionMask = SceneParticleSimulationMath.vector(
            value.mask, fallback: SIMD3(1, 1, 0)
        )
        audioResponse = SceneParticleAudioResponsePlan(value.audioResponse)
        if case .boids = value.kind {
            boids = definition.boidsPlan(for: value)
        } else {
            boids = nil
        }
        if case .vortex = value.kind {
            vortex = value.vortexPlan
        } else {
            vortex = nil
        }
        if case .capVelocity = value.kind {
            capVelocity = value.capVelocityPlan
        } else {
            capVelocity = nil
        }
        if case .remapValue = value.kind {
            velocityRemap = value.boundedVelocityRemapPlan
        } else {
            velocityRemap = nil
        }
        if case .collisionPlane = value.kind {
            collisionPlane = value.collisionPlanePlan
        } else {
            collisionPlane = nil
        }
        if value.kind == .controlPointAttract,
           definition.supportsBoundedControlPointForce(value),
           case let .supported(plan) = value.controlPointForceAdmission {
            controlPointForce = plan
        } else {
            controlPointForce = nil
        }
        if case .reduceMovement = value.kind,
           definition.supportsBoundedReduceMovement(value),
           let plan = value.reduceMovementPlan {
            reduceMovement = plan
        } else {
            reduceMovement = nil
        }
    }
}

extension SceneParticleSimulator {
    nonisolated func oscillationFactor(
        _ plan: SceneParticleScalarOscillationPlan,
        _ index: Int,
        _ operatorIndex: Int,
        age: Double
    ) -> Double {
        let frequency = oscillationRandom(
            plan.frequencyMinimum,
            plan.frequencyMaximum,
            index,
            operatorIndex,
            0
        )
        let phase = oscillationRandom(
            plan.phaseMinimum,
            plan.phaseMaximum,
            index,
            operatorIndex,
            1
        )
        let wave = (cos(frequency * age + phase) + 1) * 0.5
        return plan.minimum + (plan.maximum - plan.minimum) * wave
    }

    nonisolated func operatorBlend(
        _ value: SceneParticleOperator,
        _ life: Double
    ) -> Double {
        operatorBlend(SceneParticleOperatorBlendPlan(value), life)
    }

    nonisolated func operatorBlend(
        _ plan: SceneParticleOperatorBlendPlan,
        _ life: Double
    ) -> Double {
        var result = 1.0
        if plan.hasBlendIn {
            result *= SceneParticleSimulationMath.changeAmount(
                life,
                plan.blendInStart,
                plan.blendInEnd
            )
        }
        if plan.hasBlendOut {
            result *= 1 - SceneParticleSimulationMath.changeAmount(
                life,
                plan.blendOutStart,
                plan.blendOutEnd
            )
        }
        return result
    }

    nonisolated func oscillationRandom(
        _ first: Double,
        _ second: Double,
        _ index: Int,
        _ operatorIndex: Int,
        _ salt: Int
    ) -> Double {
        var state = particles[index].id &* 0x9E3779B97F4A7C15
        state ^= UInt64(operatorIndex &* 31 &+ salt) &* 0xBF58476D1CE4E5B9
        var generator = SceneParticleRandomGenerator(state: state)
        return generator.value(first, second)
    }

    nonisolated func positionOscillation(
        _ plan: SceneParticlePositionOscillationPlan,
        particleIndex: Int,
        operatorIndex: Int,
        mask: SIMD3<Double>
    ) -> SceneParticlePositionOscillation {
        let key = SceneParticleOscillationCacheKey(
            particleID: particles[particleIndex].id,
            operatorIndex: operatorIndex
        )
        if let cached = positionOscillationCache[key] { return cached }

        var frequency = SIMD3<Double>.zero
        var scale = SIMD3<Double>.zero
        var phase = SIMD3<Double>.zero
        for component in 0..<3 where abs(mask[component]) > 1e-6 {
            frequency[component] = oscillationRandom(
                plan.frequencyMinimum, plan.frequencyMaximum,
                particleIndex, operatorIndex, component
            )
            scale[component] = oscillationRandom(
                plan.scaleMinimum[component], plan.scaleMaximum[component],
                particleIndex, operatorIndex, component + 3
            )
            phase[component] = oscillationRandom(
                plan.phaseMinimum, plan.phaseMaximum,
                particleIndex, operatorIndex, component + 6
            )
        }
        let result = SceneParticlePositionOscillation(
            frequency: frequency, scale: scale, phase: phase
        )
        positionOscillationCache[key] = result
        return result
    }

    nonisolated func positionOscillationDelta(
        _ oscillation: SceneParticlePositionOscillation,
        blend: SceneParticleOperatorBlendPlan,
        mask: SIMD3<Double>,
        age: Double,
        lifetime: Double,
        duration: Double
    ) -> SIMD3<Double> {
        let previousAge = max(age - duration, 0)
        let currentLife = min(max(age / max(lifetime, 1e-12), 0), 1)
        let previousLife = min(max(previousAge / max(lifetime, 1e-12), 0), 1)
        let currentBlend = operatorBlend(blend, currentLife)
        let previousBlend = operatorBlend(blend, previousLife)
        var result = SIMD3<Double>.zero
        for component in 0..<3 where abs(mask[component]) > 1e-6 {
            let phase = oscillation.phase[component]
            let frequency = oscillation.frequency[component]
            let baseline = cos(phase)
            let currentWave = cos(frequency * age + phase) - baseline
            let previousWave = cos(frequency * previousAge + phase) - baseline
            result[component] = oscillation.scale[component] * mask[component]
                * (currentWave * currentBlend - previousWave * previousBlend)
        }
        return result
    }
}
