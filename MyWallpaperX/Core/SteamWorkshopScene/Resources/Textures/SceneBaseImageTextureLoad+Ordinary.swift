import Foundation
import Metal

extension SceneBaseImageTextureLoad {
    static func loadOrdinaryCandidate(
        from url: SceneResourceView.FileInput,
        loader: SceneTextureLoader,
        device: MTLDevice,
        purpose: SceneTextureLoadPurpose = .straightAlbedo,
        preparedTexSource: SceneTextureLoader.PreparedTexSource? = nil,
        preparedDirectImageSource: SceneTextureLoader.PreparedDirectImageSource? = nil,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> Outcome {
        if let preparedTexSource, preparedTexSource.input != url { throw SceneResourceView.ReadError.invalidHandle }
        if let preparedDirectImageSource, preparedDirectImageSource.input != url { throw SceneResourceView.ReadError.invalidHandle }
        let outcome: SceneTextureCandidateLoadOutcome
        if let preparedTexSource {
            outcome = try loader.loadCandidate(from: preparedTexSource, purpose: purpose,
                device: device, checkCancellation: checkCancellation)
        } else if let preparedDirectImageSource {
            outcome = try loader.loadCandidate(from: preparedDirectImageSource, purpose: purpose,
                device: device, checkCancellation: checkCancellation)
        } else {
            outcome = try loader.loadCandidate(from: url, purpose: purpose,
                device: device, checkCancellation: checkCancellation)
        }
        switch outcome {
        case .failed(let failure):
            return .failed(failure)
        case .loaded(let candidate):
            guard let scale = candidate.axisAlignedMappedUVScale(
                expectedPurpose: purpose
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
            guard SceneBaseImageTextureCandidateResolver.supportsColorSampling(
                pixelFormat: candidate.pixelFormat
            ) else {
                guard purpose == .premultipliedColor,
                      candidate.texture.textureType == .type2D,
                      candidate.texture.sampleCount == 1,
                      candidate.texture.usage.contains(.shaderRead) else {
                    return .failed(.decodeFailed(
                        "base color candidate has unsupported sampling format"
                            + " (\(candidate.diagnosticSummary))"
                    ))
                }
                return .loaded(Loaded(
                    texture: candidate.texture,
                    candidate: nil,
                    animation: nil,
                    baseTextureSampling: candidate.sampling,
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
                baseTextureSampling: nil,
                message: "; base color candidate \(candidate.diagnosticSummary)"
                    + " mappedScale=\(scale.x),\(scale.y)"
            ))
        }
    }
}
