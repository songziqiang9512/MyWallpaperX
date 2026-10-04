import Foundation

nonisolated extension SceneParticleSimulator {
    /// Both admitted author versions accelerate clockwise around positive Z.
    /// The prepared plan owns version-specific units; Movement integrates position.
    func applyVortex(
        plan: SceneParticleVortexPlan?,
        duration: Double,
        audioScale: Double?
    ) {
        guard let plan else { return }
        let audioScale = audioScale ?? 1
        let speedScale = effectiveSpeedOverride
        guard speedScale.isFinite else { return }
        let center: SIMD3<Double>
        if plan.usesControlPointOrigin {
            let angle = activeInstanceOverride?.controlPointAngles[0]?.value
            guard (dynamicControlPointAngles[0] ?? .zero) == .zero,
                  angle == nil || angle == .vector([0, 0, 0]),
                  let position = controlPointPosition(0, offset: .zero),
                  position == .zero else { return }
            center = position
        } else {
            center = .zero
        }

        for index in particles.indices {
            let relative = particles[index].position - center
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
            let acceleration = tangent * speed * speedScale * audioScale
            SceneParticleSimulationMath.addFinite(
                acceleration * duration,
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
