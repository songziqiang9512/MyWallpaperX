import Foundation

nonisolated extension SceneParticleSimulator {
    func apply(
        _ value: SceneParticleOperator,
        operatorIndex: Int,
        duration: Double,
        existingParticleIDUpperBound: UInt64 = .max,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace? = nil,
        collisionBoundsFrame: SceneParticleCollisionBoundsFrame? = nil
    ) {
#if DEBUG
        let observesParticles = componentObservation != nil && !particles.isEmpty
        componentObservation?.activeOperatorIndex = operatorIndex
        defer { componentObservation?.activeOperatorIndex = nil }
        componentObservation?.record("operator", operatorIndex, "attempted", reason: "operator-dispatch", time: simulationTime)
        if particles.isEmpty {
            componentObservation?.record("operator", operatorIndex, "not-triggered", reason: "zero-particles", time: simulationTime)
        }
#endif
        guard operatorAudioExecutionAdmission[operatorIndex] else {
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unavailable", reason: "audio-response-admission", time: simulationTime)
#endif
            return
        }
        switch value.kind {
        case .movement:
            guard let plan = operatorExecutionPlans[operatorIndex].movement else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            let gravity = plan.gravity(through: activeWorldSpaceFrame)
                * effectiveSpeedOverride
            let exponent = -plan.dampingRate * duration
            let retention = exp(exponent)
            // Near zero, use the limit of the gravity integral to avoid cancellation.
            let gravityTime = abs(exponent) < 1e-8 ? duration : (1 - retention) / plan.dampingRate
            let gravityImpulse = gravity == .zero ? .zero : gravity * gravityTime
            let retentionOverflowed = !retention.isFinite
            // Without a radius-maintaining Vortex plan no writer ever sets
            // vortexRadius, so the nil-radius clearing and the exact vortex
            // integration collapse to the plain linear step.
            let maintainsRadius = maintainsVortexRadius
            let radiusIsActive = maintainsVortexRadius && vortexOriginIsActive
            particles.withUnsafeMutableBufferPointer { buffer in
                for index in buffer.indices {
                    let initialVelocity = buffer[index].velocity
                    // An unforced stationary peer stays at rest even when growth overflows.
                    let integrated = retentionOverflowed && initialVelocity == .zero
                        ? gravityImpulse : initialVelocity * retention + gravityImpulse
                    let position: SIMD3<Double>
                    let velocity: SIMD3<Double>
                    if maintainsRadius {
                        if !radiusIsActive { buffer[index].vortexRadius = nil }
                        (position, velocity) = vortexMovement(
                            particlePosition: buffer[index].position,
                            vortexRadius: buffer[index].vortexRadius,
                            velocity: integrated, duration: duration
                        )
                    } else {
                        position = buffer[index].position + integrated * duration
                        velocity = integrated
                    }
                    guard acceptsMotionResult(velocity, position, component: "movement") else {
                        continue
                    }
                    buffer[index].velocity = velocity
                    buffer[index].position = position
#if DEBUG
                    if observesParticles {
                        componentObservation?.record("operator", operatorIndex, "evaluated", reason: "motion-result-accepted", time: simulationTime, particleID: buffer[index].id)
                    }
#endif
                }
            }
        case .angularMovement:
            guard let plan = operatorExecutionPlans[operatorIndex].angularMovement else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            for index in particles.indices {
                let acceleration = plan.force - particles[index].angularVelocity * plan.drag
                let velocity = particles[index].angularVelocity + acceleration * duration
                let position = particles[index].rotation + velocity * duration
                guard acceptsMotionResult(velocity, position, component: "angularmovement") else {
                    continue
                }
                particles[index].angularVelocity = velocity
                particles[index].rotation = position
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "angular-result-accepted", time: simulationTime, particleID: particles[index].id)
#endif
            }
        case .alphaFade:
            let executionPlan = operatorExecutionPlans[operatorIndex]
            guard let fadePlan = executionPlan.alphaFade else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            particles.withUnsafeMutableBufferPointer { buffer in
                for index in buffer.indices {
                    let life = normalizedLives[index]
                    if life <= fadePlan.fadeIn {
                        buffer[index].alpha *= SceneParticleSimulationMath.changeAmount(
                            life, 0, fadePlan.fadeIn
                        )
                    }
                    if life > fadePlan.fadeOut {
                        buffer[index].alpha *= 1 - SceneParticleSimulationMath.changeAmount(
                            life, fadePlan.fadeOut, 1
                        )
                    }
                }
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "fade-evaluated", time: simulationTime, particleID: particles[0].id)
            }
#endif
        case .alphaChange:
            guard let plan = operatorExecutionPlans[operatorIndex].scalarChange else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            for index in particles.indices {
                particles[index].alpha *= plan.value(at: normalizedLives[index])
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "alpha-evaluated", time: simulationTime, particleID: particles[0].id)
            }
#endif
        case .sizeChange:
            guard let plan = operatorExecutionPlans[operatorIndex].scalarChange else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            for index in particles.indices {
                particles[index].size *= plan.value(at: normalizedLives[index])
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "size-evaluated", time: simulationTime, particleID: particles[0].id)
            }
#endif
        case .colorChange:
            guard let plan = operatorExecutionPlans[operatorIndex].colorChange else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            for index in particles.indices {
                particles[index].color *= plan.value(at: normalizedLives[index])
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "color-evaluated", time: simulationTime, particleID: particles[0].id)
            }
#endif
        case .oscillateAlpha:
            let executionPlan = operatorExecutionPlans[operatorIndex]
            guard let oscillationPlan = executionPlan.scalarOscillation else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            let blend = executionPlan.blend
            for index in particles.indices {
                let factor = oscillationFactor(
                    oscillationPlan,
                    index,
                    operatorIndex,
                    age: particles[index].age
                )
                particles[index].alpha *= 1 + (factor - 1)
                    * operatorBlend(blend, normalizedLives[index])
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "alpha-oscillation-evaluated", time: simulationTime, particleID: particles[0].id)
            }
#endif
        case .oscillateSize:
            let executionPlan = operatorExecutionPlans[operatorIndex]
            guard let oscillationPlan = executionPlan.scalarOscillation else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            let blend = executionPlan.blend
            for index in particles.indices {
                let factor = oscillationFactor(
                    oscillationPlan,
                    index,
                    operatorIndex,
                    age: particles[index].age,
                )
                particles[index].size *= 1 + (factor - 1)
                    * operatorBlend(blend, normalizedLives[index])
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "size-oscillation-evaluated", time: simulationTime, particleID: particles[0].id)
            }
#endif
        case .oscillatePosition:
            let executionPlan = operatorExecutionPlans[operatorIndex]
            guard let oscillationPlan = executionPlan.positionOscillation else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            let mask = executionPlan.positionMask
            let blend = executionPlan.blend
            for index in particles.indices {
                let oscillation = positionOscillation(
                    oscillationPlan,
                    particleIndex: index,
                    operatorIndex: operatorIndex,
                    mask: mask
                )
                let delta = positionOscillationDelta(
                    oscillation,
                    blend: blend,
                    mask: mask,
                    age: particles[index].age,
                    lifetime: particles[index].lifetime,
                    duration: duration
                )
                SceneParticleSimulationMath.addFinite(
                    delta, to: &particles[index].position
                )
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "position-oscillation-evaluated", time: simulationTime, particleID: particles[0].id)
            }
#endif
        case .turbulence:
            guard let plan = turbulencePlans[operatorIndex] else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            let speedOverride = effectiveSpeedOverride
            let phaseAudioFactor = plan.audioResponse.map {
                1 + evaluateAudioResponse(
                    $0, componentKind: .operator, componentIndex: operatorIndex
                )
            } ?? 1
            let seed = simulationSeed
            let time = simulationTime
            let lives = normalizedLives
            particles.withUnsafeMutableBufferPointer { buffer in
                for index in buffer.indices {
                    let particleID = buffer[index].id
                    let phase = Self.turbulenceRandom(
                        plan.phaseMinimum, plan.phaseMaximum,
                        particleID: particleID, seed: seed, operatorIndex: operatorIndex, salt: 0
                    ) * phaseAudioFactor
                    let speed = Self.turbulenceRandom(
                        plan.minimumSpeed, plan.maximumSpeed,
                        particleID: particleID, seed: seed, operatorIndex: operatorIndex, salt: 1
                    ) * speedOverride
                    let direction = SceneParticleSimulationMath.turbulenceDirection(
                        position: buffer[index].position,
                        time: time,
                        phase: phase,
                        scale: plan.scale,
                        timeScale: plan.timeScale,
                        mask: plan.mask
                    )
                    let delta = direction * speed * duration * plan.blendAmount(lives[index])
                    SceneParticleSimulationMath.addFinite(delta, to: &buffer[index].velocity)
                }
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "turbulence-evaluated", time: simulationTime, particleID: particles[0].id)
            }
#endif
        case let .controlPointRadius(plan):
#if DEBUG
            if value.rawFlags != 0 {
                componentObservation?.record("operator", operatorIndex, "unknown", reason: "unmodeled-operator-flags", time: simulationTime)
            }
#endif
            applyControlPointRadius(
                plan: plan, operatorIndex: operatorIndex, duration: duration,
                existingParticleIDUpperBound: existingParticleIDUpperBound,
                blend: operatorExecutionPlans[operatorIndex].blend,
                controlPointParticleSpace: controlPointParticleSpace
            )
        case .maintainControlPointDistance:
#if DEBUG
            if value.rawFlags != 0 {
                componentObservation?.record("operator", operatorIndex, "unknown", reason: "unmodeled-operator-flags", time: simulationTime)
            }
#endif
            applyMaintainControlPointDistance(
                plan: operatorExecutionPlans[operatorIndex].maintainControlPointDistance,
                operatorIndex: operatorIndex,
                existingParticleIDUpperBound: existingParticleIDUpperBound,
                blend: operatorExecutionPlans[operatorIndex].blend,
                controlPointParticleSpace: controlPointParticleSpace
            )
        case .controlPointAttract:
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime)
#endif
            applyControlPointForce(
                plan: operatorExecutionPlans[operatorIndex].controlPointForce,
                duration: duration,
                normalizedLives: normalizedLives,
                blend: operatorExecutionPlans[operatorIndex].blend,
                controlPointParticleSpace: controlPointParticleSpace
            )
        case .boids:
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime)
#endif
            applyBoids(
                plan: operatorExecutionPlans[operatorIndex].boids,
                duration: duration
            )
        case .vortex:
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime)
#endif
            let audioScale = operatorExecutionPlans[operatorIndex].audioResponse.map {
                evaluateAudioResponse(
                    $0, componentKind: .operator, componentIndex: operatorIndex
                )
            }
            applyVortex(
                plan: operatorExecutionPlans[operatorIndex].vortex,
                duration: duration,
                audioScale: audioScale,
                controlPointParticleSpace: controlPointParticleSpace
            )
        case .capVelocity:
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime)
#endif
            applyCapVelocity(
                plan: operatorExecutionPlans[operatorIndex].capVelocity,
                normalizedLives: normalizedLives,
                blendPlan: operatorExecutionPlans[operatorIndex].blend
            )
        case .remapValue:
            if let plan = operatorExecutionPlans[operatorIndex].scalarSpeedRemap {
                for index in particles.indices {
                    guard let multiplier = SceneParticleSimulationMath.scalarSpeedRemapMultiplier(
                        plan, normalizedLife: normalizedLives[index],
                        particleID: particles[index].id, simulationSeed: simulationSeed
                    ) else { continue }
                    let velocity = particles[index].velocity * multiplier
                    guard acceptsMotionResult(velocity, particles[index].position,
                        component: "remapvalue-speed") else { continue }
                    particles[index].velocity = velocity
#if DEBUG
                    componentObservation?.record("operator", operatorIndex, "evaluated", reason: "speed-remap-result-accepted", time: simulationTime, particleID: particles[index].id)
#endif
                }
                break
            }
            guard let plan = operatorExecutionPlans[operatorIndex].velocityRemap else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
                break
            }
            for index in particles.indices {
                guard let amount = SceneParticleSimulationMath.remapNoiseAmount(
                    position: particles[index].position,
                    time: simulationTime,
                    particleID: particles[index].id,
                    simulationSeed: simulationSeed,
                    inputScale: plan.inputScale
                ) else { continue }
                particles[index].velocity = plan.minimum
                    + (plan.maximum - plan.minimum) * amount
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "velocity-remap-evaluated", time: simulationTime, particleID: particles[index].id)
#endif
            }
        case .reduceMovement:
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime)
#endif
            applyReduceMovement(
                plan: operatorExecutionPlans[operatorIndex].reduceMovement,
                duration: duration
            )
        case .collisionPlane:
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unknown", reason: "helper-evaluation-witness-unavailable", time: simulationTime)
#endif
            applyCollisionPlane(
                plan: operatorExecutionPlans[operatorIndex].collisionPlane,
                controlPointParticleSpace: controlPointParticleSpace
            )
        case let .collisionSphere(plan):
            applyCollisionSphere(
                plan: plan,
                blend: operatorExecutionPlans[operatorIndex].blend,
                controlPointParticleSpace: controlPointParticleSpace
            )
        case let .collisionBounds(defaultResponse):
            guard defaultResponse, let collisionBoundsFrame else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable",
                    reason: defaultResponse ? "canvas-bounds-unavailable" : "response-unavailable", time: simulationTime)
#endif
                break
            }
            applyCollisionBounds(collisionBoundsFrame)
        case let .inheritEventValue(operation):
            guard operation == .setColor,
                  let values = eventValueContext.operatorValues,
                  SceneParticleEventValueOperation.setColor.canConsume(values) else {
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "unavailable", reason: "event-value-unavailable", time: simulationTime)
#endif
                break
            }
            for index in particles.indices {
                particles[index].color = values.color
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "event-value-applied", time: simulationTime, particleID: particles[0].id)
            }
#endif
        case .unsupported:
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unsupported", reason: "unknown-operator-kind", time: simulationTime)
#endif
            break
        }
    }

}
