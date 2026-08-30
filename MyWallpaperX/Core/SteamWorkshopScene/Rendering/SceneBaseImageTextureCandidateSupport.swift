import Metal

struct SceneBaseImageTextureSample {
    let textureFrame: SceneTextureUVTransform
    let sampling: SceneTextureSampling
}

enum SceneBaseImageTextureCandidateResolver {
    static func sample(
        candidate: SceneTextureCandidate,
        sourceTexture: MTLTexture
    ) -> SceneBaseImageTextureSample? {
        guard candidate.texture === sourceTexture,
              candidate.purpose == .premultipliedColor,
              candidate.sampling.isResolvedForMaterialProgram,
              !candidate.sampling.usesClampBorderFallback,
              (candidate.pixelFormat == .rgba8Unorm
                || candidate.pixelFormat == .bgra8Unorm),
              candidate.texture.textureType == .type2D,
              candidate.texture.sampleCount == 1,
              candidate.texture.mipmapLevelCount > 0,
              candidate.texture.usage.contains(.shaderRead),
              candidate.axisAlignedMappedUVScale(
                  expectedPurpose: .premultipliedColor
              ) != nil else {
            return nil
        }
        switch candidate.content {
        case .color(.resolved(.opaque)),
             .color(.resolved(.premultipliedAlpha)):
            break
        case .color(.resolved(.straightAlpha)),
             .color(.resolved(.independentAlphaSignal)),
             .color(.unresolved), .scalarRedUnorm, .redGreenUnorm,
             .scalarRedFloat16, .redGreenFloat16, .data:
            return nil
        }
        return .init(
            textureFrame: candidate.uvTransform,
            sampling: candidate.sampling
        )
    }

    static func textureFrame(
        candidate: SceneTextureCandidate,
        sourceTexture: MTLTexture
    ) -> SceneTextureUVTransform? {
        sample(candidate: candidate, sourceTexture: sourceTexture)?.textureFrame
    }
}
