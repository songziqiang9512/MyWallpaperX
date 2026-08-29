import Foundation

nonisolated struct SceneParticleState: Equatable, Sendable {
    let id: UInt64
    var position: SIMD3<Double>
    var velocity: SIMD3<Double>
    var color: SIMD3<Double>
    var alpha: Double
    var size: Double
    var rotation: SIMD3<Double>
    var angularVelocity: SIMD3<Double>
    var age: Double
    var lifetime: Double

    var initialColor: SIMD3<Double>
    var initialAlpha: Double
    var initialSize: Double
}

nonisolated struct SceneParticleRandomGenerator: Sendable {
    var state: UInt64

    mutating func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func value(_ first: Double, _ second: Double) -> Double {
        let lower = min(first, second)
        return lower + unit() * (max(first, second) - lower)
    }
}

nonisolated enum SceneParticleSimulationMath {
    static func scalar(_ value: SceneParticleNumericValue?, fallback: Double) -> Double {
        switch value {
        case let .scalar(number): number
        case let .vector(values): values.first ?? fallback
        case nil: fallback
        }
    }

    static func vector(
        _ value: SceneParticleNumericValue?,
        fallback: SIMD3<Double>
    ) -> SIMD3<Double> {
        switch value {
        case let .scalar(number):
            SIMD3(repeating: number)
        case let .vector(values):
            SIMD3(
                values.indices.contains(0) ? values[0] : fallback.x,
                values.indices.contains(1) ? values[1] : fallback.y,
                values.indices.contains(2) ? values[2] : fallback.z
            )
        case nil:
            fallback
        }
    }

    static func length(_ value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }

    static func addFinite(
        _ delta: SIMD3<Double>,
        to value: inout SIMD3<Double>
    ) {
        let result = value + delta
        if result.x.isFinite && result.y.isFinite && result.z.isFinite {
            value = result
        }
    }

    static func turbulentVelocity(
        _ value: SceneParticleTurbulentVelocity?,
        _ position: SIMD3<Double>,
        _ time: Double,
        _ random: inout SceneParticleRandomGenerator,
        audioInput: SceneParticleAudioInput = .silent
    ) -> SIMD3<Double> {
        guard let value else { return .zero }
        let audioFactor: Double
        if value.audioResponse.isEnabled {
            guard let plan = SceneParticleAudioResponsePlan(value.audioResponse) else {
                return .zero
            }
            audioFactor = 1 + plan.evaluate(audioInput)
        } else {
            audioFactor = 1
        }
        let phase = random.value(
            value.phaseMinimum ?? 0,
            value.phaseMaximum ?? 2 * .pi
        ) * audioFactor
        let timeScale = value.timeScale ?? 1
        let directionalOffset = value.offset ?? 0
        guard phase.isFinite, time.isFinite, timeScale.isFinite,
              directionalOffset.isFinite,
              position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            return .zero
        }
        let noiseTime = phase + time * timeScale
        // Author positions select a coherent field; scale controls angular spread, not frequency.
        let point = position * 0.001 + SIMD3(noiseTime, 0, 0)
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return .zero }
        let turnNoise = gradientNoise(point, seed: 0xBF58476D1CE4E5B9)
        let planeNoise = gradientNoise(
            point + SIMD3(59.19, 71.41, 89.97), seed: 0x94D049BB133111EB
        )
        let forward = vector(value.forward, fallback: SIMD3(0, 1, 0))
        let normal = vector(value.right, fallback: SIMD3(0, 0, 1))
        let up = vector(value.up, fallback: .zero)
        let forwardLength = length(forward)
        guard forwardLength.isFinite, forwardLength > 1e-9 else { return .zero }
        let base = forward / forwardLength
        let adjustedNormal = normal + up * planeNoise
        let tangentValue = SIMD3(
            adjustedNormal.y * base.z - adjustedNormal.z * base.y,
            adjustedNormal.z * base.x - adjustedNormal.x * base.z,
            adjustedNormal.x * base.y - adjustedNormal.y * base.x
        )
        let tangentLength = length(tangentValue)
        guard tangentLength.isFinite, tangentLength > 1e-9 else { return .zero }
        let tangent = tangentValue / tangentLength
        let angularScale = max(value.scale ?? 1, 0)
        guard angularScale.isFinite else { return .zero }
        let turn = directionalOffset + angularScale * Double.pi * turnNoise
        var direction = base * cos(turn) + tangent * sin(turn)
        var directionLength = length(direction)
        if !directionLength.isFinite || directionLength <= 1e-9 {
            direction = base
            directionLength = length(direction)
        }
        guard directionLength.isFinite, directionLength > 1e-9 else { return .zero }
        let minimumSpeed = max(value.speedMinimum ?? 0, 0)
        let maximumSpeed = max(value.speedMaximum ?? 100, minimumSpeed)
        return direction / directionLength * random.value(minimumSpeed, maximumSpeed)
    }

    @inline(__always)
    private static func gradientNoise(_ point: SIMD3<Double>, seed: UInt64) -> Double {
        let baseX = Int(floor(point.x))
        let baseY = Int(floor(point.y))
        let baseZ = Int(floor(point.z))
        let localX = point.x - Double(baseX)
        let localY = point.y - Double(baseY)
        let localZ = point.z - Double(baseZ)
        let fadeX = noiseFade(localX)
        let fadeY = noiseFade(localY)
        let fadeZ = noiseFade(localZ)

        // This is a per-particle, per-fixed-step hot path. Eight heap-backed
        // corner arrays made a stock 1,000-particle field dominate the host
        // frame. Publish each gradient dot directly into scalar locals so the
        // coherent field and interpolation order remain unchanged.
        let c000 = noiseGradientDot(
            baseX, baseY, baseZ, seed: seed,
            offsetX: localX, offsetY: localY, offsetZ: localZ
        )
        let c100 = noiseGradientDot(
            baseX + 1, baseY, baseZ, seed: seed,
            offsetX: localX - 1, offsetY: localY, offsetZ: localZ
        )
        let c010 = noiseGradientDot(
            baseX, baseY + 1, baseZ, seed: seed,
            offsetX: localX, offsetY: localY - 1, offsetZ: localZ
        )
        let c110 = noiseGradientDot(
            baseX + 1, baseY + 1, baseZ, seed: seed,
            offsetX: localX - 1, offsetY: localY - 1, offsetZ: localZ
        )
        let c001 = noiseGradientDot(
            baseX, baseY, baseZ + 1, seed: seed,
            offsetX: localX, offsetY: localY, offsetZ: localZ - 1
        )
        let c101 = noiseGradientDot(
            baseX + 1, baseY, baseZ + 1, seed: seed,
            offsetX: localX - 1, offsetY: localY, offsetZ: localZ - 1
        )
        let c011 = noiseGradientDot(
            baseX, baseY + 1, baseZ + 1, seed: seed,
            offsetX: localX, offsetY: localY - 1, offsetZ: localZ - 1
        )
        let c111 = noiseGradientDot(
            baseX + 1, baseY + 1, baseZ + 1, seed: seed,
            offsetX: localX - 1, offsetY: localY - 1, offsetZ: localZ - 1
        )
        let lower = noiseLerp(
            noiseLerp(c000, c100, fadeX),
            noiseLerp(c010, c110, fadeX),
            fadeY
        )
        let upper = noiseLerp(
            noiseLerp(c001, c101, fadeX),
            noiseLerp(c011, c111, fadeX),
            fadeY
        )
        return noiseLerp(lower, upper, fadeZ)
    }

    @inline(__always)
    private static func noiseGradientDot(
        _ x: Int,
        _ y: Int,
        _ z: Int,
        seed: UInt64,
        offsetX: Double,
        offsetY: Double,
        offsetZ: Double
    ) -> Double {
        var hash = seed
        hash ^= UInt64(bitPattern: Int64(x)) &* 0x9E3779B185EBCA87
        hash ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F
        hash ^= UInt64(bitPattern: Int64(z)) &* 0x165667B19E3779F9
        hash ^= hash >> 29
        hash &*= 0x9FB21C651E98DF25
        hash ^= hash >> 32
        let signX = (hash & 1) == 0 ? 1.0 : -1.0
        let signY = (hash & 2) == 0 ? 1.0 : -1.0
        let signZ = (hash & 4) == 0 ? 1.0 : -1.0
        switch Int((hash >> 3) % 3) {
        case 0: return signX * offsetX + signY * offsetY
        case 1: return signX * offsetX + signZ * offsetZ
        default: return signY * offsetY + signZ * offsetZ
        }
    }

    @inline(__always)
    private static func noiseFade(_ value: Double) -> Double {
        value * value * value * (value * (value * 6 - 15) + 10)
    }

    @inline(__always)
    private static func noiseLerp(_ first: Double, _ second: Double, _ amount: Double) -> Double {
        first + (second - first) * amount
    }

    /// Project-owned coherent approximation for the bounded Rain Remap Value
    /// cohort. This is deliberately not described as official simplex parity.
    static func remapNoiseAmount(
        position: SIMD3<Double>,
        time: Double,
        particleID: UInt64,
        simulationSeed: UInt64,
        inputScale: Double
    ) -> Double? {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              time.isFinite, inputScale.isFinite, inputScale > 0 else { return nil }
        var phaseRandom = SceneParticleRandomGenerator(
            state: simulationSeed ^ (particleID &* 0x9E3779B97F4A7C15)
        )
        let phase = SIMD3(
            phaseRandom.value(-4096, 4096),
            phaseRandom.value(-4096, 4096),
            phaseRandom.value(-4096, 4096)
        )
        let temporal = time * inputScale * 0.1
        let point = position * 0.001 + phase + SIMD3(
            temporal, temporal * 0.754_877_666, temporal * 1.324_717_957
        )
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
              abs(point.x) < 1e12, abs(point.y) < 1e12, abs(point.z) < 1e12 else {
            return nil
        }
        let noise = gradientNoise(point, seed: 0xA0761D6478BD642F)
        guard noise.isFinite else { return nil }
        return min(max(noise * 0.5 + 0.5, 0), 1)
    }

    static func positionOffset(
        _ plan: SceneParticlePositionOffsetPlan,
        position: SIMD3<Double>,
        time: Double,
        particleID: UInt64,
        simulationSeed: UInt64
    ) -> SIMD3<Double> {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              time.isFinite else { return .zero }
        var phaseRandom = SceneParticleRandomGenerator(
            state: simulationSeed ^ (particleID &* 0x9E3779B97F4A7C15)
        )
        let phase = SIMD3(
            phaseRandom.value(-4096, 4096),
            phaseRandom.value(-4096, 4096),
            phaseRandom.value(-4096, 4096)
        )
        let spatialScale = plan.scale * 0.001
        let timePoint = time * plan.timeScale
        var point = position * spatialScale + phase + SIMD3(
            timePoint, timePoint * 0.754_877_666, timePoint * 1.324_717_957
        )
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
              abs(point.x) < 1e12, abs(point.y) < 1e12, abs(point.z) < 1e12 else {
            return .zero
        }

        var amplitude = 1.0
        var amplitudeSum = 0.0
        var noise = SIMD3<Double>.zero
        for _ in 0..<plan.octaves {
            noise += SIMD3(
                gradientNoise(point, seed: 0xD6E8FEB86659FD93),
                gradientNoise(
                    point + SIMD3(47.17, 73.31, 101.03),
                    seed: 0xA0761D6478BD642F
                ),
                gradientNoise(
                    point + SIMD3(83.29, 19.37, 61.43),
                    seed: 0xE7037ED1A0B428DB
                )
            ) * amplitude
            amplitudeSum += amplitude
            amplitude *= 0.5
            point *= 2
        }
        guard amplitudeSum > 0 else { return .zero }
        noise /= amplitudeSum
        for index in 0..<3 { noise[index] = min(max(noise[index], -1), 1) }
        return noise * plan.directions * plan.distance
    }

    static func turbulenceDirection(
        position: SIMD3<Double>,
        time: Double,
        phase: Double,
        scale: Double,
        timeScale: Double,
        mask: SIMD3<Double>
    ) -> SIMD3<Double> {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              time.isFinite, phase.isFinite, scale.isFinite, timeScale.isFinite,
              mask.x.isFinite, mask.y.isFinite, mask.z.isFinite else { return .zero }
        let noiseTime = phase + time * timeScale
        // De-correlate one project-owned coherent field across its three sample axes.
        let point = position * scale + SIMD3(
            noiseTime,
            noiseTime * 0.754_877_666,
            noiseTime * 1.324_717_957
        )
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
              abs(point.x) < 1e12, abs(point.y) < 1e12, abs(point.z) < 1e12 else {
            return .zero
        }
        let turn = gradientNoise(point, seed: 0xD6E8FEB86659FD93) * 2 * Double.pi
        var direction = SIMD3(cos(turn), sin(turn), 0.0)
        if abs(mask.z) > 1e-9 {
            direction.z = gradientNoise(
                point + SIMD3(47.17, 73.31, 101.03),
                seed: 0xA0761D6478BD642F
            )
            let directionLength = length(direction)
            guard directionLength.isFinite, directionLength > 1e-9 else { return .zero }
            direction /= directionLength
        }
        return direction * mask
    }

    static func changeAmount(
        _ life: Double,
        _ rawStart: Double?,
        _ rawEnd: Double?
    ) -> Double {
        let start = rawStart ?? 0
        let end = rawEnd ?? 1
        guard end > start else { return life > end ? 1 : 0 }
        return min(max((life - start) / (end - start), 0), 1)
    }
}
