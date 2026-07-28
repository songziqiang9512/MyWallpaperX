import Foundation

struct SceneParticleChildSystem {
    let id: UInt64
    let templateIndex: Int
    let depth: Int
    let spawnScopeID: UInt64?
    let parentParticleID: UInt64?
    let emissionCompletionTime: Double?
    let isWorldSpace: Bool
    var origin: SIMD3<Double>
    var particleOrigins: [UInt64: SIMD3<Double>]
    var simulator: SceneParticleSimulator
}

struct SceneParticleChildParentFrame {
    let systemID: UInt64
    let path: String
    let origin: SIMD3<Double>
    let births: [SceneParticleState]
    let deaths: [SceneParticleState]
    let particles: [SceneParticleState]
}
