import Foundation

nonisolated struct SceneParticleOscillationCacheKey: Hashable, Sendable {
    let particleID: UInt64
    let operatorIndex: Int
}

nonisolated struct SceneParticlePositionOscillation: Sendable {
    let frequency: SIMD3<Double>
    let scale: SIMD3<Double>
    let phase: SIMD3<Double>
}

extension SceneParticleSimulator {
    nonisolated mutating func positionOscillation(
        _ value: SceneParticleOperator,
        particleIndex: Int,
        operatorIndex: Int,
        mask: SIMD3<Double>
    ) -> SceneParticlePositionOscillation {
        let key = SceneParticleOscillationCacheKey(
            particleID: particles[particleIndex].id,
            operatorIndex: operatorIndex
        )
        if let cached = positionOscillationCache[key] { return cached }

        let scaleMinimum = SceneParticleSimulationMath.vector(
            value.scaleMinimum, fallback: .zero
        )
        let scaleMaximum = SceneParticleSimulationMath.vector(
            value.scaleMaximum, fallback: SIMD3(repeating: 1)
        )
        var frequency = SIMD3<Double>.zero
        var scale = SIMD3<Double>.zero
        var phase = SIMD3<Double>.zero
        for component in 0..<3 where abs(mask[component]) > 1e-6 {
            frequency[component] = oscillationRandom(
                value.frequencyMinimum ?? 0, value.frequencyMaximum ?? 5,
                particleIndex, operatorIndex, component
            )
            scale[component] = oscillationRandom(
                scaleMinimum[component], scaleMaximum[component],
                particleIndex, operatorIndex, component + 3
            )
            phase[component] = oscillationRandom(
                value.phaseMinimum ?? 0, value.phaseMaximum ?? 2 * .pi,
                particleIndex, operatorIndex, component + 6
            )
        }
        let result = SceneParticlePositionOscillation(
            frequency: frequency, scale: scale, phase: phase
        )
        positionOscillationCache[key] = result
        return result
    }
}
