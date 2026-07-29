import Foundation

extension SceneParticleSimulator {
    nonisolated mutating func randomScalar(
        _ value: SceneParticleInitializer, defaults: (Double, Double)
    ) -> Double {
        randomValue(
            SceneParticleSimulationMath.scalar(value.minimum, fallback: defaults.0),
            SceneParticleSimulationMath.scalar(value.maximum, fallback: defaults.1),
            exponent: value.exponent
        )
    }

    nonisolated mutating func randomVector(
        _ value: SceneParticleInitializer,
        defaults: (SIMD3<Double>, SIMD3<Double>)
    ) -> SIMD3<Double> {
        let minimum = SceneParticleSimulationMath.vector(value.minimum, fallback: defaults.0)
        let maximum = SceneParticleSimulationMath.vector(value.maximum, fallback: defaults.1)
        return SIMD3(
            randomValue(minimum.x, maximum.x, exponent: value.exponent),
            randomValue(minimum.y, maximum.y, exponent: value.exponent),
            randomValue(minimum.z, maximum.z, exponent: value.exponent)
        )
    }

    nonisolated mutating func randomColor(
        _ value: SceneParticleInitializer,
        defaults: (SIMD3<Double>, SIMD3<Double>)
    ) -> SIMD3<Double> {
        let minimum = SceneParticleSimulationMath.vector(value.minimum, fallback: defaults.0)
        let maximum = SceneParticleSimulationMath.vector(value.maximum, fallback: defaults.1)
        return minimum + (maximum - minimum) * randomFactor(exponent: value.exponent)
    }

    private nonisolated mutating func randomValue(
        _ first: Double,
        _ second: Double,
        exponent: Double?
    ) -> Double {
        let lower = min(first, second)
        return lower + randomFactor(exponent: exponent) * (max(first, second) - lower)
    }

    private nonisolated mutating func randomFactor(exponent: Double?) -> Double {
        let factor = random.unit()
        guard let exponent, exponent.isFinite, exponent >= 0 else { return factor }
        return pow(factor, exponent)
    }

    nonisolated func turbulenceRandom(
        _ first: Double, _ second: Double, _ index: Int, _ operatorIndex: Int, _ salt: Int
    ) -> Double {
        var state = simulationSeed ^ (particles[index].id &* 0x9E3779B97F4A7C15)
        state ^= UInt64(operatorIndex &* 31 &+ salt) &* 0xBF58476D1CE4E5B9
        var generator = SceneParticleRandomGenerator(state: state)
        return generator.value(first, second)
    }

    nonisolated mutating func randomSphereOffset(
        _ emitter: SceneParticleEmitter
    ) -> SIMD3<Double> {
        let directions = SceneParticleSimulationMath.vector(
            emitter.directions, fallback: SIMD3(1, 1, 0)
        )
        var unit = SIMD3<Double>.zero
        var foundDirection = false
        for _ in 0..<8 {
            unit = SIMD3(random.value(-1, 1), random.value(-1, 1), random.value(-1, 1))
            for component in 0..<3 where abs(directions[component]) <= 1e-6 {
                unit[component] = 0
            }
            let length = SceneParticleSimulationMath.length(unit)
            if length > 1e-6, length <= 1 {
                unit /= length
                foundDirection = true
                break
            }
        }
        if !foundDirection { unit = SIMD3(1, 0, 0) }
        let dimensions = max((0..<3).filter { abs(directions[$0]) > 1e-6 }.count, 1)
        let minimum = max(
            0, SceneParticleSimulationMath.scalar(emitter.distanceMinimum, fallback: 0)
        )
        let maximum = max(
            minimum,
            SceneParticleSimulationMath.scalar(emitter.distanceMaximum, fallback: 256)
        )
        let radius = pow(
            random.value(pow(minimum, Double(dimensions)), pow(maximum, Double(dimensions))),
            1 / Double(dimensions)
        )
        var absoluteDirections = directions
        for component in 0..<3 { absoluteDirections[component] = abs(absoluteDirections[component]) }
        var result = unit * absoluteDirections * radius
        let sign = SceneParticleSimulationMath.vector(emitter.sign, fallback: .zero)
        for component in 0..<3 where abs(sign[component]) > 1e-6 {
            result[component] = abs(result[component]) * (sign[component] < 0 ? -1 : 1)
        }
        return result
    }

    nonisolated mutating func randomBoxOffset(
        _ emitter: SceneParticleEmitter
    ) -> SIMD3<Double> {
        let minimum = SceneParticleSimulationMath.vector(
            emitter.distanceMinimum,
            fallback: .zero
        )
        let maximum = SceneParticleSimulationMath.vector(
            emitter.distanceMaximum, fallback: SIMD3(repeating: 256)
        )
        let direction = SceneParticleSimulationMath.vector(
            emitter.directions, fallback: SIMD3(1, 1, 0)
        )
        return SIMD3(
            randomBoxComponent(minimum.x, maximum.x),
            randomBoxComponent(minimum.y, maximum.y),
            randomBoxComponent(minimum.z, maximum.z)
        ) * direction
    }

    private nonisolated mutating func randomBoxComponent(
        _ rawMinimum: Double,
        _ rawMaximum: Double
    ) -> Double {
        guard rawMinimum.isFinite, rawMaximum.isFinite else { return 0 }
        guard abs(rawMinimum) <= 1e-12 else {
            return random.value(rawMinimum, rawMaximum)
        }
        let outer = abs(rawMaximum)
        guard outer.isFinite, outer > 0 else { return 0 }
        return random.value(-outer, outer)
    }
}
