import Foundation

nonisolated enum SceneParticleControlPointConstraintHistory: Equatable, Sendable {
    case unavailable
    case single(SIMD3<Double>)
    case endpoints(start: SIMD3<Double>, end: SIMD3<Double>)
}

nonisolated struct SceneParticleControlPointParticleSpace: Sendable {
    let currentOrigin: SIMD3<Double>
    let scale: SIMD3<Double>
    let birthOrigins: [UInt64: SIMD3<Double>]
}

nonisolated extension SceneParticleSimulator {
    func applyControlPointRadius(
        plan: SceneParticleControlPointRadiusPlan?,
        operatorIndex: Int,
        duration: Double,
        existingParticleIDUpperBound: UInt64,
        blend: SceneParticleOperatorBlendPlan,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace?
    ) {
        guard let plan else {
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
            return
        }
        guard let source = controlPointLocalPosition(plan.controlPoint) else {
            controlPointConstraintHistory[operatorIndex] = .unavailable
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unavailable", reason: "control-point-source-unavailable", time: simulationTime)
#endif
            return
        }
        let current: SIMD3<Double>
        if let space = controlPointParticleSpace {
            current = space.currentOrigin + space.scale * source
        } else {
            current = source + referencePositionOffset
        }
        guard current.x.isFinite, current.y.isFinite, current.z.isFinite else {
            controlPointConstraintHistory[operatorIndex] = .unavailable
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unavailable", reason: "control-point-source-nonfinite", time: simulationTime)
#endif
            return
        }
        let previous = controlPointConstraintHistory[operatorIndex]
        controlPointConstraintHistory[operatorIndex] = .single(current)
        let carry: SIMD3<Double>
        if case let .single(point) = previous {
            let delta = current - point
            carry = controlPointParticleSpace.map { delta / $0.scale } ?? delta
        } else {
            carry = .zero
        }
        let strength = plan.variableStrength > 0 ? min(plan.variableStrength * duration, 1) : 1
        for index in particles.indices {
            let identity = particles[index].id
            var position = particles[index].position
            if identity < existingParticleIDUpperBound { position += carry }
            let amount = strength * operatorBlend(blend, normalizedLives[index])
            if amount != 0 {
                let target = source + positionReferenceOffset(for: particles[index], space: controlPointParticleSpace)
                let radial = position - target
                let length = hypot(hypot(radial.x, radial.y), radial.z)
                if length > 0 {
                    let constrained = target + radial / length * plan.distance
                    position += (constrained - position) * amount
                }
            }
            guard acceptsMotionResult(particles[index].velocity, position, component: "maintaindistancetocontrolpoint")
            else { continue }
            particles[index].position = position
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "evaluated", reason: "control-point-radius-result-accepted", time: simulationTime, particleID: identity)
#endif
        }
    }

    func applyMaintainControlPointDistance(
        plan: SceneParticleMaintainControlPointDistancePlan?,
        operatorIndex: Int,
        existingParticleIDUpperBound: UInt64,
        blend: SceneParticleOperatorBlendPlan,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace?
    ) {
        guard let plan else {
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unavailable", reason: "prepared-plan-unavailable", time: simulationTime)
#endif
            return
        }
        guard let start = controlPointLocalPosition(plan.start),
              let end = controlPointLocalPosition(plan.end) else {
            controlPointConstraintHistory[operatorIndex] = .unavailable
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unavailable", reason: "control-point-endpoints-unavailable", time: simulationTime)
#endif
            return
        }
        let currentStart: SIMD3<Double>
        let currentEnd: SIMD3<Double>
        if let space = controlPointParticleSpace {
            currentStart = space.currentOrigin + space.scale * start
            currentEnd = space.currentOrigin + space.scale * end
        } else {
            let offset = referencePositionOffset
            currentStart = start + offset
            currentEnd = end + offset
        }
        let previous = controlPointConstraintHistory[operatorIndex]
        // Advance once per operator, including empty and newly born cohorts.
        controlPointConstraintHistory[operatorIndex] = .endpoints(start: currentStart, end: currentEnd)
        guard case let .endpoints(previousStart, previousEnd) = previous else {
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "not-triggered", reason: "control-point-history-initialized", time: simulationTime)
#endif
            return
        }
        guard currentStart != previousStart || currentEnd != previousEnd else { return }
        let axis = previousEnd - previousStart
        let axisLengthSquared = axis.x * axis.x + axis.y * axis.y + axis.z * axis.z
        guard axisLengthSquared.isFinite, axisLengthSquared > 0 else {
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "not-triggered", reason: "control-point-axis-degenerate", time: simulationTime)
#endif
            return
        }
        let startDelta = currentStart - previousStart
        let endDelta = currentEnd - previousEnd
        for index in particles.indices where particles[index].id < existingParticleIDUpperBound {
            let canonicalPosition: SIMD3<Double>
            if let space = controlPointParticleSpace {
                // Birth origins are published after advance; new births in this
                // cadence all share its fixed current origin.
                let origin = space.birthOrigins[particles[index].id] ?? space.currentOrigin
                canonicalPosition = origin + space.scale * particles[index].position
            } else {
                canonicalPosition = particles[index].position
            }
            let relative = canonicalPosition - previousStart
            let weight = (relative.x * axis.x + relative.y * axis.y + relative.z * axis.z)
                / axisLengthSquared
            let delta = startDelta * (1 - weight) + endDelta * weight
            let localDelta = controlPointParticleSpace.map { delta / $0.scale } ?? delta
            let position = particles[index].position
                + localDelta * operatorBlend(blend, normalizedLives[index])
            guard acceptsMotionResult(
                particles[index].velocity, position,
                component: "maintaindistancebetweencontrolpoints"
            ) else { continue }
            particles[index].position = position
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "evaluated", reason: "control-point-distance-result-accepted", time: simulationTime, particleID: particles[index].id)
#endif
        }
    }
}
