import Metal
import simd

/// Optional root draw owned by a particle layer. A stock particle definition may
/// be a child-system container and therefore have no root renderer at all.
/// Such a container must not manufacture a sprite draw or a root simulator.
struct SceneParticleRootRenderRuntime {
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
    let instanceBuffer = SceneParticleMetalInstanceBuffer()
    var instances: [SceneParticleGPUInstance] = []
    var simulator: SceneParticleSimulator
    var ropeTrailHistory: SceneParticleRopeTrailHistory?
}

/// Per-layer mutable particle state owned by one SceneParticleRuntime launch.
/// Root draw state and child-system state are separate official lifecycles: a
/// layer may own both, or a strict child-only container may own only the latter.
struct SceneParticleLayerRuntime {
    let layerID: Int
    let particlePath: String
    let definition: SceneParticleDefinition
    let layerAlpha: Float
    var rootRender: SceneParticleRootRenderRuntime?
    var childRuntime: SceneParticleChildRuntime?
}
