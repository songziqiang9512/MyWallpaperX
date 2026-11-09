import Foundation

extension SceneParticleSimulator {
    /// Executes an already admitted authored plan. The dynamic control-point
    /// value is still resolved for this frame by the single simulator owner.
    nonisolated func applyPositionAroundControlPoint(
        _ plan: SceneParticlePositionAroundControlPointPlan,
        to particle: inout SceneParticleState
    ) -> Bool {
        guard let target = controlPointPosition(plan.controlPoint, offset: .zero)
        else { return false }

        let relative = particle.position - target
        let axialDistance = dot(relative, plan.axis)
        let radial = relative - plan.axis * axialDistance
        let radius = SceneParticleSimulationMath.length(radial)
        guard radius.isFinite else { return false }

        let sequence = plan.sequence(particleID: particle.id)
        let phase = plan.bounds.lowerBound
            + (plan.bounds.upperBound - plan.bounds.lowerBound) * sequence
        let angle = phase * 2 * Double.pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let radialDirection = plan.circleBasisU * cosine + plan.circleBasisV * sine
        let tangentDirection = plan.circleBasisV * cosine - plan.circleBasisU * sine
        let mappedPosition = target + plan.axis * axialDistance + radialDirection * radius
        let sampledSpeed = SIMD3(
            random.value(plan.speedMinimum.x, plan.speedMaximum.x),
            random.value(plan.speedMinimum.y, plan.speedMaximum.y),
            random.value(plan.speedMinimum.z, plan.speedMaximum.z)
        )
        let rotatedSpeed = tangentDirection * sampledSpeed.x
            + radialDirection * sampledSpeed.y + plan.axis * sampledSpeed.z
        guard isFinite(mappedPosition), isFinite(rotatedSpeed) else { return false }
        particle.position = mappedPosition
        particle.velocity += rotatedSpeed
        return true
    }

    private nonisolated func dot(
        _ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>
    ) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private nonisolated func isFinite(_ value: SIMD3<Double>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
