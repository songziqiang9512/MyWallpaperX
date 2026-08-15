import Foundation

nonisolated extension SceneParticleSimulator {
    func applyBoids(_ value: SceneParticleOperator, duration: Double) {
        guard let plan = definition.boidsPlan(for: value), particles.count > 1 else { return }
        let snapshot = particles
        let thresholdSquared = plan.neighborThreshold * plan.neighborThreshold
        for index in snapshot.indices {
            var positionSum = SIMD3<Double>.zero
            var velocitySum = SIMD3<Double>.zero
            var neighborCount = 0
            for neighborIndex in snapshot.indices where neighborIndex != index {
                let offset = snapshot[neighborIndex].position - snapshot[index].position
                let distanceSquared = offset.x * offset.x + offset.y * offset.y
                    + offset.z * offset.z
                guard distanceSquared.isFinite, distanceSquared <= thresholdSquared else { continue }
                positionSum += snapshot[neighborIndex].position
                velocitySum += snapshot[neighborIndex].velocity
                neighborCount += 1
            }
            guard neighborCount > 0 else { continue }
            let divisor = Double(neighborCount)
            let alignment = (velocitySum / divisor - snapshot[index].velocity)
                * plan.alignmentFactor
            let cohesion = (positionSum / divisor - snapshot[index].position)
                * plan.cohesionFactor
            SceneParticleSimulationMath.addFinite(
                (alignment + cohesion) * duration,
                to: &particles[index].velocity
            )
        }
    }
}
