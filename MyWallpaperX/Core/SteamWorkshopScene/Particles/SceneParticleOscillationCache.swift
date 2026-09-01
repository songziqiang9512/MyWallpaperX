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

nonisolated struct SceneParticleOperatorBlendPlan: Sendable {
    let hasBlendIn: Bool
    let blendInStart: Double
    let blendInEnd: Double
    let hasBlendOut: Bool
    let blendOutStart: Double
    let blendOutEnd: Double

    nonisolated init(_ value: SceneParticleOperator) {
        hasBlendIn = value.blendInStart != nil || value.blendInEnd != nil
        blendInStart = value.blendInStart ?? 0
        blendInEnd = value.blendInEnd ?? 0
        hasBlendOut = value.blendOutStart != nil || value.blendOutEnd != nil
        blendOutStart = value.blendOutStart ?? 1
        blendOutEnd = value.blendOutEnd ?? 1
    }
}

nonisolated struct SceneParticlePositionOscillationPlan: Sendable {
    let frequencyMinimum: Double
    let frequencyMaximum: Double
    let scaleMinimum: SIMD3<Double>
    let scaleMaximum: SIMD3<Double>
    let phaseMinimum: Double
    let phaseMaximum: Double

    nonisolated init(_ value: SceneParticleOperator) {
        frequencyMinimum = value.frequencyMinimum ?? 0
        frequencyMaximum = value.frequencyMaximum ?? 5
        scaleMinimum = SceneParticleSimulationMath.vector(
            value.scaleMinimum, fallback: .zero
        )
        scaleMaximum = SceneParticleSimulationMath.vector(
            value.scaleMaximum, fallback: SIMD3(repeating: 1)
        )
        phaseMinimum = value.phaseMinimum ?? 0
        phaseMaximum = value.phaseMaximum ?? 2 * .pi
    }
}

extension SceneParticleSimulator {
    nonisolated func oscillationFactor(
        _ value: SceneParticleOperator,
        _ index: Int,
        _ operatorIndex: Int,
        age: Double,
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
        let wave = (cos(frequency * age + phase) + 1) * 0.5
        return minimum + (maximum - minimum) * wave
    }

    nonisolated func operatorBlend(
        _ value: SceneParticleOperator,
        _ life: Double
    ) -> Double {
        operatorBlend(SceneParticleOperatorBlendPlan(value), life)
    }

    nonisolated func operatorBlend(
        _ plan: SceneParticleOperatorBlendPlan,
        _ life: Double
    ) -> Double {
        var result = 1.0
        if plan.hasBlendIn {
            result *= SceneParticleSimulationMath.changeAmount(
                life,
                plan.blendInStart,
                plan.blendInEnd
            )
        }
        if plan.hasBlendOut {
            result *= 1 - SceneParticleSimulationMath.changeAmount(
                life,
                plan.blendOutStart,
                plan.blendOutEnd
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

    nonisolated func positionOscillation(
        _ plan: SceneParticlePositionOscillationPlan,
        particleIndex: Int,
        operatorIndex: Int,
        mask: SIMD3<Double>
    ) -> SceneParticlePositionOscillation {
        let key = SceneParticleOscillationCacheKey(
            particleID: particles[particleIndex].id,
            operatorIndex: operatorIndex
        )
        if let cached = positionOscillationCache[key] { return cached }

        var frequency = SIMD3<Double>.zero
        var scale = SIMD3<Double>.zero
        var phase = SIMD3<Double>.zero
        for component in 0..<3 where abs(mask[component]) > 1e-6 {
            frequency[component] = oscillationRandom(
                plan.frequencyMinimum, plan.frequencyMaximum,
                particleIndex, operatorIndex, component
            )
            scale[component] = oscillationRandom(
                plan.scaleMinimum[component], plan.scaleMaximum[component],
                particleIndex, operatorIndex, component + 3
            )
            phase[component] = oscillationRandom(
                plan.phaseMinimum, plan.phaseMaximum,
                particleIndex, operatorIndex, component + 6
            )
        }
        let result = SceneParticlePositionOscillation(
            frequency: frequency, scale: scale, phase: phase
        )
        positionOscillationCache[key] = result
        return result
    }

    nonisolated func positionOscillationDelta(
        _ oscillation: SceneParticlePositionOscillation,
        blend: SceneParticleOperatorBlendPlan,
        mask: SIMD3<Double>,
        age: Double,
        lifetime: Double,
        duration: Double
    ) -> SIMD3<Double> {
        let previousAge = max(age - duration, 0)
        let currentLife = min(max(age / max(lifetime, 1e-12), 0), 1)
        let previousLife = min(max(previousAge / max(lifetime, 1e-12), 0), 1)
        let currentBlend = operatorBlend(blend, currentLife)
        let previousBlend = operatorBlend(blend, previousLife)
        var result = SIMD3<Double>.zero
        for component in 0..<3 where abs(mask[component]) > 1e-6 {
            let phase = oscillation.phase[component]
            let frequency = oscillation.frequency[component]
            let baseline = cos(phase)
            let currentWave = cos(frequency * age + phase) - baseline
            let previousWave = cos(frequency * previousAge + phase) - baseline
            result[component] = oscillation.scale[component] * mask[component]
                * (currentWave * currentBlend - previousWave * previousBlend)
        }
        return result
    }
}
