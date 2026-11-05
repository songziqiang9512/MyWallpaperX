import Foundation

nonisolated extension SceneParticleSimulator {
    func apply(
        _ value: SceneParticleOperator,
        operatorIndex: Int,
        duration: Double,
        existingParticleIDUpperBound: UInt64 = .max,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace? = nil
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
            let radiusIsActive = maintainsVortexRadius && vortexOriginIsActive
            for index in particles.indices {
                if !radiusIsActive { particles[index].vortexRadius = nil }
                let acceleration = gravity - particles[index].velocity * plan.drag
                let integrated = particles[index].velocity + acceleration * duration
                let (position, velocity) = vortexMovement(
                    particle: particles[index], velocity: integrated, duration: duration
                )
                guard acceptsMotionResult(velocity, position, component: "movement") else {
                    continue
                }
                particles[index].velocity = velocity
                particles[index].position = position
#if DEBUG
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "motion-result-accepted", time: simulationTime, particleID: particles[index].id)
#endif
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
            for index in particles.indices {
                let life = normalizedLives[index]
                if life <= fadePlan.fadeIn {
                    particles[index].alpha *= SceneParticleSimulationMath.changeAmount(
                        life, 0, fadePlan.fadeIn
                    )
                }
                if life > fadePlan.fadeOut {
                    particles[index].alpha *= 1 - SceneParticleSimulationMath.changeAmount(
                        life, fadePlan.fadeOut, 1
                    )
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
            for index in particles.indices {
                let phase = turbulenceRandom(
                    plan.phaseMinimum, plan.phaseMaximum,
                    index, operatorIndex, 0
                ) * phaseAudioFactor
                let speed = turbulenceRandom(
                    plan.minimumSpeed, plan.maximumSpeed, index, operatorIndex, 1
                ) * speedOverride
                let direction = SceneParticleSimulationMath.turbulenceDirection(
                    position: particles[index].position,
                    time: simulationTime,
                    phase: phase,
                    scale: plan.scale,
                    timeScale: plan.timeScale,
                    mask: plan.mask
                )
                let delta = direction * speed * duration
                    * plan.blendAmount(normalizedLives[index])
                SceneParticleSimulationMath.addFinite(delta, to: &particles[index].velocity)
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
        case let .inheritEventColor(declaration):
            guard declaration.isBoundedSetColor,
                  let color = eventColorContext.operatorColor else { break }
            for index in particles.indices {
                particles[index].color = color
            }
#if DEBUG
            if observesParticles {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "event-color-applied", time: simulationTime, particleID: particles[0].id)
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
