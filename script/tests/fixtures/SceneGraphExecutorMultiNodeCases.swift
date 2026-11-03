private func runMultiNodeCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline
) -> (
    ordinaryGraph: Graph,
    secondarySelfUnavailableGraph: Graph,
    secondarySelfUnavailableChain: AdmittedLayerGraph,
    secondarySelfUnavailableCapabilities: Capabilities,
    commandVisualFailureGraph: Graph,
    commandVisualFailureChain: AdmittedLayerGraph,
    commandVisualFailureCapabilities: Capabilities,
    commandDynamicTarget: SceneDynamicTarget,
    commandDynamicDefinition: SceneDynamicTargetDefinition,
    commandDynamicCapabilities: Capabilities,
    ordinaryChain: AdmittedLayerGraph,
    ordinaryCapabilities: Capabilities,
    uniformSchemaMultiNodeCapabilities: Capabilities,
    samplerSchemaMultiNodeCapabilities: Capabilities,
    ordinaryClaim: Capabilities.ClaimedLayer,
    ordinaryExecutor: Executor,
    ordinaryAttemptsAfterWarmup: Int,
    ordinaryLease: SceneGraphRenderTargetLease,
    dynamicMultiCapabilities: Capabilities,
    staticUniformMultiNodeCapabilities: Capabilities,
    declarationConflictMultiNodeCapabilities: Capabilities,
    hostConflictMultiNodeCapabilities: Capabilities,
    dynamicUniformMultiNodeFailure: String,
    staticUniformMultiNodeFailure: String,
    hostConflictMultiNodeFailure: String,
    declarationConflictMultiNodeFailure: String,
    results: [String: Bool]
) {
    let ordinaryGraph = graph(
        targets: [rawTarget(first)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let secondarySelfUnavailableGraph = graph(
        targets: [rawTarget(first)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(
                1,
                ordinal: 1,
                target: output,
                read: first,
                additionalBindings: [binding(
                    input,
                    slot: 1,
                    authoredName: "previous"
                )]
            ),
        ]
    )
    let secondarySelfUnavailableChain = admittedGraph(
        secondarySelfUnavailableGraph
    )
    let secondarySelfUnavailableReference =
        SceneDependencyRenderPlan.Reference(
            consumerLayerID: layerID,
            providerLayerID: layerID,
            slot: .init(
                effectID: effect.descriptorID,
                passIndex: 1,
                slotIndex: 1
            ),
            variant: .secondary
        )
    let secondarySelfUnavailableCapabilities = capabilities(
        secondarySelfUnavailableChain,
        catalog: catalog(for: secondarySelfUnavailableGraph),
        secondarySelfUnavailableReference:
            secondarySelfUnavailableReference
    )
    let commandVisualFailureGraph = graph(
        targets: [rawTarget(first), rawTarget(second)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            command(1, kind: .copy, source: first, target: second),
            material(2, ordinal: 1, target: output, read: second),
        ]
    )
    let commandVisualFailureChain = admittedGraph(commandVisualFailureGraph)
    let commandVisualFailureCapabilities = capabilities(
        commandVisualFailureChain,
        catalog: catalog(
            for: commandVisualFailureGraph,
            uniformSchemaInvalidNodes: [0]
        )
    )
    let commandDynamicTarget = dynamicUniformTarget(
        commandVisualFailureGraph.nodes[2]
    )
    let commandDynamicDefinition = SceneDynamicTargetDefinition(
        target: commandDynamicTarget,
        valueType: .scalar,
        authoredValue: .scalar(1)
    )
    let commandDynamicCapabilities = capabilities(
        commandVisualFailureChain,
        catalog: catalog(
            for: commandVisualFailureGraph,
            dynamicUniformNodes: [2]
        ),
        dynamicProducers: .init(
            userProperties: [],
            timelineTargets: [commandDynamicTarget],
            sceneScriptTargets: []
        )
    )
    let ordinaryChain = admittedGraph(ordinaryGraph)
    let ordinaryCatalog = catalog(for: ordinaryGraph)
    let ordinaryCapabilities = capabilities(
        ordinaryChain,
        catalog: ordinaryCatalog
    )
    let uniformSchemaMultiNodeCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(
            for: ordinaryGraph,
            uniformSchemaInvalidNodes: [0]
        )
    )
    let samplerSchemaMultiNodeCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(
            for: ordinaryGraph,
            samplerSchemaInvalidNodes: [0]
        )
    )
    let ordinaryClaim = ordinaryCapabilities.claim(ordinaryChain)!
    let ordinaryExecutor = Executor(
        device: device,
        capabilities: ordinaryCapabilities
    )!
    let ordinaryWarmupReport = ordinaryExecutor.pipelineWarmupReport
    let ordinaryAttemptsAfterWarmup = ordinaryExecutor.materialEncoder
        .pipelineCompilationAttemptCount
    let ordinaryPlan = requirePlan(ordinaryGraph)
    let ordinaryLease = makeLease(ordinaryPlan, device: device)
    let dynamicMultiTarget = dynamicUniformTarget(ordinaryGraph.nodes[1])
    let dynamicMultiCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(for: ordinaryGraph, dynamicUniformNodes: [1]),
        dynamicProducers: .init(
            userProperties: [],
            timelineTargets: [dynamicMultiTarget],
            sceneScriptTargets: []
        )
    )
    let staticUniformMultiNodeCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(
            for: ordinaryGraph,
            staticUniformMissingDefaultNodes: [0]
        )
    )
    let declarationConflictMultiNodeCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(
            for: ordinaryGraph,
            uniformDeclarationConflictNodes: [0]
        )
    )
    let hostConflictMultiNodeCapabilities = capabilities(
        ordinaryChain,
        catalog: catalog(
            for: ordinaryGraph,
            hostUniformDeclarationConflictNodes: [0]
        )
    )
    func uniformMultiNodeFailure(
        _ capabilities: Capabilities,
        generation: UInt64
    ) -> String {
        guard let claim = capabilities.claim(ordinaryChain),
              let executor = Executor(device: device, capabilities: capabilities),
              let command = queue.makeCommandBuffer() else { return "not-claimed" }
        return failureCode(executor.prepare(
            token: claim.token,
            leases: [makeLease(
                ordinaryPlan,
                device: device,
                generation: generation
            )],
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
        ))
    }
    let dynamicUniformMultiNodeFailure = uniformMultiNodeFailure(
        dynamicMultiCapabilities,
        generation: 6
    )
    let dynamicUniformMultiNodeUsesWholeEffectPassthrough =
        dynamicUniformMultiNodeFailure == "success"
    let staticUniformMultiNodeFailure = uniformMultiNodeFailure(
        staticUniformMultiNodeCapabilities,
        generation: 8
    )
    let staticUniformMultiNodeUsesWholeEffectPassthrough =
        staticUniformMultiNodeFailure == "success"
    let hostConflictMultiNodeFailure = uniformMultiNodeFailure(
        hostConflictMultiNodeCapabilities,
        generation: 10
    )
    let hostConflictMultiNodeUsesWholeEffectPassthrough =
        hostConflictMultiNodeFailure == "success"
    let declarationConflictMultiNodeFailure = uniformMultiNodeFailure(
        declarationConflictMultiNodeCapabilities,
        generation: 12
    )
    let declarationConflictMultiNodeUsesWholeEffectPassthrough =
        declarationConflictMultiNodeFailure == "success"

    let dynamicMultiDefinition = SceneDynamicTargetDefinition(
        target: dynamicMultiTarget,
        valueType: .scalar,
        authoredValue: .scalar(1)
    )
    var fboVisualFailurePrepared = false
    var fboVisualFailureEncoded = false
    var fboVisualFailureGPUCompleted = false
    var fboVisualFailurePreservedPreviousCurrent = false
    var fboVisualFailureDiscardedUncommittedTargetState = false
    var fboVisualFailureRecoveredNextFrame = false
    if let claim = dynamicMultiCapabilities.claim(ordinaryChain),
       let capability = dynamicMultiCapabilities.resolve(
           claim.token,
           for: ordinaryChain
       ), let executor = Executor(
           device: device,
           capabilities: dynamicMultiCapabilities
       ), let firstCommand = queue.makeCommandBuffer() {
        let firstLease = makeLease(
            ordinaryPlan,
            device: device,
            generation: 30
        )
        let firstPreparation = executor.prepare(
            token: claim.token,
            leases: [firstLease],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(30),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: firstCommand,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 30,
            resetGeneration: 30
        )
        if case let .success(prepared) = firstPreparation,
           let stage = prepared.stages.first,
           stage.effectLocalFailureReasonCode
                == "material-finalizer-dynamic-uniform-binding",
           stage.programCacheKeys == [
               "visual-failure-passthrough:"
                   + "material-finalizer-dynamic-uniform-binding"
           ] {
            fboVisualFailurePrepared = true
            fboVisualFailureDiscardedUncommittedTargetState =
                stage.transition.transaction.intents.isEmpty
                && stage.transition.transaction.mappingBefore.isEmpty
                && stage.transition.transaction.mappingAfter.isEmpty
                && stage.transition.nextState.logicalMapping.isEmpty
                && stage.transition.nextState.historyClosureIdentities.isEmpty
                && stage.frameResources.isEmpty
                && stage.persistentResources.isEmpty
                && !stage.discardedPersistentTargetState
            fboVisualFailureEncoded = executor.encode(
                prepared,
                commandBuffer: firstCommand
            )
            let readback = fboVisualFailureEncoded
                ? appendReadback(
                    prepared.finalTexture,
                    commandBuffer: firstCommand
                ) : nil
            firstCommand.commit()
            firstCommand.waitUntilCompleted()
            fboVisualFailureGPUCompleted = firstCommand.status == .completed
                && firstCommand.error == nil
            fboVisualFailurePreservedPreviousCurrent = readback.map {
                matches($0.firstPixel, [0, 0, 255, 255])
                    && matches($0.lastPixel, [0, 0, 255, 255])
            } ?? false

            if let recoveryCommand = queue.makeCommandBuffer() {
                let recovery = executor.prepare(
                    token: claim.token,
                    leases: [makeLease(
                        ordinaryPlan,
                        device: device,
                        generation: 31
                    )],
                    historyRehydrateCopiesByEffect: [:],
                    frame: frame(
                        31,
                        dynamicDefinitions: [dynamicMultiDefinition],
                        timelineValues: [dynamicMultiTarget: .scalar(1)]
                    ),
                    sourceTexture: source,
                    sourceUniforms: .neutral(),
                    sourcePipeline: sourcePipeline,
                    frameInputs: .init(),
                    commandBuffer: recoveryCommand,
                    previousStates: [effect: stage.transition.nextState],
                    previousGraphResources: [effect: [:]],
                    effectGeneration: 30,
                    resetGeneration: 30
                )
                if case let .success(recovered) = recovery,
                   let recoveredStage = recovered.stages.first {
                    fboVisualFailureRecoveredNextFrame =
                        recoveredStage.effectLocalFailureReasonCode == nil
                        && recoveredStage.programCacheKeys.count == 2
                        && !recoveredStage.transition.transaction.mappingAfter.isEmpty
                        && executor.encode(
                            recovered,
                            commandBuffer: recoveryCommand
                        )
                    recoveryCommand.commit()
                    recoveryCommand.waitUntilCompleted()
                    fboVisualFailureRecoveredNextFrame =
                        fboVisualFailureRecoveredNextFrame
                        && recoveryCommand.status == .completed
                        && recoveryCommand.error == nil
                }
            }
        }
    }
    let results: [String: Bool] = [
        "launchWarmupPreparesEveryUniqueOrdinaryPipeline":
            ordinaryWarmupReport.plannedPlanCount == 2
                && ordinaryWarmupReport.uniqueKeyCount > 0
                && ordinaryWarmupReport.readyKeyCount
                    == ordinaryWarmupReport.uniqueKeyCount
                && ordinaryWarmupReport.failedKeyCount == 0
                && ordinaryWarmupReport.compilationAttemptCount
                    == ordinaryWarmupReport.uniqueKeyCount
                && ordinaryAttemptsAfterWarmup
                    == ordinaryWarmupReport.uniqueKeyCount,
        "dynamicUniformMultiNodeUsesWholeEffectPassthrough":
            dynamicUniformMultiNodeUsesWholeEffectPassthrough,
        "staticUniformMultiNodeUsesWholeEffectPassthrough":
            staticUniformMultiNodeUsesWholeEffectPassthrough,
        "hostConflictMultiNodeUsesWholeEffectPassthrough":
            hostConflictMultiNodeUsesWholeEffectPassthrough,
        "declarationConflictMultiNodeUsesWholeEffectPassthrough":
            declarationConflictMultiNodeUsesWholeEffectPassthrough,
        "fboVisualFailurePassthroughPrepared": fboVisualFailurePrepared,
        "fboVisualFailurePassthroughEncoded": fboVisualFailureEncoded,
        "fboVisualFailurePassthroughGPUCompleted":
            fboVisualFailureGPUCompleted,
        "fboVisualFailurePreservesPreviousCurrent":
            fboVisualFailurePreservedPreviousCurrent,
        "fboVisualFailureDiscardsUncommittedTargetState":
            fboVisualFailureDiscardedUncommittedTargetState,
        "fboVisualFailureRecoversOnNextFrame":
            fboVisualFailureRecoveredNextFrame,
    ]
    return (
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
        results
    )
}
