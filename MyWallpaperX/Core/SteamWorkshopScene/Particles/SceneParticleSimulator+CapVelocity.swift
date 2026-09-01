import Foundation

nonisolated extension SceneParticleSimulator {
    /// Removes the blended fraction of speed above the authored cap without changing
    /// direction. This is a bounded clean-room contract; no Windows numeric golden exists.
    func applyCapVelocity(_ value: SceneParticleOperator) {
        guard let plan = value.capVelocityPlan else { return }
        let speedScale = definition.flags.disablesSpeedOverrides
            ? 1
            : overrideScalar(activeInstanceOverride?.speed)
        let maximumSpeed = plan.maximumSpeed * max(speedScale, 0)
        guard maximumSpeed.isFinite, maximumSpeed <= 1_000_000 else { return }
        let blendPlan = SceneParticleOperatorBlendPlan(value)

        for index in particles.indices {
            let velocity = particles[index].velocity
            let speed = SceneParticleSimulationMath.length(velocity)
            guard speed.isFinite, speed > maximumSpeed, speed > 1e-12 else { continue }
            let life = min(max(
                particles[index].age / max(particles[index].lifetime, 1e-12), 0
            ), 1)
            let blend = operatorBlend(blendPlan, life)
            let target = velocity / speed * maximumSpeed
            let result = velocity + (target - velocity) * blend
            guard result.x.isFinite, result.y.isFinite, result.z.isFinite else { continue }
            particles[index].velocity = result
        }
    }
}
