import Foundation

extension SceneParticleSimulator {
    nonisolated func applyInstanceOverride(to particle: inout SceneParticleState) {
        guard let value = instanceOverride else { return }
        particle.lifetime *= overrideScalar(value.lifetime)
        particle.alpha *= overrideScalar(value.alpha)
        particle.size *= overrideScalar(value.size)
        particle.velocity *= overrideScalar(value.speed)
        if let color = overrideVector(value.color) {
            let normalized = color / 255
            particle.color = normalized * normalized
        } else if let color = overrideVector(value.normalizedColor) {
            particle.color = color * color
        }
        particle.color *= overrideScalar(value.brightness)
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
