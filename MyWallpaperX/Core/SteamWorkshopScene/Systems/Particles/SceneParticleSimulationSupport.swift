import Foundation
import simd

nonisolated struct SceneParticleFrameTiming: Sendable {
    var sceneTime: Double = 0
    var turbulenceForceFactor: Double = 1
}

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

    // Birth baselines: makeParticle writes them together with color/alpha/size.
    // Afterwards only a writing operator moves the live value, so a per-step
    // reset can skip attributes no operator kind writes.
    var initialColor: SIMD3<Double>
    var initialAlpha: Double
    var initialSize: Double
    /// Anchored after the first valid ring-vortex step; frame snapshots own it.
    var vortexRadius: Double? = nil
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

    static func particleUnit(id: UInt64, seed: UInt64) -> Double {
        var generator = Self(state: seed ^ (id &* 0x9E3779B97F4A7C15))
        return generator.unit()
    }

    mutating func value(_ first: Double, _ second: Double) -> Double {
        let lower = min(first, second)
        return lower + unit() * (max(first, second) - lower)
    }
}

nonisolated struct SceneParticleTurbulentVelocityPlan: Sendable {
    let basis: (parallel: SIMD3<Double>, radial: SIMD3<Double>, tangent: SIMD3<Double>)?
    let offset: Double
    let phaseMinimum: Double
    let phaseSpan: Double
    let angularScale: Double
    let speedMinimum: Double
    let speedMaximum: Double
    let timeScale: Double
    let audioResponseEnabled: Bool
    let audioResponsePlan: SceneParticleAudioResponsePlan?

    nonisolated init(_ value: SceneParticleTurbulentVelocity) {
        let forward = SceneParticleSimulationMath.vector(value.forward, fallback: SIMD3(0, 1, 0))
        let right = SceneParticleSimulationMath.vector(value.right, fallback: SIMD3(0, 0, 1))
        let length = simd_length(right)
        offset = Double(Float(value.offset ?? 0))
        angularScale = Double(Float(value.scale ?? 1) * .pi)
        if length.isFinite, length > 1e-9, offset.isFinite, angularScale.isFinite,
           SceneParticleSimulationMath.isGPUFinite(forward) {
            let axis = right / length
            let parallel = axis * simd_dot(axis, forward)
            basis = (parallel, forward - parallel, simd_cross(axis, forward))
        } else {
            basis = nil
        }
        phaseMinimum = value.phaseMinimum ?? 0
        phaseSpan = (value.phaseMaximum ?? 0.1) - phaseMinimum
        speedMinimum = max(value.speedMinimum ?? 100, 0)
        speedMaximum = max(value.speedMaximum ?? 250, 0)
        timeScale = value.timeScale ?? 1
        audioResponseEnabled = value.audioResponse.isEnabled
        audioResponsePlan = value.peakAudioResponsePlan
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

    @inline(__always)
    static func isGPUFinite(_ value: SIMD3<Double>) -> Bool {
        // SIMD3<Float> converts per lane exactly like Float(lane), so the
        // accepted and rejected values stay identical to the scalar form.
        let float = SIMD3<Float>(value)
        return float.x.isFinite && float.y.isFinite && float.z.isFinite
    }

    static func addFinite(
        _ delta: SIMD3<Double>,
        to value: inout SIMD3<Double>
    ) {
        let result = value + delta
        if isGPUFinite(result) {
            value = result
        }
    }

    static func turbulentVelocity(
        _ value: SceneParticleTurbulentVelocityPlan?,
        sceneTime: Double, rate: Double,
        random: inout SceneParticleRandomGenerator,
        audioFactor: Double? = nil, strict: Bool = false
    ) -> SIMD3<Double> {
        guard let value, !value.audioResponseEnabled || audioFactor != nil else {
            return strict ? SIMD3(repeating: .nan) : .zero
        }
        let phase = value.phaseMinimum + random.unit() * value.phaseSpan * (audioFactor ?? 1)
        let sampleTime = Float((sceneTime + phase) * (value.timeScale * rate))
        guard let basis = value.basis, sampleTime.isFinite else {
            return strict ? SIMD3(repeating: .nan) : .zero
        }
        let turn = value.offset + Double(turbulentNoise(sampleTime)) * value.angularScale
        let direction = basis.parallel + basis.radial * cos(turn) + basis.tangent * sin(turn)
        return direction * random.value(value.speedMinimum, value.speedMaximum)
    }

    // Perlin's published 256-cell permutation, shared by both simplex fields.
    private static let simplexPermutation: [UInt8] = [
        151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
        140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
        247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
        57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175,
        74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122,
        60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54,
        65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169,
        200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64,
        52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212,
        207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213,
        119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9,
        129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104,
        218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241,
        81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157,
        184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93,
        222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
    ]

    private static func turbulentNoise(_ time: Float) -> Float {
        let lattice = time.rounded(.down)
        let cell = Int(lattice.truncatingRemainder(dividingBy: 256)) & 255
        let x = time - lattice
        func contribution(_ distance: Float, cell: Int) -> Float {
            let weight = 1 - distance * distance
            let weightSquared = weight * weight
            let hash = simplexPermutation[cell]
            let magnitude = Float(1 + (hash & 7))
            let gradient = hash & 8 == 0 ? magnitude : -magnitude
            return gradient * distance * weightSquared * weightSquared
        }
        return 0.395 * (contribution(x, cell: cell) + contribution(x - 1, cell: (cell + 1) & 255))
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
        let x = (hash & 1) == 0 ? offsetX : -offsetX
        let y = (hash & 2) == 0 ? offsetY : -offsetY
        let z = (hash & 4) == 0 ? offsetZ : -offsetZ
        let axes = (hash >> 3) % 3
        return (axes == 2 ? y : x) + (axes == 0 ? y : z)
    }

    @inline(__always)
    private static func noiseFade(_ value: Double) -> Double {
        value * value * value * (value * (value * 6 - 15) + 10)
    }

    @inline(__always)
    private static func noiseLerp(_ first: Double, _ second: Double, _ amount: Double) -> Double {
        first + (second - first) * amount
    }

    private static func particleNoisePhase(particleID: UInt64, simulationSeed: UInt64) -> SIMD3<Double> {
        var phaseRandom = SceneParticleRandomGenerator(
            state: simulationSeed ^ (particleID &* 0x9E3779B97F4A7C15)
        )
        return SIMD3(
            phaseRandom.value(-4096, 4096),
            phaseRandom.value(-4096, 4096),
            phaseRandom.value(-4096, 4096)
        )
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
        let phase = particleNoisePhase(particleID: particleID, simulationSeed: simulationSeed)
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

    /// Bounded project FBM approximation, not an official phase/scale formula.
    /// The local phase generator never consumes the simulator's emission RNG.
    static func scalarSpeedRemapMultiplier(
        _ plan: SceneParticleRemapPlan.Scalar, inputScale: Double,
        normalizedLife: Double, particleID: UInt64, simulationSeed: UInt64
    ) -> Double? {
        let temporal = normalizedLife * inputScale
        var point = particleNoisePhase(particleID: particleID, simulationSeed: simulationSeed)
            + SIMD3(temporal, temporal * 0.754_877_666, temporal * 1.324_717_957)
        var amplitude = 1.0, amplitudeSum = 0.0, noise = 0.0
        for _ in 0..<4 {
            // gradientNoise narrows floor(point) to Int; reject before that ABI.
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
                  abs(point.x) < 1e12, abs(point.y) < 1e12, abs(point.z) < 1e12 else { return nil }
            noise += gradientNoise(point, seed: 0xA0761D6478BD642F) * amplitude
            amplitudeSum += amplitude
            amplitude *= 0.5
            point *= 2
        }
        let amount = min(max(noise / amplitudeSum * 0.5 + 0.5, 0), 1)
        return min(max(plan.value(at: amount), 0), 1)
    }

    static func positionOffset(
        _ plan: SceneParticlePositionOffsetPlan,
        position: SIMD3<Double>,
        time: Double,
        particleID: UInt64,
        simulationSeed: UInt64, strict: Bool = false
    ) -> SIMD3<Double> {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              time.isFinite else { return strict ? SIMD3(repeating: .nan) : .zero }
        let phase = particleNoisePhase(particleID: particleID, simulationSeed: simulationSeed)
        let spatialScale = plan.scale * 0.001
        let timePoint = time * plan.timeScale
        var point = position * spatialScale + phase + SIMD3(
            timePoint, timePoint * 0.754_877_666, timePoint * 1.324_717_957
        )
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
              abs(point.x) < 1e12, abs(point.y) < 1e12, abs(point.z) < 1e12 else {
            return strict ? SIMD3(repeating: .nan) : .zero
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
        guard amplitudeSum > 0 else { return strict ? SIMD3(repeating: .nan) : .zero }
        noise /= amplitudeSum
        for index in 0..<3 { noise[index] = min(max(noise[index], -1), 1) }
        return noise * plan.directions * plan.distance
    }

    static func continuousTurbulence(at point: SIMD3<Float>, mask: SIMD3<Double>) -> SIMD3<Double> {
        guard abs(point.x) < 1e12, abs(point.y) < 1e12, abs(point.z) < 1e12 else { return .zero }
        return SIMD3(
            mask.x == 0 ? 0 : Double(simplexField(point)) * mask.x,
            mask.y == 0 ? 0 : Double(simplexField(SIMD3(point.z, point.x, point.y))) * mask.y,
            mask.z == 0 ? 0 : Double(simplexField(SIMD3(point.y, point.z, point.x))) * mask.z
        )
    }

    private static let simplexGradients: [SIMD3<Float>] = [
        SIMD3(1, 1, 0), SIMD3(-1, 1, 0), SIMD3(1, -1, 0), SIMD3(-1, -1, 0),
        SIMD3(1, 0, 1), SIMD3(-1, 0, 1), SIMD3(1, 0, -1), SIMD3(-1, 0, -1),
        SIMD3(0, 1, 1), SIMD3(0, -1, 1), SIMD3(0, 1, -1), SIMD3(0, -1, -1),
    ]

    private static func simplexField(_ point: SIMD3<Float>) -> Float {
        let cell = (point + simd_reduce_add(point) / 3).rounded(.down)
        let offset = point - cell + simd_reduce_add(cell) / 6
        let xy = offset.x >= offset.y
        let xz = offset.x >= offset.z
        let yz = offset.y >= offset.z
        let first = SIMD3<Int>(xy && xz ? 1 : 0, !xy && yz ? 1 : 0, !xz && !yz ? 1 : 0)
        let second = SIMD3<Int>(xy || xz ? 1 : 0, !xy || yz ? 1 : 0, !xz || !yz ? 1 : 0)
        let lattice = SIMD3(Int(cell.x), Int(cell.y), Int(cell.z))
        func corner(_ distance: SIMD3<Float>, at index: SIMD3<Int>) -> Float {
            let weight = 0.6 - simd_length_squared(distance)
            guard weight > 0 else { return 0 }
            let z = Int(simplexPermutation[index.z & 255])
            let y = Int(simplexPermutation[(index.y + z) & 255])
            let hash = Int(simplexPermutation[(index.x + y) & 255])
            let squared = weight * weight
            return squared * squared * simd_dot(simplexGradients[hash % 12], distance)
        }
        // The continuous field's far corner uses the starting Z lattice index for its gradient.
        return 32 * (
            corner(offset, at: lattice)
            + corner(offset - SIMD3<Float>(first) + 1.0 / 6, at: lattice &+ first)
            + corner(offset - SIMD3<Float>(second) + 1.0 / 3, at: lattice &+ second)
            + corner(offset - 0.5, at: lattice &+ SIMD3(1, 1, 0))
        )
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
