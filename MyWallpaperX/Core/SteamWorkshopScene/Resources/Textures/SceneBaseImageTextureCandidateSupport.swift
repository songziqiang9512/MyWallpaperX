import Metal
import simd

struct SceneBaseImageTextureSample {
    let textureFrame: SceneTextureUVTransform
    let sampling: SceneTextureSampling
    let representation: SceneShaderColorRepresentation
    let identity: SceneTextureResourceIdentity?
    let spriteFrameExtent: CGSize?

    init(
        textureFrame: SceneTextureUVTransform,
        sampling: SceneTextureSampling,
        representation: SceneShaderColorRepresentation = .premultipliedAlpha,
        identity: SceneTextureResourceIdentity? = nil,
        spriteFrameExtent: CGSize? = nil
    ) {
        self.textureFrame = textureFrame
        self.sampling = sampling
        self.representation = representation
        self.identity = identity
        self.spriteFrameExtent = spriteFrameExtent
    }

    static func spriteFrame(
        _ frame: SceneTextureUVTransform, texture: MTLTexture, sampling: SceneTextureSampling
    ) -> Self {
        let lower = frame.origin + simd_min(frame.xAxis, .zero) + simd_min(frame.yAxis, .zero)
        let upper = frame.origin + simd_max(frame.xAxis, .zero) + simd_max(frame.yAxis, .zero)
        var extent: CGSize?
        if frame.isFiniteAndNondegenerate, lower.x >= -0.000_001, lower.y >= -0.000_001,
           upper.x <= 1.000_001, upper.y <= 1.000_001,
           sampling.isResolvedForMaterialProgram, !sampling.usesClampBorderFallback {
            let atlas = SIMD2(Float(texture.width), Float(texture.height))
            let width = simd_length(frame.xAxis * atlas).rounded()
            let height = simd_length(frame.yAxis * atlas).rounded()
            if width > 0, height > 0 {
                extent = CGSize(width: CGFloat(width), height: CGFloat(height))
            }
        }
        return .init(textureFrame: frame, sampling: sampling, spriteFrameExtent: extent)
    }
}

enum SceneBaseImageTextureCandidateResolver {
    static func sample(
        candidate: SceneTextureCandidate,
        sourceTexture: MTLTexture
    ) -> SceneBaseImageTextureSample? {
        guard candidate.texture === sourceTexture,
              !candidate.isSpriteSheet,
              candidate.sampling.isResolvedForMaterialProgram,
              !candidate.sampling.usesClampBorderFallback,
              supportsColorSampling(pixelFormat: candidate.pixelFormat),
              candidate.texture.textureType == .type2D,
              candidate.texture.sampleCount == 1,
              candidate.texture.mipmapLevelCount > 0,
              candidate.texture.usage.contains(.shaderRead),
              candidate.axisAlignedMappedUVScale(
                  expectedPurpose: candidate.purpose
              ) != nil else {
            return nil
        }
        let representation: SceneShaderColorRepresentation
        switch (candidate.purpose, candidate.content) {
        case (.premultipliedColor, .color(.resolved(.opaque))):
            representation = .opaque
        case (.premultipliedColor, .color(.resolved(.premultipliedAlpha))):
            representation = .premultipliedAlpha
        case (.straightAlbedo, .color(.resolved(.straightAlpha))):
            representation = .straightAlpha
        default:
            return nil
        }
        return .init(
            textureFrame: candidate.uvTransform,
            sampling: candidate.sampling,
            representation: representation,
            identity: candidate.identity
        )
    }

    static func supportsColorSampling(pixelFormat: MTLPixelFormat) -> Bool {
        switch pixelFormat {
        case .rgba8Unorm, .bgra8Unorm, .rgba16Float,
             .bc1_rgba, .bc2_rgba, .bc3_rgba:
            return true
        default:
            return false
        }
    }

    static func textureFrame(
        candidate: SceneTextureCandidate,
        sourceTexture: MTLTexture
    ) -> SceneTextureUVTransform? {
        sample(candidate: candidate, sourceTexture: sourceTexture)?.textureFrame
    }
}
