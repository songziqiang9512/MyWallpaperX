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
            guard vortexOriginIsActive else { return }
            center = .zero
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
            var velocity = particles[index].velocity
            if plan.maintainsRadius {
                velocity -= radial / radialLength * dot(velocity, radial / radialLength)
            }
            velocity += acceleration * duration
            guard SceneParticleSimulationMath.isGPUFinite(velocity) else { continue }
            particles[index].velocity = velocity
            if plan.maintainsRadius && particles[index].vortexRadius == nil {
                particles[index].vortexRadius = radialLength
            }
        }
    }

    /// Shared dynamic admission for the force and the preceding Movement.
    var vortexOriginIsActive: Bool {
        let angle = activeInstanceOverride?.controlPointAngles[0]?.value
        return (dynamicControlPointAngles[0] ?? .zero) == .zero
            && (angle == nil || angle == .vector([0, 0, 0]))
            && controlPointPosition(0, offset: .zero) == .zero
    }

    /// Movement remains the only position integrator. Exact rotation avoids
    /// the energy/radius drift of Euler centripetal acceleration or projection.
    func vortexMovement(
        particle: SceneParticleState, velocity: SIMD3<Double>, duration: Double
    ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        guard let radius = particle.vortexRadius else {
            return (particle.position + velocity * duration, velocity)
        }
        let radial = SIMD3(particle.position.x, particle.position.y, 0)
        let length = SceneParticleSimulationMath.length(radial)
        guard length > 1e-12 else { return (particle.position, velocity) }
        let unit = radial / length
        let tangent = SIMD3(unit.y, -unit.x, 0)
        let speed = dot(velocity, tangent)
        let angle = speed * duration / radius
        let nextUnit = unit * cos(angle) + tangent * sin(angle)
        let position = SIMD3(nextUnit.x * radius, nextUnit.y * radius,
                             particle.position.z + velocity.z * duration)
        let nextVelocity = SIMD3(nextUnit.y * speed, -nextUnit.x * speed, velocity.z)
        return (position, nextVelocity)
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
