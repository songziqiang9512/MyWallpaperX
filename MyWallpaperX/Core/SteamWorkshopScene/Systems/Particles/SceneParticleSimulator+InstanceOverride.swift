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
            if let preparedInstanceColor {
                particle.color = preparedInstanceColor
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

    nonisolated static func prepareInstanceColor(
        _ instanceOverride: SceneParticleInstanceOverride?, legacy: Bool
    ) -> SIMD3<Double>? {
        let color: SIMD3<Double>
        if let raw = instanceOverride?.color?.value {
            color = SceneParticleSimulationMath.vector(raw, fallback: .zero) / 255
        } else if let normalized = instanceOverride?.normalizedColor?.value {
            color = SceneParticleSimulationMath.vector(normalized, fallback: .zero)
        } else {
            return nil
        }
        guard color.x >= 0, color.y >= 0, color.z >= 0 else { return nil }
        return legacy ? color * color : color
    }
}
