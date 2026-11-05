import Foundation

nonisolated struct SceneParticleControlPointEndpoints: Equatable, Sendable {
    let start: SIMD3<Double>
    let end: SIMD3<Double>
}

nonisolated struct SceneParticleControlPointParticleSpace: Sendable {
    let currentOrigin: SIMD3<Double>
    let scale: SIMD3<Double>
    let birthOrigins: [UInt64: SIMD3<Double>]
}

nonisolated extension SceneParticleSimulator {
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
            controlPointDistanceHistory[operatorIndex] = nil
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "unavailable", reason: "control-point-endpoints-unavailable", time: simulationTime)
#endif
            return
        }
        let current: SceneParticleControlPointEndpoints
        if let space = controlPointParticleSpace {
            current = .init(start: space.currentOrigin + space.scale * start,
                            end: space.currentOrigin + space.scale * end)
        } else {
            let offset = referencePositionOffset
            current = .init(start: start + offset, end: end + offset)
        }
        let previous = controlPointDistanceHistory[operatorIndex]
        // Advance once per operator, including empty and newly born cohorts.
        controlPointDistanceHistory[operatorIndex] = current
        guard let previous else {
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "not-triggered", reason: "control-point-history-initialized", time: simulationTime)
#endif
            return
        }
        guard current != previous else { return }
        let axis = previous.end - previous.start
        let axisLengthSquared = axis.x * axis.x + axis.y * axis.y + axis.z * axis.z
        guard axisLengthSquared.isFinite, axisLengthSquared > 0 else {
#if DEBUG
            componentObservation?.record("operator", operatorIndex, "not-triggered", reason: "control-point-axis-degenerate", time: simulationTime)
#endif
            return
        }
        let startDelta = current.start - previous.start
        let endDelta = current.end - previous.end
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
            let relative = canonicalPosition - previous.start
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
