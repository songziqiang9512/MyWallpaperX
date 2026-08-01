import Metal
import simd

/// Per-layer mutable particle state owned by one SceneParticleRuntime launch.
/// Keeping the renderer plan beside its simulator makes rebuild/teardown replace
/// the complete layer state rather than retaining topology across generations.
struct SceneParticleLayerRuntime {
    let layerID: Int
    let particlePath: String
    let definition: SceneParticleDefinition
    let trail: SceneParticleTrailRenderPlan?
    let rope: SceneParticleRopePlan?
    let texture: MTLTexture
    let colorUVScale: SIMD2<Float>
    let colorSampling: SceneParticleTextureSampling
    let refraction: SceneParticleRefractionBinding?
    let renderState: SceneParticlePipelineRenderState
    let spriteAnimation: SceneSpriteAnimation?
    let orientation: SceneParticleOrientation
    let orientationAxis: SIMD3<Float>?
    let usesPerspective: Bool
    let layerAlpha: Float
    let instanceBuffer = SceneParticleMetalInstanceBuffer()
    var instances: [SceneParticleGPUInstance] = []
    var simulator: SceneParticleSimulator
    var ropeTrailHistory: SceneParticleRopeTrailHistory?
    var childRuntime: SceneParticleChildRuntime?
}
