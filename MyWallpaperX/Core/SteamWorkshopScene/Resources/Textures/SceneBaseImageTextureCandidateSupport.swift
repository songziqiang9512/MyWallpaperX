import Metal

struct SceneBaseImageTextureSample {
    let textureFrame: SceneTextureUVTransform
    let sampling: SceneTextureSampling
    let representation: SceneShaderColorRepresentation
    let identity: SceneTextureResourceIdentity?

    init(
        textureFrame: SceneTextureUVTransform,
        sampling: SceneTextureSampling,
        representation: SceneShaderColorRepresentation = .premultipliedAlpha,
        identity: SceneTextureResourceIdentity? = nil
    ) {
        self.textureFrame = textureFrame
        self.sampling = sampling
        self.representation = representation
        self.identity = identity
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
