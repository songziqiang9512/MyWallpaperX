import Foundation

nonisolated extension SceneParticleSimulator {
    /// Applies a bounded classic vortex as tangential acceleration in particle-local space.
    /// Positive speed follows the right-hand rule around the authored axis; negative speed
    /// reverses it. This is a project-owned clean-room numeric contract, not a Windows golden.
    func applyVortex(
        _ value: SceneParticleOperator,
        duration: Double
    ) {
        guard let plan = value.vortexPlan else { return }
        let audioScale: Double
        if value.audioResponse.isEnabled {
            guard let audioPlan = SceneParticleAudioResponsePlan(value.audioResponse) else {
                return
            }
            audioScale = audioPlan.evaluate(audioInput)
        } else {
            audioScale = 1
        }
        let speedScale = definition.flags.disablesSpeedOverrides
            ? 1
            : overrideScalar(activeInstanceOverride?.speed)
        guard speedScale.isFinite else { return }

        for index in particles.indices {
            let relative = particles[index].position
            let axial = plan.axis * dot(relative, plan.axis)
            let radial = relative - axial
            let radialLength = SceneParticleSimulationMath.length(radial)
            guard radialLength.isFinite, radialLength > 1e-12 else { continue }
            let distance = plan.usesInfiniteAxis
                ? radialLength
                : SceneParticleSimulationMath.length(relative)
            guard distance.isFinite else { continue }
            let amount = plan.distanceOuter > plan.distanceInner
                ? min(max(
                    (distance - plan.distanceInner)
                        / (plan.distanceOuter - plan.distanceInner),
                    0
                ), 1)
                : 0
            let speed = plan.speedInner + (plan.speedOuter - plan.speedInner) * amount
            let tangent = cross(plan.axis, radial) / radialLength
            SceneParticleSimulationMath.addFinite(
                tangent * speed * speedScale * audioScale * duration,
                to: &particles[index].velocity
            )
        }
    }

    private func dot(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private func cross(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            lhs.y * rhs.z - lhs.z * rhs.y,
            lhs.z * rhs.x - lhs.x * rhs.z,
            lhs.x * rhs.y - lhs.y * rhs.x
        )
    }
}
