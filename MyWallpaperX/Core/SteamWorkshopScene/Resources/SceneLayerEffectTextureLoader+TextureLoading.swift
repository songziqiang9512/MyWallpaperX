import Foundation
import Metal
import simd

extension SceneLayerEffectTextureLoader {
    static func loadTexture(
        url: URL?,
        label: String,
        purpose: SceneTextureLoadPurpose,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneEffectTextureLoadResult {
        guard let url else {
            return failure("")
        }
        switch loader.load(from: url, purpose: purpose, device: device) {
        case .loaded(let texture):
            let container = loader.texContainer(from: url)
            let mappedUVScale = container.map {
                SceneTextureMappedUVScale.resolve(
                    physicalWidth: $0.textureWidth,
                    physicalHeight: $0.textureHeight,
                    mappedWidth: $0.imageWidth,
                    mappedHeight: $0.imageHeight,
                    sampledWidth: texture.width,
                    sampledHeight: texture.height
                )
            } ?? SIMD2(repeating: 1)
            return SceneEffectTextureLoadResult(
                candidate: nil,
                texture: texture,
                mappedUVScale: mappedUVScale,
                sampling: container.map { SceneTextureSampling(texFlags: $0.flags) }
                    ?? .directImageFallback,
                message: "; \(label) OK \(url.lastPathComponent) → "
                    + "\(texture.width)×\(texture.height)"
            )
        case let outcome:
            return failure(
                outcome: outcome,
                label: label,
                fileName: url.lastPathComponent
            )
        }
    }

    static func loadTextureCandidate(
        url: URL?,
        label: String,
        purpose: SceneTextureLoadPurpose,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneEffectTextureLoadResult {
        guard let url else {
            return failure("")
        }
        switch loader.loadCandidate(from: url, purpose: purpose, device: device) {
        case .loaded(let candidate):
            guard let mappedUVScale = candidate.axisAlignedMappedUVScale(
                expectedPurpose: purpose
            ) else {
                return failure("; \(label) candidate metadata failed (\(url.lastPathComponent))")
            }
            return SceneEffectTextureLoadResult(
                candidate: candidate,
                texture: candidate.texture,
                mappedUVScale: mappedUVScale,
                sampling: candidate.sampling,
                message: "; \(label) OK \(url.lastPathComponent) → "
                    + candidate.diagnosticSummary
            )
        case .failed(let outcome):
            return failure(
                outcome: outcome,
                label: label,
                fileName: url.lastPathComponent
            )
        }
    }

    static func mappedUVScale(for url: URL?, texture: MTLTexture?) -> SIMD2<Float> {
        guard let url, url.pathExtension.localizedLowercase == "tex",
              let data = try? Data(contentsOf: url),
              let container = try? SceneTexContainerReader().read(data: data) else {
            return SIMD2(repeating: 1)
        }
        return SceneTextureMappedUVScale.resolve(
            physicalWidth: container.textureWidth,
            physicalHeight: container.textureHeight,
            mappedWidth: container.imageWidth,
            mappedHeight: container.imageHeight,
            sampledWidth: texture?.width,
            sampledHeight: texture?.height
        )
    }

    private static func failure(
        outcome: SceneTextureLoadOutcome,
        label: String,
        fileName: String
    ) -> SceneEffectTextureLoadResult {
        switch outcome {
        case .loaded:
            return failure("; \(label) candidate metadata failed (\(fileName))")
        case .unsupportedFormat(let ext):
            return failure("; \(label) unsupported \(ext) (\(fileName))")
        case .unsupportedTexFormat(let code):
            return failure(
                "; \(label) unsupported .tex format \(code) (\(fileName))"
            )
        case .texNoEmbeddedImage:
            return failure(
                "; \(label) has no embedded JPEG/PNG (\(fileName))"
            )
        case .texContainsVideoPayload:
            return failure("; \(label) is mp4 payload (\(fileName))")
        case .decodeFailed(let message):
            return failure("; \(label) decode failed (\(message))")
        case .textureAllocationFailed(let width, let height):
            return failure("; \(label) allocation failed at \(width)×\(height)")
        }
    }

    private static func failure(_ message: String) -> SceneEffectTextureLoadResult {
        SceneEffectTextureLoadResult(
            candidate: nil,
            texture: nil,
            mappedUVScale: SIMD2(repeating: 1),
            sampling: .directImageFallback,
            message: message
        )
    }
}
