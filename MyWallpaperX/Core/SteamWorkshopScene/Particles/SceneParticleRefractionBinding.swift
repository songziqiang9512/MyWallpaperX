import Metal

struct SceneParticleRefractionBinding {
    enum ColorEncoding: UInt32 {
        case rgba = 0
        case luminanceAlpha = 1
    }

    let normalTexture: MTLTexture
    let amount: Float
    let overbright: Float
    let colorEncoding: ColorEncoding
    let normalUsesParticleFrames: Bool
    let normalUVScale: SIMD2<Float>
    let normalSampling: SceneParticleTextureSampling
}
