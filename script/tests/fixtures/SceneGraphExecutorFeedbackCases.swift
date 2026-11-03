private func runFeedbackCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    secondarySelfUnavailableGraph: Graph,
    secondarySelfUnavailableChain: AdmittedLayerGraph,
    secondarySelfUnavailableCapabilities: Capabilities,
    commandVisualFailureGraph: Graph,
    commandVisualFailureChain: AdmittedLayerGraph,
    commandDynamicTarget: SceneDynamicTarget,
    commandDynamicDefinition: SceneDynamicTargetDefinition,
    commandDynamicCapabilities: Capabilities
) -> [String: Bool] {
    let feedbackVisualFailureGraph = historyGraph(fixedSize: false)
    let feedbackVisualFailureChain = admittedGraph(feedbackVisualFailureGraph)
    let feedbackVisualFailureTarget = dynamicUniformTarget(
        feedbackVisualFailureGraph.nodes[2]
    )
    let feedbackVisualFailureCapabilities = capabilities(
        feedbackVisualFailureChain,
        catalog: catalog(
            for: feedbackVisualFailureGraph,
            dynamicUniformNodes: [2]
        ),
        dynamicProducers: .init(
            userProperties: [],
            timelineTargets: [feedbackVisualFailureTarget],
            sceneScriptTargets: []
        )
    )
    var feedbackVisualFailureDiscardsOnlyUnpublishedHistory = false
    var feedbackVisualFailureRecoversFreshHistory = false
    if let claim = feedbackVisualFailureCapabilities.claim(
            feedbackVisualFailureChain
       ), let executor = Executor(
           device: device,
           capabilities: feedbackVisualFailureCapabilities
       ), let failureCommand = queue.makeCommandBuffer() {
        let failure = executor.prepare(
            token: claim.token,
            leases: [makeLease(
                requirePlan(feedbackVisualFailureGraph),
                device: device,
                generation: 35
            )],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(35),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: failureCommand,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 35,
            resetGeneration: 35
        )
        if case let .success(prepared) = failure,
           let stage = prepared.stages.first {
            feedbackVisualFailureDiscardsOnlyUnpublishedHistory =
                stage.effectLocalFailureReasonCode
                    == "material-finalizer-dynamic-uniform-binding"
                && stage.discardedPersistentTargetState
                && stage.transition.transaction.intents.isEmpty
                && stage.transition.transaction.mappingBefore.isEmpty
                && stage.transition.transaction.mappingAfter.isEmpty
                && stage.transition.nextState.logicalMapping.isEmpty
                && stage.transition.nextState.historyClosureIdentities.isEmpty
                && stage.frameResources.isEmpty
                && stage.persistentResources.isEmpty
                && prepared.historyTokensByEffect[effect] == nil
        }

        if let recoveryCommand = queue.makeCommandBuffer() {
            let recovery = executor.prepare(
                token: claim.token,
                leases: [makeLease(
                    requirePlan(feedbackVisualFailureGraph),
                    device: device,
                    generation: 36
                )],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(
                    36,
                    dynamicDefinitions: [.init(
                        target: feedbackVisualFailureTarget,
                        valueType: .scalar,
                        authoredValue: .scalar(1)
                    )],
                    timelineValues: [
                        feedbackVisualFailureTarget: .scalar(1),
                    ]
                ),
                sourceTexture: source,
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                frameInputs: .init(),
                commandBuffer: recoveryCommand,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 35,
                resetGeneration: 35
            )
            if case let .success(recovered) = recovery,
               let stage = recovered.stages.first {
                feedbackVisualFailureRecoversFreshHistory =
                    !stage.discardedPersistentTargetState
                    && stage.effectLocalFailureReasonCode == nil
                    && !stage.transition.nextState
                        .historyClosureIdentities.isEmpty
                    && !(recovered.historyTokensByEffect[effect] ?? []).isEmpty
            }
        }
    }

    var commandVisualFailurePrepared = false
    var commandVisualFailureEncoded = false
    var commandVisualFailureGPUCompleted = false
    var commandVisualFailurePreservedPreviousCurrent = false
    var commandVisualFailureDiscardedPreparedPrefix = false
    var commandVisualFailureRecoveredNextFrame = false
    if let claim = commandDynamicCapabilities.claim(commandVisualFailureChain),
       let executor = Executor(
           device: device,
           capabilities: commandDynamicCapabilities
       ), let firstCommand = queue.makeCommandBuffer() {
        let plan = requirePlan(commandVisualFailureGraph)
        let preparation = executor.prepare(
            token: claim.token,
            leases: [makeLease(plan, device: device, generation: 32)],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(32),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: firstCommand,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 32,
            resetGeneration: 32
        )
        if case let .success(prepared) = preparation,
           let stage = prepared.stages.first,
           stage.effectLocalFailureReasonCode
                == "material-finalizer-dynamic-uniform-binding",
           stage.programCacheKeys == [
               "visual-failure-passthrough:"
                   + "material-finalizer-dynamic-uniform-binding"
           ] {
            commandVisualFailurePrepared = true
            commandVisualFailureDiscardedPreparedPrefix =
                stage.transition.transaction.intents.isEmpty
                && stage.transition.transaction.mappingBefore.isEmpty
                && stage.transition.transaction.mappingAfter.isEmpty
                && stage.transition.nextState.logicalMapping.isEmpty
                && stage.frameResources.isEmpty
                && stage.persistentResources.isEmpty
            commandVisualFailureEncoded = executor.encode(
                prepared,
                commandBuffer: firstCommand
            )
            let readback = commandVisualFailureEncoded
                ? appendReadback(
                    prepared.finalTexture,
                    commandBuffer: firstCommand
                ) : nil
            firstCommand.commit()
            firstCommand.waitUntilCompleted()
            commandVisualFailureGPUCompleted =
                firstCommand.status == .completed && firstCommand.error == nil
            commandVisualFailurePreservedPreviousCurrent = readback.map {
                matches($0.firstPixel, [0, 0, 255, 255])
                    && matches($0.lastPixel, [0, 0, 255, 255])
            } ?? false

            if let recoveryCommand = queue.makeCommandBuffer() {
                let recovery = executor.prepare(
                    token: claim.token,
                    leases: [makeLease(
                        plan,
                        device: device,
                        generation: 33
                    )],
                    historyRehydrateCopiesByEffect: [:],
                    frame: frame(
                        33,
                        dynamicDefinitions: [commandDynamicDefinition],
                        timelineValues: [commandDynamicTarget: .scalar(1)]
                    ),
                    sourceTexture: source,
                    sourceUniforms: .neutral(),
                    sourcePipeline: sourcePipeline,
                    frameInputs: .init(),
                    commandBuffer: recoveryCommand,
                    previousStates: [effect: stage.transition.nextState],
                    previousGraphResources: [effect: [:]],
                    effectGeneration: 32,
                    resetGeneration: 32
                )
                if case let .success(recovered) = recovery,
                   let recoveredStage = recovered.stages.first {
                    commandVisualFailureRecoveredNextFrame =
                        recoveredStage.effectLocalFailureReasonCode == nil
                        && recoveredStage.programCacheKeys.count == 2
                        && intentKinds(recovered) == [
                            "material", "copy", "material",
                        ]
                        && executor.encode(
                            recovered,
                            commandBuffer: recoveryCommand
                        )
                    recoveryCommand.commit()
                    recoveryCommand.waitUntilCompleted()
                    commandVisualFailureRecoveredNextFrame =
                        commandVisualFailureRecoveredNextFrame
                        && recoveryCommand.status == .completed
                        && recoveryCommand.error == nil
                }
            }
        }
    }

    var secondarySelfUnavailablePrepared = false
    var secondarySelfUnavailableEncoded = false
    var secondarySelfUnavailableGPUCompleted = false
    var secondarySelfUnavailablePreservedPreviousCurrent = false
    var secondarySelfUnavailableDiscardedTargetState = false
    if let claim = secondarySelfUnavailableCapabilities.claim(
            secondarySelfUnavailableChain
       ), let executor = Executor(
           device: device,
           capabilities: secondarySelfUnavailableCapabilities
       ), let commandBuffer = queue.makeCommandBuffer() {
        let preparation = executor.prepare(
            token: claim.token,
            leases: [makeLease(
                requirePlan(secondarySelfUnavailableGraph),
                device: device,
                generation: 50
            )],
            historyRehydrateCopiesByEffect: [:],
            frame: frame(50),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: commandBuffer,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 50,
            resetGeneration: 50
        )
        if case let .success(prepared) = preparation,
           let stage = prepared.stages.first,
           stage.effectLocalFailureReasonCode
                == "dependency-stage-secondary-reference-unavailable",
           stage.programCacheKeys == [
               "visual-failure-passthrough:"
                   + "dependency-stage-secondary-reference-unavailable"
           ] {
            secondarySelfUnavailablePrepared = true
            secondarySelfUnavailableDiscardedTargetState =
                stage.transition.transaction.intents.isEmpty
                && stage.transition.transaction.mappingBefore.isEmpty
                && stage.transition.transaction.mappingAfter.isEmpty
                && stage.transition.nextState.logicalMapping.isEmpty
                && stage.transition.nextState.historyClosureIdentities.isEmpty
                && stage.frameResources.isEmpty
                && stage.persistentResources.isEmpty
            secondarySelfUnavailableEncoded = executor.encode(
                prepared,
                commandBuffer: commandBuffer
            )
            let readback = secondarySelfUnavailableEncoded
                ? appendReadback(
                    prepared.finalTexture,
                    commandBuffer: commandBuffer
                ) : nil
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            secondarySelfUnavailableGPUCompleted =
                commandBuffer.status == .completed
                && commandBuffer.error == nil
            secondarySelfUnavailablePreservedPreviousCurrent =
                readback.map {
                    matches($0.firstPixel, [0, 0, 255, 255])
                        && matches($0.lastPixel, [0, 0, 255, 255])
                } ?? false
        }
    }

    precondition(shaderContract(nodeIndex: 1, pass: false).canonicalSHA256
        != shaderContract(nodeIndex: 1, pass: false, scalarConsumer: "red").canonicalSHA256)
    let results: [String: Bool] = [
        "feedbackVisualFailureDiscardsOnlyUnpublishedHistory":
            feedbackVisualFailureDiscardsOnlyUnpublishedHistory,
        "feedbackVisualFailureRecoversFreshHistory":
            feedbackVisualFailureRecoversFreshHistory,
        "commandVisualFailurePassthroughPrepared":
            commandVisualFailurePrepared,
        "commandVisualFailurePassthroughEncoded":
            commandVisualFailureEncoded,
        "commandVisualFailurePassthroughGPUCompleted":
            commandVisualFailureGPUCompleted,
        "commandVisualFailurePreservesPreviousCurrent":
            commandVisualFailurePreservedPreviousCurrent,
        "commandVisualFailureDiscardsPreparedMaterialAndCopyPrefix":
            commandVisualFailureDiscardedPreparedPrefix,
        "commandVisualFailureRecoversOnNextFrame":
            commandVisualFailureRecoveredNextFrame,
        "secondarySelfUnavailableFBOFailurePrepared":
            secondarySelfUnavailablePrepared,
        "secondarySelfUnavailableFBOFailureEncoded":
            secondarySelfUnavailableEncoded,
        "secondarySelfUnavailableFBOFailureGPUCompleted":
            secondarySelfUnavailableGPUCompleted,
        "secondarySelfUnavailableFBOPreservesPreviousCurrent":
            secondarySelfUnavailablePreservedPreviousCurrent,
        "secondarySelfUnavailableFBODiscardsTargetState":
            secondarySelfUnavailableDiscardedTargetState,
    ]
    return results
}
