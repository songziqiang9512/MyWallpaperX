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

    nonisolated var durationSeconds: Float {
        Float(frameCount) / framesPerSecond
    }
}

struct SceneMdlPuppetAnimationSet {
    let boneCount: Int
    let animations: [SceneMdlPuppetAnimation]
}
