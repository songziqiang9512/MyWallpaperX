private func makeDefaultActivationGraph() -> Graph {
    graph(
        targets: [],
        nodes: [material(0, ordinal: 0, target: output, read: input)]
    )
}

private func makeDefaultActivationLeases(
    _ graph: Graph, _ capability: Capabilities.LayerCapability,
    _ device: MTLDevice, _ generation: UInt64
) -> [SceneGraphRenderTargetLease]? {
    makeChainedLeases(capability, device: device, generation: generation)
}

private func checkDefaultSamplerFailure(
    _ device: MTLDevice, _ queue: MTLCommandQueue,
    _ source: MTLTexture, _ sourcePipeline: SceneImageLayerPipeline,
    _ samplerClaim: Capabilities.ClaimedLayer?, _ samplerCapability: Capabilities.LayerCapability?, _ samplerCapabilities: Capabilities,
    _ colorClaim: Capabilities.ClaimedLayer?, _ colorCapability: Capabilities.LayerCapability?, _ colorCapabilities: Capabilities
) -> (prepared: Bool, encoded: Bool, gpuCompleted: Bool, continued: Bool, failureCode: String) {
    executeVisualFailurePassthrough(
        device: device, queue: queue, source: source, sourcePipeline: sourcePipeline,
        claim: samplerClaim, capability: samplerCapability, capabilities: samplerCapabilities,
        generation: 8, reason: "material-variant-envelope-sampler-schema"
    )
}

private func runExecutorHarness(
    device: MTLDevice,
    queue: MTLCommandQueue,
    activationGraphInput: () -> Graph,
    activationLeaseFactory: (Graph, Capabilities.LayerCapability, MTLDevice, UInt64) -> [SceneGraphRenderTargetLease]?,
    maskState: SceneAssetTextureLaunchState,
    samplerFailureCheck: SamplerFailureCheck,
    externalPrimaryCases: ((MTLDevice, MTLCommandQueue, MTLTexture, SceneImageLayerPipeline, SceneNamedTextureReference) -> (
        results: [String: Bool], failureCodes: [String: String], recoveryPixel: [UInt8]
    ))? = nil
) throws -> [String: Any] {
    let source = makeSource(device)
    let (
        sourcePipeline,
        activationResults
    ) = try runActivationCases(
        device: device,
        queue: queue,
        source: source,
        activationGraphInput: activationGraphInput,
        activationLeaseFactory: activationLeaseFactory
    )
    let (
        materialFunction,
        materialFunctionResults
    ) = runMaterialFunctionCases(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline
    )
    let (
        crossLayerGraph,
        crossLayerChain,
        namedReference,
        crossLayerCapabilities,
        crossLayerCapability,
        mixedPropertyNamedCapabilities,
        crossLayerPixel,
        crossLayerFailure,
        missingProvider,
        wrongProvider,
        secondaryReference,
        secondaryProvider,
        staleProvider,
        secondaryCapabilities,
        namedResults
    ) = runNamedCases(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline
    )
    let external = externalPrimaryCases?(device, queue, source, sourcePipeline, namedReference)
    let (
        pixelGraph,
        pixelChain,
        pixelCapabilities,
        forwardUnavailableCapabilities,
        forwardUnavailableClaim,
        forwardUnavailableCapability,
        backwardUnsupportedCapabilities,
        backwardUnsupportedClaim,
        backwardUnsupportedCapability,
        chainedMiddleProgramKey,
        pixelChainFailure,
        pixelClaim,
        pixelCapability,
        dormantGraphInputFailure,
        dynamicTarget,
        dynamicDefinition,
        stageChainResults
    ) = runStageChainCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        secondaryReference: secondaryReference
    )
    let (
        colorBlendCapabilities,
        colorBlendClaim,
        colorBlendCapability,
        colorBlendSnapshot,
        colorBlendProfiles,
        colorBlendOptionalMaskProof,
        systemProviderCapabilities,
        systemProviderClaim,
        systemProviderCapability,
        visualFailureResults
    ) = runVisualFailureCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        crossLayerCapability: crossLayerCapability,
        pixelGraph: pixelGraph,
        pixelChain: pixelChain,
        forwardUnavailableCapabilities: forwardUnavailableCapabilities,
        forwardUnavailableClaim: forwardUnavailableClaim,
        forwardUnavailableCapability: forwardUnavailableCapability,
        backwardUnsupportedCapabilities: backwardUnsupportedCapabilities,
        backwardUnsupportedClaim: backwardUnsupportedClaim,
        backwardUnsupportedCapability: backwardUnsupportedCapability,
        pixelCapability: pixelCapability,
        dynamicTarget: dynamicTarget,
        dynamicDefinition: dynamicDefinition,
        maskState: maskState,
        samplerFailureCheck: samplerFailureCheck
    )
    let (
        colorBlendPendingFailure,
        colorBlendWrongPurposeFailure,
        systemProviderReadyExecution,
        systemProviderAbsentExecution,
        optionalProviderResults
    ) = runOptionalProviderCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        pixelCapabilities: pixelCapabilities,
        chainedMiddleProgramKey: chainedMiddleProgramKey,
        pixelClaim: pixelClaim,
        pixelCapability: pixelCapability,
        colorBlendCapabilities: colorBlendCapabilities,
        colorBlendClaim: colorBlendClaim,
        colorBlendCapability: colorBlendCapability,
        systemProviderCapabilities: systemProviderCapabilities,
        systemProviderClaim: systemProviderClaim,
        systemProviderCapability: systemProviderCapability
    )
    let (
        visualFailureObservedPixels,
        passthroughResults
    ) = runPassthroughCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        pixelGraph: pixelGraph,
        pixelChain: pixelChain
    )
    let (
        ordinaryGraph,
        secondarySelfUnavailableGraph,
        secondarySelfUnavailableChain,
        secondarySelfUnavailableCapabilities,
        commandVisualFailureGraph,
        commandVisualFailureChain,
        commandVisualFailureCapabilities,
        commandDynamicTarget,
        commandDynamicDefinition,
        commandDynamicCapabilities,
        ordinaryChain,
        ordinaryCapabilities,
        uniformSchemaMultiNodeCapabilities,
        samplerSchemaMultiNodeCapabilities,
        ordinaryClaim,
        ordinaryExecutor,
        ordinaryAttemptsAfterWarmup,
        ordinaryLease,
        dynamicMultiCapabilities,
        staticUniformMultiNodeCapabilities,
        declarationConflictMultiNodeCapabilities,
        hostConflictMultiNodeCapabilities,
        dynamicUniformMultiNodeFailure,
        staticUniformMultiNodeFailure,
        hostConflictMultiNodeFailure,
        declarationConflictMultiNodeFailure,
        multiNodeResults
    ) = runMultiNodeCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline
    )
    let feedbackResults = runFeedbackCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        secondarySelfUnavailableGraph: secondarySelfUnavailableGraph,
        secondarySelfUnavailableChain: secondarySelfUnavailableChain,
        secondarySelfUnavailableCapabilities: secondarySelfUnavailableCapabilities,
        commandVisualFailureGraph: commandVisualFailureGraph,
        commandVisualFailureChain: commandVisualFailureChain,
        commandDynamicTarget: commandDynamicTarget,
        commandDynamicDefinition: commandDynamicDefinition,
        commandDynamicCapabilities: commandDynamicCapabilities
    )
    let (
        scalarGraph,
        scalarChain,
        scalarCapabilities,
        redGreenGraph,
        redGreenChain,
        redGreenCapabilities,
        scalarClaim,
        redGreenClaim,
        typedStorageResults
    ) = runTypedStorageCases(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline
    )
    let (
        redGreenRedConsumerGraph,
        redGreenWholeConsumerGraph,
        redGreenUniqueGraph,
        redGreenMultipleWriterGraph,
        scalarGreenGraph,
        scalarWholeGraph,
        scalarAliasGraph,
        scalarConditionalWriterGraph,
        scalarClearGraph,
        typedAdmissionResults
    ) = runTypedAdmissionCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline
    )
    let (
        scalarUniqueGraph,
        scalarNoConsumerGraph,
        scalarMultipleWriterGraph,
        scalarCopyGraph,
        scalarSwapGraph,
        rgbaClampProbe,
        rgbaRepeatProbe,
        scalarClampProbe,
        scalarRepeatProbe,
        addressResults
    ) = runAddressCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        ordinaryGraph: ordinaryGraph,
        scalarGraph: scalarGraph
    )
    let (
        rtDefaultResults,
        framebufferResults
    ) = runFramebufferCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        ordinaryClaim: ordinaryClaim,
        ordinaryExecutor: ordinaryExecutor,
        ordinaryLease: ordinaryLease
    )
    let (
        conditionGraph,
        composeGraph,
        genericComposeCapabilities,
        inactiveComposeGraph,
        nonzeroClearGraph,
        uniqueVisualFailureGraph,
        readBeforeWriteVisualFailureGraph,
        unusedTargetVisualFailureGraph,
        passCapabilities,
        missingCapabilities,
        nonOverwriteCapabilities,
        capturedDefaultCapabilities,
        nonzeroClearCapabilities,
        clearVisualFailureCapabilities,
        uniqueVisualFailureCapabilities,
        readBeforeWriteVisualFailureCapabilities,
        unusedTargetVisualFailureCapabilities,
        largeNodeGraph,
        largeLogicalGraph,
        genericComposeClaim,
        genericComposeCapability,
        genericComposeExecutor,
        genericComposeLease,
        compositionSetupResults
    ) = runCompositionSetupCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        ordinaryGraph: ordinaryGraph,
        ordinaryChain: ordinaryChain
    )
    let (
        ordinaryCapability,
        compilerCountsAfterFirst,
        lateCapabilities,
        latePreparation,
        firstTexture,
        prepared,
        encodedRead,
        ordinaryFrameResults
    ) = runOrdinaryFrameCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        ordinaryGraph: ordinaryGraph,
        ordinaryChain: ordinaryChain,
        ordinaryCapabilities: ordinaryCapabilities,
        ordinaryClaim: ordinaryClaim,
        ordinaryExecutor: ordinaryExecutor,
        ordinaryAttemptsAfterWarmup: ordinaryAttemptsAfterWarmup,
        ordinaryLease: ordinaryLease
    )
    let (
        genericComposePreparation,
        genericComposePublicationContract,
        genericComposeEncoded,
        genericComposePixelsPreserved,
        genericComposeFirstFailure,
        genericComposeSecondFailure,
        compositionExecutionResults
    ) = runCompositionExecutionCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        genericComposeCapabilities: genericComposeCapabilities,
        genericComposeClaim: genericComposeClaim,
        genericComposeCapability: genericComposeCapability,
        genericComposeExecutor: genericComposeExecutor,
        genericComposeLease: genericComposeLease
    )
    let (
        failingCapabilities,
        firstFailedVariant,
        secondFailedVariant,
        ordinaryCacheResults
    ) = runOrdinaryCacheCases(
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        ordinaryGraph: ordinaryGraph,
        ordinaryChain: ordinaryChain,
        ordinaryClaim: ordinaryClaim,
        ordinaryExecutor: ordinaryExecutor,
        ordinaryLease: ordinaryLease,
        ordinaryCapability: ordinaryCapability,
        compilerCountsAfterFirst: compilerCountsAfterFirst,
        firstTexture: firstTexture,
        prepared: prepared
    )
    let (
        copyMismatch,
        swapMismatchRejectedBeforeFrame,
        mixedKinds,
        copyResults
    ) = runCopyCases(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline
    )
    let (
        litCapture,
        litResults,
        historyResults
    ) = runHistoryCases(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline
    )
    var results: [String: Bool] = [
        "typedPreflightFailureCodesAreStable":
            Executor.Failure.graphStructureRejected.rawValue
                == "graph-structure-rejected"
                && Executor.Failure.materialPassEncoderRejected.rawValue
                    == "material-pass-encoder-rejected",
        "finalizerFailureIncludesBoundedSanitizedField":
            Executor.Failure.materialFinalizerRejected(
                stageIndex: 1,
                effect: .init(
                    layerID: 7,
                    effectIndex: 4,
                    descriptorID: "fixture-effect"
                ),
                nodeIndex: 3,
                materialOrdinal: 2,
                failure: .init(
                    phase: .uniform,
                    code: .uniformBindingInvalid,
                    details: ["g_Test[0] bad/field"]
                )
            ).rawValue
                == "stage-1-layer-7-effect-4-descriptor-"
                    + "6de7b3207797"
                    + "-node-3-material-2-finalizer-uniform-"
                    + "uniformBindingInvalid-detail-g_Test_0__bad_field",
        "exactSecondaryPreviousInputIsShadowProvenance":
            SceneResolvedMaterialExactPreviousInputShadow.accepts(
                .init(providerLayerID: layerID, variant: .secondary),
                input: chainedSecondOutput,
                consumer: chainedThirdEffect
            ),
    ]
    results.merge(activationResults) { _, new in new }
    results.merge(materialFunctionResults) { _, new in new }
    results.merge(namedResults) { _, new in new }
    results.merge(stageChainResults) { _, new in new }
    results.merge(visualFailureResults) { _, new in new }
    results.merge(optionalProviderResults) { _, new in new }
    results.merge(passthroughResults) { _, new in new }
    results.merge(multiNodeResults) { _, new in new }
    results.merge(feedbackResults) { _, new in new }
    results.merge(typedStorageResults) { _, new in new }
    results.merge(typedAdmissionResults) { _, new in new }
    results.merge(addressResults) { _, new in new }
    results.merge(framebufferResults) { _, new in new }
    results.merge(compositionSetupResults) { _, new in new }
    results.merge(ordinaryFrameResults) { _, new in new }
    results.merge(compositionExecutionResults) { _, new in new }
    results.merge(ordinaryCacheResults) { _, new in new }
    results.merge(copyResults) { _, new in new }
    results.merge(historyResults) { _, new in new }
    results.merge(finalAdmissionResults(
        crossLayerGraph: crossLayerGraph,
        crossLayerChain: crossLayerChain,
        namedReference: namedReference,
        secondaryCapabilities: secondaryCapabilities,
        pixelGraph: pixelGraph,
        commandVisualFailureGraph: commandVisualFailureGraph,
        commandVisualFailureCapabilities: commandVisualFailureCapabilities,
        ordinaryChain: ordinaryChain,
        ordinaryCapabilities: ordinaryCapabilities,
        uniformSchemaMultiNodeCapabilities: uniformSchemaMultiNodeCapabilities,
        samplerSchemaMultiNodeCapabilities: samplerSchemaMultiNodeCapabilities,
        ordinaryClaim: ordinaryClaim,
        scalarGraph: scalarGraph,
        scalarChain: scalarChain,
        scalarCapabilities: scalarCapabilities,
        redGreenGraph: redGreenGraph,
        redGreenChain: redGreenChain,
        redGreenCapabilities: redGreenCapabilities,
        scalarClaim: scalarClaim,
        redGreenClaim: redGreenClaim,
        redGreenRedConsumerGraph: redGreenRedConsumerGraph,
        redGreenWholeConsumerGraph: redGreenWholeConsumerGraph,
        redGreenUniqueGraph: redGreenUniqueGraph,
        redGreenMultipleWriterGraph: redGreenMultipleWriterGraph,
        scalarGreenGraph: scalarGreenGraph,
        scalarWholeGraph: scalarWholeGraph,
        scalarAliasGraph: scalarAliasGraph,
        scalarConditionalWriterGraph: scalarConditionalWriterGraph,
        scalarClearGraph: scalarClearGraph,
        scalarUniqueGraph: scalarUniqueGraph,
        scalarNoConsumerGraph: scalarNoConsumerGraph,
        scalarMultipleWriterGraph: scalarMultipleWriterGraph,
        scalarCopyGraph: scalarCopyGraph,
        scalarSwapGraph: scalarSwapGraph,
        conditionGraph: conditionGraph,
        composeGraph: composeGraph,
        inactiveComposeGraph: inactiveComposeGraph,
        nonzeroClearGraph: nonzeroClearGraph,
        uniqueVisualFailureGraph: uniqueVisualFailureGraph,
        readBeforeWriteVisualFailureGraph: readBeforeWriteVisualFailureGraph,
        unusedTargetVisualFailureGraph: unusedTargetVisualFailureGraph,
        passCapabilities: passCapabilities,
        missingCapabilities: missingCapabilities,
        nonOverwriteCapabilities: nonOverwriteCapabilities,
        nonzeroClearCapabilities: nonzeroClearCapabilities,
        clearVisualFailureCapabilities: clearVisualFailureCapabilities,
        uniqueVisualFailureCapabilities: uniqueVisualFailureCapabilities,
        readBeforeWriteVisualFailureCapabilities: readBeforeWriteVisualFailureCapabilities,
        unusedTargetVisualFailureCapabilities: unusedTargetVisualFailureCapabilities,
        largeNodeGraph: largeNodeGraph,
        largeLogicalGraph: largeLogicalGraph,
        lateCapabilities: lateCapabilities,
        failingCapabilities: failingCapabilities
    )) { _, new in new }
    results.merge(external?.results ?? [:]) { _, new in new }
    for litEntry in litResults {
        results[litEntry.key] = litEntry.value
    }
    var payload: [String: Any] = [
        "metalAvailable": true,
        "debugLastCandidateFailureCode": debugLastCandidateFailureCode,
        "results": results,
        "failureCodes": [
            "crossLayer": crossLayerFailure,
            "crossLayerMissing": missingProvider.failureCode,
            "crossLayerWrongProvider": wrongProvider.failureCode,
            "crossLayerSecondary": secondaryProvider.failureCode,
            "crossLayerStale": staleProvider.failureCode,
            "late": failureCode(latePreparation),
            "copyMismatch": failureCode(copyMismatch),
            "swapMismatch": swapMismatchRejectedBeforeFrame
                ? "swap-target-descriptor-incompatible" : "unexpected-admission",
            "firstFailedVariant": launchEnvelopeFailureCode(firstFailedVariant),
            "secondFailedVariant": launchEnvelopeFailureCode(secondFailedVariant),
            "systemProviderReady": systemProviderReadyExecution.failureCode,
            "systemProviderAbsent": systemProviderAbsentExecution.failureCode,
        ].merging(external?.failureCodes ?? [:]) { _, new in new },
        "composeDiagnostics": [
            "genericFailure": failureCode(genericComposePreparation),
            "genericPublication": String(genericComposePublicationContract),
            "genericEncoded": String(genericComposeEncoded),
            "genericPixels": String(genericComposePixelsPreserved),
            "genericFirstFailureRestored": String(
                genericComposeFirstFailure.restored
            ),
            "genericSecondFailureRestored": String(
                genericComposeSecondFailure.restored
            ),
        ],
        "materialFunctionSetupFailure": materialFunction.setupFailure,
        "materialFunctionDiagnostics": [
            "invocationIntentCount": materialFunction.invocationIntentCount,
            "invokedPixel": materialFunction.invokedPixel,
            "failedEncodePreservedPixel":
                materialFunction.failedEncodePreservedPixel,
        ],
        "mixedKinds": mixedKinds,
        "crossLayerPixel": crossLayerPixel,
        "crossLayerReport": crossLayerCapabilities.reportLines,
        "mixedPropertyReport": mixedPropertyNamedCapabilities.reportLines,
        "encodedPixel": encodedRead.firstPixel,
        "encodedLastPixel": encodedRead.lastPixel,
        "addressProbePixels": [
            "rgbaClamp": [rgbaClampProbe.first, rgbaClampProbe.last],
            "rgbaRepeat": [rgbaRepeatProbe.first, rgbaRepeatProbe.last],
            "scalarClamp": [scalarClampProbe.first, scalarClampProbe.last],
            "scalarRepeat": [scalarRepeatProbe.first, scalarRepeatProbe.last],
        ],
        "pixelChainCanClaim": pixelCapabilities.claim(pixelChain) != nil,
        "pixelChainReport": pixelCapabilities.reportLines,
        "colorBlendCanClaim": colorBlendClaim != nil,
        "colorBlendCapabilityResolved": colorBlendCapability != nil,
        "colorBlendOptionalMaskProof": colorBlendOptionalMaskProof,
        "colorBlendProfiles": colorBlendProfiles,
        "colorBlendVariantCount": colorBlendSnapshot?.variants.count ?? -1,
        "colorBlendAllEntriesReady":
            colorBlendSnapshot?.allEntriesReady == true,
        "colorBlendLeasesAvailable": colorBlendCapability.flatMap {
            makeChainedLeases($0, device: device, generation: 91)
        } != nil,
        "colorBlendReport": colorBlendCapabilities.reportLines,
        "colorBlendPendingPreparation": colorBlendPendingFailure.failureCode,
        "colorBlendWrongPurposePreparation":
            colorBlendWrongPurposeFailure.failureCode,
        "systemProviderSelectionDiagnostics": [
            "readyStagePixels": systemProviderReadyExecution.stagePixels,
            "readyFinalPixel": systemProviderReadyExecution.finalPixel,
            "absentStagePixels": systemProviderAbsentExecution.stagePixels,
            "absentFinalPixel": systemProviderAbsentExecution.finalPixel,
        ],
        "pixelChainFailure": pixelChainFailure,
        "dormantGraphInputFailure": dormantGraphInputFailure,
        "visualFailureObservedPixels": visualFailureObservedPixels,
        "dynamicUniformMultiNodeFailure": dynamicUniformMultiNodeFailure,
        "dynamicUniformMultiNodeReport": dynamicMultiCapabilities.reportLines,
        "staticUniformMultiNodeFailure": staticUniformMultiNodeFailure,
        "staticUniformMultiNodeReport":
            staticUniformMultiNodeCapabilities.reportLines,
        "hostConflictMultiNodeFailure": hostConflictMultiNodeFailure,
        "hostConflictMultiNodeReport":
            hostConflictMultiNodeCapabilities.reportLines,
        "declarationConflictMultiNodeFailure":
            declarationConflictMultiNodeFailure,
        "declarationConflictMultiNodeReport":
            declarationConflictMultiNodeCapabilities.reportLines,
        "rtDefaultDiagnostics": rtDefaultResults,
        "capturedDefaultReport": capturedDefaultCapabilities.reportLines,
        "litCapture": litCapture,
    ]
    if let external {
        payload["externalRecoveryMiddlePixel"] = external.recoveryPixel
    }
    return payload
}
