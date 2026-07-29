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
    nonisolated func oscillationFactor(
        _ value: SceneParticleOperator,
        _ index: Int,
        _ operatorIndex: Int,
        life: Double,
        sizeDefaults: Bool = false
    ) -> Double {
        let minimum = SceneParticleSimulationMath.scalar(
            value.scaleMinimum,
            fallback: sizeDefaults ? 0.8 : 0
        )
        let maximum = SceneParticleSimulationMath.scalar(
            value.scaleMaximum,
            fallback: sizeDefaults ? 1.2 : 1
        )
        let frequency = oscillationRandom(
            value.frequencyMinimum ?? 0,
            value.frequencyMaximum ?? 10,
            index,
            operatorIndex,
            0
        )
        let phase = oscillationRandom(
            value.phaseMinimum ?? 0,
            value.phaseMaximum ?? 2 * .pi,
            index,
            operatorIndex,
            1
        )
        let wave = (cos(2 * .pi * frequency * life + phase) + 1) * 0.5
        return minimum + (maximum - minimum) * wave
    }

    nonisolated func oscillationBlend(
        _ value: SceneParticleOperator,
        _ life: Double
    ) -> Double {
        var result = 1.0
        if value.blendInStart != nil || value.blendInEnd != nil {
            result *= SceneParticleSimulationMath.changeAmount(
                life,
                value.blendInStart ?? 0,
                value.blendInEnd ?? 0
            )
        }
        if value.blendOutStart != nil || value.blendOutEnd != nil {
            result *= 1 - SceneParticleSimulationMath.changeAmount(
                life,
                value.blendOutStart ?? 1,
                value.blendOutEnd ?? 1
            )
        }
        return result
    }

    nonisolated func oscillationRandom(
        _ first: Double,
        _ second: Double,
        _ index: Int,
        _ operatorIndex: Int,
        _ salt: Int
    ) -> Double {
        var state = particles[index].id &* 0x9E3779B97F4A7C15
        state ^= UInt64(operatorIndex &* 31 &+ salt) &* 0xBF58476D1CE4E5B9
        var generator = SceneParticleRandomGenerator(state: state)
        return generator.value(first, second)
    }

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
