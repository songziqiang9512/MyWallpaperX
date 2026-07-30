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
                texture: texture,
                mappedUVScale: mappedUVScale,
                sampling: container.map { SceneTextureSampling(texFlags: $0.flags) }
                    ?? .directImageFallback,
                message: "; \(label) OK \(url.lastPathComponent) → "
                    + "\(texture.width)×\(texture.height)"
            )
        case .unsupportedFormat(let ext):
            return failure("; \(label) unsupported \(ext) (\(url.lastPathComponent))")
        case .unsupportedTexFormat(let code):
            return failure(
                "; \(label) unsupported .tex format \(code) (\(url.lastPathComponent))"
            )
        case .texNoEmbeddedImage:
            return failure(
                "; \(label) has no embedded JPEG/PNG (\(url.lastPathComponent))"
            )
        case .texContainsVideoPayload:
            return failure("; \(label) is mp4 payload (\(url.lastPathComponent))")
        case .decodeFailed(let message):
            return failure("; \(label) decode failed (\(message))")
        case .textureAllocationFailed(let width, let height):
            return failure("; \(label) allocation failed at \(width)×\(height)")
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

    private static func failure(_ message: String) -> SceneEffectTextureLoadResult {
        SceneEffectTextureLoadResult(
            texture: nil,
            mappedUVScale: SIMD2(repeating: 1),
            sampling: .directImageFallback,
            message: message
        )
    }
}
