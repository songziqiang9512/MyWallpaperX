import CoreGraphics
import Foundation
import Metal
import simd

enum SceneTextureCandidateLoadOutcome {
    case loaded(SceneTextureCandidate)
    case failed(SceneTextureLoadOutcome)
}

extension SceneTextureLoader {
    func loadCandidate(
        from url: URL,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureCandidateLoadOutcome {
        let source = sourceKey(for: url)
        let outcome = load(
            from: url,
            source: source,
            purpose: purpose,
            device: device
        )
        guard case .loaded(let texture) = outcome else {
            return .failed(outcome)
        }
        let isTex = url.pathExtension.lowercased() == "tex"
        let parsedContainer = texContainer(from: url, source: source)
        guard !isTex || parsedContainer != nil else {
            return .failed(.decodeFailed(
                "typed slot candidate requires parsed TEX metadata"
            ))
        }
        let container = isTex ? parsedContainer : nil
        guard container?.imageCount ?? 1 == 1,
              !(container?.isAnimated ?? false),
              container?.spriteFrames.isEmpty ?? true else {
            return .failed(.decodeFailed(
                "typed slot candidate requires one non-sprite image"
            ))
        }
        let physicalSize = CGSize(width: texture.width, height: texture.height)
        let mappedSize: CGSize
        if let container {
            guard let firstMip = container.mips.first,
                  container.textureWidth > 0,
                  container.textureHeight > 0,
                  container.imageWidth > 0,
                  container.imageHeight > 0,
                  container.imageWidth <= container.textureWidth,
                  container.imageHeight <= container.textureHeight,
                  firstMip.width == container.textureWidth,
                  firstMip.height == container.textureHeight,
                  texture.width == container.textureWidth,
                  texture.height == container.textureHeight else {
                return .failed(.decodeFailed(
                    "typed slot candidate has inconsistent physical/mapped dimensions"
                ))
            }
            mappedSize = CGSize(
                width: container.imageWidth,
                height: container.imageHeight
            )
        } else {
            mappedSize = physicalSize
        }
        let uvScale = SIMD2<Float>(
            Float(mappedSize.width / physicalSize.width),
            Float(mappedSize.height / physicalSize.height)
        )
        return .loaded(SceneTextureCandidate(
            texture: texture,
            identity: .file(path: source.path),
            generation: .file(
                byteCount: source.size,
                modifiedAtBits: source.modifiedAtBits
            ),
            purpose: purpose,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: SceneTextureUVTransform(
                origin: .zero,
                xAxis: SIMD2(uvScale.x, 0),
                yAxis: SIMD2(0, uvScale.y)
            ),
            sampling: container.map { SceneTextureSampling(texFlags: $0.flags) }
                ?? .directImageFallback
        ))
    }
}
