import CoreGraphics
import Foundation
import Metal
import simd

nonisolated enum SceneTextureCandidateLoadOutcome {
    case loaded(SceneTextureCandidate)
    case failed(SceneTextureLoadOutcome)
}

nonisolated struct SceneAnimatedTextureCandidate {
    let candidate: SceneTextureCandidate
    let frames: [SceneTexContainer.SpriteFrame]
}

nonisolated enum SceneAnimatedTextureCandidateLoadOutcome {
    case loaded(SceneAnimatedTextureCandidate)
    case failed(SceneTextureLoadOutcome)
}

nonisolated enum SceneAnimatedMaterialAtlasAdmission {
    case valid
    case invalidFrameMetadata
    case unsupportedStructure
}

nonisolated extension SceneTextureLoader {
    /// One request-local decoded image serves every representation even when
    /// the persistent decode budget declines admission. Nothing is published
    /// until the source snapshot and all requested candidates are complete.
    func loadDirectImageCandidates(
        from input: Input, purposes: Set<SceneTextureLoadPurpose>, device: MTLDevice,
        isCancelled: () -> Bool = { false },
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> [SceneTextureLoadPurpose: SceneTextureCandidateLoadOutcome] {
        try checkCancellation?()
        guard !isCancelled(), let source = try sourceKey(for: input, checkCancellation: checkCancellation),
              let snapshot = try sourceSnapshot(input, source: source, checkCancellation: checkCancellation) else {
            return Dictionary(uniqueKeysWithValues: purposes.map {
                ($0, .failed(.decodeFailed("image source unavailable")))
            })
        }
        let image = SceneImageTextureUploader.decodeSourceImage(snapshot.data)
        try checkCancellation?()
        guard let image else {
            return Dictionary(uniqueKeysWithValues: purposes.map {
                ($0, .failed(.decodeFailed("image source unavailable")))
            })
        }
        recordDirectImageDecodeAttempt()
        var results: [SceneTextureLoadPurpose: SceneTextureCandidateLoadOutcome] = [:]
        for purpose in purposes.sorted(by: { $0.reportToken < $1.reportToken }) {
            try checkCancellation?()
            guard !isCancelled() else { break }
            let outcome = SceneImageTextureUploader.upload(
                image: image, purpose: purpose, maxDimension: Self.maxTextureDimension,
                uploadCommandQueue: uploadCommandQueue, device: device
            )
            if case let .loaded(texture) = outcome {
                results[purpose] = try makeCandidate(
                    texture: texture, resource: nil, source: source,
                    purpose: purpose, decodedSourceImage: image,
                    checkCancellation: checkCancellation
                )
            } else { results[purpose] = .failed(outcome) }
        }
        try checkCancellation?()
        return results
    }

    func loadDirectImageCandidates(
        from url: URL, purposes: Set<SceneTextureLoadPurpose>, device: MTLDevice,
        isCancelled: () -> Bool = { false }, checkCancellation: (() throws -> Void)? = nil
    ) throws -> [SceneTextureLoadPurpose: SceneTextureCandidateLoadOutcome] {
        try loadDirectImageCandidates(from: .externalFile(url), purposes: purposes, device: device,
            isCancelled: isCancelled, checkCancellation: checkCancellation)
    }

    func loadCandidate(
        from input: Input, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneTextureCandidateLoadOutcome {
        let isTex = input.pathExtension.lowercased() == "tex"
        if isTex {
            guard let prepared = try prepareTexSource(from: input, checkCancellation: checkCancellation) else {
                return .failed(.decodeFailed("TEX source unavailable: \(input.lastPathComponent)"))
            }
            return try loadCandidate(from: prepared, purpose: purpose, device: device,
                                     checkCancellation: checkCancellation)
        }
        guard let prepared = try prepareDirectImageSource(from: input, checkCancellation: checkCancellation) else {
            return .failed(.decodeFailed("image source unavailable: \(input.lastPathComponent)"))
        }
        return try loadCandidate(from: prepared, purpose: purpose, device: device,
                                 checkCancellation: checkCancellation)
    }

    func loadCandidate(
        from url: URL, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneTextureCandidateLoadOutcome {
        try loadCandidate(from: .externalFile(url), purpose: purpose, device: device,
                          checkCancellation: checkCancellation)
    }

    func loadCandidate(
        from prepared: PreparedTexSource, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneTextureCandidateLoadOutcome {
        try loadCandidate(from: prepared.input, source: prepared.source, prepared: prepared,
            purpose: purpose, device: device, checkCancellation: checkCancellation)
    }

    func loadCandidate(
        from prepared: PreparedDirectImageSource, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneTextureCandidateLoadOutcome {
        try loadCandidate(from: prepared.input, source: prepared.source, prepared: nil,
            preparedDirect: prepared, purpose: purpose, device: device, checkCancellation: checkCancellation)
    }

    private func loadCandidate(
        from input: Input, source: SourceKey, prepared: PreparedTexSource?,
        preparedDirect: PreparedDirectImageSource? = nil,
        purpose: SceneTextureLoadPurpose, device: MTLDevice,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneTextureCandidateLoadOutcome {
        let outcome = try load(from: input, source: source, purpose: purpose, device: device,
            preparedTexSource: prepared, preparedDirectImageSource: preparedDirect,
            checkCancellation: checkCancellation)
        guard case .loaded(let texture) = outcome else { return .failed(outcome) }
        guard texture.textureType == .type2D else {
            return .failed(.decodeFailed("typed slot candidate requires a 2D texture"))
        }
        let isTex = input.pathExtension.lowercased() == "tex"
        let container = prepared?.container
        guard !isTex || container != nil else {
            return .failed(.decodeFailed("typed slot candidate requires parsed TEX metadata"))
        }
        guard container?.imageCount ?? 1 == 1, !(container?.isAnimated ?? false),
              container?.spriteFrames.isEmpty ?? true else {
            return .failed(.decodeFailed("typed slot candidate requires one non-sprite image"))
        }
        return try makeCandidate(texture: texture, resource: prepared?.resource, source: source,
            purpose: purpose, checkCancellation: checkCancellation)
    }

    /// Catalog-only admission shares the exact source/device cache and typed
    /// candidate geometry with ordinary static texture loading.
    func loadAnimatedMaterialCandidate(
        from input: Input, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneAnimatedTextureCandidateLoadOutcome {
        guard let prepared = try prepareTexSource(from: input, checkCancellation: checkCancellation) else {
            return .failed(.decodeFailed("animated material candidate requires one finite axis-aligned atlas"))
        }
        return try loadAnimatedMaterialCandidate(from: prepared, purpose: purpose, device: device,
                                                 checkCancellation: checkCancellation)
    }

    func loadAnimatedMaterialCandidate(
        from url: URL, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneAnimatedTextureCandidateLoadOutcome {
        try loadAnimatedMaterialCandidate(from: .externalFile(url), purpose: purpose, device: device,
                                         checkCancellation: checkCancellation)
    }

    func loadAnimatedMaterialCandidate(
        from prepared: PreparedTexSource, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneAnimatedTextureCandidateLoadOutcome {
        try checkCancellation?()
        guard let container = prepared.container, materialAtlasAdmission(container) == .valid else {
            return .failed(.decodeFailed("animated material candidate requires one finite axis-aligned atlas"))
        }
        let outcome = try load(from: prepared.input, source: prepared.source, purpose: purpose,
            device: device, preparedTexSource: prepared, checkCancellation: checkCancellation)
        guard case let .loaded(texture) = outcome else { return .failed(outcome) }
        guard case let .loaded(candidate) = try makeCandidate(texture: texture, resource: prepared.resource,
            source: prepared.source, purpose: purpose,
            checkCancellation: checkCancellation) else {
            return .failed(.decodeFailed("animated material candidate has inconsistent texture geometry"))
        }
        return .loaded(.init(candidate: candidate, frames: container.spriteFrames))
    }

    private func makeCandidate(
        texture: MTLTexture,
        resource: TexResource?,
        source: SourceKey,
        purpose: SceneTextureLoadPurpose,
        decodedSourceImage: CGImage? = nil,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneTextureCandidateLoadOutcome {
        guard texture.textureType == .type2D else {
            return .failed(.decodeFailed(
                "typed slot candidate requires a 2D texture"
            ))
        }
        let container = resource?.container
        let physicalSize: CGSize
        let mappedSize: CGSize
        if let resource, let container {
            guard let firstMip = container.mips.first,
                  container.textureWidth > 0,
                  container.textureHeight > 0,
                  container.imageWidth > 0,
                  container.imageHeight > 0,
                  container.imageWidth <= container.textureWidth,
                  container.imageHeight <= container.textureHeight,
                  let sourcePhysicalSize = candidateSourcePhysicalSize(
                      container: container, resource: resource,
                      firstMip: firstMip,
                      purpose: purpose
                  ),
                  let outputGeometry = candidateOutputGeometry(
                      texture: texture,
                      container: container, resource: resource,
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
        try checkCancellation?()
        let content: SceneTextureContent
        switch purpose {
        case .premultipliedColor:
            content = .color(.resolved(
                sourceIsProvenOpaque(
                    source: source,
                    resource: resource,
                    physicalSize: physicalSize,
                    mappedSize: mappedSize,
                    decodedSourceImage: decodedSourceImage
                ) ? .opaque : .premultipliedAlpha
            ))
        case .straightAlbedo:
            content = .color(.resolved(.straightAlpha))
        case .preservedChannels, .mask, .noise, .flow, .phase, .normal,
             .depth, .lookupTable:
            content = .data
        }
        let identity: SceneTextureResourceIdentity
        let generation: SceneTextureResourceGeneration
        switch source {
        case let .file(file):
            identity = .file(path: file.path)
            generation = .file(byteCount: file.size, modifiedAtBits: file.modifiedAtBits,
                revision: .init(fileSystemID: file.fileSystemID, fileID: file.fileID,
                    statusChangedAtSeconds: file.statusChangedAtSeconds,
                    statusChangedAtNanoseconds: file.statusChangedAtNanoseconds))
        case let .package(entry):
            identity = .package(.init(packagePath: entry.packagePath, rawEntryPath: entry.rawEntryPath))
            let file = entry.fileRevision
            generation = .package(.init(fileSystemID: file.fileSystemID, fileID: file.fileID,
                fileByteCount: file.byteCount, modifiedSeconds: file.modifiedSeconds,
                modifiedNanoseconds: file.modifiedNanoseconds, changedSeconds: file.changedSeconds,
                changedNanoseconds: file.changedNanoseconds, dataStartOffset: entry.dataStartOffset,
                offset: entry.offset, byteCount: entry.byteCount))
        }
        return .loaded(SceneTextureCandidate(
            texture: texture,
            identity: identity,
            generation: generation,
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
        source: SourceKey,
        resource: TexResource?,
        physicalSize: CGSize,
        mappedSize: CGSize,
        decodedSourceImage: CGImage? = nil
    ) -> Bool {
        let container = resource?.container
        if container == nil {
            if let decodedSourceImage {
                return SceneImageTextureUploader.imageHasNoAlpha(decodedSourceImage)
            }
            return directImageFacts[source]?.isOpaque ?? false
        }
        guard let container else { return false }
        return container.format == 0
            && container.containerVersion == .texb0003
            && container.freeImageFormat == 2
            && physicalSize == mappedSize
            && resource?.hasValidTexb3EmbeddedMipChain == true
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
        container: SceneTexContainer, resource: TexResource,
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
        let embeddedSize = resource.firstEmbeddedMipSize
        if container.format == 0,
           container.containerVersion == .texb0003,
           embeddedSize != nil
            || container.freeImageFormat == 2
            || container.freeImageFormat == 13,
           !resource.hasValidTexb3EmbeddedMipChain {
            return nil
        }
        if firstMipSize == headerPhysical {
            guard embeddedSize == nil
                    || embeddedSize == headerPhysical
                    || ((purpose == .premultipliedColor || purpose == .straightAlbedo)
                        && embeddedSize == mapped) else {
                return nil
            }
            // Legacy embedded color may already contain only mapped pixels.
            // Straight sampling uses that decoded physical extent directly.
            return purpose == .straightAlbedo && embeddedSize == mapped ? mapped : headerPhysical
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

    private func candidateOutputGeometry(
        texture: MTLTexture,
        container: SceneTexContainer, resource: TexResource,
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
        let sourceMappedEmbeddedImage = container.format == 0
            && sourcePhysicalSize == sourceMapped
            && ((container.containerVersion == .texb0003
                && [2, 13].contains(container.freeImageFormat)
                && resource.hasValidTexb3EmbeddedMipChain)
                || (container.containerVersion == .texb0002
                    && resource.firstEmbeddedMipSize == sourceMapped))
        let mayNormalizeMappedColor = purpose == .premultipliedColor
            || (purpose == .straightAlbedo && sourceMappedEmbeddedImage)
        guard mayNormalizeMappedColor else {
            return nil
        }
        let normalizedMapped = normalizedSize(
            sourceMapped,
            maxDimension: Self.maxTextureDimension
        )
        guard output == sourceMapped
                || output == normalizedMapped else {
            return nil
        }
        // Color uploads may crop authored padding or proportionally normalize
        // the mapped image to the loader budget. The successful straight
        // uploader has preserved each source channel during bounded resizing
        // without an intermediate premultiplied image. Padded
        // straight/data roles still require the exact physical extent.
        // In every accepted case the resulting texture contains only mapped
        // pixels, so its consumer UV is identity.
        return (output, output)
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
