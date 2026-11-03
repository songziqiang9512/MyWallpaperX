private func runMaterialFunctionCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline
) -> (
    materialFunction: MaterialFunctionScenarioResult,
    results: [String: Bool]
) {
    let materialFunction = runMaterialFunctionScenario(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline
    )
    let results: [String: Bool] = [
        "materialFunctionCapabilityClaimed":
            materialFunction.capabilityClaimed,
        "materialFunctionNoCallRejectsUninitializedHistory":
            materialFunction.noCallFailure == "state-rejected",
        "materialFunctionClearVisible":
            matches(materialFunction.invokedPixel, [0, 0, 0, 0]),
        "materialFunctionDuplicateOrderPreserved":
            materialFunction.invocationIntentCount == 4,
        "materialFunctionStaleRejected":
            materialFunction.staleFailure
                == "function-invocation-stale-frame",
        "materialFunctionUnknownEffectRejected":
            materialFunction.unknownEffectFailure
                == "function-invocation-unknown-effect",
        "materialFunctionUnknownNameRejected":
            materialFunction.unknownFunctionFailure
                == "function-invocation-unknown-function",
        "materialFunctionEncodeFailureTyped":
            materialFunction.encodeFailure
                == "function-clear-encode-rejected",
        "materialFunctionFailedEncodeHasTypedNoGPUCommit":
            materialFunction.encodeFailure
                == "function-clear-encode-rejected",
    ]
    return (
        materialFunction,
        results
    )
}

private func runCopyCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline
) -> (
    copyMismatch: Result<Executor.PreparedGraph, Executor.Failure>,
    swapMismatchRejectedBeforeFrame: Bool,
    mixedKinds: [String],
    results: [String: Bool]
) {
    let mixedGraph = graph(
        targets: [rawTarget(first), rawTarget(second)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: second, read: input),
            command(2, kind: .copy, source: first, target: second),
            command(3, kind: .swap, source: first, target: second),
            material(4, ordinal: 2, target: output, read: first),
        ]
    )
    let mixedChain = admittedGraph(mixedGraph)
    let mixedCapabilities = capabilities(
        mixedChain,
        catalog: catalog(for: mixedGraph)
    )
    let mixedVisualFailureTarget = dynamicUniformTarget(mixedGraph.nodes[4])
    let mixedVisualFailureCapabilities = capabilities(
        mixedChain,
        catalog: catalog(
            for: mixedGraph,
            dynamicUniformNodes: [4]
        ),
        dynamicProducers: .init(
            userProperties: [],
            timelineTargets: [mixedVisualFailureTarget],
            sceneScriptTargets: []
        )
    )
    let mixedClaim = mixedCapabilities.claim(mixedChain)!
    let mixedExecutor = Executor(
        device: device,
        capabilities: mixedCapabilities
    )!
    let mixedLease = makeLease(requirePlan(mixedGraph), device: device)
    guard let mixedBuffer = queue.makeCommandBuffer() else {
        fatalError("mixed buffer unavailable")
    }
    let mixedPreparation = mixedExecutor.prepare(
        token: mixedClaim.token,
        leases: [mixedLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(1),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: mixedBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    var mixedVisualFailureRollsBackWholeEffect = false
    if let claim = mixedVisualFailureCapabilities.claim(mixedChain),
       let executor = Executor(
           device: device,
           capabilities: mixedVisualFailureCapabilities
       ), let command = queue.makeCommandBuffer() {
        let preparation = executor.prepare(
            token: claim.token,
            leases: [makeLease(
                requirePlan(mixedGraph),
                device: device,
                generation: 34
            )],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(34),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 34,
            resetGeneration: 34
        )
        if case let .success(prepared) = preparation,
           let stage = prepared.stages.first,
           stage.effectLocalFailureReasonCode
                == "material-finalizer-dynamic-uniform-binding",
           stage.programCacheKeys == [
               "visual-failure-passthrough:"
                   + "material-finalizer-dynamic-uniform-binding"
           ],
           stage.transition.transaction.intents.isEmpty,
           stage.transition.transaction.mappingBefore.isEmpty,
           stage.transition.transaction.mappingAfter.isEmpty,
           stage.transition.nextState.logicalMapping.isEmpty,
           stage.frameResources.isEmpty,
           stage.persistentResources.isEmpty,
           executor.encode(prepared, commandBuffer: command),
           let readback = appendReadback(
               prepared.finalTexture,
               commandBuffer: command
           ) {
            command.commit()
            command.waitUntilCompleted()
            mixedVisualFailureRollsBackWholeEffect =
                command.status == .completed
                && command.error == nil
                && matches(readback.firstPixel, [0, 0, 255, 255])
                && matches(readback.lastPixel, [0, 0, 255, 255])
        }
    }

    let freshCopyGraph = graph(
        targets: [rawTarget(first), rawTarget(second)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            command(1, kind: .copy, source: first, target: second),
            material(2, ordinal: 1, target: output, read: second),
        ]
    )
    let freshCopyChain = admittedGraph(freshCopyGraph)
    let freshCopyCapabilities = capabilities(
        freshCopyChain,
        catalog: catalog(for: freshCopyGraph)
    )
    let freshCopyClaim = freshCopyCapabilities.claim(freshCopyChain)!
    let freshCopyExecutor = Executor(
        device: device,
        capabilities: freshCopyCapabilities
    )!
    let freshCopyLease = makeLease(
        requirePlan(freshCopyGraph),
        device: device
    )
    guard let freshCopyBuffer = queue.makeCommandBuffer() else {
        fatalError("fresh copy buffer unavailable")
    }
    let freshCopyPreparation = freshCopyExecutor.prepare(
        token: freshCopyClaim.token,
        leases: [freshCopyLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(1),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: freshCopyBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    var freshCopyPreparedAndEncoded = false
    var freshCopyPublicationMatches = false
    if case let .success(value) = freshCopyPreparation,
       let transition = value.stages.first,
       let mapped = transition.transition.transaction.mappingAfter[second],
       let published = transition.frameResources[second],
       let targetTexture = freshCopyLease.texture(for: second) {
        if case let .provider(.graph(generation, token)) =
            published.publication.candidate.identity {
            freshCopyPublicationMatches = generation == freshCopyLease.generation
                && token == mapped.token.rawValue
                && published.publication.requestIdentity == .graph(second)
                && published.resourceGeneration == mapped.contentGeneration
                && published.publication.contentGeneration
                    == mapped.contentGeneration
                && published.publication.texture === targetTexture
        }
        let appended = freshCopyExecutor.encode(
            value,
            commandBuffer: freshCopyBuffer
        )
        guard let readback = appendReadback(
            targetTexture,
            commandBuffer: freshCopyBuffer
        ) else { fatalError("fresh copy readback unavailable") }
        freshCopyBuffer.commit()
        freshCopyBuffer.waitUntilCompleted()
        freshCopyPreparedAndEncoded = appended
            && freshCopyBuffer.status == .completed
            && freshCopyBuffer.error == nil
            && matches(readback.firstPixel, [0, 0, 255, 255])
    }

    let copyMismatchGraph = graph(
        targets: [rawTarget(first), rawTarget(second, width: 1, height: 2)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            command(1, kind: .copy, source: first, target: second),
            material(2, ordinal: 1, target: output, read: second),
        ]
    )
    let copyMismatchPlan = manualPlan(
        targets: [
            logical(
                first,
                firstWrite: 0,
                lastWrite: 0,
                firstRead: 1,
                lastRead: 1
            ),
            logical(
                second,
                width: 1,
                height: 2,
                firstWrite: 1,
                lastWrite: 1,
                firstRead: 2,
                lastRead: 2
            ),
        ],
        commands: [.init(
            nodeIndex: 1,
            kind: .copy,
            source: first,
            target: second
        )]
    )
    let copyMismatchChain = admittedGraph(copyMismatchGraph)
    let copyMismatchCapabilities = capabilities(
        copyMismatchChain,
        catalog: catalog(for: copyMismatchGraph)
    )
    let copyMismatchClaim = copyMismatchCapabilities.claim(
        copyMismatchChain
    )!
    let copyMismatchExecutor = Executor(
        device: device,
        capabilities: copyMismatchCapabilities
    )!
    let copyMismatchLease = makeLease(copyMismatchPlan, device: device)
    guard let copyMismatchBuffer = queue.makeCommandBuffer() else {
        fatalError("copy mismatch buffer unavailable")
    }
    let copyMismatch = copyMismatchExecutor.prepare(
        token: copyMismatchClaim.token,
        leases: [copyMismatchLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(1),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: copyMismatchBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )

    let swapMismatchGraph = graph(
        targets: [rawTarget(first), rawTarget(second, unique: true)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: second, read: input),
            command(2, kind: .swap, source: first, target: second),
            material(3, ordinal: 2, target: output, read: first),
        ]
    )
    let swapMismatchChain = admittedGraph(swapMismatchGraph)
    let swapMismatchCapabilities = capabilities(
        swapMismatchChain,
        catalog: catalog(for: swapMismatchGraph)
    )
    let swapMismatchRejectedBeforeFrame = swapMismatchCapabilities.claim(
        swapMismatchChain
    ) == nil && swapMismatchCapabilities.reportLines.contains {
        $0.contains("rejection: swap-target-descriptor-incompatible count=1")
    }

    let mixedKinds: [String]
    let mixedPublicationChain: Bool
    switch mixedPreparation {
    case let .success(value):
        mixedKinds = intentKinds(value)
        let transition = value.stages[0]
        mixedPublicationChain = transition.programCacheKeys.count == 3
            && transition.frameResources[first] != nil
            && transition.frameResources[second] != nil
            && transition.effectOutputResource.publication.requestIdentity
                == .graph(output)
    case .failure:
        mixedKinds = []
        mixedPublicationChain = false
    }
    let results: [String: Bool] = [
        "copyAndSwapPrepared": failureCode(mixedPreparation) == "success"
            && mixedKinds.contains("copy")
            && mixedKinds.contains("swap")
            && mixedPublicationChain,
        "unseenMixedCopySwapVisualFailureRollsBackWholeEffect":
            mixedVisualFailureRollsBackWholeEffect,
        "freshCopyTargetPreparedAndEncoded":
            failureCode(freshCopyPreparation) == "success"
                && freshCopyPreparedAndEncoded,
        "freshCopyPublicationMatchesTargetVersion":
            freshCopyPublicationMatches,
        "copyExtentMismatchRejectedBeforeFrame": failureCode(copyMismatch)
            == Executor.Failure.invalidClaim.rawValue,
        "swapDescriptorMismatchRejectedBeforeFrame":
            swapMismatchRejectedBeforeFrame,
    ]
    return (
        copyMismatch,
        swapMismatchRejectedBeforeFrame,
        mixedKinds,
        results
    )
}

private func runHistoryCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline
) -> (
    litCapture: [String: Any],
    litResults: [String: Bool],
    results: [String: Bool]
) {
    let sameDescriptorHistory = runHistoryScenario(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline,
        fixedSize: false,
        resizedWidth: extent.width,
        resizedHeight: extent.height,
        preservesDescriptors: true
    )
    let dynamicResizeHistory = runHistoryScenario(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline,
        fixedSize: false,
        resizedWidth: 3,
        resizedHeight: 3,
        preservesDescriptors: false
    )
    let fixedResizeHistory = runHistoryScenario(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline,
        fixedSize: true,
        resizedWidth: 3,
        resizedHeight: 3,
        preservesDescriptors: true
    )

    let litCapture = runLitCaptureScenarios(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline
    )
    var litResults: [String: Bool] = [:]
    if let captured = litCapture["results"] as? [String: Bool] {
        litResults = captured
    }
    let results: [String: Bool] = [
        "freshSameDescriptorLeaseWithoutCopiesRejectsHistory":
            sameDescriptorHistory.noCopiesBehavior,
        "graphResourceKeyRequestIdentityMismatchRejected":
            sameDescriptorHistory.wrongRequestIdentityRejected,
        "freshSameDescriptorLeaseWithIncompleteCopiesRejectsHistory":
            sameDescriptorHistory.incompleteCopiesBehavior,
        "completeHistoryCopiesPreserveSwapPermutationAndGeneration":
            sameDescriptorHistory.fixtureHasSwapPermutation
                && sameDescriptorHistory.mappingBehavior,
        "completeHistoryCopiesEncodePreservedPixels":
            sameDescriptorHistory.preparedAndEncoded
                && sameDescriptorHistory.pixelBehavior,
        "dynamicFramebufferResizeRejectsStaleCopies":
            dynamicResizeHistory.unexpectedCopiesRejected,
        "dynamicFramebufferResizeResetsWithoutCopies":
            dynamicResizeHistory.noCopiesBehavior
                && dynamicResizeHistory.fixtureHasSwapPermutation
                && dynamicResizeHistory.mappingBehavior
                && dynamicResizeHistory.preparedAndEncoded
                && dynamicResizeHistory.pixelBehavior,
        "fixedFramebufferPairResizeRequiresCompleteCopies":
            fixedResizeHistory.noCopiesBehavior
                && fixedResizeHistory.incompleteCopiesBehavior,
        "fixedFramebufferPairResizePreservesHistory":
            fixedResizeHistory.fixtureHasSwapPermutation
                && fixedResizeHistory.mappingBehavior
                && fixedResizeHistory.preparedAndEncoded
                && fixedResizeHistory.pixelBehavior,
    ]
    return (
        litCapture,
        litResults,
        results
    )
}
