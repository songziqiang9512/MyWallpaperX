import Foundation

extension SceneParticleSimulator {
    nonisolated var effectiveCountOverride: Double {
        definition.flags.disablesCountOverrides ? 1 : max(0, overrideScalar(activeInstanceOverride?.count))
    }

    nonisolated var effectiveSpeedOverride: Double {
        definition.flags.disablesSpeedOverrides ? 1 : overrideScalar(activeInstanceOverride?.speed)
    }

    nonisolated var effectiveSizeOverride: Double {
        definition.flags.disablesSizeOverrides ? 1 : overrideScalar(activeInstanceOverride?.size)
    }

    nonisolated func applyInstanceOverride(to particle: inout SceneParticleState) {
        guard let value = activeInstanceOverride else { return }
        let flags = definition.flags
        if !flags.disablesLifetimeOverrides {
            particle.lifetime *= overrideScalar(value.lifetime)
        }
        particle.alpha *= overrideScalar(value.alpha)
        particle.size *= effectiveSizeOverride
        let speed = effectiveSpeedOverride
        particle.velocity *= speed
        particle.angularVelocity *= speed
        if !flags.disablesColorOverrides {
            if let color = overrideVector(value.color) {
                particle.color = color / 255
            } else if let color = overrideVector(value.normalizedColor) {
                particle.color = color
            }
            if let brightness = value.brightness {
                particle.color *= overrideScalar(brightness)
            }
        }
    }

    nonisolated func overrideScalar(_ value: SceneParticleBoundValue?) -> Double {
        let result = SceneParticleSimulationMath.scalar(value?.value, fallback: 1)
        return result.isFinite ? result : 1
    }

    nonisolated func overrideVector(_ value: SceneParticleBoundValue?) -> SIMD3<Double>? {
        guard value?.value != nil else { return nil }
        return SceneParticleSimulationMath.vector(value?.value, fallback: .zero)
    }
}
