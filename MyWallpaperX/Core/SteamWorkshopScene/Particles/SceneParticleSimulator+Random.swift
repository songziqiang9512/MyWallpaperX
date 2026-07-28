import Foundation

extension SceneParticleSimulator {
    nonisolated mutating func randomScalar(
        _ value: SceneParticleInitializer, defaults: (Double, Double)
    ) -> Double {
        random.value(
            SceneParticleSimulationMath.scalar(value.minimum, fallback: defaults.0),
            SceneParticleSimulationMath.scalar(value.maximum, fallback: defaults.1)
        )
    }

    nonisolated mutating func randomVector(
        _ value: SceneParticleInitializer,
        defaults: (SIMD3<Double>, SIMD3<Double>)
    ) -> SIMD3<Double> {
        let minimum = SceneParticleSimulationMath.vector(value.minimum, fallback: defaults.0)
        let maximum = SceneParticleSimulationMath.vector(value.maximum, fallback: defaults.1)
        return SIMD3(
            random.value(minimum.x, maximum.x),
            random.value(minimum.y, maximum.y),
            random.value(minimum.z, maximum.z)
        )
    }

    nonisolated mutating func randomColor(
        _ value: SceneParticleInitializer,
        defaults: (SIMD3<Double>, SIMD3<Double>)
    ) -> SIMD3<Double> {
        let minimum = SceneParticleSimulationMath.vector(value.minimum, fallback: defaults.0)
        let maximum = SceneParticleSimulationMath.vector(value.maximum, fallback: defaults.1)
        return minimum + (maximum - minimum) * random.unit()
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
        let minimum = SceneParticleSimulationMath.vector(emitter.distanceMinimum, fallback: .zero)
        let maximum = SceneParticleSimulationMath.vector(
            emitter.distanceMaximum, fallback: SIMD3(repeating: 256)
        )
        let direction = SceneParticleSimulationMath.vector(
            emitter.directions, fallback: SIMD3(1, 1, 0)
        )
        return SIMD3(
            random.value(minimum.x, maximum.x),
            random.value(minimum.y, maximum.y),
            random.value(minimum.z, maximum.z)
        ) * direction
    }
}
