extension Harness {
    static func baseAndSpriteCases(
        device: MTLDevice,
        loader: SceneTextureLoader,
        spriteTextureLoader: SceneMultiImageSpriteTextureLoader,
        imageLayerLibrary: MTLLibrary,
        directory: URL,
        url: URL,
        spriteURL: URL,
        crossImageSpriteURL: URL,
        rotatedCrossImageSpriteURL: URL,
        mismatchedPhysicalURL: URL,
        fallbackPNGURL: URL,
        unparsedFallbackURL: URL,
        croppedColorURL: URL,
        nearestRepeatColorURL: URL,
        clampBorderColorURL: URL,
        unknownSamplerColorURL: URL
    ) throws -> [String: Any] {
        let baseDirect = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: .externalFile(fallbackPNGURL),
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let baseCropped = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: .externalFile(croppedColorURL),
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let clampBorderBaseLoadRejected: Bool
        switch SceneBaseImageTextureLoad.load(
            from: .externalFile(clampBorderColorURL),
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ) {
        case .failed(.decodeFailed(let message)):
            clampBorderBaseLoadRejected = message.contains("clamp-border")
                && message.contains("rawFlags=8")
        default:
            clampBorderBaseLoadRejected = false
        }
        let unknownSamplerBaseLoadRejected: Bool
        switch SceneBaseImageTextureLoad.load(
            from: .externalFile(unknownSamplerColorURL),
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ) {
        case .failed(.decodeFailed(let message)):
            unknownSamplerBaseLoadRejected = message.contains("unknown")
                && message.contains("rawFlags=16")
        default:
            unknownSamplerBaseLoadRejected = false
        }
        let baseNearestRepeat = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: .externalFile(nearestRepeatColorURL),
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let basePaddedSpecialized = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: .externalFile(url),
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let baseSpritePlayback = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: .externalFile(spriteURL),
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let baseCrossImageSprite = try baseLoaded(
            SceneBaseImageTextureLoad.load(
                from: .externalFile(crossImageSpriteURL),
                usesPuppet: false,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
        )
        let baseRotatedCrossImageSprite = try baseLoaded(
            SceneBaseImageTextureLoad.load(
                from: .externalFile(rotatedCrossImageSpriteURL),
                usesPuppet: false,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
        )
        let baseBudgetLimitedCrossImageSprite = try baseLoaded(
            SceneBaseImageTextureLoad.load(
                from: .externalFile(crossImageSpriteURL),
                usesPuppet: false,
                loader: loader,
                spriteTextureLoader: SceneMultiImageSpriteTextureLoader(
                    residentByteBudget: 1
                ),
                device: device
            )
        )
        guard let crossImageAnimation = baseCrossImageSprite.animation,
              let commandQueue = device.makeCommandQueue() else {
            throw HarnessError.loadFailed
        }
        let firstFrameCommandBuffer = commandQueue.makeCommandBuffer()!
        let firstFrameTransaction = SceneSourceUpdateTransaction()
        crossImageAnimation.encode(
            playbackTime: 0,
            commandBuffer: firstFrameCommandBuffer,
            transaction: firstFrameTransaction
        )
        firstFrameCommandBuffer.commit()
        firstFrameTransaction.commit()
        firstFrameCommandBuffer.waitUntilCompleted()
        let crossImageFrame0Pixel = try readFirstPixel(
            texture: baseCrossImageSprite.texture,
            device: device
        )
        let secondFrameCommandBuffer = commandQueue.makeCommandBuffer()!
        let secondFrameTransaction = SceneSourceUpdateTransaction()
        crossImageAnimation.encode(
            playbackTime: 0.04,
            commandBuffer: secondFrameCommandBuffer,
            transaction: secondFrameTransaction
        )
        secondFrameCommandBuffer.commit()
        secondFrameTransaction.commit()
        secondFrameCommandBuffer.waitUntilCompleted()
        let crossImageFrame1Pixel = try readFirstPixel(
            texture: baseCrossImageSprite.texture,
            device: device
        )
        let boundaryURL = directory.appendingPathComponent("sprite-boundaries.tex")
        try crossImageSpriteBC3Tex(frameCount: 64, frameDuration: 0.1).write(to: boundaryURL)
        let boundarySprite = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: .externalFile(boundaryURL), usesPuppet: false, loader: loader,
            spriteTextureLoader: spriteTextureLoader, device: device
        ))
        let boundaryAnimation = boundarySprite.animation!
        var boundaryPixelsMatch = true
        var boundaryCases: [(Float, Int)] = [(0, 0), (boundaryAnimation.duration, 0), (-0.001, 63)]
        for index in 1..<64 {
            let time = boundaryAnimation.frameEndTimes[index - 1]
            boundaryCases += [(time.nextDown, index - 1), (time, index), (time.nextUp, index)]
        }
        for (time, index) in boundaryCases {
            let buffer = commandQueue.makeCommandBuffer()!
            let transaction = SceneSourceUpdateTransaction()
            boundaryAnimation.encode(playbackTime: time, commandBuffer: buffer, transaction: transaction)
            buffer.commit()
            transaction.commit()
            buffer.waitUntilCompleted()
            let pixel = try readFirstPixel(texture: boundarySprite.texture, device: device)
            let expected = index % 2 == 0 ? crossImageFrame0Pixel : crossImageFrame1Pixel
            boundaryPixelsMatch = boundaryPixelsMatch && pixel == expected && buffer.status == .completed
        }
        let crossImageTransform = crossImageAnimation.transform(at: 0.04)
        let basePuppetSpecialized = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: .externalFile(croppedColorURL),
            usesPuppet: true,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let sourceContinuity = try sourceContinuityProbe(
            directory: directory, pngURL: fallbackPNGURL,
            loader: loader, spriteTextureLoader: spriteTextureLoader, device: device
        )
        let baseUnparsedOutcome = SceneBaseImageTextureLoad.load(
            from: .externalFile(unparsedFallbackURL),
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        )
        let baseUnparsedRejected: Bool
        if case .failed(.decodeFailed) = baseUnparsedOutcome {
            baseUnparsedRejected = true
        } else {
            baseUnparsedRejected = false
        }
        let baseCandidateFailureTerminal = baseRejectedDimensions(
            SceneBaseImageTextureLoad.load(
                from: .externalFile(mismatchedPhysicalURL),
                usesPuppet: false,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
        )
        guard let baseDirectCandidate = baseDirect.candidate else {
            throw HarnessError.loadFailed
        }
        let mappedNearestCandidate = copy(
            baseDirectCandidate,
            mappedSize: CGSize(
                width: baseDirectCandidate.physicalSize.width / 2,
                height: baseDirectCandidate.physicalSize.height
            ),
            uvTransform: SceneTextureUVTransform(
                origin: .zero,
                xAxis: SIMD2(0.5, 0),
                yAxis: SIMD2(0, 1)
            ),
            sampling: SceneTextureSampling(texFlags: 1)
        )
        let mappedNearestSample = SceneBaseImageTextureCandidateResolver.sample(
            candidate: mappedNearestCandidate,
            sourceTexture: mappedNearestCandidate.texture
        )
        let layerRepeatLinear = SceneTextureSampling(texFlags: 1).applying(
            clampUVs: false,
            noInterpolation: false
        )
        let layerClampNearest = SceneTextureSampling(texFlags: 0).applying(
            clampUVs: true,
            noInterpolation: true
        )
        let layerOmissionPreservesSource = SceneTextureSampling(texFlags: 1).applying(
            clampUVs: nil,
            noInterpolation: nil
        )
        let clampBorderSample = SceneBaseImageTextureCandidateResolver.sample(
            candidate: copy(
                baseDirectCandidate,
                sampling: SceneTextureSampling(texFlags: 8)
            ),
            sourceTexture: baseDirectCandidate.texture
        )
        let unknownFlagsSample = SceneBaseImageTextureCandidateResolver.sample(
            candidate: copy(
                baseDirectCandidate,
                sampling: SceneTextureSampling(texFlags: 16)
            ),
            sourceTexture: baseDirectCandidate.texture
        )
        guard let mappedNearestSample else { throw HarnessError.loadFailed }
        let compositor = SceneImageLayerCompositor()
        let values = SceneImageLayerUniformValues(
            time: 0,
            alpha: 1,
            cursorUV: .zero,
            tint: SIMD3(repeating: 1)
        )
        let sourceUniforms = compositor.sourceFragmentUniforms(
            for: .init(
                layer: .init(contentKind: "image", brightness: nil),
                texture: baseDirect.texture,
                uniforms: values,
                dependencyEffects: [],
                effectSourceExtent: nil,
                sourceSample: mappedNearestSample
            ),
            routesOffscreen: true
        )
        let sourceFragmentUniformCarriesCandidateAtom =
            sourceUniforms?.sourceSampling == SIMD2(3, 1)
                && sourceUniforms?.textureFrame0
                    == mappedNearestSample.textureFrame.uniform0
                && sourceUniforms?.textureFrame1
                    == mappedNearestSample.textureFrame.uniform1
        let styledSourceUniforms = compositor.sourceFragmentUniforms(
            for: .init(
                layer: .init(contentKind: "image", brightness: 1.5),
                texture: baseDirect.texture,
                uniforms: .init(
                    time: 0,
                    alpha: 0.5,
                    cursorUV: .zero,
                    tint: SIMD3(0.2, 0.4, 0.6)
                ),
                dependencyEffects: [],
                effectSourceExtent: nil,
                sourceSample: mappedNearestSample
            ),
            routesOffscreen: true
        )
        let styledTint = styledSourceUniforms?.tint
        let sourceFragmentUniformCarriesAuthoredStyle =
            styledSourceUniforms?.alpha == 0.5
                && abs((styledTint?.x ?? 0) - 0.3) < 0.000_001
                && abs((styledTint?.y ?? 0) - 0.6) < 0.000_001
                && abs((styledTint?.z ?? 0) - 0.9) < 0.000_001
                && styledTint?.w == 1
        let zeroAlphaPixel = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: .init(
                    time: 0,
                    alpha: 0,
                    cursorUV: .zero,
                    tint: SIMD3(repeating: 1)
                ),
                textureFrame: .identity,
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil
            ),
            library: imageLayerLibrary,
            device: device
        )
        let wrappedInterior = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(0.25, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: SceneTextureSampling(texFlags: 3)
            ),
            library: imageLayerLibrary,
            device: device
        )
        let repeatedOutside = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(1.25, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: mappedNearestSample.sampling
            ),
            library: imageLayerLibrary,
            device: device
        )
        let clampedOutside = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(1.25, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: SceneTextureSampling(texFlags: 3)
            ),
            library: imageLayerLibrary,
            device: device
        )
        let nearestBetweenTexels = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(0.375, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: SceneTextureSampling(texFlags: 3)
            ),
            library: imageLayerLibrary,
            device: device
        )
        let linearBetweenTexels = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(0.375, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: SceneTextureSampling(texFlags: 2)
            ),
            library: imageLayerLibrary,
            device: device
        )
        var baseStore = SceneBaseImageTextureStore()
        baseStore.set(
            baseDirect.texture,
            candidate: baseDirect.candidate,
            layerID: 7
        )
        let initialBasePublication = baseStore.publications[7]
        let staticCandidatePublicationPreservesRevision =
            initialBasePublication?.candidate.identity
                == baseDirect.candidate?.identity
            && initialBasePublication?.candidate.generation
                == baseDirect.candidate?.generation
            && initialBasePublication?.candidate.purpose
                == baseDirect.candidate?.purpose
            && initialBasePublication?.candidate.content
                == baseDirect.candidate?.content
            && initialBasePublication?.candidate.uvTransform.xAxis
                == baseDirect.candidate?.uvTransform.xAxis
            && initialBasePublication?.candidate.sampling
                == baseDirect.candidate?.sampling
            && initialBasePublication?.isComplete == true
        baseStore[7] = baseCropped.texture
        let baseStoreReplacementClearsCandidate =
            baseStore.candidates[7] == nil
                && baseStore.publications[7] == nil
        baseStore.set(
            baseDirect.texture,
            candidate: baseDirect.candidate,
            layerID: 7
        )
        let mismatchedSnapshot = baseStore.snapshot(
            textures: [7: baseCropped.texture]
        )
        let baseSnapshotDropsMismatchedCandidate =
            mismatchedSnapshot.candidate(
                for: 7,
                matching: baseCropped.texture
            ) == nil
        let mismatchedPublicationSnapshot = baseStore.snapshot(
            textures: [7: baseDirect.texture],
            explicitLayerSources: [
                7: SceneTextureProviderPublication(
                    requestIdentity: .layerSource(7),
                    candidate: baseCropped.candidate!,
                    contentGeneration: 1
                )
            ]
        )
        let baseSnapshotRejectsMismatchedPublication =
            mismatchedPublicationSnapshot[7] == nil
                && mismatchedPublicationSnapshot.explicitLayerSources[7] == nil
        return [
            "sourceContinuity": sourceContinuity,
            "baseDirectCandidate": baseDirect.candidate != nil,
            "baseDirectGeneratesMipChain":
                baseDirect.texture.mipmapLevelCount > 1,
            "baseCroppedCandidate": baseCropped.candidate != nil,
            "baseNearestRepeatCandidate":
                baseNearestRepeat.candidate?.sampling.filter == .nearest
                    && baseNearestRepeat.candidate?.sampling.addressMode
                        == .repeatWrap
                    && baseNearestRepeat.candidate?.sampling.rawFlags == 1,
            "mappedNearestCandidateSample":
                mappedNearestSample.textureFrame.xAxis == SIMD2(0.5, 0)
                    && mappedNearestSample.textureFrame.yAxis == SIMD2(0, 1)
                    && mappedNearestSample.sampling.imageLayerUniformMode == 3,
            "layerSamplerOverrideRepeatLinear":
                layerRepeatLinear.imageLayerUniformMode == 1,
            "layerSamplerOverrideClampNearest":
                layerClampNearest.imageLayerUniformMode == 2,
            "layerSamplerOmissionPreservesSource":
                layerOmissionPreservesSource.imageLayerUniformMode == 3,
            "clampBorderBaseSampleRejected": clampBorderSample == nil,
            "clampBorderBaseLoadRejected": clampBorderBaseLoadRejected,
            "unknownFlagsBaseSampleRejected": unknownFlagsSample == nil,
            "unknownSamplerBaseLoadRejected": unknownSamplerBaseLoadRejected,
            "samplerFailureDoesNotPoisonSiblingLoad":
                baseNearestRepeat.candidate != nil,
            "imageShaderUsesAuthoredRepeatSampler":
                repeatedOutside == wrappedInterior
                    && repeatedOutside != clampedOutside,
            "imageShaderUsesAuthoredNearestFilter":
                nearestBetweenTexels != linearBetweenTexels,
            "sourceFragmentUniformCarriesCandidateAtom":
                sourceFragmentUniformCarriesCandidateAtom,
            "sourceFragmentUniformCarriesAuthoredStyle":
                sourceFragmentUniformCarriesAuthoredStyle,
            "zeroAlphaPixel": zeroAlphaPixel,
            "basePaddedR8Specialized":
                basePaddedSpecialized.candidate == nil
                    && basePaddedSpecialized.message.contains("specialized authored binding"),
            "baseSpritePlayback":
                baseSpritePlayback.candidate == nil
                    && baseSpritePlayback.animation != nil,
            "baseCrossImageSpritePlayback":
                baseCrossImageSprite.candidate == nil
                    && baseCrossImageSprite.animation != nil
                    && baseCrossImageSprite.message.contains(
                        "cross-image sprite playback"
                    )
                    && baseCrossImageSprite.texture.width == 4
                    && baseCrossImageSprite.texture.height == 4
                    && crossImageTransform.origin == .zero
                    && crossImageTransform.xAxis == SIMD2(1, 0)
                    && crossImageTransform.yAxis == SIMD2(0, 1),
            "boundaryPixelsMatch": boundaryPixelsMatch,
            "baseCrossImageFrame0Pixel": crossImageFrame0Pixel,
            "baseCrossImageFrame1Pixel": crossImageFrame1Pixel,
            "baseRotatedCrossImageSpriteFailsClosed":
                baseRotatedCrossImageSprite.candidate == nil
                    && baseRotatedCrossImageSprite.animation == nil
                    && baseRotatedCrossImageSprite.message.contains(
                        "specialized authored load (multi-image TEX)"
                    ),
            "baseBudgetLimitedCrossImageSpriteFailsClosed":
                baseBudgetLimitedCrossImageSprite.candidate == nil
                    && baseBudgetLimitedCrossImageSprite.animation == nil
                    && baseBudgetLimitedCrossImageSprite.message.contains(
                        "resident budget exceeded"
                    ),
            "basePuppetCandidate":
                basePuppetSpecialized.candidate?.purpose == .straightAlbedo
                    && basePuppetSpecialized.candidate?.content
                        == .color(.resolved(.straightAlpha))
                    && basePuppetSpecialized.candidate?.uvTransform.xAxis == SIMD2(0.5, 0),
            "baseUnparsedRejected": baseUnparsedRejected,
            "baseCandidateFailureTerminal": baseCandidateFailureTerminal,
            "baseStoreReplacementClearsCandidate":
                baseStoreReplacementClearsCandidate,
            "staticCandidatePublicationPreservesRevision":
                staticCandidatePublicationPreservesRevision,
            "baseSnapshotDropsMismatchedCandidate":
                baseSnapshotDropsMismatchedCandidate,
            "baseSnapshotRejectsMismatchedPublication":
                baseSnapshotRejectsMismatchedPublication,
        ]
    }

    static func renderSample(
        texture: MTLTexture,
        uniforms: SceneLayerFragmentUniforms,
        library: MTLLibrary,
        device: MTLDevice
    ) throws -> [Int] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: descriptor),
              let pipeline = SceneImageLayerPipeline(
                  device: device,
                  pixelFormat: .rgba8Unorm,
                  library: library
              ),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.loadFailed
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: pass
        ) else { throw HarnessError.loadFailed }
        pipeline.bind(encoder: encoder)
        var mvp = matrix_identity_float4x4
        mvp.columns.0.x = 2
        mvp.columns.1.y = 2
        pipeline.drawLayer(
            texture: texture,
            mvp: mvp,
            uniforms: uniforms,
            encoder: encoder
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw HarnessError.loadFailed
        }
        return try readFirstPixel(texture: target, device: device)
    }
}
