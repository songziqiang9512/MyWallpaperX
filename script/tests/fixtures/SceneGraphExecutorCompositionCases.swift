private func runCompositionSetupCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    ordinaryGraph: Graph,
    ordinaryChain: AdmittedLayerGraph
) -> (
    conditionGraph: Graph,
    composeGraph: Graph,
    genericComposeCapabilities: Capabilities,
    inactiveComposeGraph: Graph,
    nonzeroClearGraph: Graph,
    uniqueVisualFailureGraph: Graph,
    readBeforeWriteVisualFailureGraph: Graph,
    unusedTargetVisualFailureGraph: Graph,
    passCapabilities: Capabilities,
    missingCapabilities: Capabilities,
    nonOverwriteCapabilities: Capabilities,
    capturedDefaultCapabilities: Capabilities,
    nonzeroClearCapabilities: Capabilities,
    clearVisualFailureCapabilities: Capabilities,
    uniqueVisualFailureCapabilities: Capabilities,
    readBeforeWriteVisualFailureCapabilities: Capabilities,
    unusedTargetVisualFailureCapabilities: Capabilities,
    largeNodeGraph: Graph,
    largeLogicalGraph: Graph,
    genericComposeClaim: Capabilities.ClaimedLayer,
    genericComposeCapability: Capabilities.LayerCapability,
    genericComposeExecutor: Executor,
    genericComposeLease: SceneGraphRenderTargetLease,
    results: [String: Bool]
) {
    let conditionGraph = graph(
        targets: [rawTarget(first)],
        nodes: [
            material(
                0,
                ordinal: 0,
                target: first,
                read: input,
                conditions: .bool(true)
            ),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let composeGraph = graph(
        targets: [rawTarget(first)],
        nodes: [
            material(
                0,
                ordinal: 0,
                target: first,
                read: input,
                compose: .bool(true)
            ),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let genericComposeGraph = graph(
        targets: [],
        nodes: [
            material(
                0,
                ordinal: 0,
                target: output,
                read: input,
                compose: .bool(true)
            ),
            material(1, ordinal: 1, target: output, read: input),
        ]
    )
    let genericComposeChain = admittedGraph(genericComposeGraph)
    let genericComposeCapabilities = capabilities(
        genericComposeChain,
        catalog: catalog(
            for: genericComposeGraph,
            pixelTransformsByNode: [0: 1]
        )
    )
    guard let genericComposeClaim = genericComposeCapabilities.claim(
              genericComposeChain
          ),
          let genericComposeCapability = genericComposeCapabilities.resolve(
              genericComposeClaim.token,
              for: genericComposeChain
          ),
          let genericComposeExecutor = Executor(
              device: device,
              capabilities: genericComposeCapabilities
          ),
          let genericComposeLease = makeChainedLeases(
              genericComposeCapability,
              device: device
          )?.first else {
        fatalError(
            "generic compose setup failed: "
                + genericComposeCapabilities.reportLines.joined(separator: " | ")
        )
    }
    let inactiveComposeGraph = graph(
        targets: [rawTarget(first)],
        nodes: [
            material(
                0,
                ordinal: 0,
                target: first,
                read: input,
                compose: .bool(false)
            ),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let nonzeroClearGraph = graph(
        targets: [rawTarget(first, clear: .string("1 0 0 0"))],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let uniqueVisualFailureGraph = graph(
        targets: [rawTarget(first, unique: true)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let readBeforeWriteVisualFailureGraph = graph(
        targets: [rawTarget(first), rawTarget(second)],
        nodes: [
            material(0, ordinal: 0, target: first, read: second),
            material(1, ordinal: 1, target: second, read: input),
            material(2, ordinal: 2, target: output, read: first),
        ]
    )
    let unusedTargetVisualFailureGraph = graph(
        targets: [rawTarget(first), rawTarget(second)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: second, read: input),
            material(2, ordinal: 2, target: output, read: first),
        ]
    )
    let passCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(for: ordinaryGraph, passNodes: [1])
    )
    let missingCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(for: ordinaryGraph, omittedNodes: [1])
    )
    let nonOverwriteCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(for: ordinaryGraph, nonOverwriteNodes: [1])
    )
    let capturedDefaultGraph = graph(targets: [], nodes: [material(0, ordinal: 0, target: output, read: input)])
    let capturedDefaultChain = admittedGraph(capturedDefaultGraph)
    let capturedDefaultCapabilities = capabilities(capturedDefaultChain,
        catalog: catalog(for: capturedDefaultGraph, internalDefaultNodes: [0], pixelTransformsByNode: [0: 1]), capturedMainTarget: true)
    var capturedIdleDefaultGPU = false
    if let claim = capturedDefaultCapabilities.claim(capturedDefaultChain),
       capturedDefaultCapabilities.resolve(claim.token, for: capturedDefaultChain)?.sourceRoute == .capturedMainTargetTexture,
       let executor = Executor(device: device, capabilities: capturedDefaultCapabilities),
       let buffer = queue.makeCommandBuffer() {
        let lease = makeLease(requirePlan(capturedDefaultGraph), device: device, generation: 99)
        let preparation = executor.prepare(token: claim.token, leases: [lease], historyRehydrateCopiesByEffect: [:],
            frame: frame(99), sourceTexture: source, sourceUniforms: .neutral(), sourcePipeline: sourcePipeline,
            frameInputs: .init(), commandBuffer: buffer, previousStates: [:], previousGraphResources: [:],
            effectGeneration: 99, resetGeneration: 99)
        if case let .success(prepared) = preparation,
           prepared.stages[0].programCacheKeys.count == 1,
           executor.encode(prepared, commandBuffer: buffer),
           let readback = appendReadback(prepared.finalTexture, commandBuffer: buffer) {
            buffer.commit(); buffer.waitUntilCompleted()
            capturedIdleDefaultGPU = buffer.status == .completed && buffer.error == nil
                && matches(readback.firstPixel, [255, 0, 0, 255]) && matches(readback.lastPixel, [255, 0, 0, 255])
        }
    }
    let internalDefaultCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(for: ordinaryGraph, internalDefaultNodes: [1], pixelTransformsByNode: [1: 1])
    )
    var internalDefaultCandidateGPU = false
    if let claim = internalDefaultCapabilities.claim(ordinaryChain),
       let executor = Executor(device: device, capabilities: internalDefaultCapabilities),
       let buffer = queue.makeCommandBuffer() {
        let lease = makeLease(requirePlan(ordinaryGraph), device: device, generation: 98)
        let preparation = executor.prepare(token: claim.token, leases: [lease], historyRehydrateCopiesByEffect: [:],
            frame: frame(98), sourceTexture: source, sourceUniforms: .neutral(), sourcePipeline: sourcePipeline,
            frameInputs: .init(), commandBuffer: buffer, previousStates: [:], previousGraphResources: [:],
            effectGeneration: 98, resetGeneration: 98)
        if case let .success(prepared) = preparation,
           prepared.stages[0].programCacheKeys.count == 2,
           executor.encode(prepared, commandBuffer: buffer),
           let readback = appendReadback(prepared.finalTexture, commandBuffer: buffer) {
            buffer.commit(); buffer.waitUntilCompleted()
            internalDefaultCandidateGPU = buffer.status == .completed && buffer.error == nil
                && matches(readback.firstPixel, [255, 0, 0, 255])
                && matches(readback.lastPixel, [255, 0, 0, 255])
        }
    }

    let nonzeroClearCapabilities = capabilities(
        admittedGraph(nonzeroClearGraph),
        catalog: catalog(for: nonzeroClearGraph)
    )
    let clearVisualFailureCapabilities = capabilities(
        admittedGraph(nonzeroClearGraph),
        catalog: catalog(
            for: nonzeroClearGraph,
            uniformSchemaInvalidNodes: [0]
        )
    )
    let uniqueVisualFailureCapabilities = capabilities(
        admittedGraph(uniqueVisualFailureGraph),
        catalog: catalog(
            for: uniqueVisualFailureGraph,
            uniformSchemaInvalidNodes: [0]
        )
    )
    let readBeforeWriteVisualFailureCapabilities = capabilities(
        admittedGraph(readBeforeWriteVisualFailureGraph),
        catalog: catalog(
            for: readBeforeWriteVisualFailureGraph,
            uniformSchemaInvalidNodes: [0]
        )
    )
    let unusedTargetVisualFailureCapabilities = capabilities(
        admittedGraph(unusedTargetVisualFailureGraph),
        catalog: catalog(
            for: unusedTargetVisualFailureGraph,
            uniformSchemaInvalidNodes: [0]
        )
    )
    let largeNodeGraph = graph(
        targets: [],
        nodes: (0 ..< 513).map { index in
            material(
                index,
                ordinal: index,
                target: output,
                read: input,
                compose: index < 512 ? .bool(true) : nil
            )
        }
    )
    let largeLogicalTargets = (0 ..< 513).map { index in
        Graph.TextureIdentity(
            kind: .framebuffer,
            layerID: layerID,
            effect: effect,
            name: "oversized-\(index)"
        )
    }
    let largeLogicalGraph = graph(
        targets: largeLogicalTargets.map { rawTarget($0) },
        nodes: largeLogicalTargets.enumerated().map {
            material($0.offset, ordinal: $0.offset, target: $0.element, read: input)
        } + [material(513, ordinal: 513, target: output, read: largeLogicalTargets.last!)]
    )
    let results: [String: Bool] = [
        "capturedMainExplicitSourceIgnoresIdleDefaultOnGPU": capturedIdleDefaultGPU,
        "selectedGraphCandidateIgnoresIdleUnknownDefaultAndExecutesShader": internalDefaultCandidateGPU,
    ]
    return (
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
        results
    )
}

private func runCompositionExecutionCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    genericComposeCapabilities: Capabilities,
    genericComposeClaim: Capabilities.ClaimedLayer,
    genericComposeCapability: Capabilities.LayerCapability,
    genericComposeExecutor: Executor,
    genericComposeLease: SceneGraphRenderTargetLease
) -> (
    genericComposePreparation: Result<Executor.PreparedGraph, Executor.Failure>,
    genericComposePublicationContract: Bool,
    genericComposeEncoded: Bool,
    genericComposePixelsPreserved: Bool,
    genericComposeFirstFailure: (prepared: Bool, encoded: Bool, gpu: Bool, restored: Bool),
    genericComposeSecondFailure: (prepared: Bool, encoded: Bool, gpu: Bool, restored: Bool),
    results: [String: Bool]
) {
    guard let genericComposeBuffer = queue.makeCommandBuffer() else {
        fatalError("generic compose buffer unavailable")
    }
    let genericComposePreparation = genericComposeExecutor.prepare(
        token: genericComposeClaim.token,
        leases: [genericComposeLease],
        historyRehydrateCopiesByEffect: [:],
        frame: frame(3),
        sourceTexture: source,
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(),
        commandBuffer: genericComposeBuffer,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    let genericComposeAppended: Bool
    var genericComposePublicationContract = false
    var genericComposeReadback: Readback?
    var genericComposeProgramKeys: [String] = []
    if case let .success(value) = genericComposePreparation {
        let stage = value.stages[0]
        genericComposeProgramKeys = stage.programCacheKeys
        let firstPairNode = stage.pairStep.nodes[0]
        let secondPairNode = stage.pairStep.nodes[1]
        genericComposePublicationContract = value.stages.count == 1
            && stage.programCacheKeys.count == 2
            && stage.programCacheKeys.allSatisfy {
                !$0.hasPrefix("dedicated:")
            }
            && stage.persistentResources.isEmpty
            && intentKinds(value) == ["material", "material"]
            && genericComposeLease.table.plan.logicalTargets.isEmpty
            && genericComposeLease.table.inputOutputAliased
            && genericComposeLease.table.inputTexture
                === genericComposeLease.table.outputTexture
            && genericComposeLease.table.fullFramePair.first
                !== genericComposeLease.table.fullFramePair.second
            && stage.pairStep.nodes.count == 2
            && stage.pairStep.fullFrameOutputWriteCount == 2
            && firstPairNode.currentMemberBeforeNode == .zero
            && firstPairNode.fullFrameWriteMember == .one
            && firstPairNode.rotatesAfterNode
            && firstPairNode.currentMemberAfterNode == .one
            && secondPairNode.currentMemberBeforeNode == .one
            && secondPairNode.fullFrameWriteMember == .zero
            && !secondPairNode.rotatesAfterNode
            && secondPairNode.currentMemberAfterNode == .one
            && stage.effectOutputResource.resourceGeneration == 3
            && stage.effectOutputResource.publication.requestIdentity
                == .graph(output)
            && stage.effectOutputResource.publication.texture
                === genericComposeLease.table.outputTexture
            && value.finalResource.publication.isSameAtom(
                as: stage.effectOutputResource.publication
            )
        genericComposeAppended = genericComposeExecutor.encode(
            value,
            commandBuffer: genericComposeBuffer
        )
            && stage.pairStep.composeTransitionCount == 1
            && stage.pairStep.inputMember == .zero
            && stage.pairStep.outputMember == .zero
            && value.finalTexture
                === genericComposeLease.table.fullFramePair.first
        genericComposeReadback = appendReadback(
            value.finalTexture,
            commandBuffer: genericComposeBuffer
        )
    } else {
        genericComposeAppended = false
    }
    genericComposeBuffer.commit()
    genericComposeBuffer.waitUntilCompleted()
    let genericComposeEncoded = genericComposeAppended
        && genericComposeBuffer.status == .completed
        && genericComposeBuffer.error == nil
    let genericComposePixelsPreserved = genericComposeReadback.map {
        matches($0.firstPixel, [255, 0, 0, 255])
            && matches($0.lastPixel, [255, 0, 0, 255])
    } ?? false

    func executeGenericComposeFailure(
        preparedKey: String?,
        generation: UInt64
    ) -> (prepared: Bool, encoded: Bool, gpu: Bool, restored: Bool) {
        guard let preparedKey,
              let lease = makeChainedLeases(
                  genericComposeCapability,
                  device: device,
                  generation: generation
              )?.first,
              let executor = Executor(
                  device: device,
                  capabilities: genericComposeCapabilities
              ), let command = queue.makeCommandBuffer() else {
            return (false, false, false, false)
        }
        executor.materialEncoder.installTestingPreparationFailure(
            .libraryCompilationRejected(diagnostic: "compose-fixture"),
            preparedKey: preparedKey
        )
        let preparation = executor.prepare(
            token: genericComposeClaim.token,
            leases: [lease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(generation),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: generation,
            resetGeneration: generation
        )
        let reason = "material-pass-preparation-library-compilation"
        guard case let .success(prepared) = preparation,
              prepared.stages.count == 1,
              prepared.stages[0].programCacheKeys == [
                  "visual-failure-passthrough:" + reason
              ],
              prepared.stages[0].effectLocalFailureReasonCode == reason,
              prepared.stages[0].effectOutputResource.publication.texture
                  === lease.table.fullFramePair.first,
              prepared.finalResource.publication.isSameAtom(
                  as: prepared.stages[0].effectOutputResource.publication
              ) else { return (false, false, false, false) }
        let encoded = executor.encode(prepared, commandBuffer: command)
        guard encoded,
              let readback = appendReadback(
                  prepared.finalTexture,
                  commandBuffer: command
              ) else { return (true, encoded, false, false) }
        command.commit()
        command.waitUntilCompleted()
        let gpu = command.status == .completed && command.error == nil
        let restored = matches(readback.firstPixel, [0, 0, 255, 255])
            && matches(readback.lastPixel, [0, 0, 255, 255])
        return (true, encoded, gpu, restored)
    }

    let genericComposeFirstFailure = executeGenericComposeFailure(
        preparedKey: genericComposeProgramKeys.first,
        generation: 23
    )
    let genericComposeSecondFailure = executeGenericComposeFailure(
        preparedKey: genericComposeProgramKeys.last,
        generation: 24
    )
    let results: [String: Bool] = [
        "genericComposeProgramsRotateAndReturnTerminalZero":
            failureCode(genericComposePreparation) == "success"
                && genericComposePublicationContract
                && genericComposeEncoded
                && genericComposePixelsPreserved,
        "genericComposeFirstProgramFailureRestoresPreviousCurrent":
            genericComposeFirstFailure.prepared
                && genericComposeFirstFailure.encoded
                && genericComposeFirstFailure.gpu
                && genericComposeFirstFailure.restored,
        "genericComposeSecondProgramFailureDiscardsPreparedPrefix":
            genericComposeSecondFailure.prepared
                && genericComposeSecondFailure.encoded
                && genericComposeSecondFailure.gpu
                && genericComposeSecondFailure.restored,
    ]
    return (
        genericComposePreparation,
        genericComposePublicationContract,
        genericComposeEncoded,
        genericComposePixelsPreserved,
        genericComposeFirstFailure,
        genericComposeSecondFailure,
        results
    )
}
