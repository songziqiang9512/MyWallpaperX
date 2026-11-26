import Foundation

struct SceneParticleChildAdvanceResult {
    let batches: [SceneParticleDrawBatch]
#if DEBUG
    let limitationDetails: [String]
#endif
}

struct SceneParticleChildRendererKey: Hashable {
    let templateIndex: Int
    let rendererIndex: Int
}

#if DEBUG
struct SceneParticleChildAudioEvaluationObservation {
    let particlePath: String
    let evaluation: SceneParticleAudioEvaluationObservation
}
#endif

struct SceneParticleChildSystem {
    let id: UInt64
    let templateIndex: Int
    let depth: Int
    let spawnScopeID: UInt64?
    var parentParticleID: UInt64?
    let isWorldSpace: Bool
    var origin: SIMD3<Double>
    var particleOrigins: [UInt64: SIMD3<Double>]
    var simulator: SceneParticleSimulator
    var receivedControlPoints: UInt8 = 0
}

struct SceneParticleChildParentFrame {
    let systemID: UInt64
    let path: String
    let origin: SIMD3<Double>
    let scale: SIMD3<Double>
    let particleOrigins: [UInt64: SIMD3<Double>]
    let births: [SceneParticleState]
    let deaths: [SceneParticleState]
    let particles: ArraySlice<SceneParticleState>
    let streamPoints: [SIMD3<Double>]

    func position(for particle: SceneParticleState) -> SIMD3<Double> {
        (particleOrigins[particle.id] ?? origin) + scale * particle.position
    }
}
