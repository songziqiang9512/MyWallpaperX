import simd

nonisolated enum SceneParticlePipelineBlendMode: Equatable, Sendable {
    case translucent
    case additive
}

nonisolated enum SceneParticleSpriteAnimationMode: Equatable, Sendable {
    case sequence
    case randomFrame

    nonisolated init(authoredValue: String?) {
        self = authoredValue?.lowercased() == "randomframe" ? .randomFrame : .sequence
    }
}

nonisolated struct SceneParticleSpriteFrameSelection: Equatable, Sendable {
    let currentIndex: Int
    let nextIndex: Int
    let mix: Float
}

nonisolated enum SceneParticleSpriteFrameSelector {
    static func select(
        mode: SceneParticleSpriteAnimationMode,
        frameDurations: [Float],
        age: Float,
        lifetime: Float,
        sequenceMultiplier: Float = 1,
        particleID: UInt64,
        blendsFrames: Bool
    ) -> SceneParticleSpriteFrameSelection? {
        guard !frameDurations.isEmpty else { return nil }
        let durations = frameDurations.map(effectiveDuration)
        let total = durations.reduce(0, +)
        guard total > 0, total.isFinite else {
            return SceneParticleSpriteFrameSelection(currentIndex: 0, nextIndex: 0, mix: 0)
        }

        let animationLifetime = mode == .randomFrame
            ? stableUnit(particleID)
            : (lifetime > 0 ? age / lifetime * sequenceMultiplier : 0)
        var elapsed = animationLifetime.truncatingRemainder(dividingBy: 1)
        if elapsed < 0 { elapsed += 1 }
        elapsed *= total

        let allowsBlend = blendsFrames && mode == .sequence
        for index in durations.indices {
            if elapsed < durations[index] || index == durations.index(before: durations.endIndex) {
                let next = (index + 1) % durations.count
                let blend = allowsBlend ? min(max(elapsed / durations[index], 0), 1) : 0
                return SceneParticleSpriteFrameSelection(
                    currentIndex: index,
                    nextIndex: allowsBlend ? next : index,
                    mix: blend
                )
            }
            elapsed -= durations[index]
        }
        return nil
    }

    private static func effectiveDuration(_ value: Float) -> Float {
        value.isFinite && value > 0 ? value : 1.0 / 60.0
    }

    private static func stableUnit(_ input: UInt64) -> Float {
        var value = input &+ 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Float(value >> 40) * (1.0 / 16_777_216.0)
    }
}

nonisolated enum SceneParticleOrientation: Equatable, Sendable {
    case screen
    case upright
    case fixed

    nonisolated init(authoredValue: String?) {
        switch authoredValue?.lowercased() {
        case "upright", "vertical": self = .upright
        case "fixed", "world", "worldspace": self = .fixed
        default: self = .screen
        }
    }

    nonisolated func basis(
        cameraRight: SIMD3<Float>,
        cameraUp: SIMD3<Float>,
        cameraForward: SIMD3<Float>,
        worldUp: SIMD3<Float> = SIMD3(0, 1, 0),
        fixedRight: SIMD3<Float> = SIMD3(1, 0, 0),
        fixedUp: SIMD3<Float> = SIMD3(0, 1, 0)
    ) -> SceneParticleOrientationBasis {
        switch self {
        case .screen:
            return SceneParticleOrientationBasis.orthonormalized(
                right: cameraRight,
                up: cameraUp
            )
        case .upright:
            let up = SceneParticleOrientationBasis.normalized(
                worldUp,
                fallback: SIMD3(0, 1, 0)
            )
            let horizontal = simd_cross(cameraForward, up)
            let right = simd_length_squared(horizontal) > 1e-8 ? horizontal : cameraRight
            return SceneParticleOrientationBasis.orthonormalized(right: right, up: up)
        case .fixed:
            return SceneParticleOrientationBasis.orthonormalized(
                right: fixedRight,
                up: fixedUp
            )
        }
    }
}

nonisolated struct SceneParticleOrientationBasis: Equatable, Sendable {
    let right: SIMD3<Float>
    let up: SIMD3<Float>

    fileprivate static func orthonormalized(
        right rawRight: SIMD3<Float>,
        up rawUp: SIMD3<Float>
    ) -> SceneParticleOrientationBasis {
        let right = normalized(rawRight, fallback: SIMD3(1, 0, 0))
        let rejected = rawUp - right * simd_dot(rawUp, right)
        var up = normalized(rejected, fallback: SIMD3(0, 1, 0))
        if abs(simd_dot(right, up)) > 1e-4 {
            up = normalized(
                simd_cross(SIMD3(0, 0, 1), right),
                fallback: SIMD3(0, 1, 0)
            )
        }
        return SceneParticleOrientationBasis(right: right, up: up)
    }

    fileprivate static func normalized(
        _ value: SIMD3<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(value)
        return lengthSquared.isFinite && lengthSquared > 1e-8
            ? value / sqrt(lengthSquared)
            : fallback
    }
}

nonisolated struct SceneParticleFrameTransform: Equatable, Sendable {
    let origin: SIMD2<Float>
    let xAxis: SIMD2<Float>
    let yAxis: SIMD2<Float>

    static let identity = SceneParticleFrameTransform(
        origin: .zero,
        xAxis: SIMD2(1, 0),
        yAxis: SIMD2(0, 1)
    )
}

// Seven float4 values keep this layout identical to ParticleInstance in MSL.
nonisolated struct SceneParticleGPUInstance: Sendable {
    var positionAndSize: SIMD4<Float>
    var rotationAndAlpha: SIMD4<Float>
    var colorAndFrameMix: SIMD4<Float>
    var frame0A: SIMD4<Float>
    var frame0B: SIMD4<Float>
    var frame1A: SIMD4<Float>
    var frame1B: SIMD4<Float>

    nonisolated init(
        position: SIMD3<Float>,
        size: Float,
        rotation: SIMD3<Float>,
        color: SIMD3<Float>,
        alpha: Float,
        currentFrame: SceneParticleFrameTransform = .identity,
        nextFrame: SceneParticleFrameTransform? = nil,
        frameMix: Float = 0
    ) {
        let following = nextFrame ?? currentFrame
        positionAndSize = SIMD4(position.x, position.y, position.z, size)
        rotationAndAlpha = SIMD4(rotation.x, rotation.y, rotation.z, alpha)
        colorAndFrameMix = SIMD4(color.x, color.y, color.z, min(max(frameMix, 0), 1))
        frame0A = SIMD4(
            currentFrame.origin.x,
            currentFrame.origin.y,
            currentFrame.xAxis.x,
            currentFrame.xAxis.y
        )
        frame0B = SIMD4(currentFrame.yAxis.x, currentFrame.yAxis.y, 0, 0)
        frame1A = SIMD4(
            following.origin.x,
            following.origin.y,
            following.xAxis.x,
            following.xAxis.y
        )
        frame1B = SIMD4(following.yAxis.x, following.yAxis.y, 0, 0)
    }
}

nonisolated struct SceneParticleLayerUniforms: Sendable {
    var viewProjection: simd_float4x4
    var layerModel: simd_float4x4
    var basisRight: SIMD4<Float>
    var basisUp: SIMD4<Float>

    nonisolated init(
        viewProjection: simd_float4x4,
        layerModel: simd_float4x4,
        basis: SceneParticleOrientationBasis
    ) {
        self.viewProjection = viewProjection
        self.layerModel = layerModel
        basisRight = SIMD4(basis.right.x, basis.right.y, basis.right.z, 0)
        basisUp = SIMD4(basis.up.x, basis.up.y, basis.up.z, 0)
    }
}
