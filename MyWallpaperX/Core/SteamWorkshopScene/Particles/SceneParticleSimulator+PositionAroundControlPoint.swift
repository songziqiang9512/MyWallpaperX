import Foundation

extension SceneParticleSimulator {
    nonisolated func applyPositionAroundControlPoint(
        _ initializer: SceneParticleInitializer,
        to particle: inout SceneParticleState
    ) {
        guard definition.supportsBoundedPositionAroundControlPoint(initializer),
              let plan = initializer.positionAroundControlPointPlan,
              let target = controlPointPosition(plan.controlPoint, offset: .zero)
        else { return }

        let emitter = definition.emitters[0]
        let relative = emitter.controlPoint == plan.controlPoint
            ? particle.position - target : particle.position
        let axialDistance = dot(relative, plan.axis)
        let radial = relative - plan.axis * axialDistance
        let radius = SceneParticleSimulationMath.length(radial)
        guard radius.isFinite else { return }

        let sequence = Double(particle.id % UInt64(plan.count)) / Double(plan.count)
        let phase = plan.bounds.lowerBound
            + (plan.bounds.upperBound - plan.bounds.lowerBound) * sequence
        let angle = phase * 2 * Double.pi
        guard let basis = circleBasis(axis: plan.axis) else { return }
        let mappedPosition = target + plan.axis * axialDistance
            + (basis.0 * cos(angle) + basis.1 * sin(angle)) * radius
        let sampledSpeed = SIMD3(
            random.value(plan.speedMinimum.x, plan.speedMaximum.x),
            random.value(plan.speedMinimum.y, plan.speedMaximum.y),
            random.value(plan.speedMinimum.z, plan.speedMaximum.z)
        )
        let rotatedSpeed = rotate(sampledSpeed, axis: plan.axis, angle: angle)
        guard isFinite(mappedPosition), isFinite(rotatedSpeed) else { return }
        particle.position = mappedPosition
        particle.velocity += rotatedSpeed
    }

    private nonisolated func circleBasis(
        axis: SIMD3<Double>
    ) -> (SIMD3<Double>, SIMD3<Double>)? {
        let reference = abs(axis.z) > 0.9 ? SIMD3<Double>(0, 1, 0) : .init(0, 0, 1)
        let first = cross(reference, axis)
        let length = SceneParticleSimulationMath.length(first)
        guard length.isFinite, length > 1e-12 else { return nil }
        let unit = first / length
        return (unit, cross(axis, unit))
    }

    private nonisolated func rotate(
        _ value: SIMD3<Double>, axis: SIMD3<Double>, angle: Double
    ) -> SIMD3<Double> {
        value * cos(angle) + cross(axis, value) * sin(angle)
            + axis * dot(axis, value) * (1 - cos(angle))
    }

    private nonisolated func cross(
        _ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>
    ) -> SIMD3<Double> {
        SIMD3(
            lhs.y * rhs.z - lhs.z * rhs.y,
            lhs.z * rhs.x - lhs.x * rhs.z,
            lhs.x * rhs.y - lhs.y * rhs.x
        )
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
