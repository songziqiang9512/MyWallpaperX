import Foundation
import simd

nonisolated struct SceneParticleCollisionBoundsFrame {
    let extent: SIMD2<Double>
    let origin: SIMD2<Double>
    let localToCanvas: simd_double2x2
    let canvasToLocal: simd_double2x2

    init?(extent: SIMD2<Float>, worldFrame: simd_float4x4) {
        let (x, y, z, translation) = worldFrame.columns
        guard extent.x.isFinite, extent.y.isFinite, extent.x > 0, extent.y > 0,
              x.z == 0, y.z == 0, z.x == 0, z.y == 0,
              translation.x.isFinite, translation.y.isFinite else { return nil }
        let a = SIMD2(Double(x.x), Double(x.y))
        // Match the local Y reflection in the particle draw model.
        let b = -SIMD2(Double(y.x), Double(y.y))
        let determinant = a.x * b.y - a.y * b.x
        guard determinant.isFinite, determinant != 0 else { return nil }
        self.extent = SIMD2(Double(extent.x), Double(extent.y))
        origin = SIMD2(Double(translation.x), Double(translation.y))
        localToCanvas = simd_double2x2(a, b)
        canvasToLocal = simd_double2x2(SIMD2(b.y, -a.y) / determinant,
                                       SIMD2(-b.x, a.x) / determinant)
    }
}

extension SceneParticleSimulator {
    nonisolated func applyCollisionBounds(_ frame: SceneParticleCollisionBoundsFrame) {
        for index in particles.indices {
            let localPosition = particles[index].position
            let canvasPosition = frame.origin + frame.localToCanvas
                * SIMD2(localPosition.x, localPosition.y)
            let clamped = simd_clamp(canvasPosition, .zero, frame.extent)
            guard clamped != canvasPosition else { continue }

            let localVelocity = particles[index].velocity
            let canvasVelocity = frame.localToCanvas * SIMD2(localVelocity.x, localVelocity.y)
            var impulse = SIMD2<Double>.zero
            for axis in 0..<2 where (clamped[axis] - canvasPosition[axis]) * canvasVelocity[axis] < 0 {
                impulse[axis] = -1.5 * canvasVelocity[axis]
            }
            let projectedPosition = frame.canvasToLocal * (clamped - frame.origin)
            let localImpulse = frame.canvasToLocal * impulse
            let position = SIMD3(projectedPosition.x, projectedPosition.y, localPosition.z)
            let velocity = localVelocity + SIMD3(localImpulse.x, localImpulse.y, 0)
            guard acceptsMotionResult(velocity, position, component: "collisionbounds") else { continue }
            particles[index].position = position
            particles[index].velocity = velocity
#if DEBUG
            if let operatorIndex = componentObservation?.activeOperatorIndex {
                componentObservation?.record("operator", operatorIndex, "evaluated",
                    reason: "canvas-contact-applied", time: simulationTime, particleID: particles[index].id)
            }
#endif
        }
    }

    nonisolated func applyCollisionPlane(
        plan: SceneParticleCollisionPlanePlan?,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace? = nil
    ) {
        guard let plan else { return }
        for index in particles.indices {
            let offset = positionReferenceOffset(for: particles[index], space: controlPointParticleSpace)
            let signedDistance = dot(particles[index].position - offset, plan.normal)
                - plan.distance
            guard signedDistance.isFinite, signedDistance < 0 else { continue }

            let correctedPosition = particles[index].position
                - plan.normal * signedDistance
            guard isFinite(correctedPosition) else { continue }
            particles[index].position = correctedPosition

            let normalSpeed = dot(particles[index].velocity, plan.normal)
            guard normalSpeed.isFinite, normalSpeed < 0 else { continue }
            let reflectedVelocity = particles[index].velocity
                - plan.normal * ((1 + plan.bounceFactor) * normalSpeed)
            if isFinite(reflectedVelocity) {
                particles[index].velocity = reflectedVelocity
            }
        }
    }

    nonisolated func applyCollisionSphere(
        plan: SceneParticleCollisionSpherePlan?,
        blend: SceneParticleOperatorBlendPlan,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace?
    ) {
        guard let plan else { return }
        for index in particles.indices {
            let particle = particles[index]
            let center = plan.origin + positionReferenceOffset(
                for: particle, space: controlPointParticleSpace
            )
            let delta = particle.position - center
            let distance = SceneParticleSimulationMath.length(delta)
            guard distance > 0, distance < plan.radius else { continue }

            let amount = operatorBlend(blend, normalizedLives[index])
            guard amount > 0 else { continue }
            let normal = delta / distance
            let position = particle.position
                + (center + normal * plan.radius - particle.position) * amount
            let normalSpeed = dot(particle.velocity, normal)
            let velocity = normalSpeed < 0
                ? particle.velocity - normal * ((1 + plan.bounceFactor) * normalSpeed * amount)
                : particle.velocity
            guard acceptsMotionResult(velocity, position, component: "collisionsphere") else {
                continue
            }
            particles[index].position = position
            particles[index].velocity = velocity
#if DEBUG
            if let operatorIndex = componentObservation?.activeOperatorIndex {
                componentObservation?.record("operator", operatorIndex, "evaluated", reason: "sphere-contact-applied", time: simulationTime, particleID: particle.id)
            }
#endif
        }
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
