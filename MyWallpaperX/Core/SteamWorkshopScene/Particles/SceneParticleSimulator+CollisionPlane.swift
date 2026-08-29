import Foundation

extension SceneParticleSimulator {
    nonisolated func applyCollisionPlane(_ value: SceneParticleOperator) {
        guard let plan = value.collisionPlanePlan else { return }
        for index in particles.indices {
            let signedDistance = dot(particles[index].position, plan.normal)
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

    private nonisolated func dot(
        _ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>
    ) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private nonisolated func isFinite(_ value: SIMD3<Double>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
}
