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


    static func run() throws -> [String: Any] {
        try distribution()
    }
}
