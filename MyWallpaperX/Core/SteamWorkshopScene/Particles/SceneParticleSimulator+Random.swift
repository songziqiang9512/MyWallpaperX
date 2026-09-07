import Foundation

extension SceneParticleSimulator {
    nonisolated func randomScalar(
        _ plan: SceneParticleRandomScalarPlan
    ) -> Double {
        randomValue(plan.minimum, plan.maximum, exponent: plan.exponent)
    }

    nonisolated func randomVector(
        _ plan: SceneParticleRandomVectorPlan
    ) -> SIMD3<Double> {
        return SIMD3(
            randomValue(plan.minimum.x, plan.maximum.x, exponent: plan.exponent),
            randomValue(plan.minimum.y, plan.maximum.y, exponent: plan.exponent),
            randomValue(plan.minimum.z, plan.maximum.z, exponent: plan.exponent)
        )
    }

    nonisolated func randomColor(
        _ plan: SceneParticleRandomColorPlan
    ) -> SIMD3<Double> {
        return plan.minimum
            + (plan.maximum - plan.minimum) * randomFactor(exponent: plan.exponent)
    }

    nonisolated func randomColorFromList(
        _ colors: [SIMD3<Double>]
    ) -> SIMD3<Double>? {
        let index = min(Int(random.unit() * Double(colors.count)), colors.count - 1)
        return colors[index]
    }

    nonisolated func randomHSVColor(
        _ plan: SceneParticleHSVColorPlan
    ) -> SIMD3<Double>? {
        let hueIndex = min(
            Int(random.unit() * Double(plan.hueSteps)), plan.hueSteps - 1
        )
        let hue = plan.hue.lowerBound
            + (plan.hue.upperBound - plan.hue.lowerBound)
                * Double(hueIndex) / Double(plan.hueSteps)
        let saturation = random.value(
            plan.saturation.lowerBound, plan.saturation.upperBound
        )
        let brightness = random.value(plan.value.lowerBound, plan.value.upperBound)
        return SceneParticleSimulationMath.hsvToRGB(
            hue: hue, saturation: saturation, value: brightness
        )
    }

    private nonisolated func randomValue(
        _ first: Double,
        _ second: Double,
        exponent: Double?
    ) -> Double {
        let lower = min(first, second)
        return lower + randomFactor(exponent: exponent) * (max(first, second) - lower)
    }

    private nonisolated func randomFactor(exponent: Double?) -> Double {
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

    nonisolated func randomSphereOffset(
        _ plan: SceneParticleEmitterSpawnPlan
    ) -> SIMD3<Double> {
        let directions = plan.directions
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
        let minimum = plan.sphereDistanceMinimum
        let maximum = plan.sphereDistanceMaximum
        let radius = pow(
            random.value(pow(minimum, Double(dimensions)), pow(maximum, Double(dimensions))),
            1 / Double(dimensions)
        )
        var absoluteDirections = directions
        for component in 0..<3 { absoluteDirections[component] = abs(absoluteDirections[component]) }
        var result = unit * absoluteDirections * radius
        let sign = plan.sign
        for component in 0..<3 where abs(sign[component]) > 1e-6 {
            result[component] = abs(result[component]) * (sign[component] < 0 ? -1 : 1)
        }
        return result
    }

    nonisolated func randomBoxOffset(
        _ plan: SceneParticleEmitterSpawnPlan
    ) -> SIMD3<Double> {
        let minimum = plan.boxDistanceMinimum
        let maximum = plan.boxDistanceMaximum
        let direction = plan.directions
        return SIMD3(
            randomBoxComponent(minimum.x, maximum.x),
            randomBoxComponent(minimum.y, maximum.y),
            randomBoxComponent(minimum.z, maximum.z)
        ) * direction
    }

    private nonisolated func randomBoxComponent(
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

extension SceneParticleSimulationMath {
    nonisolated static func hsvToRGB(
        hue: Double, saturation: Double, value: Double
    ) -> SIMD3<Double> {
        let wrappedHue = hue - floor(hue)
        let chroma = value * saturation
        let sector = wrappedHue * 6
        let intermediate = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let primary: SIMD3<Double> = switch Int(floor(sector)) % 6 {
        case 0: SIMD3(chroma, intermediate, 0)
        case 1: SIMD3(intermediate, chroma, 0)
        case 2: SIMD3(0, chroma, intermediate)
        case 3: SIMD3(0, intermediate, chroma)
        case 4: SIMD3(intermediate, 0, chroma)
        default: SIMD3(chroma, 0, intermediate)
        }
        return primary + SIMD3(repeating: value - chroma)
    }
}
