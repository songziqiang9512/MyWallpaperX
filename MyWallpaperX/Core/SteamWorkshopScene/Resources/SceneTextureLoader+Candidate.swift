import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

enum SceneTextureCandidateLoadOutcome {
    case loaded(SceneTextureCandidate)
    case failed(SceneTextureLoadOutcome)
}

struct SceneAnimatedTextureCandidate {
    let candidate: SceneTextureCandidate
    let frames: [SceneTexContainer.SpriteFrame]
}

enum SceneAnimatedTextureCandidateLoadOutcome {
    case loaded(SceneAnimatedTextureCandidate)
    case failed(SceneTextureLoadOutcome)
}

enum SceneAnimatedMaterialAtlasAdmission {
    case valid
    case invalidFrameMetadata
    case unsupportedStructure
}

extension SceneTextureLoader {
    func loadCandidate(
        from url: URL,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureCandidateLoadOutcome {
        guard let source = sourceKey(for: url) else {
            return .failed(.decodeFailed(
                "file metadata unavailable: \(url.lastPathComponent)"
            ))
        }
        let outcome = load(
            from: url,
            source: source,
            purpose: purpose,
            device: device
        )
        guard case .loaded(let texture) = outcome else {
            return .failed(outcome)
        }
        guard texture.textureType == .type2D else {
            return .failed(.decodeFailed(
                "typed slot candidate requires a 2D texture"
            ))
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
        return makeCandidate(
            texture: texture,
            container: container,
            source: source,
            url: url,
            purpose: purpose
        )
    }

    /// Catalog-only admission for one parsed single-image atlas. This keeps
    /// ordinary candidate loading static while sharing its exact file/device
    /// cache and typed candidate construction.
    func loadAnimatedMaterialCandidate(
        from url: URL,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneAnimatedTextureCandidateLoadOutcome {
        guard url.pathExtension.lowercased() == "tex",
              let source = sourceKey(for: url),
              let container = texContainer(from: url, source: source),
              materialAtlasAdmission(container) == .valid else {
            return .failed(.decodeFailed(
                "animated material candidate requires one finite axis-aligned atlas"
            ))
        }
        let outcome = load(
            from: url,
            source: source,
            purpose: purpose,
            device: device
        )
        guard case let .loaded(texture) = outcome else {
            return .failed(outcome)
        }
        guard case let .loaded(candidate) = makeCandidate(
            texture: texture,
            container: container,
            source: source,
            url: url,
            purpose: purpose
        ) else {
            return .failed(.decodeFailed(
                "animated material candidate has inconsistent texture geometry"
            ))
        }
        return .loaded(.init(candidate: candidate, frames: container.spriteFrames))
    }

    private func makeCandidate(
        texture: MTLTexture,
        container: SceneTexContainer?,
        source: SourceKey,
        url: URL,
        purpose: SceneTextureLoadPurpose
    ) -> SceneTextureCandidateLoadOutcome {
        guard texture.textureType == .type2D else {
            return .failed(.decodeFailed(
                "typed slot candidate requires a 2D texture"
            ))
        }
        let physicalSize: CGSize
        let mappedSize: CGSize
        if let container {
            guard let firstMip = container.mips.first,
                  container.textureWidth > 0,
                  container.textureHeight > 0,
                  container.imageWidth > 0,
                  container.imageHeight > 0,
                  container.imageWidth <= container.textureWidth,
                  container.imageHeight <= container.textureHeight,
                  let sourcePhysicalSize = candidateSourcePhysicalSize(
                      container: container,
                      firstMip: firstMip,
                      purpose: purpose
                  ),
                  let outputGeometry = candidateOutputGeometry(
                      texture: texture,
                      container: container,
                      sourcePhysicalSize: sourcePhysicalSize,
                      purpose: purpose
                  ) else {
                return .failed(.decodeFailed(
                    "typed slot candidate has inconsistent physical/mapped dimensions"
                ))
            }
            physicalSize = outputGeometry.physical
            mappedSize = outputGeometry.mapped
        } else {
            physicalSize = CGSize(width: texture.width, height: texture.height)
            mappedSize = physicalSize
        }
        let uvScale = SIMD2<Float>(
            Float(mappedSize.width / physicalSize.width),
            Float(mappedSize.height / physicalSize.height)
        )
        guard sourceKey(for: url) == source else {
            return .failed(.decodeFailed(
                "file changed while loading: \(url.lastPathComponent)"
            ))
        }
        let content: SceneTextureContent
        switch purpose {
        case .premultipliedColor:
            content = .color(.resolved(
                sourceIsProvenOpaque(
                    url: url,
                    container: container,
                    physicalSize: physicalSize,
                    mappedSize: mappedSize
                ) ? .opaque : .premultipliedAlpha
            ))
        case .straightAlbedo:
            content = .color(.resolved(.straightAlpha))
        case .preservedChannels, .mask, .noise, .flow, .phase, .normal,
             .depth, .lookupTable:
            content = .data
        }
        return .loaded(SceneTextureCandidate(
            texture: texture,
            identity: .file(path: source.path),
            generation: .file(
                byteCount: source.size,
                modifiedAtBits: source.modifiedAtBits,
                revision: SceneTextureFileRevision(
                    fileSystemID: source.fileSystemID,
                    fileID: source.fileID,
                    statusChangedAtSeconds: source.statusChangedAtSeconds,
                    statusChangedAtNanoseconds: source.statusChangedAtNanoseconds
                )
            ),
            purpose: purpose,
            content: content,
            physicalSize: physicalSize,
            mappedSize: mappedSize,
            uvTransform: SceneTextureUVTransform(
                origin: .zero,
                xAxis: SIMD2(uvScale.x, 0),
                yAxis: SIMD2(0, uvScale.y)
            ),
            sampling: container.map { SceneTextureSampling(texFlags: $0.flags) }
                ?? .directImageFallback,
            authoredFormat: container.flatMap {
                SceneShaderTextureFormat(rawValue: $0.format)
            }
        ))
    }

    private func sourceIsProvenOpaque(
        url: URL,
        container: SceneTexContainer?,
        physicalSize: CGSize,
        mappedSize: CGSize
    ) -> Bool {
        if container == nil {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return false }
            return SceneImageTextureUploader.imageHasNoAlpha(image)
        }
        guard let container else { return false }
        return container.format == 0
            && container.containerVersion == .texb0003
            && container.freeImageFormat == 2
            && physicalSize == mappedSize
            && hasValidTexb3EmbeddedMipChain(container)
    }

    func materialAtlasAdmission(
        _ container: SceneTexContainer
    ) -> SceneAnimatedMaterialAtlasAdmission {
        let tolerance: Float = 0.000_001
        guard container.imageCount == 1,
              container.isAnimated,
              !container.isVolume,
              !container.spriteFrames.isEmpty,
              container.textureWidth > 0,
              container.textureHeight > 0,
              container.imageWidth > 0,
              container.imageHeight > 0 else {
            return .unsupportedStructure
        }
        var duration: Float = 0
        for frame in container.spriteFrames {
            guard frame.imageIndex == 0,
                  frame.duration.isFinite,
                  frame.duration >= 0,
                  frame.origin.x.isFinite,
                  frame.origin.y.isFinite,
                  frame.xAxis.x.isFinite,
                  frame.xAxis.y.isFinite,
                  frame.yAxis.x.isFinite,
                  frame.yAxis.y.isFinite,
                  abs(frame.xAxis.y) <= tolerance,
                  abs(frame.yAxis.x) <= tolerance,
                  frame.origin.x >= -tolerance,
                  frame.origin.y >= -tolerance,
                  frame.xAxis.x > 0,
                  frame.yAxis.y > 0,
                  frame.origin.x + frame.xAxis.x <= 1 + tolerance,
                  frame.origin.y + frame.yAxis.y <= 1 + tolerance else {
                return .invalidFrameMetadata
            }
            duration += frame.duration > 0 ? frame.duration : 1.0 / 60.0
            guard duration.isFinite else { return .invalidFrameMetadata }
        }
        return duration > 0 ? .valid : .invalidFrameMetadata
    }

    private func candidateSourcePhysicalSize(
        container: SceneTexContainer,
        firstMip: SceneTexContainer.Mip,
        purpose: SceneTextureLoadPurpose
    ) -> CGSize? {
        let headerPhysical = CGSize(
            width: container.textureWidth,
            height: container.textureHeight
        )
        let mapped = CGSize(
            width: container.imageWidth,
            height: container.imageHeight
        )
        let firstMipSize = CGSize(width: firstMip.width, height: firstMip.height)
        let embeddedSize = container.format == 0
            ? embeddedImagePixelSize(firstMip.data)
            : nil
        if container.format == 0,
           container.containerVersion == .texb0003,
           embeddedSize != nil
            || container.freeImageFormat == 2
            || container.freeImageFormat == 13,
           !hasValidTexb3EmbeddedMipChain(container) {
            return nil
        }
        if firstMipSize == headerPhysical {
            guard embeddedSize == nil
                    || embeddedSize == headerPhysical
                    || (purpose == .premultipliedColor && embeddedSize == mapped) else {
                return nil
            }
            return headerPhysical
        }
        guard container.format == 0,
              container.containerVersion == .texb0003,
              firstMipSize == mapped,
              embeddedSize == mapped else {
            return nil
        }
        // TEXB0003 embedded PNG/JPEG resources can declare a header texture
        // extent that differs from the encoded image dimensions in the mip table.
        // The mip is the actual physical pixel source; the exact
        // mapped-size match keeps raw and BC metadata mismatches fail-closed.
        return mapped
    }

    private func hasValidTexb3EmbeddedMipChain(
        _ container: SceneTexContainer
    ) -> Bool {
        guard let first = container.mips.first else {
            return false
        }
        let expectedMagic: Data
        switch container.freeImageFormat {
        case 2:
            expectedMagic = Data([0xFF, 0xD8, 0xFF])
        case 13:
            expectedMagic = Data([0x89, 0x50, 0x4E, 0x47])
        default:
            return false
        }
        return container.mips.enumerated().allSatisfy { level, mip in
            let expectedWidth = max(1, first.width >> level)
            let expectedHeight = max(1, first.height >> level)
            return mip.width == expectedWidth
                && mip.height == expectedHeight
                && mip.data.starts(with: expectedMagic)
                && embeddedImagePixelSize(mip.data)
                    == CGSize(width: mip.width, height: mip.height)
        }
    }

    private func candidateOutputGeometry(
        texture: MTLTexture,
        container: SceneTexContainer,
        sourcePhysicalSize: CGSize,
        purpose: SceneTextureLoadPurpose
    ) -> (physical: CGSize, mapped: CGSize)? {
        let output = CGSize(width: texture.width, height: texture.height)
        let sourceMapped = CGSize(
            width: container.imageWidth,
            height: container.imageHeight
        )
        if output == sourcePhysicalSize {
            return (sourcePhysicalSize, sourceMapped)
        }
        let sourceProvenOpaqueJPEG = container.format == 0
            && container.containerVersion == .texb0003
            && container.freeImageFormat == 2
            && sourcePhysicalSize == sourceMapped
            && hasValidTexb3EmbeddedMipChain(container)
        let mayNormalizeMappedColor = purpose == .premultipliedColor
            || (purpose == .straightAlbedo && sourceProvenOpaqueJPEG)
        guard mayNormalizeMappedColor else {
            return nil
        }
        let normalizedMapped = normalizedSize(
            sourceMapped,
            maxDimension: Self.maxTextureDimension
        )
        guard output == sourceMapped || output == normalizedMapped else {
            return nil
        }
        // Color uploads may crop authored padding or proportionally normalize
        // the mapped image to the loader budget. A source-proven opaque JPEG
        // straight-albedo is also safe when it has no authored padding; padded
        // straight/data roles continue to require the exact physical extent.
        // In every accepted case the resulting texture contains only mapped
        // pixels, so its consumer UV is identity.
        return (output, output)
    }

    private func embeddedImagePixelSize(_ data: Data) -> CGSize? {
        guard data.starts(with: Data([0x89, 0x50, 0x4E, 0x47]))
                || data.starts(with: Data([0xFF, 0xD8, 0xFF])),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?
                  .intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?
                  .intValue,
              width > 0,
              height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func normalizedSize(
        _ size: CGSize,
        maxDimension: Int
    ) -> CGSize {
        let scale = min(
            1,
            Double(maxDimension) / Double(max(size.width, size.height))
        )
        return CGSize(
            width: max(1, Int(Double(size.width) * scale)),
            height: max(1, Int(Double(size.height) * scale))
        )
    }
}
