private func runTypedStorageCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline
) -> (
    scalarGraph: Graph,
    scalarChain: AdmittedLayerGraph,
    scalarCapabilities: Capabilities,
    redGreenGraph: Graph,
    redGreenChain: AdmittedLayerGraph,
    redGreenCapabilities: Capabilities,
    scalarClaim: Capabilities.ClaimedLayer,
    redGreenClaim: Capabilities.ClaimedLayer,
    results: [String: Bool]
) {
    let scalarGraph = graph(
        targets: [rawTarget(first, format: "r8")],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let scalarChain = admittedGraph(scalarGraph)
    let scalarCapabilities = capabilities(
        scalarChain,
        catalog: catalog(
            for: scalarGraph,
            scalarConsumerNodes: [1: "red"]
        )
    )
    guard let scalarClaim = scalarCapabilities.claim(scalarChain) else {
        fatalError("scalar capability rejected: \(scalarCapabilities.reportLines)")
    }
    let scalarExecutor = Executor(
        device: device,
        capabilities: scalarCapabilities
    )!
    let scalarLease = makeLease(requirePlan(scalarGraph), device: device)
    guard let scalarTarget = scalarLease.texture(for: first),
          fill(
              scalarTarget,
              color: MTLClearColorMake(1, 0, 0, 1),
              queue: queue
          ), let scalarPreparationBuffer = queue.makeCommandBuffer() else {
        fatalError("scalar preparation setup failed")
    }
    let scalarSource = makeSource(
        device,
        bgra: [191, 128, 64, 255]
    )
    let scalarPreparation = scalarExecutor.prepare(
        token: scalarClaim.token,
        leases: [scalarLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(0),
        sourceTexture: scalarSource,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: scalarPreparationBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(scalarPrepared) = scalarPreparation,
          let scalarPrepareRead = appendScalarReadback(
              scalarTarget,
              commandBuffer: scalarPreparationBuffer
          ) else {
        fatalError("scalar preparation failed: \(failureCode(scalarPreparation))")
    }
    scalarPreparationBuffer.commit()
    scalarPreparationBuffer.waitUntilCompleted()
    let scalarPrepareHasNoWrite = scalarPreparationBuffer.status == .completed
        && scalarPrepareRead.first == 255
        && scalarPrepareRead.last == 255
    let scalarStage = scalarPrepared.stages[0]
    let scalarPublication = scalarStage.frameResources[first]
    let scalarPublicationContract = scalarPrepared.stages.count == 1
        && scalarStage.programCacheKeys.count == 2
        && intentKinds(scalarPrepared) == ["material", "material"]
        && scalarPublication?.publication.requestIdentity == .graph(first)
        && scalarPublication?.publication.candidate.content == .scalarRedUnorm
        && scalarPublication?.publication.candidate.purpose == .preservedChannels
        && scalarPublication?.publication.candidate.pixelFormat == .r8Unorm
        && scalarPublication?.publication.candidate.authoredFormat == nil
        && scalarPublication?.publication.candidate.sampling == .directImageFallback
        && scalarPrepared.finalResource.publication.candidate.content
            != .scalarRedUnorm
    guard let scalarEncodeBuffer = queue.makeCommandBuffer() else {
        fatalError("scalar encode buffer unavailable")
    }
    let scalarEncoded = scalarExecutor.encode(
        scalarPrepared,
        commandBuffer: scalarEncodeBuffer
    )
    guard let scalarStorageRead = appendScalarReadback(
              scalarTarget,
              commandBuffer: scalarEncodeBuffer
          ), let scalarFinalRead = appendReadback(
              scalarPrepared.finalTexture,
              commandBuffer: scalarEncodeBuffer
          ) else { fatalError("scalar readback unavailable") }
    scalarEncodeBuffer.commit()
    scalarEncodeBuffer.waitUntilCompleted()
    let scalarGPUCompleted = scalarEncoded
        && scalarEncodeBuffer.status == .completed
        && scalarEncodeBuffer.error == nil
    let scalarRedStored = abs(Int(scalarStorageRead.first) - 64) <= 2
        && abs(Int(scalarStorageRead.last) - 64) <= 2
    let scalarTerminalMatches = matches(
        scalarFinalRead.firstPixel,
        [0, 0, 64, 255]
    ) && matches(scalarFinalRead.lastPixel, [0, 0, 64, 255])
    let redGreenGraph = graph(
        targets: [rawTarget(first, format: "rg88")],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let redGreenChain = admittedGraph(redGreenGraph)
    let redGreenCapabilities = capabilities(
        redGreenChain,
        catalog: catalog(
            for: redGreenGraph,
            scalarConsumerNodes: [1: "rg"]
        )
    )
    guard let redGreenClaim = redGreenCapabilities.claim(redGreenChain) else {
        fatalError(
            "red-green capability rejected: \(redGreenCapabilities.reportLines)"
        )
    }
    let redGreenExecutor = Executor(
        device: device,
        capabilities: redGreenCapabilities
    )!
    let redGreenLease = makeLease(requirePlan(redGreenGraph), device: device)
    guard let redGreenTarget = redGreenLease.texture(for: first),
          fill(
              redGreenTarget,
              color: MTLClearColorMake(1, 1, 0, 1),
              queue: queue
          ), let redGreenPreparationBuffer = queue.makeCommandBuffer() else {
        fatalError("red-green preparation setup failed")
    }
    let redGreenPreparation = redGreenExecutor.prepare(
        token: redGreenClaim.token,
        leases: [redGreenLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(0),
        sourceTexture: scalarSource,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: redGreenPreparationBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 2,
        resetGeneration: 1
    )
    guard case let .success(redGreenPrepared) = redGreenPreparation,
          let redGreenPrepareRead = appendRedGreenReadback(
              redGreenTarget,
              commandBuffer: redGreenPreparationBuffer
          ) else {
        fatalError(
            "red-green preparation failed: \(failureCode(redGreenPreparation))"
        )
    }
    redGreenPreparationBuffer.commit()
    redGreenPreparationBuffer.waitUntilCompleted()
    let redGreenPrepareHasNoWrite =
        redGreenPreparationBuffer.status == .completed
            && redGreenPrepareRead.first == [255, 255]
            && redGreenPrepareRead.last == [255, 255]
    let redGreenStage = redGreenPrepared.stages[0]
    let redGreenPublication = redGreenStage.frameResources[first]
    let redGreenPublicationContract = redGreenPrepared.stages.count == 1
        && redGreenStage.programCacheKeys.count == 2
        && intentKinds(redGreenPrepared) == ["material", "material"]
        && redGreenPublication?.publication.requestIdentity == .graph(first)
        && redGreenPublication?.publication.candidate.content == .redGreenUnorm
        && redGreenPublication?.publication.candidate.purpose
            == .preservedChannels
        && redGreenPublication?.publication.candidate.pixelFormat == .rg8Unorm
        && redGreenPublication?.publication.candidate.authoredFormat == nil
        && redGreenPrepared.finalResource.publication.candidate.content
            != .redGreenUnorm
    guard let redGreenEncodeBuffer = queue.makeCommandBuffer() else {
        fatalError("red-green encode buffer unavailable")
    }
    let redGreenEncoded = redGreenExecutor.encode(
        redGreenPrepared,
        commandBuffer: redGreenEncodeBuffer
    )
    guard let redGreenStorageRead = appendRedGreenReadback(
              redGreenTarget,
              commandBuffer: redGreenEncodeBuffer
          ), let redGreenFinalRead = appendReadback(
              redGreenPrepared.finalTexture,
              commandBuffer: redGreenEncodeBuffer
          ) else { fatalError("red-green readback unavailable") }
    redGreenEncodeBuffer.commit()
    redGreenEncodeBuffer.waitUntilCompleted()
    let redGreenGPUCompleted = redGreenEncoded
        && redGreenEncodeBuffer.status == .completed
        && redGreenEncodeBuffer.error == nil
    let redGreenPairStored = matches(
        redGreenStorageRead.first,
        [64, 128]
    ) && matches(redGreenStorageRead.last, [64, 128])
    let redGreenTerminalMatches = matches(
        redGreenFinalRead.firstPixel,
        [0, 128, 64, 255]
    ) && matches(redGreenFinalRead.lastPixel, [0, 128, 64, 255])
    let results: [String: Bool] = [
        "scalarPrepareHasNoEncodingSideEffect": scalarPrepareHasNoWrite,
        "scalarPublicationIsTypedAndComplete": scalarPublicationContract,
        "scalarGraphEncoded": scalarEncoded,
        "scalarGraphGPUCompleted": scalarGPUCompleted,
        "scalarProducerStoresRedComponent": scalarRedStored,
        "scalarDirectRedConsumerReachesColorTerminal": scalarTerminalMatches,
        "redGreenPrepareHasNoEncodingSideEffect": redGreenPrepareHasNoWrite,
        "redGreenPublicationIsTypedAndComplete": redGreenPublicationContract,
        "redGreenGraphEncoded": redGreenEncoded,
        "redGreenGraphGPUCompleted": redGreenGPUCompleted,
        "redGreenProducerStoresExactPair": redGreenPairStored,
        "redGreenDirectPairConsumerReachesColorTerminal":
            redGreenTerminalMatches,
    ]
    return (
        scalarGraph,
        scalarChain,
        scalarCapabilities,
        redGreenGraph,
        redGreenChain,
        redGreenCapabilities,
        scalarClaim,
        redGreenClaim,
        results
    )
}

private func runTypedAdmissionCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline
) -> (
    redGreenRedConsumerGraph: Graph,
    redGreenWholeConsumerGraph: Graph,
    redGreenUniqueGraph: Graph,
    redGreenMultipleWriterGraph: Graph,
    scalarGreenGraph: Graph,
    scalarWholeGraph: Graph,
    scalarAliasGraph: Graph,
    scalarConditionalWriterGraph: Graph,
    scalarClearGraph: Graph,
    results: [String: Bool]
) {
    let redGreenRedConsumerGraph = redGreenConsumerGraph()
    let redGreenWholeConsumerGraph = redGreenConsumerGraph()
    let redGreenClearGraph = graph(
        targets: [
            rawTarget(
                first,
                format: "rg88",
                clear: .string("0.25 0.5 0.75 1")
            ),
            rawTarget(second, format: "rg88"),
        ],
        nodes: [
            material(0, ordinal: 0, target: second, read: first),
            material(1, ordinal: 1, target: first, read: second),
            material(2, ordinal: 2, target: output, read: first),
        ]
    )
    let redGreenUniqueGraph = redGreenConsumerGraph(unique: true)
    let redGreenMultipleWriterGraph = graph(
        targets: [rawTarget(first, format: "rg88")],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: first, read: input),
            material(2, ordinal: 2, target: output, read: first),
        ]
    )
    let scalarGreenGraph = scalarConsumerGraph()
    let scalarWholeGraph = scalarConsumerGraph()
    let scalarAliasGraph = scalarConsumerGraph()
    let scalarConditionalWriterGraph = scalarConsumerGraph()
    let scalarClearGraph = graph(
        targets: [
            rawTarget(
                first,
                format: "r8",
                clear: .string("0.25 0 0 0")
            ),
            rawTarget(second, format: "r8"),
        ],
        nodes: [
            material(0, ordinal: 0, target: second, read: first),
            material(1, ordinal: 1, target: first, read: second),
            material(2, ordinal: 2, target: output, read: first),
        ]
    )
    let redGreenClearChain = admittedGraph(redGreenClearGraph)
    let redGreenClearCapabilities = capabilities(
        redGreenClearChain,
        catalog: catalog(
            for: redGreenClearGraph,
            scalarConsumerNodes: [0: "rg", 1: "rg", 2: "rg"]
        )
    )
    let redGreenClearClaim = redGreenClearCapabilities.claim(
        redGreenClearChain
    )
    var redGreenClearSeededFirstFrame = false
    var redGreenClearSeededNextFrame = false
    if let claim = redGreenClearClaim,
       let executor = Executor(
           device: device,
           capabilities: redGreenClearCapabilities
       ) {
        let lease = makeLease(
            requirePlan(redGreenClearGraph),
            device: device,
            generation: 41
        )
        if let firstBuffer = queue.makeCommandBuffer() {
            let firstPreparation = executor.prepare(
                token: claim.token,
                leases: [lease],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(40),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                frameInputs: .init(),
                commandBuffer: firstBuffer,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 40,
                resetGeneration: 40
            )
            if case let .success(firstPrepared) = firstPreparation,
               firstPrepared.stages.count == 1,
               intentKinds(firstPrepared) == [
                   "initialize", "material", "material", "material",
               ],
               firstPrepared.stages[0].persistentResources[first] != nil,
               executor.encode(firstPrepared, commandBuffer: firstBuffer),
               let firstTarget = lease.texture(for: first),
               let secondTarget = lease.texture(for: second),
               let firstRead = appendRedGreenReadback(
                   firstTarget,
                   commandBuffer: firstBuffer
               ),
               let secondRead = appendRedGreenReadback(
                   secondTarget,
                   commandBuffer: firstBuffer
               ),
               let terminalRead = appendReadback(
                   firstPrepared.finalTexture,
                   commandBuffer: firstBuffer
               ) {
                firstBuffer.commit()
                firstBuffer.waitUntilCompleted()
                redGreenClearSeededFirstFrame =
                    firstBuffer.status == .completed
                    && firstBuffer.error == nil
                    && firstRead.first == [64, 128]
                    && firstRead.last == [64, 128]
                    && secondRead.first == [64, 128]
                    && secondRead.last == [64, 128]
                    && matches(
                        terminalRead.firstPixel,
                        [0, 128, 64, 255]
                    )
                    && matches(
                        terminalRead.lastPixel,
                        [0, 128, 64, 255]
                    )

                if redGreenClearSeededFirstFrame,
                   let nextBuffer = queue.makeCommandBuffer() {
                    let firstStage = firstPrepared.stages[0]
                    let nextPreparation = executor.prepare(
                        token: claim.token,
                        leases: [lease],
                        historyRehydrateCopiesByEffect: [:],
                        frame: frame(41),
                        sourceTexture: source,
                        sourceUniforms: .neutral(),
                        sourcePipeline: sourcePipeline,
                        frameInputs: .init(),
                        commandBuffer: nextBuffer,
                        previousStates: [
                            effect: firstStage.transition.nextState,
                        ],
                        previousGraphResources: [
                            effect: firstStage.persistentResources,
                        ],
                        effectGeneration: 40,
                        resetGeneration: 40
                    )
                    if case let .success(nextPrepared) = nextPreparation,
                       intentKinds(nextPrepared) == [
                           "material", "material", "material",
                       ],
                       executor.encode(
                           nextPrepared,
                           commandBuffer: nextBuffer
                       ),
                       let nextRead = appendReadback(
                           nextPrepared.finalTexture,
                           commandBuffer: nextBuffer
                       ) {
                        nextBuffer.commit()
                        nextBuffer.waitUntilCompleted()
                        redGreenClearSeededNextFrame =
                            nextBuffer.status == .completed
                            && nextBuffer.error == nil
                            && matches(
                                nextRead.firstPixel,
                                [0, 128, 64, 255]
                            )
                            && matches(
                                nextRead.lastPixel,
                                [0, 128, 64, 255]
                            )
                    }
                }
            }
        }
    }
    let results: [String: Bool] = [
        "redGreenClearSeedFirstFrameExecutes":
            redGreenClearSeededFirstFrame,
        "redGreenClearSeedPersistsIntoNextFrame":
            redGreenClearSeededNextFrame,
    ]
    return (
        redGreenRedConsumerGraph,
        redGreenWholeConsumerGraph,
        redGreenUniqueGraph,
        redGreenMultipleWriterGraph,
        scalarGreenGraph,
        scalarWholeGraph,
        scalarAliasGraph,
        scalarConditionalWriterGraph,
        scalarClearGraph,
        results
    )
}
