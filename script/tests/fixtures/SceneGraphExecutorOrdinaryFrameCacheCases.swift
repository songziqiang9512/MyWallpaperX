private func runOrdinaryFrameCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    ordinaryGraph: Graph,
    ordinaryChain: AdmittedLayerGraph,
    ordinaryCapabilities: Capabilities,
    ordinaryClaim: Capabilities.ClaimedLayer,
    ordinaryExecutor: Executor,
    ordinaryAttemptsAfterWarmup: Int,
    ordinaryLease: SceneGraphRenderTargetLease
) -> (
    ordinaryCapability: Capabilities.LayerCapability,
    compilerCountsAfterFirst: (shader: Int, frontend: Int),
    lateCapabilities: Capabilities,
    latePreparation: Result<Executor.PreparedGraph, Executor.Failure>,
    firstTexture: MTLTexture,
    prepared: Executor.PreparedGraph,
    encodedRead: Readback,
    results: [String: Bool]
) {
    guard clear(ordinaryLease, queue: queue),
          let preparationBuffer = queue.makeCommandBuffer() else {
        fatalError("ordinary preparation setup failed")
    }
    let preparation = ordinaryExecutor.prepare(
        token: ordinaryClaim.token,
        leases: [ordinaryLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(1),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: preparationBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(prepared) = preparation,
          let firstTexture = ordinaryLease.texture(for: first),
          let outputTexture = ordinaryLease.texture(for: output),
          let prepareFirstRead = appendReadback(
              firstTexture,
              commandBuffer: preparationBuffer
          ),
          let prepareOutputRead = appendReadback(
              outputTexture,
              commandBuffer: preparationBuffer
          ) else {
        fatalError("ordinary preparation failed: \(failureCode(preparation))")
    }
    let ordinaryCapability = ordinaryCapabilities.resolve(
        ordinaryClaim.token,
        for: ordinaryChain
    )!
    let ordinaryAttemptsAfterFirstPreparation = ordinaryExecutor.materialEncoder
        .pipelineCompilationAttemptCount
    let ordinaryWarmupHitsAfterFirstPreparation = ordinaryExecutor.materialEncoder
        .launchWarmupHitCount
    let compilerCountsAfterFirst = compilerCounts(ordinaryCapability)
    preparationBuffer.commit()
    preparationBuffer.waitUntilCompleted()
    let prepareHasNoEncodingSideEffect = preparationBuffer.status == .completed
        && matches(prepareFirstRead.firstPixel, [255, 0, 0, 255])
        && matches(prepareOutputRead.firstPixel, [255, 0, 0, 255])

    let lateCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(for: ordinaryGraph, nonOverwriteNodes: [1])
    )
    let lateExecutor = Executor(
        device: device,
        capabilities: lateCapabilities
    )!
    guard let lateBuffer = queue.makeCommandBuffer() else {
        fatalError("late failure buffer unavailable")
    }
    let latePreparation = lateExecutor.prepare(
        token: ordinaryClaim.token,
        leases: [ordinaryLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(1),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: lateBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard let lateFirstRead = appendReadback(
              firstTexture,
              commandBuffer: lateBuffer
          ),
          let lateOutputRead = appendReadback(
              outputTexture,
              commandBuffer: lateBuffer
          ) else {
        fatalError("late readback unavailable")
    }
    lateBuffer.commit()
    lateBuffer.waitUntilCompleted()
    let staticClaimRejectionHasNoPartialWrite = failureCode(latePreparation)
            == Executor.Failure.invalidClaim.rawValue
        && matches(lateFirstRead.firstPixel, [255, 0, 0, 255])
        && matches(lateOutputRead.firstPixel, [255, 0, 0, 255])

    guard let encodeBuffer = queue.makeCommandBuffer() else {
        fatalError("encode buffer unavailable")
    }
    let encoded = ordinaryExecutor.encode(
        prepared,
        commandBuffer: encodeBuffer
    )
    guard let encodedRead = appendReadback(
        prepared.finalTexture,
        commandBuffer: encodeBuffer
    ) else { fatalError("encoded readback unavailable") }
    encodeBuffer.commit()
    encodeBuffer.waitUntilCompleted()
    let encodedOutputReadable = encoded
        && encodeBuffer.status == .completed
        && encodeBuffer.error == nil
        && matches(encodedRead.firstPixel, [0, 0, 255, 255])
    let sourceCaptureCoversFullTarget = encodedOutputReadable
        && matches(encodedRead.lastPixel, [0, 0, 255, 255])
    let results: [String: Bool] = [
        "prepareHasNoEncodingSideEffect": prepareHasNoEncodingSideEffect,
        "firstFrameConsumesLaunchWarmupWithoutMetalCompilation":
            ordinaryAttemptsAfterFirstPreparation == ordinaryAttemptsAfterWarmup
                && ordinaryWarmupHitsAfterFirstPreparation > 0,
        "staticClaimRejectionHasNoPartialWrite":
            staticClaimRejectionHasNoPartialWrite,
        "twoMaterialPublicationFinalized": prepared.stages.count == 1
            && prepared.stages[0].programCacheKeys.count == 2
            && prepared.stages[0].frameResources[first] != nil
            && prepared.stages[0].effectOutputResource.publication
                .requestIdentity == .graph(output),
        "encodedOutputReadable": encodedOutputReadable,
        "sourceCaptureRendersAcrossFullTarget":
            sourceCaptureCoversFullTarget,
    ]
    return (
        ordinaryCapability,
        compilerCountsAfterFirst,
        lateCapabilities,
        latePreparation,
        firstTexture,
        prepared,
        encodedRead,
        results
    )
}

private func runOrdinaryCacheCases(
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    ordinaryGraph: Graph,
    ordinaryChain: AdmittedLayerGraph,
    ordinaryClaim: Capabilities.ClaimedLayer,
    ordinaryExecutor: Executor,
    ordinaryLease: SceneGraphRenderTargetLease,
    ordinaryCapability: Capabilities.LayerCapability,
    compilerCountsAfterFirst: (shader: Int, frontend: Int),
    firstTexture: MTLTexture,
    prepared: Executor.PreparedGraph
) -> (
    failingCapabilities: Capabilities,
    firstFailedVariant: Result<[UInt8], SceneResolvedMaterialVariantCache.LaunchEnvelopeFailure>,
    secondFailedVariant: Result<[UInt8], SceneResolvedMaterialVariantCache.LaunchEnvelopeFailure>,
    results: [String: Bool]
) {
    guard let secondFrameBuffer = queue.makeCommandBuffer() else {
        fatalError("second frame buffer unavailable")
    }
    let firstTransition = prepared.stages[0]
    let secondFrame = ordinaryExecutor.prepare(
        token: ordinaryClaim.token,
        leases: [ordinaryLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(2),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: secondFrameBuffer,
        previousStates: [effect: firstTransition.transition.nextState],
        previousGraphResources: [effect: firstTransition.persistentResources],
        effectGeneration: 1,
        resetGeneration: 1
    )
    let compilerCountsAfterSecond = compilerCounts(ordinaryCapability)

    let cacheTemplate = template(for: ordinaryGraph.nodes[0])
    guard case let .success(boundedCache) =
            SceneResolvedMaterialVariantCache.launchValidated(
        template: cacheTemplate,
        textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: cacheTemplate),
        maximumVariantCount: 1
    ) else { fatalError("bounded cache rejected") }
    let boundedLaunch = boundedCache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: input
    )
    let boundedCountsAfterLaunch = boundedCache.counters
    var readyResources = prepared.stages[0].frameResources
    readyResources[input] = prepared.stages[0].effectOutputResource
        .rewrappedForGraphIdentity(input)!
    let readyVariantFrame = frame(3).overlayingGraphResources(readyResources)!
    let readyVariant = boundedCache.resolveSelection(
        readyVariantFrame.finalizationInput(
            layerID: 9001,
            renderSize: CGSize(width: extent.width, height: extent.height),
            modelViewProjection: Executor.fullTargetMVP(firstTexture),
            layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            implicitFramebufferIdentity: input
        )
    )
    let absentVariantFrame: SceneResolvedMaterialFrameSnapshot = {
        let result = SceneResolvedMaterialFrameSnapshot.validated(
            textureSnapshot: .init(
                frameEpoch: 4,
                frameIndex: 4,
                entries: [.graph(input): .absent]
            ),
            dynamicSnapshot: .empty(frameIndex: 4),
            frameInputs: .init(
                frameIndex: 4,
                screenSize: CGSize(width: extent.width, height: extent.height),
                sceneTime: 4,
                dayTime: 0,
                frameTime: 1 / 60,
                pointerCurrentNDC: .zero,
                pointerPreviousNDC: .zero
            )
        )
        guard case let .success(value) = result else {
            fatalError("absent variant frame failed")
        }
        return value
    }()
    let absentGraphOverride = boundedCache.resolveSelection(
        absentVariantFrame.finalizationInput(
            layerID: 9001,
            renderSize: CGSize(width: extent.width, height: extent.height),
            modelViewProjection: Executor.fullTargetMVP(firstTexture),
            layerModelMatrix: matrix_identity_float4x4,
            effectOutputModelViewProjection: matrix_identity_float4x4,
            effectTextureProjectionMatrixInverse: matrix_identity_float4x4,
            implicitFramebufferIdentity: input
        )
    )
    let absentGraphOverrideRejectedWithoutCompilation: Bool = {
        guard case .success = boundedLaunch,
              case .success = readyVariant,
              case let .failure(failure) = absentGraphOverride else {
            return false
        }
        return failure.phase == .texture
            && failure.code == .resourceSnapshotUnresolved
            && boundedCache.counters == boundedCountsAfterLaunch
            && boundedCache.counters.capacityRejectionCount == 0
    }()

    let failingCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(
            for: ordinaryGraph,
            frontendInvalidNodes: [0]
        )
    )
    let failingTemplate = template(
        for: ordinaryGraph.nodes[0],
        frontendInvalid: true
    )
    guard case let .success(failingVariantCache) =
            SceneResolvedMaterialVariantCache.launchValidated(
        template: failingTemplate,
        textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: failingTemplate),
        maximumVariantCount: 1
    ) else { fatalError("failing cache rejected") }
    let firstFailedVariant = failingVariantCache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: input
    )
    let failedCountsAfterFirst = failingVariantCache.counters
    let secondFailedVariant = failingVariantCache.precompileLaunchEnvelope(
        implicitFramebufferIdentity: input
    )
    let failedCountsAfterSecond = failingVariantCache.counters
    let failedVariantRejectionIsCached: Bool = {
        guard case let .failure(.material(firstFailure)) = firstFailedVariant,
              case let .failure(.material(secondFailure)) = secondFailedVariant else {
            return false
        }
        return firstFailure.code == .shaderFrontendFailed
            && secondFailure.code == firstFailure.code
            && failedCountsAfterFirst.cachedVariantCount == 1
            && failedCountsAfterFirst.shaderPreparationCount == 1
            && failedCountsAfterFirst.frontendCompilationCount == 1
            && failedCountsAfterSecond == failedCountsAfterFirst
    }()
    let results: [String: Bool] = [
        "secondFramePreviousStateAndResourcesPrepared": failureCode(secondFrame)
            == "success",
        "secondFrameReusesShaderAndFrontendVariant":
            compilerCountsAfterFirst.shader > 0
                && compilerCountsAfterFirst.frontend > 0
                && compilerCountsAfterSecond.shader
                    == compilerCountsAfterFirst.shader
                && compilerCountsAfterSecond.frontend
                    == compilerCountsAfterFirst.frontend,
        "frameSelectionRejectsAbsentGraphOverrideWithoutCompilation":
            absentGraphOverrideRejectedWithoutCompilation,
        "independentLaunchVariantRejectionIsCached":
            failedVariantRejectionIsCached,
    ]
    return (
        failingCapabilities,
        firstFailedVariant,
        secondFailedVariant,
        results
    )
}
