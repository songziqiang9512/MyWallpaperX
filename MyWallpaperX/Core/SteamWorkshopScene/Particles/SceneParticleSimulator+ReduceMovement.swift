import Foundation

nonisolated extension SceneParticleSimulator {
    /// Project-owned fixed-step approximation of the public speed-reduction
    /// contract. It preserves direction and interpolates the authored reduction
    /// linearly between the inner and outer radii.
    func applyReduceMovement(
        _ value: SceneParticleOperator,
        duration: Double
    ) {
        guard duration.isFinite, duration > 0,
              definition.supportsBoundedReduceMovement(value),
              let plan = value.reduceMovementPlan,
              let target = controlPointPosition(plan.controlPoint, offset: .zero) else {
            return
        }
        for index in particles.indices {
            let distance = SceneParticleSimulationMath.length(
                particles[index].position - target
            )
            guard distance.isFinite, distance <= plan.distanceOuter else { continue }
            let reduction: Double
            if distance <= plan.distanceInner || plan.distanceOuter == plan.distanceInner {
                reduction = plan.reductionInner
            } else {
                let amount = (distance - plan.distanceInner)
                    / (plan.distanceOuter - plan.distanceInner)
                reduction = plan.reductionInner
                    + (plan.reductionOuter - plan.reductionInner) * amount
            }
            let velocity = particles[index].velocity
            let speed = SceneParticleSimulationMath.length(velocity)
            guard speed.isFinite, speed > 1e-12 else { continue }
            let reducedSpeed = max(0, speed - reduction * duration)
            guard reducedSpeed.isFinite, reducedSpeed <= 1_000_000 else { continue }
            let result = velocity / speed * reducedSpeed
            guard result.x.isFinite, result.y.isFinite, result.z.isFinite else { continue }
            particles[index].velocity = result
        }
    }
}
