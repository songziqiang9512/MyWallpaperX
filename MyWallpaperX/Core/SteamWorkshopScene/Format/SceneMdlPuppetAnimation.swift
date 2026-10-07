struct SceneMdlPuppetAnimation {
    struct Transform: Equatable, Sendable {
        let translation: SIMD3<Float>
        let rotation: SIMD3<Float>
        let scale: SIMD3<Float>
    }

    let id: Int
    let name: String
    let mode: String
    let framesPerSecond: Float
    let frameCount: Int
    let transformsByBone: [[Transform]]
    /// Exported per-bone alpha samples use the same frame schedule as TRS.
    /// Absence means opaque; exported values are consumed directly.
    let alphaByBone: [[Float]]?

    init(
        id: Int,
        name: String,
        mode: String,
        framesPerSecond: Float,
        frameCount: Int,
        transformsByBone: [[Transform]],
        alphaByBone: [[Float]]? = nil
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.framesPerSecond = framesPerSecond
        self.frameCount = frameCount
        self.transformsByBone = transformsByBone
        self.alphaByBone = alphaByBone
    }

    nonisolated var durationSeconds: Float {
        Float(frameCount) / framesPerSecond
    }
}

struct SceneMdlPuppetAnimationSet {
    let boneCount: Int
    let animations: [SceneMdlPuppetAnimation]
}
