import Foundation

nonisolated extension SceneParticleSimulator {
    /// Applies a bounded classic vortex as tangential acceleration in particle-local space.
    /// Positive speed turns clockwise around positive Z in the author XY plane,
    /// matching the fixed-client direction control; negative speed reverses it.
    /// Acceleration magnitude and integration remain project-owned, not a Windows golden.
    func applyVortex(
        plan: SceneParticleVortexPlan?,
        duration: Double,
        audioScale: Double?
    ) {
        guard let plan else { return }
        let audioScale = audioScale ?? 1
        let speedScale = effectiveSpeedOverride
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
            let tangent = cross(radial, plan.axis) / radialLength
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
