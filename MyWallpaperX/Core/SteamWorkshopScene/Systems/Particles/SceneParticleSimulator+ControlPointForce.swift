import Foundation

nonisolated extension SceneParticleSimulator {
    func applyControlPointForce(
        plan: SceneParticleControlPointForcePlan?,
        duration: Double,
        normalizedLives: [Double],
        blend: SceneParticleOperatorBlendPlan
    ) {
        guard let plan,
              let source = controlPointPosition(plan.controlPoint, offset: plan.origin),
              normalizedLives.count == particles.count
        else { return }
        let target: SIMD3<Double>
        switch plan.sourceSpace {
        case .local: target = source
        case .world:
            guard let local = controlPointFrame?.localPosition(worldPoint: source)
            else { return }
            target = local
        }
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

    func controlPointLocalPosition(_ identity: Int) -> SIMD3<Double>? {
        guard controlPointSourcesAreValid,
              let position = controlPointPosition(identity, offset: .zero) else { return nil }
        if (controlPointsByID[identity]?.rawFlags ?? 0) & 2 != 0 {
            return controlPointFrame?.localPosition(worldPoint: position)
        }
        return position
    }

    func controlPointPosition(
        _ identity: Int,
        offset: SIMD3<Double>
    ) -> SIMD3<Double>? {
        let point: SceneParticleControlPoint?
        if controlPointsByID.isEmpty {
            point = definition.controlPoints.first(where: { $0.id == identity })
        } else {
            point = controlPointsByID[identity]
        }
        let dynamic = dynamicControlPoints[identity]
        let instance = dynamic == nil ? activeInstanceOverride?.controlPoints[identity] : nil
        guard let position = SceneParticleSimulationMath.resolvedControlPointPosition(
            authored: SceneParticleSimulationMath.vector(point?.offset, fallback: .zero),
            dynamic: dynamic,
            instance: (instance?.value).map { SceneParticleSimulationMath.vector($0, fallback: .zero) },
            followsPointer: point?.followsPointer == true,
            requiresPointerValue: point?.hasBoundedPointerInput == true
        ) else { return nil }
        let result = offset + position
        return result.isFinite ? result : nil
    }
}

private nonisolated extension SIMD3 where Scalar == Double {
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
