import Foundation

extension SceneParticleSimulator {
    nonisolated mutating func applyInitializers(to particle: inout SceneParticleState) {
        for initializer in definition.initializers {
            switch initializer.kind {
            case .lifetime:
                particle.lifetime = randomScalar(initializer, defaults: (0, 1))
            case .size:
                particle.size = randomScalar(initializer, defaults: (0, 20))
            case .velocity:
                particle.velocity += randomVector(
                    initializer,
                    defaults: (SIMD3(-32, -32, 0), SIMD3(32, 32, 0))
                )
            case .color:
                particle.color = randomColor(
                    initializer, defaults: (.zero, SIMD3(repeating: 255))
                ) / 255
            case .colorList:
                if let color = randomColorFromList(initializer) { particle.color = color }
            case .alpha:
                particle.alpha = randomScalar(initializer, defaults: (0.05, 1))
            case .rotation:
                particle.rotation += randomVector(
                    initializer, defaults: (.zero, SIMD3(0, 0, 2 * .pi))
                )
            case .angularVelocity:
                particle.angularVelocity += randomVector(
                    initializer, defaults: (SIMD3(0, 0, -5), SIMD3(0, 0, 5))
                )
            case .turbulentVelocity:
                particle.velocity += SceneParticleSimulationMath.turbulentVelocity(
                    initializer.turbulentVelocity, particle.position, simulationTime,
                    &random, audioInput: audioInput
                )
            case .positionOffset:
                if let plan = initializer.boundedPositionOffset {
                    SceneParticleSimulationMath.addFinite(
                        SceneParticleSimulationMath.positionOffset(
                            plan, position: particle.position, time: simulationTime,
                            particleID: particle.id, simulationSeed: simulationSeed
                        ),
                        to: &particle.position
                    )
                }
            case .unsupported:
                break
            }
        }
    }
}
