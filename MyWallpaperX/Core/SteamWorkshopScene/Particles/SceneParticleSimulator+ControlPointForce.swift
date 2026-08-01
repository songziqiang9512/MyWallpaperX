import Foundation

nonisolated extension SceneParticleSimulator {
    mutating func applyControlPointForce(
        _ value: SceneParticleOperator,
        duration: Double
    ) {
        guard definition.supportsBoundedControlPointForce(value),
              case let .supported(plan) = value.controlPointForceAdmission,
              let target = controlPointPosition(plan.controlPoint, offset: plan.origin)
        else { return }
        for index in particles.indices {
            let delta = target - particles[index].position
            let distance = SceneParticleSimulationMath.length(delta)
            guard distance.isFinite, distance > 1e-12,
                  distance <= plan.maximumDistance else { continue }
            SceneParticleSimulationMath.addFinite(
                delta / distance * plan.acceleration * duration,
                to: &particles[index].velocity
            )
        }
    }

    private func controlPointPosition(
        _ identity: Int,
        offset: SIMD3<Double>
    ) -> SIMD3<Double>? {
        var result = offset
        if let point = definition.controlPoints.first(where: { $0.id == identity }) {
            result += SceneParticleSimulationMath.vector(point.offset, fallback: .zero)
        }
        if let dynamic = dynamicControlPoints[identity] {
            result += dynamic
        } else if let override = instanceOverride?.controlPoints[identity] {
            result += SceneParticleSimulationMath.vector(override.value, fallback: .zero)
        }
        return result.x.isFinite && result.y.isFinite && result.z.isFinite ? result : nil
    }

    func changeFactor(
        _ value: SceneParticleOperator,
        life: Double,
        fallback: (Double, Double)
    ) -> Double {
        let start = SceneParticleSimulationMath.scalar(value.startValue, fallback: fallback.0)
        let end = SceneParticleSimulationMath.scalar(value.endValue, fallback: fallback.1)
        return start + (end - start) * SceneParticleSimulationMath.changeAmount(
            life, value.startTime, value.endTime
        )
    }
}
