import Foundation

nonisolated extension SceneParticleSimulator {
    func applyControlPointForce(
        plan: SceneParticleControlPointForcePlan?,
        duration: Double,
        normalizedLives: [Double],
        blend: SceneParticleOperatorBlendPlan
    ) {
        guard let plan,
              let target = controlPointPosition(plan.controlPoint, offset: plan.origin),
              normalizedLives.count == particles.count
        else { return }
        for index in particles.indices {
            let delta = target - particles[index].position
            let distance = SceneParticleSimulationMath.length(delta)
            guard distance.isFinite, distance > 1e-12,
                  distance <= plan.maximumDistance else { continue }
            SceneParticleSimulationMath.addFinite(
                delta / distance * plan.acceleration * duration
                    * operatorBlend(blend, normalizedLives[index]),
                to: &particles[index].velocity
            )
        }
    }

    func controlPointPosition(
        _ identity: Int,
        offset: SIMD3<Double>
    ) -> SIMD3<Double>? {
        var result = offset
        let point: SceneParticleControlPoint?
        if controlPointsByID.isEmpty {
            point = definition.controlPoints.first(where: { $0.id == identity })
        } else {
            point = controlPointsByID[identity]
        }
        if let point {
            result += SceneParticleSimulationMath.vector(point.offset, fallback: .zero)
            // Pointer-linked control points have no authored static position. A missing
            // or outside pointer must disable the bounded consumer instead of mapping
            // particles to the system origin.
            if point.hasBoundedPointerInput {
                guard let dynamic = dynamicControlPoints[identity], dynamic.isFinite else {
                    return nil
                }
                result += dynamic
                return result.isFinite ? result : nil
            }
        }
        if let dynamic = dynamicControlPoints[identity] {
            result += dynamic
        } else if let override = activeInstanceOverride?.controlPoints[identity] {
            result += SceneParticleSimulationMath.vector(override.value, fallback: .zero)
        }
        return result.x.isFinite && result.y.isFinite && result.z.isFinite ? result : nil
    }
}

private nonisolated extension SIMD3 where Scalar == Double {
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
