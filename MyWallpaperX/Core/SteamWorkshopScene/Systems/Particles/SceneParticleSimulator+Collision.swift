import Foundation

extension SceneParticleSimulator {
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
