import Metal
import simd

struct SceneEffectTextureLoadResult {
    let texture: MTLTexture?
    let mappedUVScale: SIMD2<Float>
    let sampling: SceneTextureSampling
    let message: String
}
