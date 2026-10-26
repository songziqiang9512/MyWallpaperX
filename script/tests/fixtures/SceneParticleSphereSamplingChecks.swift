import Foundation
import simd

nonisolated enum SceneParticleSphereSamplingChecks {
    private static func distribution() throws -> [String: Any] {
        func make(_ directions: SIMD3<Double>, count: Int = 20_000,
                  seed: UInt64 = 52, minimum: Double = 10,
                  maximum: Double = 10, sign: String = "0 0 0",
                  speed: Double = 0, rate: Double = 0, instantaneous: Int? = nil) throws -> SceneParticleSimulator {
            let root: [String: Any] = [
                "material": "p.json", "maxcount": count,
                "emitter": [["name": "sphererandom", "instantaneous": instantaneous ?? count, "rate": rate,
                    "origin": "0 0 0", "directions": "\(directions.x) \(directions.y) \(directions.z)",
                    "sign": sign, "distancemin": minimum, "distancemax": maximum,
                    "speedmin": speed, "speedmax": speed]],
                "initializer": [["name": "lifetimerandom", "min": 10, "max": 10]],
                "renderer": [["name": "sprite"]]
            ]
            let data = try JSONSerialization.data(withJSONObject: root)
            let definition = try SceneParticleDefinitionParser().parse(data: data)
            let simulation = SceneParticleSimulator(definition: definition, seed: seed)
            simulation.advance(by: 1.0 / 60)
            return simulation
        }
        var rows: [[String: Any]] = []
        for mask in 0...7 {
            let directions = SIMD3<Double>(mask & 1 == 0 ? 0 : 1,
                mask & 2 == 0 ? 0 : 1, mask & 4 == 0 ? 0 : 1)
            let simulation = try make(directions)
            var mean = SIMD3<Double>.zero, second = SIMD3<Double>.zero
            var minRadius = Double.infinity, maxRadius = 0.0, axisAtoms = 0
            for particle in simulation.particles {
                let v = particle.position / 10
                let radius = simd_length(v)
                minRadius = min(minRadius, radius); maxRadius = max(maxRadius, radius)
                mean += v; second += v * v
                if (0..<3).filter({ v[$0] != 0 }).count == 1 { axisAtoms += 1 }
            }
            let n = Double(simulation.particles.count)
            rows.append(["mask": mask, "count": simulation.particles.count,
                "minimumRadius": minRadius, "maximumRadius": maxRadius,
                "mean": [mean.x/n, mean.y/n, mean.z/n],
                "secondMoment": [second.x/n, second.y/n, second.z/n], "axisAtoms": axisAtoms])
        }
        let counterexample = try make(SIMD3(0, 1, 1), count: 1, seed: 262085)
        let velocity = try make(SIMD3(0, 1, 1), count: 1, seed: 262085, speed: 7)
        let volume = try make(SIMD3(1, 1, 1), minimum: 2, maximum: 4)
        let volumeFactors = volume.particles.map { (pow(simd_length($0.position), 3) - 8) / 56 }
        let signed = try make(SIMD3(2, 0, 3), count: 128, sign: "-1 0 1")
        let replay = try make(SIMD3(1, 1, 1), count: 20, rate: 60, instantaneous: 1)
        let snapshot = replay.frameSnapshot()
        replay.advance(by: 0.1); let expected = replay.particles
        replay.restoreFrame(snapshot); replay.advance(by: 0.1)
        let again = try make(SIMD3(0, 1, 1), count: 1, seed: 262085)
        return ["rows": rows, "counterexampleRadius": simd_length(counterexample.particles[0].position),
            "counterexampleSpeed": simd_length(velocity.particles[0].velocity),
            "counterexampleRadialSpeed": simd_length(velocity.particles[0].velocity - velocity.particles[0].position * 0.7),
            "volumeFactorMean": volumeFactors.reduce(0,+) / Double(volumeFactors.count),
            "volumeFactorMin": volumeFactors.min()!, "volumeFactorMax": volumeFactors.max()!,
            "signedShell": signed.particles.allSatisfy {
                $0.position.x <= 0 && $0.position.z >= 0 && $0.position.y == 0
                && abs(simd_length($0.position / SIMD3(2, 1, 3)) - 10) < 1e-9
            },
            "deterministic": counterexample.particles == again.particles,
            "rollback": replay.particles == expected && expected.count > 1]
    }


    private struct Input {
        let name: String
        var directions: SIMD3<Double>? = SIMD3(1, 1, 0)
        var sign: SIMD3<Double>? = .zero
        var minimum: Double? = 2
        var maximum: Double? = 4
    }

    static func run() throws -> [String: Any] {
        var result = try distribution()
        var inputs = (0...7).map { mask in
            Input(name: "mask-\(mask)", directions: SIMD3(
                mask & 1 == 0 ? 0 : 1, mask & 2 == 0 ? 0 : 1, mask & 4 == 0 ? 0 : 1))
        }
        let threshold = 1e-6
        inputs += [
            .init(name: "defaults", directions: nil, sign: nil, minimum: nil, maximum: nil),
            .init(name: "below-threshold", directions: SIMD3(threshold.nextDown, 1, 0)),
            .init(name: "at-threshold", directions: SIMD3(threshold, 1, 0)),
            .init(name: "above-threshold", directions: SIMD3(threshold.nextUp, 1, 0)),
            .init(name: "negative-below-threshold", directions: SIMD3(-threshold.nextDown, 0, 1)),
            .init(name: "negative-at-threshold", directions: SIMD3(-threshold, 0, 1)),
            .init(name: "negative-above-threshold", directions: SIMD3(-threshold.nextUp, 0, 1)),
            .init(name: "signed-zero", directions: SIMD3(-0.0, 0.0, -0.0),
                  sign: SIMD3(-0.0, 0.0, -0.0), minimum: -0.0, maximum: 0.0),
            .init(name: "negative-direction-sign", directions: SIMD3(-2, 0, -3), sign: SIMD3(-1, 0, 1)),
            .init(name: "reverse-range", minimum: 8, maximum: 2),
            .init(name: "negative-distance-clamp", minimum: -8, maximum: -2),
            .init(name: "equal-shell", directions: SIMD3(1, 1, 1), minimum: 3, maximum: 3),
            .init(name: "subnormal-shell", directions: SIMD3(1, 0, 0),
                  minimum: .leastNonzeroMagnitude, maximum: .leastNonzeroMagnitude),
            .init(name: "power-overflow", directions: SIMD3(1, 1, 1), minimum: 1e200, maximum: 2e200),
            .init(name: "infinite-maximum", directions: SIMD3(1, 1, 1), minimum: 2, maximum: .infinity),
            .init(name: "nan-minimum", minimum: .nan, maximum: 4),
            .init(name: "nan-maximum", minimum: 2, maximum: .nan),
        ]
        result["oracleRows"] = inputs.map(compareSamples)
        result["birthRows"] = inputs.map(compareBirths)
        return result
    }

    private static func definition(_ input: Input, count: Int) -> SceneParticleDefinition {
        var emitter: [String: Any] = ["name": "sphererandom", "instantaneous": count, "rate": 0,
                                     "speedmin": 0, "speedmax": 0]
        if let v = input.directions { emitter["directions"] = "\(v.x) \(v.y) \(v.z)" }
        if let v = input.sign { emitter["sign"] = "\(v.x) \(v.y) \(v.z)" }
        if let v = input.minimum { emitter["distancemin"] = v }
        if let v = input.maximum { emitter["distancemax"] = v }
        // parse(root:) preserves numeric extremes without asking JSONSerialization
        // to encode non-JSON NaN/Infinity. These remain actual parser inputs.
        return SceneParticleDefinitionParser().parse(root: [
            "material": "p.json", "maxcount": 64, "emitter": [emitter],
            "initializer": [["name": "lifetimerandom", "min": 10, "max": 10]],
            "renderer": [["name": "sprite"]],
        ])
    }

    private static func bits(_ value: SIMD3<Double>) -> [UInt64] {
        [value.x.bitPattern, value.y.bitPattern, value.z.bitPattern]
    }

    private static func sameValues(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Bool {
        (0..<3).allSatisfy {
            (first[$0].isNaN && second[$0].isNaN) || first[$0].bitPattern == second[$0].bitPattern
        }
    }

    private static func compareSamples(_ input: Input) -> [String: Any] {
        let definition = definition(input, count: 0)
        let emitter = definition.emitters[0]
        let simulator = SceneParticleSimulator(definition: definition, seed: 52)
        let plan = SceneParticleEmitterSpawnPlan(emitter)
        var reference = simulator.random, expectedDraws = simulator.random
        let beforeID = simulator.frameSnapshot().nextParticleID
        var matches = true, statesMatch = true, nonfiniteValues = 0
        var firstMismatch: [String: Any] = [:]
        for index in 0..<64 {
            let expected = originalOffset(emitter, random: &reference)
            let actual = simulator.randomSphereOffset(plan)
            let same = sameValues(actual, expected)
            if !same && firstMismatch.isEmpty {
                firstMismatch = ["sample": index, "actual": bits(actual), "expected": bits(expected)]
            }
            matches = matches && same
            statesMatch = statesMatch && simulator.random.state == reference.state
            nonfiniteValues += (0..<3).filter { !actual[$0].isFinite }.count
        }
        let directionDraws = plan.sphereAxisMask == 7 ? 2 : (plan.sphereAxisMask == 0 ? 0 : 1)
        for _ in 0..<(64 * (directionDraws + 1)) { _ = expectedDraws.unit() }
        let countMatches = simulator.random.state == expectedDraws.state
        let nextActual = simulator.random.value(-7, 13), nextExpected = reference.value(-7, 13)
        return ["name": input.name, "mask": plan.sphereAxisMask, "samples": 64,
                "bitsOrNaNClassMatch": matches, "rngAfterEachSampleMatches": statesMatch,
                "drawCountMatches": countMatches, "nextRandomMatches": nextActual.bitPattern == nextExpected.bitPattern,
                "nextIDUnchanged": simulator.frameSnapshot().nextParticleID == beforeID,
                "nonfiniteValues": nonfiniteValues, "firstMismatch": firstMismatch]
    }

    private static func compareBirths(_ input: Input) -> [String: Any] {
        let definition = definition(input, count: 8)
        let emitter = definition.emitters[0]
        let simulator = SceneParticleSimulator(definition: definition, seed: 52)
        let before = simulator.frameSnapshot()
        var reference = simulator.random
        let frame = definition.emitterControlPointFrame(
            for: emitter, instanceOverride: nil, dynamicControlPoints: [:],
            preparedOrigin: SceneParticleSimulationMath.vector(emitter.origin, fallback: .zero))!
        var positions: [SIMD3<Double>] = [], identities: [UInt64] = []
        for identity in 0..<8 {
            let relative = originalOffset(emitter, random: &reference)
            let position = frame.position(for: relative)
            _ = reference.value(0, 0) // Emitter speed always consumes its draw.
            _ = reference.value(10, 10) // The fixed lifetime still consumes its draw.
            if SceneParticleSimulationMath.isGPUFinite(position) {
                positions.append(position); identities.append(UInt64(identity))
            }
        }
        simulator.advance(by: 1.0 / 60)
        let after = simulator.frameSnapshot()
        let actualPositions = simulator.particles.map(\.position)
        let matches = actualPositions.count == positions.count
            && zip(actualPositions, positions).allSatisfy { sameValues($0.0, $0.1) }
        let rngMatches = after.random.state == reference.state
        var nextActual = after.random
        let nextMatch = nextActual.value(-7, 13).bitPattern == reference.value(-7, 13).bitPattern
        simulator.restoreFrame(before)
        simulator.advance(by: 1.0 / 60)
        let replay = simulator.frameSnapshot()
        return ["name": input.name, "positionsMatch": matches,
                "identitiesMatch": simulator.particles.map(\.id) == identities,
                "birthEventsMatch": simulator.birthEvents.map(\.id) == identities,
                "nextIDMatches": after.nextParticleID == 8,
                "rngMatches": rngMatches, "nextRandomMatches": nextMatch,
                "rollbackMatches": replay.particles == after.particles && replay.birthEvents == after.birthEvents
                    && replay.deathEvents == after.deathEvents && replay.nextParticleID == after.nextParticleID
                    && replay.random.state == after.random.state,
                "accepted": positions.count, "rejected": 8 - positions.count]
    }

    // Original project-owned per-sample implementation, before fixed radial
    // math moved into SpawnPlan. It reads no prepared radial result.
    private static func originalOffset(
        _ emitter: SceneParticleEmitter, random: inout SceneParticleRandomGenerator
    ) -> SIMD3<Double> {
        let directions = SceneParticleSimulationMath.vector(emitter.directions, fallback: SIMD3(1, 1, 0))
        let sign = SceneParticleSimulationMath.vector(emitter.sign, fallback: .zero)
        let mask: UInt8 = (abs(directions.x) > 1e-6 ? 1 : 0)
            | (abs(directions.y) > 1e-6 ? 2 : 0) | (abs(directions.z) > 1e-6 ? 4 : 0)
        let dimensions = max(mask.nonzeroBitCount, 1)
        let unit: SIMD3<Double>
        switch mask {
        case 7:
            let z = random.value(-1, 1)
            let angle = random.unit() * (2 * .pi)
            let radial = sqrt(max(0, 1 - z * z))
            unit = SIMD3(radial * cos(angle), radial * sin(angle), z)
        case 3, 5, 6:
            let angle = random.unit() * (2 * .pi)
            let first = cos(angle), second = sin(angle)
            if mask == 3 { unit = SIMD3(first, second, 0) }
            else if mask == 5 { unit = SIMD3(first, 0, second) }
            else { unit = SIMD3(0, first, second) }
        case 1, 2, 4:
            let direction = random.unit() < 0.5 ? -1.0 : 1.0
            if mask == 1 { unit = SIMD3(direction, 0, 0) }
            else if mask == 2 { unit = SIMD3(0, direction, 0) }
            else { unit = SIMD3(0, 0, direction) }
        default:
            unit = .zero
        }
        let minimum = max(0, SceneParticleSimulationMath.scalar(emitter.distanceMinimum, fallback: 0))
        let maximum = max(minimum, SceneParticleSimulationMath.scalar(emitter.distanceMaximum, fallback: 256))
        let radius = pow(
            random.value(pow(minimum, Double(dimensions)), pow(maximum, Double(dimensions))),
            1 / Double(dimensions)
        )
        var absoluteDirections = directions
        for component in 0..<3 { absoluteDirections[component] = abs(absoluteDirections[component]) }
        var result = unit * absoluteDirections * radius
        for component in 0..<3 where abs(sign[component]) > 1e-6 {
            result[component] = abs(result[component]) * (sign[component] < 0 ? -1 : 1)
        }
        return result
    }
}
