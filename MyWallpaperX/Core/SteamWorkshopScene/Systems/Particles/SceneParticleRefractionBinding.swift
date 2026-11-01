import Metal

struct SceneParticleRefractionBinding {
    enum ColorEncoding: UInt32 {
        case rgba = 0
        case luminanceAlpha = 1
    }

    struct NormalArguments {
        let texture: MTLTexture
        let usesParticleFrames: Bool
        let uvScale: SIMD2<Float>
        let sampling: SceneParticleTextureSampling
        let authoredFormat: SceneShaderTextureFormat?
    }

    private enum NormalSource {
        case staticCandidate(SceneTextureCandidate)
        case baseV1(
            texture: MTLTexture,
            usesParticleFrames: Bool,
            uvScale: SIMD2<Float>,
            sampling: SceneParticleTextureSampling,
            authoredFormat: SceneShaderTextureFormat?
        )
    }

    private let normalSource: NormalSource
    let amount: Float
    let overbright: Float
    let colorEncoding: ColorEncoding

    init(
        normalTexture: MTLTexture,
        amount: Float,
        overbright: Float,
        colorEncoding: ColorEncoding,
        normalUsesParticleFrames: Bool,
        normalUVScale: SIMD2<Float>,
        normalSampling: SceneParticleTextureSampling,
        normalFormat: SceneShaderTextureFormat?
    ) {
        normalSource = .baseV1(
            texture: normalTexture,
            usesParticleFrames: normalUsesParticleFrames,
            uvScale: normalUVScale,
            sampling: normalSampling,
            authoredFormat: normalFormat
        )
        self.amount = amount
        self.overbright = overbright
        self.colorEncoding = colorEncoding
    }

    init?(
        normalCandidate: SceneTextureCandidate,
        amount: Float,
        overbright: Float,
        colorEncoding: ColorEncoding
    ) {
        guard Self.resolve(normalCandidate) != nil else {
            return nil
        }
        normalSource = .staticCandidate(normalCandidate)
        self.amount = amount
        self.overbright = overbright
        self.colorEncoding = colorEncoding
    }

    func resolvedNormalArguments() -> NormalArguments? {
        switch normalSource {
        case .staticCandidate(let candidate):
            return Self.resolve(candidate)
        case let .baseV1(texture, usesParticleFrames, uvScale, sampling, authoredFormat):
            guard authoredFormat == nil || authoredFormat == .rgba8888
                || authoredFormat == .rg88 || authoredFormat == .dxt5
                else { return nil }
            if let authoredFormat {
                guard texture.pixelFormat == .rgba8Unorm
                    || (texture.pixelFormat == .rg8Unorm && authoredFormat == .rg88)
                    || (texture.pixelFormat == .bc3_rgba && authoredFormat == .dxt5)
                    else { return nil }
            }
            return NormalArguments(
                texture: texture,
                usesParticleFrames: usesParticleFrames,
                uvScale: uvScale,
                sampling: sampling,
                authoredFormat: authoredFormat
            )
        }
    }

    var usesStaticNormalCandidate: Bool {
        if case .staticCandidate = normalSource {
            return true
        }
        return false
    }

    private static func resolve(
        _ candidate: SceneTextureCandidate
    ) -> NormalArguments? {
        // A two-channel authored normal (rg88) has no blue or alpha storage.
        // The particle refraction shader decodes X from the sampled alpha and
        // Y from green, with red as mask; an rg8Unorm sample supplies A=1, so
        // rg88 reads as X=+1 with the authored red mask. stock light_shafts_0
        // keeps red at 255, which matches that decode.
        guard let authoredFormat = candidate.authoredFormat,
              authoredFormat == .rgba8888 || authoredFormat == .rg88
                || authoredFormat == .dxt5,
              let uvScale = candidate.axisAlignedMappedUVScale(
            expectedPurpose: .normal
        ), candidate.pixelFormat == .rgba8Unorm
            || (candidate.pixelFormat == .rg8Unorm && authoredFormat == .rg88)
            || (candidate.pixelFormat == .bc3_rgba && authoredFormat == .dxt5),
              candidate.texture.textureType == .type2D,
              candidate.texture.sampleCount == 1,
              candidate.texture.usage.contains(.shaderRead),
              !candidate.sampling.usesClampBorderFallback else {
            return nil
        }
        return NormalArguments(
            texture: candidate.texture,
            usesParticleFrames: false,
            uvScale: uvScale,
            sampling: candidate.sampling,
            authoredFormat: authoredFormat
        )
    }
}
