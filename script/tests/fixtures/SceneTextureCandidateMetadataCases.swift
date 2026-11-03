extension Harness {
    static func candidateMetadataCases(
        device: MTLDevice,
        loader: SceneTextureLoader,
        url: URL,
        missingURL: URL,
        spriteURL: URL,
        zeroMappedURL: URL,
        oversizedMappedURL: URL,
        mismatchedPhysicalURL: URL,
        emptySpriteURL: URL,
        unparsedFallbackURL: URL,
        croppedColorURL: URL,
        normalizedColorURL: URL,
        wrongOutputURL: URL
    ) throws -> (first: SceneTextureCandidate, croppedColor: SceneTextureCandidate, normalizedColor: SceneTextureCandidate, result: [String: Any]) {
        let missingSourceKeyUnavailable = (try loader.sourceKey(for: missingURL)) == nil
        let missingSourceCandidateRejected: Bool
        switch (try loader.loadCandidate(
            from: missingURL,
            purpose: .mask,
            device: device
        )) {
        case .failed(.decodeFailed):
            missingSourceCandidateRejected = true
        default:
            missingSourceCandidateRejected = false
        }
        let first = try candidate((try loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        )))
        let repeated = try candidate((try loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        )))
        let flow = try candidate((try loader.loadCandidate(
            from: url,
            purpose: .flow,
            device: device
        )))
        let spriteRejected: Bool
        switch (try loader.loadCandidate(
            from: spriteURL,
            purpose: .mask,
            device: device
        )) {
        case .failed(.decodeFailed(let message)):
            spriteRejected = message.contains("one non-sprite image")
        default:
            spriteRejected = false
        }
        let zeroMappedRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: zeroMappedURL,
                purpose: .mask,
                device: device
            ))
        )
        let oversizedMappedRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: oversizedMappedURL,
                purpose: .mask,
                device: device
            ))
        )
        let mismatchedPhysicalRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: mismatchedPhysicalURL,
                purpose: .mask,
                device: device
            ))
        )
        let emptySpriteRejected = rejectedNonSprite(
            (try loader.loadCandidate(
                from: emptySpriteURL,
                purpose: .mask,
                device: device
            ))
        )
        let unparsedFallbackRejected = rejectedUnparsedMetadata(
            (try loader.loadCandidate(
                from: unparsedFallbackURL,
                purpose: .mask,
                device: device
            ))
        )
        let croppedColor = try candidate((try loader.loadCandidate(
            from: croppedColorURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let normalizedColor = try candidate((try loader.loadCandidate(
            from: normalizedColorURL,
            purpose: .premultipliedColor,
            device: device
        )))
        let wrongOutputRejected = rejectedDimensions(
            (try loader.loadCandidate(
                from: wrongOutputURL,
                purpose: .premultipliedColor,
                device: device
            ))
        )
        let result: [String: Any] = [
            "identityIsCanonicalFile": filePath(first.identity)
                == url.resolvingSymlinksInPath().standardizedFileURL.path,
            "generationIsFile": generationByteCount(first.generation) != nil,
            "firstPhysical": [
                Int(first.physicalSize.width), Int(first.physicalSize.height),
            ],
            "firstMapped": [
                Int(first.mappedSize.width), Int(first.mappedSize.height),
            ],
            "firstSampling": [
                first.sampling.filter.rawValue,
                first.sampling.addressMode.rawValue,
            ],
            "firstPixelFormat": first.pixelFormat.rawValue,
            "firstAuthoredFormat": first.authoredFormat?.rawValue ?? UInt32.max,
            "sameCandidateTexture": first.texture === repeated.texture,
            "sameCandidateGeneration": first.generation == repeated.generation,
            "sameResourceIdentityAcrossPurpose": first.identity == flow.identity,
            "sameGenerationAcrossPurpose": first.generation == flow.generation,
            "purposeCacheSeparated": first.texture !== flow.texture,
            "slotBindingRangeRejected":
                SceneTextureSlotBinding(slotIndex: -1, candidate: first) == nil
                    && SceneTextureSlotBinding(
                        slotIndex: 8,
                        candidate: first
                    ) == nil,
            "spriteRejected": spriteRejected,
            "zeroMappedRejected": zeroMappedRejected,
            "oversizedMappedRejected": oversizedMappedRejected,
            "mismatchedPhysicalRejected": mismatchedPhysicalRejected,
            "emptySpriteRejected": emptySpriteRejected,
            "unparsedFallbackRejected": unparsedFallbackRejected,
            "croppedColorPhysical": [
                Int(croppedColor.physicalSize.width),
                Int(croppedColor.physicalSize.height),
            ],
            "croppedColorMapped": [
                Int(croppedColor.mappedSize.width),
                Int(croppedColor.mappedSize.height),
            ],
            "normalizedColorPhysical": [
                Int(normalizedColor.physicalSize.width),
                Int(normalizedColor.physicalSize.height),
            ],
            "normalizedColorMapped": [
                Int(normalizedColor.mappedSize.width),
                Int(normalizedColor.mappedSize.height),
            ],
            "normalizedColorPreservesCompiledBaseLevel":
                normalizedColor.texture.mipmapLevelCount == 1,
            "wrongOutputRejected": wrongOutputRejected,
            "missingSourceKeyUnavailable": missingSourceKeyUnavailable,
            "missingSourceCandidateRejected": missingSourceCandidateRejected,
            "diagnosticCarriesContract":
                first.diagnosticSummary.contains("purpose=mask")
                    && first.diagnosticSummary.contains("physical=8x4")
                    && first.diagnosticSummary.contains("mapped=4x4")
                    && first.diagnosticSummary.contains("sampling=nearest/clampToEdge"),
        ]
        return (first, croppedColor, normalizedColor, result)
    }

    static func slotAndUVMetadataCases(
        first: SceneTextureCandidate,
        croppedColor: SceneTextureCandidate,
        normalizedColor: SceneTextureCandidate
    ) -> [String: Any] {
        let firstScale = first.axisAlignedMappedUVScale(expectedPurpose: .mask)
        let croppedColorScale = croppedColor.axisAlignedMappedUVScale(
            expectedPurpose: .premultipliedColor
        )
        let normalizedColorScale = normalizedColor.axisAlignedMappedUVScale(
            expectedPurpose: .premultipliedColor
        )

        let wrongPurposeRejected =
            first.axisAlignedMappedUVScale(expectedPurpose: .flow) == nil
        let invalidPhysical = copy(
            first,
            physicalSize: CGSize(
                width: first.physicalSize.width + 1,
                height: first.physicalSize.height
            )
        )
        let invalidMapped = copy(
            first,
            mappedSize: CGSize(
                width: first.physicalSize.width + 1,
                height: first.mappedSize.height
            )
        )
        let oversizedPhysical = copy(
            first,
            physicalSize: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: first.physicalSize.height
            )
        )
        let overflowingTransform = copy(
            first,
            uvTransform: SceneTextureUVTransform(
                origin: .zero,
                xAxis: SIMD2(Float.greatestFiniteMagnitude, 0),
                yAxis: SIMD2(0, Float.greatestFiniteMagnitude)
            )
        )
        let translated = copy(
            first,
            uvTransform: SceneTextureUVTransform(
                origin: SIMD2(0.1, 0),
                xAxis: first.uvTransform.xAxis,
                yAxis: first.uvTransform.yAxis
            )
        )
        let rotated = copy(
            first,
            uvTransform: SceneTextureUVTransform(
                origin: .zero,
                xAxis: SIMD2(0, first.uvTransform.xAxis.x),
                yAxis: SIMD2(first.uvTransform.yAxis.y, 0)
            )
        )
        let clampBorder = copy(
            first,
            sampling: SceneTextureSampling(texFlags: 8)
        )
        let firstBinding = SceneTextureSlotBinding(
            slotIndex: 0,
            candidate: first
        )
        let lastBinding = SceneTextureSlotBinding(
            slotIndex: 7,
            candidate: first
        )
        let rotatedBinding = SceneTextureSlotBinding(
            slotIndex: 1,
            candidate: rotated
        )
        let clampBorderBinding = SceneTextureSlotBinding(
            slotIndex: 1,
            candidate: clampBorder
        )
        let firstBindingScale = firstBinding?.axisAlignedUVScale(
            expectedSlotIndex: 0,
            expectedPurpose: .mask,
            allowedPixelFormats: [.r8Unorm]
        )
        return [
            "firstScale": [firstScale?.x ?? -1, firstScale?.y ?? -1],
            "wrongPurposeRejected": wrongPurposeRejected,
            "slotBindingRangeAccepted":
                firstBinding != nil && lastBinding != nil,
            "slotBindingMetadataAtomic":
                firstBinding?.texture === first.texture
                    && firstBinding?.identity == first.identity
                    && firstBinding?.generation == first.generation
                    && firstBinding?.purpose == first.purpose
                    && firstBinding?.physicalMappedResolution
                        == SIMD4(8, 4, 4, 4)
                    && firstBinding?.physicalTexelSize == SIMD2(0.125, 0.25)
                    && firstBinding?.mappedTexelSize == SIMD2(0.25, 0.25)
                    && firstBinding?.mipmapLevelCount == 1,
            "slotBindingScale": [
                firstBindingScale?.x ?? -1,
                firstBindingScale?.y ?? -1,
            ],
            "slotBindingWrongSlotRejected":
                firstBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 1,
                    expectedPurpose: .mask,
                    allowedPixelFormats: [.r8Unorm]
                ) == nil,
            "slotBindingWrongPurposeRejected":
                firstBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 0,
                    expectedPurpose: .flow,
                    allowedPixelFormats: [.r8Unorm]
                ) == nil,
            "slotBindingWrongFormatRejected":
                firstBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 0,
                    expectedPurpose: .mask,
                    allowedPixelFormats: [.rg8Unorm]
                ) == nil,
            "slotBindingIdentityRequirementRejected":
                firstBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 0,
                    expectedPurpose: .mask,
                    allowedPixelFormats: [.r8Unorm],
                    requiresIdentityUV: true
                ) == nil,
            "slotBindingInvalidCandidateRejected":
                SceneTextureSlotBinding(
                    slotIndex: 0,
                    candidate: invalidPhysical
                ) == nil,
            "slotBindingOversizedPhysicalRejected":
                SceneTextureSlotBinding(
                    slotIndex: 0,
                    candidate: oversizedPhysical
                ) == nil,
            "slotBindingOverflowingTransformRejected":
                SceneTextureSlotBinding(
                    slotIndex: 0,
                    candidate: overflowingTransform
                ) == nil,
            "slotBindingPreservesRotatedUV":
                rotatedBinding?.uvTransform.xAxis
                    == rotated.uvTransform.xAxis
                    && rotatedBinding?.axisAlignedUVScale(
                        expectedSlotIndex: 1,
                        expectedPurpose: .mask,
                        allowedPixelFormats: [.r8Unorm]
                    ) == nil,
            "slotBindingClampBorderRejected":
                clampBorderBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 1,
                    expectedPurpose: .mask,
                    allowedPixelFormats: [.r8Unorm]
                ) == nil,
            "invalidPhysicalRejected": invalidPhysical
                .axisAlignedMappedUVScale(expectedPurpose: .mask) == nil,
            "invalidMappedRejected": invalidMapped
                .axisAlignedMappedUVScale(expectedPurpose: .mask) == nil,
            "translatedRejected": translated
                .axisAlignedMappedUVScale(expectedPurpose: .mask) == nil,
            "rotatedRejected": rotated
                .axisAlignedMappedUVScale(expectedPurpose: .mask) == nil,
            "croppedColorScale": [
                croppedColorScale?.x ?? -1,
                croppedColorScale?.y ?? -1,
            ],
            "normalizedColorScale": [
                normalizedColorScale?.x ?? -1,
                normalizedColorScale?.y ?? -1,
            ],
        ]
    }

    static func sourceRevisionCases(
        device: MTLDevice,
        loader: SceneTextureLoader,
        url: URL,
        first: SceneTextureCandidate
    ) throws -> [String: Any] {
        guard case let .file(originalSource)? = try loader.sourceKey(for: url) else {
            throw HarnessError.loadFailed
        }
        let originalStatus = try fileStatus(url)
        let originalGeneration = first.generation
        Thread.sleep(forTimeInterval: 0.01)
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 3,
            payloadByte: 64
        ).write(to: url)
        try restoreTimestamps(originalStatus, at: url)
        guard case let .file(inPlaceSource)? = try loader.sourceKey(for: url) else {
            throw HarnessError.loadFailed
        }
        let inPlaceStableMetadata =
            inPlaceSource.size == originalSource.size
                && inPlaceSource.modifiedAtBits == originalSource.modifiedAtBits
                && inPlaceSource.fileSystemID == originalSource.fileSystemID
                && inPlaceSource.fileID == originalSource.fileID
        let inPlaceStatusChangeDetected =
            inPlaceSource.statusChangedAtSeconds
                != originalSource.statusChangedAtSeconds
                || inPlaceSource.statusChangedAtNanoseconds
                    != originalSource.statusChangedAtNanoseconds
        let restoredMetadata = try candidate((try loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        )))
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 3,
            payloadByte: 32
        ).write(to: url, options: .atomic)
        try restoreTimestamps(originalStatus, at: url)
        guard case let .file(atomicSource)? = try loader.sourceKey(for: url) else {
            throw HarnessError.loadFailed
        }
        let atomicReplaceMetadataPreconditions =
            atomicSource.size == inPlaceSource.size
                && atomicSource.modifiedAtBits == inPlaceSource.modifiedAtBits
                && atomicSource.fileSystemID == inPlaceSource.fileSystemID
                && atomicSource.fileID != inPlaceSource.fileID
        let atomicReplacement = try candidate((try loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        )))
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 8,
            imageWidth: 8,
            imageHeight: 8,
            flags: 0
        ).write(to: url)
        let refreshed = try candidate((try loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        )))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return [
            "generationChangedAfterRewrite": originalGeneration != refreshed.generation,
            "textureChangedAfterRewrite": first.texture !== refreshed.texture,
            "generationChangedWithRestoredSizeAndMTime":
                originalGeneration != restoredMetadata.generation,
            "textureChangedWithRestoredSizeAndMTime":
                first.texture !== restoredMetadata.texture,
            "inPlaceStableMetadata": inPlaceStableMetadata,
            "inPlaceStatusChangeDetected": inPlaceStatusChangeDetected,
            "atomicReplaceMetadataPreconditions":
                atomicReplaceMetadataPreconditions,
            "generationChangedAfterAtomicReplace":
                restoredMetadata.generation != atomicReplacement.generation,
            "textureChangedAfterAtomicReplace":
                restoredMetadata.texture !== atomicReplacement.texture,
            "refreshedPhysical": [
                Int(refreshed.physicalSize.width), Int(refreshed.physicalSize.height),
            ],
            "refreshedGenerationMatchesFileSize":
                generationByteCount(refreshed.generation)
                    == (attributes[.size] as? NSNumber)?.uint64Value,
        ]
    }
}
