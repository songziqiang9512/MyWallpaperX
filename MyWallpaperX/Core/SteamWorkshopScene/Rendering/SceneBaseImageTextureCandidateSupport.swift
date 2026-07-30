import Metal

enum SceneBaseImageTextureCandidateResolver {
    static func textureFrame(
        candidate: SceneTextureCandidate,
        sourceTexture: MTLTexture
    ) -> SceneTextureUVTransform? {
        guard candidate.texture === sourceTexture,
              candidate.sampling == .linearClamp,
              candidate.pixelFormat == .rgba8Unorm,
              candidate.texture.textureType == .type2D,
              candidate.texture.sampleCount == 1,
              candidate.texture.usage.contains(.shaderRead),
              candidate.axisAlignedMappedUVScale(
                  expectedPurpose: .premultipliedColor
              ) == SIMD2(repeating: 1) else {
            return nil
        }
        return candidate.uvTransform
    }
}
