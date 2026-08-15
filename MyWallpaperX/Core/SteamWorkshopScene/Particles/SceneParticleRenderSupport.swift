import simd

nonisolated enum SceneParticlePipelineBlendMode: String, Equatable, Sendable {
    case translucent
    case additive
}

nonisolated enum SceneParticlePipelineCullMode: String, Equatable, Sendable {
    case none
    case back
}

nonisolated struct SceneParticlePipelineRenderState: Equatable, Sendable {
    let blendMode: SceneParticlePipelineBlendMode
    let cullMode: SceneParticlePipelineCullMode
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
        frameEndTimes: [Float]? = nil,
        totalDuration authoredTotalDuration: Float? = nil,
        age: Float,
        lifetime: Float,
        sequenceMultiplier: Float = 1,
        particleID: UInt64,
        blendsFrames: Bool
    ) -> SceneParticleSpriteFrameSelection? {
        guard !frameDurations.isEmpty else { return nil }
        let hasPreparedTimeline = frameEndTimes?.count == frameDurations.count
            && authoredTotalDuration?.isFinite == true
            && (authoredTotalDuration ?? 0) > 0
        let total = hasPreparedTimeline
            ? authoredTotalDuration ?? 0
            : frameDurations.reduce(0) { $0 + effectiveDuration($1) }
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
        if hasPreparedTimeline, let frameEndTimes {
            var lower = 0
            var upper = frameEndTimes.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if elapsed < frameEndTimes[middle] {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            let index = min(lower, frameDurations.count - 1)
            let frameStart = index == 0 ? 0 : frameEndTimes[index - 1]
            let duration = max(frameEndTimes[index] - frameStart, Float.leastNonzeroMagnitude)
            let next = (index + 1) % frameDurations.count
            let blend = allowsBlend ? min(max((elapsed - frameStart) / duration, 0), 1) : 0
            return SceneParticleSpriteFrameSelection(
                currentIndex: index,
                nextIndex: allowsBlend ? next : index,
                mix: blend
            )
        }
        for index in frameDurations.indices {
            let duration = effectiveDuration(frameDurations[index])
            if elapsed < duration || index == frameDurations.index(before: frameDurations.endIndex) {
                let next = (index + 1) % frameDurations.count
                let blend = allowsBlend ? min(max(elapsed / duration, 0), 1) : 0
                return SceneParticleSpriteFrameSelection(
                    currentIndex: index,
                    nextIndex: allowsBlend ? next : index,
                    mix: blend
                )
            }
            elapsed -= duration
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
    case worldScreen
    case worldUpright
    case worldFixed

    nonisolated init(authoredValue: String?, isWorldSpace: Bool = false) {
        switch (authoredValue?.lowercased(), isWorldSpace) {
        case ("upright", false), ("vertical", false): self = .upright
        case ("upright", true), ("vertical", true): self = .worldUpright
        case ("fixed", false), ("world", false), ("worldspace", false): self = .fixed
        case ("fixed", true), ("world", true), ("worldspace", true): self = .worldFixed
        case (_, true): self = .worldScreen
        default: self = .screen
        }
    }

    nonisolated var isFixed: Bool {
        self == .fixed || self == .worldFixed
    }

    nonisolated var isWorldSpace: Bool {
        switch self {
        case .worldScreen, .worldUpright, .worldFixed: true
        case .screen, .upright, .fixed: false
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
        case .screen, .worldScreen:
            return SceneParticleOrientationBasis.orthonormalized(
                right: cameraRight,
                up: cameraUp
            )
        case .upright, .worldUpright:
            let up = SceneParticleOrientationBasis.normalized(
                worldUp,
                fallback: SIMD3(0, 1, 0)
            )
            let horizontal = simd_cross(cameraForward, up)
            let aligned = simd_dot(horizontal, cameraRight) < 0 ? -horizontal : horizontal
            let right = simd_length_squared(aligned) > 1e-8 ? aligned : cameraRight
            return SceneParticleOrientationBasis.orthonormalized(right: right, up: up)
        case .fixed, .worldFixed:
            return SceneParticleOrientationBasis.orthonormalized(
                right: fixedRight,
                up: fixedUp
            )
        }
    }

    nonisolated func fixedBasisVectors(
        axis rawAxis: SIMD3<Float>,
        layerModel: simd_float4x4
    ) -> (right: SIMD3<Float>, up: SIMD3<Float>) {
        let axisLength = simd_length_squared(rawAxis)
        let normal = axisLength.isFinite && axisLength > 1e-8
            ? rawAxis / sqrt(axisLength)
            : SIMD3<Float>(0, 0, 1)
        let reference = abs(normal.y) < 0.999
            ? SIMD3<Float>(0, 1, 0)
            : SIMD3<Float>(1, 0, 0)
        let localRight = simd_normalize(simd_cross(reference, normal))
        let localUp = simd_normalize(simd_cross(normal, localRight))
        let basisModel = isWorldSpace
            ? simd_float4x4(
                SIMD4(1, 0, 0, 0),
                SIMD4(0, -1, 0, 0),
                SIMD4(0, 0, 1, 0),
                SIMD4(0, 0, 0, 1)
            )
            : layerModel
        let transformedRight = basisModel * SIMD4(localRight.x, localRight.y, localRight.z, 0)
        let transformedUp = basisModel * SIMD4(localUp.x, localUp.y, localUp.z, 0)
        return (
            SIMD3(transformedRight.x, transformedRight.y, transformedRight.z),
            SIMD3(transformedUp.x, transformedUp.y, transformedUp.z)
        )
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

    nonisolated func orientedForTrail(_ enabled: Bool) -> SceneParticleFrameTransform {
        enabled ? verticalTrailSlice(tailPosition: 0, headPosition: 1) : self
    }

    nonisolated func verticalTrailSlice(
        tailPosition: Float,
        headPosition: Float
    ) -> SceneParticleFrameTransform {
        SceneParticleFrameTransform(
            origin: origin + yAxis * (1 - tailPosition),
            xAxis: yAxis * (tailPosition - headPosition),
            yAxis: xAxis
        )
    }
}

// Eight float4 values keep this layout identical to ParticleInstance in MSL.
nonisolated struct SceneParticleGPUInstance: Sendable {
    var positionAndSize: SIMD4<Float>
    var rotationAndAlpha: SIMD4<Float>
    var colorAndFrameMix: SIMD4<Float>
    var frame0A: SIMD4<Float>
    var frame0B: SIMD4<Float>
    var frame1A: SIMD4<Float>
    var frame1B: SIMD4<Float>
    var velocityAndTrail: SIMD4<Float>

    nonisolated init(
        position: SIMD3<Float>,
        size: Float,
        rotation: SIMD3<Float>,
        color: SIMD3<Float>,
        alpha: Float,
        velocity: SIMD3<Float> = .zero,
        trailStretch: Float? = nil,
        trailUVRange: SIMD2<Float>? = nil,
        usesTrailDisplacement: Bool = false,
        currentFrame: SceneParticleFrameTransform = .identity,
        nextFrame: SceneParticleFrameTransform? = nil,
        currentFrameAspect: Float = 1,
        nextFrameAspect: Float? = nil,
        frameMix: Float = 0
    ) {
        let following = nextFrame ?? currentFrame
        let currentAspect = Self.validAspect(currentFrameAspect) ? currentFrameAspect : 1
        let authoredNextAspect = nextFrameAspect ?? currentAspect
        let followingAspect = Self.validAspect(authoredNextAspect) ? authoredNextAspect : currentAspect
        // Wallpaper Engine's generic particle vertex stream publishes half of
        // the authored particle size. Its stock vertex shader then expands the
        // quad around the center with `(uv - 0.5)`. Keep the authored value in
        // the simulator for operators/collision, and apply this geometry-only
        // conversion at the final GPU record boundary.
        positionAndSize = SIMD4(position.x, position.y, position.z, size * 0.5)
        rotationAndAlpha = SIMD4(rotation.x, rotation.y, rotation.z, alpha)
        colorAndFrameMix = SIMD4(color.x, color.y, color.z, min(max(frameMix, 0), 1))
        frame0A = SIMD4(
            currentFrame.origin.x,
            currentFrame.origin.y,
            currentFrame.xAxis.x,
            currentFrame.xAxis.y
        )
        let range = trailUVRange
            ?? (trailStretch == nil
                ? SIMD2(currentAspect, followingAspect)
                : SIMD2<Float>(0, 1))
        frame0B = SIMD4(
            currentFrame.yAxis.x,
            currentFrame.yAxis.y,
            range.x,
            range.y
        )
        frame1A = SIMD4(
            following.origin.x,
            following.origin.y,
            following.xAxis.x,
            following.xAxis.y
        )
        frame1B = SIMD4(
            following.yAxis.x,
            following.yAxis.y,
            usesTrailDisplacement ? 1 : 0,
            0
        )
        velocityAndTrail = SIMD4(
            velocity.x,
            velocity.y,
            velocity.z,
            trailStretch.map { max($0, 0) } ?? -1
        )
    }

    private static func validAspect(_ value: Float) -> Bool {
        value.isFinite && value >= 1.0 / 64.0 && value <= 64
    }
}

nonisolated struct SceneParticleLayerUniforms: Sendable {
    var viewProjection: simd_float4x4
    var layerModel: simd_float4x4
    var basisRight: SIMD4<Float>
    var basisUp: SIMD4<Float>
    var viewportSize: SIMD2<Float>

    nonisolated init(
        viewProjection: simd_float4x4,
        layerModel: simd_float4x4,
        basis: SceneParticleOrientationBasis,
        viewportSize: SIMD2<Float> = SIMD2(repeating: 1)
    ) {
        self.viewProjection = viewProjection
        self.layerModel = layerModel
        basisRight = SIMD4(basis.right.x, basis.right.y, basis.right.z, 0)
        basisUp = SIMD4(basis.up.x, basis.up.y, basis.up.z, 0)
        self.viewportSize = viewportSize.x.isFinite && viewportSize.y.isFinite
            && viewportSize.x > 0 && viewportSize.y > 0
            ? viewportSize : SIMD2(repeating: 1)
    }
}

extension SIMD3 where Scalar == Double {
    var particleFloatValue: SIMD3<Float> {
        SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}
