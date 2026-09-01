import Foundation

extension SceneParticleSimulator {
    nonisolated func applyInitializers(to particle: inout SceneParticleState) {
        for initializer in definition.initializers {
            switch initializer.kind {
            case .lifetime:
                particle.lifetime = randomScalar(initializer, defaults: (0, 1))
            case .size:
                particle.size = randomScalar(initializer, defaults: (0, 20))
            case .velocity:
                // Wallpaper Engine initializes both authored velocity vectors to zero before
                // reading the optional `min` and `max` fields. Keep a missing endpoint at that
                // public engine default; inventing a symmetric range changes one-sided authored
                // profiles such as `max: "0 100 0"` into bidirectional motion.
                particle.velocity += randomVector(
                    initializer,
                    defaults: (.zero, .zero)
                )
            case .color:
                particle.color = randomColor(
                    initializer, defaults: (.zero, SIMD3(repeating: 255))
                ) / 255
            case .hsvColor:
                if let color = randomHSVColor(initializer) { particle.color = color }
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
            case .positionAroundControlPoint:
                applyPositionAroundControlPoint(initializer, to: &particle)
            case let .inheritEventColor(declaration):
                if declaration.isBoundedSetColor,
                   let color = eventColorContext.initializerColor {
                    particle.color = color
                }
            case .unsupported:
                break
            }
        }
    }

}
