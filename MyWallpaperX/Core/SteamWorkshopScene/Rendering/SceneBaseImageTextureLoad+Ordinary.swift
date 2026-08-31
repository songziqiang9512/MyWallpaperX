import Foundation
import Metal

extension SceneBaseImageTextureLoad {
    static func loadOrdinaryCandidate(
        from url: URL,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> Outcome {
        switch loader.loadCandidate(
            from: url,
            purpose: .premultipliedColor,
            device: device
        ) {
        case .failed(let failure):
            return .failed(failure)
        case .loaded(let candidate):
            guard let scale = candidate.axisAlignedMappedUVScale(
                expectedPurpose: .premultipliedColor
            ) else {
                return .failed(.decodeFailed(
                    "base color candidate failed its final purpose/UV validation"
                ))
            }
            guard !candidate.sampling.usesClampBorderFallback else {
                return .failed(.decodeFailed(
                    "base color candidate uses unsupported clamp-border sampler"
                        + " rawFlags=\(candidate.sampling.rawFlags.map(String.init) ?? "direct")"
                ))
            }
            guard candidate.sampling.isResolvedForMaterialProgram else {
                return .failed(.decodeFailed(
                    "base color candidate has unknown authored sampler flags"
                        + " rawFlags=\(candidate.sampling.rawFlags.map(String.init) ?? "direct")"
                ))
            }
            guard candidate.pixelFormat == .rgba8Unorm,
                  candidate.texture.textureType == .type2D,
                  candidate.texture.sampleCount == 1,
                  candidate.texture.usage.contains(.shaderRead) else {
                return .loaded(Loaded(
                    texture: candidate.texture,
                    candidate: nil,
                    animation: nil,
                    message: "; base color specialized authored binding"
                        + " (unsupported candidate UV/sampler:"
                        + " \(candidate.diagnosticSummary))"
                ))
            }
            guard SceneBaseImageTextureCandidateResolver.sample(
                candidate: candidate,
                sourceTexture: candidate.texture
            ) != nil else {
                return .failed(.decodeFailed(
                    "base color candidate failed its source sampling contract"
                ))
            }
            return .loaded(Loaded(
                texture: candidate.texture,
                candidate: candidate,
                animation: nil,
                message: "; base color candidate \(candidate.diagnosticSummary)"
                    + " mappedScale=\(scale.x),\(scale.y)"
            ))
        }
    }
}
