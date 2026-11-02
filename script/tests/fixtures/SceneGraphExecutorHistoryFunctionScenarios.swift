private func historyGraph(fixedSize: Bool) -> Graph {
    let width = fixedSize ? 2.0 : nil
    let height = fixedSize ? 2.0 : nil
    return graph(
        targets: [
            rawTarget(first, width: width, height: height, unique: true),
            rawTarget(second, width: width, height: height, unique: true),
        ],
        nodes: [
            material(0, ordinal: 0, target: second, read: first),
            command(1, kind: .swap, source: first, target: second),
            material(2, ordinal: 1, target: output, read: first),
        ]
    )
}

private func materialFunctionGraph() -> Graph {
    let nodes = [
        material(0, ordinal: 0, target: output, read: first),
        material(1, ordinal: 1, target: first, read: input),
    ]
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effect,
            definitionPath: "effects/executor/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )],
        renderTargets: [rawTarget(first, unique: true)],
        nodes: nodes,
        finalOutput: output,
        blockers: [.init(
            effect: effect,
            definitionPassIndex: nil,
            reason: .unsupportedFunctions,
            detail: "explicit function registry"
        )]
    )
}

private func materialFunctionRegistry() -> SceneJSONValue {
    .object([
        "reset": .object([
            "action": .string("clear"),
            "fbos": .array([.string(first.name!), .string(first.name!)]),
        ]),
    ])
}

private func historyCopies(
    transition: Executor.PreparedStage,
    sourceLease: SceneGraphRenderTargetLease,
    targetLease: SceneGraphRenderTargetLease
) -> [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy]? {
    let state = transition.transition.nextState
    let authoredSlotByToken = Dictionary(uniqueKeysWithValues:
        state.authoredResources.map { ($0.value.token, $0.key) }
    )
    let sourceTokens = Set(state.logicalMapping.values.compactMap {
        $0.contentGeneration > 0 ? $0.token : nil
    }).sorted { $0.rawValue < $1.rawValue }
    var copies: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy] = []
    for sourceToken in sourceTokens {
        guard let identity = authoredSlotByToken[sourceToken],
              let sourceTexture = sourceLease.texturesByToken[sourceToken],
              let target = targetLease.framebufferAllocation.resources[identity],
              let targetTexture = targetLease.texturesByToken[target.token] else {
            return nil
        }
        copies.append(.init(
            sourceToken: sourceToken,
            sourceTexture: sourceTexture,
            targetToken: target.token,
            targetTexture: targetTexture
        ))
    }
    return copies
}

private func preservesPermutation(
    previous: Executor.State,
    mapping: [Graph.TextureIdentity: Executor.State.VersionedResource],
    targetLease: SceneGraphRenderTargetLease,
    preservesContent: Bool
) -> Bool {
    guard Set(mapping.keys) == Set(previous.logicalMapping.keys) else {
        return false
    }
    let authoredSlotByToken = Dictionary(uniqueKeysWithValues:
        previous.authoredResources.map { ($0.value.token, $0.key) }
    )
    return previous.logicalMapping.allSatisfy { identity, old in
        guard let authoredSlot = authoredSlotByToken[old.token],
              let replacement = targetLease.framebufferAllocation
                .resources[authoredSlot],
              let rebased = mapping[identity] else { return false }
        return rebased.token == replacement.token
            && rebased.descriptor == replacement.descriptor
            && rebased.contentGeneration
                == (preservesContent ? old.contentGeneration : 0)
    }
}

private struct HistoryScenarioResult {
    var fixtureHasSwapPermutation = false
    var wrongRequestIdentityRejected = false
    var noCopiesBehavior = false
    var incompleteCopiesBehavior = false
    var unexpectedCopiesRejected = false
    var mappingBehavior = false
    var preparedAndEncoded = false
    var pixelBehavior = false
}

private func runHistoryScenario(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline,
    fixedSize: Bool,
    resizedWidth: Int,
    resizedHeight: Int,
    preservesDescriptors: Bool
) -> HistoryScenarioResult {
    let graph = historyGraph(fixedSize: fixedSize)
    let admittedGraph = admittedGraph(graph)
    let capabilities = capabilities(admittedGraph, catalog: catalog(for: graph))
    guard let claim = capabilities.claim(admittedGraph),
          let executor = Executor(device: device, capabilities: capabilities),
          let firstBuffer = queue.makeCommandBuffer() else { return .init() }
    let firstLease = makeLease(
        requirePlan(graph),
        device: device,
        generation: 30
    )
    let firstPreparation = executor.prepare(
        token: claim.token,
        leases: [firstLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(30),
        sourceTexture: makeSource(device),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: firstBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(firstPrepared) = firstPreparation,
          executor.encode(firstPrepared, commandBuffer: firstBuffer),
          let transition = firstPrepared.stages.first else {
        return .init()
    }
    firstBuffer.commit()
    firstBuffer.waitUntilCompleted()
    guard firstBuffer.status == .completed, firstBuffer.error == nil,
          let historicalFirst = transition.persistentResources[first]?.publication
            .texture,
          let historicalSecond = transition.persistentResources[second]?.publication
            .texture,
          fill(
              historicalFirst,
              color: MTLClearColorMake(0, 1, 0, 1),
              queue: queue
          ), fill(
              historicalSecond,
              color: MTLClearColorMake(0, 0, 1, 1),
              queue: queue
          ) else { return .init() }

    var result = HistoryScenarioResult()
    let previous = transition.transition.nextState
    if let original = transition.persistentResources[first] {
        var forgedResources = transition.persistentResources
        forgedResources[first] = .init(
            publication: original.publication.publication(for: .graph(second)),
            resourceGeneration: original.resourceGeneration
        )
        result.wrongRequestIdentityRejected = executor.resources(
            matching: previous.logicalMapping,
            from: forgedResources
        ) == nil
    }
    result.fixtureHasSwapPermutation =
        previous.logicalMapping[first]?.token
            == previous.authoredResources[second]?.token
        && previous.logicalMapping[second]?.token
            == previous.authoredResources[first]?.token

    let nextLease = makeLease(
        requirePlan(
            graph,
            width: resizedWidth,
            height: resizedHeight
        ),
        device: device,
        generation: 31
    )
    guard let copies = historyCopies(
        transition: transition,
        sourceLease: firstLease,
        targetLease: nextLease
    ), copies.count == 2 else { return result }
    let nextSource = makeSource(
        device,
        width: resizedWidth,
        height: resizedHeight
    )

    guard let noCopiesBuffer = queue.makeCommandBuffer() else { return result }
    let noCopies = executor.prepare(
        token: claim.token,
        leases: [nextLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(31, width: resizedWidth, height: resizedHeight),
        sourceTexture: nextSource,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: noCopiesBuffer,
        previousStates: [effect: previous],
        previousGraphResources: [effect: transition.persistentResources],
        effectGeneration: 1,
        resetGeneration: 1
    )

    if preservesDescriptors {
        result.noCopiesBehavior = failureCode(noCopies)
            == Executor.Failure.historyRejected.rawValue
        guard let incompleteBuffer = queue.makeCommandBuffer() else {
            return result
        }
        let incomplete = executor.prepare(
            token: claim.token,
            leases: [nextLease],
            historyRehydrateCopiesByEffect: [effect: [copies[0]]],
            frame: frame(32, width: resizedWidth, height: resizedHeight),
            sourceTexture: nextSource,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: incompleteBuffer,
            previousStates: [effect: previous],
            previousGraphResources: [effect: transition.persistentResources],
            effectGeneration: 1,
            resetGeneration: 1
        )
        result.incompleteCopiesBehavior = failureCode(incomplete)
            == Executor.Failure.historyRejected.rawValue
    } else {
        guard let unexpectedBuffer = queue.makeCommandBuffer() else {
            return result
        }
        let unexpected = executor.prepare(
            token: claim.token,
            leases: [nextLease],
            historyRehydrateCopiesByEffect: [effect: copies],
            frame: frame(32, width: resizedWidth, height: resizedHeight),
            sourceTexture: nextSource,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: unexpectedBuffer,
            previousStates: [effect: previous],
            previousGraphResources: [effect: transition.persistentResources],
            effectGeneration: 1,
            resetGeneration: 1
        )
        result.unexpectedCopiesRejected = failureCode(unexpected)
            == Executor.Failure.historyRejected.rawValue
    }

    let acceptedPreparation: Result<Executor.PreparedGraph, Executor.Failure>
    let acceptedBuffer: MTLCommandBuffer
    if preservesDescriptors {
        guard let buffer = queue.makeCommandBuffer() else { return result }
        acceptedBuffer = buffer
        acceptedPreparation = executor.prepare(
            token: claim.token,
            leases: [nextLease],
            historyRehydrateCopiesByEffect: [effect: copies],
            frame: frame(33, width: resizedWidth, height: resizedHeight),
            sourceTexture: nextSource,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: buffer,
            previousStates: [effect: previous],
            previousGraphResources: [effect: transition.persistentResources],
            effectGeneration: 1,
            resetGeneration: 1
        )
    } else {
        acceptedBuffer = noCopiesBuffer
        acceptedPreparation = noCopies
        result.noCopiesBehavior = failureCode(noCopies) == "success"
    }

    guard case let .success(accepted) = acceptedPreparation,
          let acceptedTransition = accepted.stages.first else {
        return result
    }
    result.mappingBehavior = preservesPermutation(
        previous: previous,
        mapping: acceptedTransition.transition.transaction.mappingBefore,
        targetLease: nextLease,
        preservesContent: preservesDescriptors
    )
    result.preparedAndEncoded = executor.encode(
        accepted,
        commandBuffer: acceptedBuffer
    )
    guard result.preparedAndEncoded,
          let readback = appendReadback(
              accepted.finalTexture,
              commandBuffer: acceptedBuffer
          ) else { return result }
    acceptedBuffer.commit()
    acceptedBuffer.waitUntilCompleted()
    result.preparedAndEncoded = acceptedBuffer.status == .completed
        && acceptedBuffer.error == nil
    result.pixelBehavior = matches(
        readback.firstPixel,
        preservesDescriptors ? [0, 255, 0, 255] : [0, 0, 0, 0]
    )
    return result
}

private struct MaterialFunctionScenarioResult {
    var capabilityClaimed = false
    var setupFailure = "none"
    var noCallFailure = "setup"
    var invokedPixel = [UInt8]()
    var invocationIntentCount = 0
    var staleFailure = "setup"
    var unknownEffectFailure = "setup"
    var unknownFunctionFailure = "setup"
    var encodeFailure = "setup"
    var failedEncodePreservedPixel = [UInt8]()
}

private func runMaterialFunctionScenario(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline
) -> MaterialFunctionScenarioResult {
    let raw = materialFunctionGraph()
    let chain = admittedGraph(raw)
    let registry = materialFunctionRegistry()
    let capabilities = capabilities(
        chain,
        catalog: catalog(for: raw),
        functionsByEffect: [effect: registry]
    )
    guard let claim = capabilities.claim(chain),
          let executor = Executor(device: device, capabilities: capabilities),
          let capability = capabilities.resolve(claim.token),
          capability.admittedProducts.first?.clearFunctions
            .function(named: "reset")?.targets == [first, first],
          let firstBuffer = queue.makeCommandBuffer() else { return .init() }
    var result = MaterialFunctionScenarioResult()
    result.capabilityClaimed = true
    let functionLease = makeLease(
        requireMaterialFunctionPlan(capability.admittedProducts[0].graph),
        device: device
    )
    let normalLease = makeLease(
        requirePlan(capability.admittedProducts[0].graph),
        device: device
    )
    let firstPreparation = executor.prepare(
        token: claim.token,
        leases: [functionLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(80),
        sceneBackgroundResource: nil,
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: firstBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        materialFunctionInvocations: [
            .init(effect: effect, functionName: "reset", frameEpoch: 80)
        ],
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(firstPrepared) = firstPreparation else {
        result.setupFailure = failureCode(firstPreparation)
        return result
    }
    guard let firstStage = firstPrepared.stages.first,
          executor.encode(firstPrepared, commandBuffer: firstBuffer) else {
        result.setupFailure = "first-encode"
        return result
    }
    firstBuffer.commit()
    firstBuffer.waitUntilCompleted()
    guard firstBuffer.status == .completed, firstBuffer.error == nil else {
        result.setupFailure = "first-gpu-\(firstBuffer.status.rawValue)"
        return result
    }

    let previousStates = [effect: firstStage.transition.nextState]
    let previousResources = [effect: firstStage.persistentResources]
    guard let controlBuffer = queue.makeCommandBuffer() else { return result }
    let controlPreparation = executor.prepare(
        token: claim.token,
        leases: [normalLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(81),
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: controlBuffer,
        previousStates: previousStates,
        previousGraphResources: previousResources,
        effectGeneration: 1,
        resetGeneration: 1
    )
    result.noCallFailure = failureCode(controlPreparation)
    result.setupFailure = "ready"

    func prepareFailure(
        frameIndex: UInt64,
        request: SceneGraphMaterialFunctionInvocationRequest
    ) -> String {
        guard let buffer = queue.makeCommandBuffer() else { return "buffer" }
        return failureCode(executor.prepare(
            token: claim.token,
            leases: [functionLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(frameIndex),
            sourceTexture: makeSource(device, width: 2, height: 2),
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: buffer,
            previousStates: previousStates,
            previousGraphResources: previousResources,
            materialFunctionInvocations: [request],
            effectGeneration: 1,
            resetGeneration: 1
        ))
    }
    result.staleFailure = prepareFailure(
        frameIndex: 82,
        request: .init(effect: effect, functionName: "reset", frameEpoch: 81)
    )
    result.unknownEffectFailure = prepareFailure(
        frameIndex: 82,
        request: .init(
            effect: .init(
                layerID: layerID,
                effectIndex: 9,
                descriptorID: "unknown"
            ),
            functionName: "reset",
            frameEpoch: 82
        )
    )
    result.unknownFunctionFailure = prepareFailure(
        frameIndex: 82,
        request: .init(effect: effect, functionName: "missing", frameEpoch: 82)
    )

    let requests = [
        SceneGraphMaterialFunctionInvocationRequest(
            effect: effect,
            functionName: "reset",
            frameEpoch: 83
        ),
        SceneGraphMaterialFunctionInvocationRequest(
            effect: effect,
            functionName: "reset",
            frameEpoch: 83
        ),
    ]
    guard let failedBuffer = queue.makeCommandBuffer() else { return result }
    let failedPreparation = executor.prepare(
        token: claim.token,
        leases: [functionLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(83),
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: failedBuffer,
        previousStates: previousStates,
        previousGraphResources: previousResources,
        materialFunctionInvocations: requests,
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(failedPrepared) = failedPreparation else { return result }
    let failedEncode = executor.encodeResult(
        failedPrepared,
        commandBuffer: failedBuffer,
        functionClearObserver: { _, _, targetOrdinal, _ in targetOrdinal == 0 }
    )
    if case let .failure(failure) = failedEncode {
        result.encodeFailure = failure.rawValue
    }
    if let persistentTexture = firstStage.persistentResources[first]?
            .publication.texture,
       let preservationBuffer = queue.makeCommandBuffer(),
       let preservationReadback = appendReadback(
           persistentTexture,
           commandBuffer: preservationBuffer
       ) {
        preservationBuffer.commit()
        preservationBuffer.waitUntilCompleted()
        guard preservationBuffer.status == .completed,
              preservationBuffer.error == nil else { return result }
        result.failedEncodePreservedPixel = preservationReadback.firstPixel
    }

    let successfulRequests = requests.map {
        SceneGraphMaterialFunctionInvocationRequest(
            effect: $0.effect,
            functionName: $0.functionName,
            frameEpoch: 84
        )
    }
    guard let invokedBuffer = queue.makeCommandBuffer() else { return result }
    let invokedPreparation = executor.prepare(
        token: claim.token,
        leases: [functionLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(84),
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: invokedBuffer,
        previousStates: previousStates,
        previousGraphResources: previousResources,
        materialFunctionInvocations: successfulRequests,
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case let .success(invokedPrepared) = invokedPreparation,
          let invokedStage = invokedPrepared.stages.first else { return result }
    result.invocationIntentCount = invokedStage.transition.transaction.intents.filter {
        guard case let .initialize(_, _, reason) = $0,
              case .materialFunctionClear = reason else { return false }
        return true
    }.count
    guard executor.encode(invokedPrepared, commandBuffer: invokedBuffer),
          let invokedReadback = appendReadback(
              invokedPrepared.finalTexture,
              commandBuffer: invokedBuffer
          ) else { return result }
    invokedBuffer.commit()
    invokedBuffer.waitUntilCompleted()
    guard invokedBuffer.status == .completed, invokedBuffer.error == nil else {
        return result
    }
    result.invokedPixel = invokedReadback.firstPixel
    return result
}
