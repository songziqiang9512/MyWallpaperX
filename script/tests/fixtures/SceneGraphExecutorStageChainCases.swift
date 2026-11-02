private func runStageChainCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    secondaryReference: SceneNamedTextureReference
) -> (
    pixelGraph: Graph,
    pixelChain: AdmittedLayerGraph,
    pixelCapabilities: Capabilities,
    forwardUnavailableCapabilities: Capabilities,
    forwardUnavailableClaim: Capabilities.ClaimedLayer?,
    forwardUnavailableCapability: Capabilities.LayerCapability?,
    backwardUnsupportedCapabilities: Capabilities,
    backwardUnsupportedClaim: Capabilities.ClaimedLayer?,
    backwardUnsupportedCapability: Capabilities.LayerCapability?,
    chainedMiddleProgramKey: String?,
    pixelChainFailure: String,
    pixelClaim: Capabilities.ClaimedLayer?,
    pixelCapability: Capabilities.LayerCapability?,
    dormantGraphInputFailure: String,
    dynamicTarget: SceneDynamicTarget,
    dynamicDefinition: SceneDynamicTargetDefinition,
    results: [String: Bool]
) {
    let pixelGraph = chainedGraph()
    let pixelChain = orderedLayerGraph(pixelGraph)
    let exactSecondaryPreviousReference =
        SceneDependencyRenderPlan.Reference(
            consumerLayerID: layerID,
            providerLayerID: layerID,
            slot: .init(
                effectID: chainedThirdEffect.descriptorID,
                passIndex: 0,
                slotIndex: 0
            ),
            variant: .secondary
        )
    let nonImmediateSecondaryReference =
        SceneDependencyRenderPlan.Reference(
            consumerLayerID: layerID,
            providerLayerID: layerID,
            slot: .init(
                effectID: chainedFirstEffect.descriptorID,
                passIndex: 0,
                slotIndex: 0
            ),
            variant: .secondary
        )
    let mixedForwardUnavailableKeys = mixedForwardUnavailableEffectKeys(
        graph: pixelGraph,
        secondaryReference: exactSecondaryPreviousReference
    )
    let nonImmediateMixedForwardUnavailableKeys =
        mixedForwardUnavailableEffectKeys(
            graph: pixelGraph,
            secondaryReference: nonImmediateSecondaryReference
        )
    let pixelCapabilities = capabilities(
        pixelChain,
        catalog: catalog(for: pixelGraph)
    )
    let forwardUnavailableReference = SceneDependencyRenderPlan.Reference(
        consumerLayerID: layerID,
        providerLayerID: layerID + 1,
        slot: .init(
            effectID: chainedSecondEffect.descriptorID,
            passIndex: 0,
            slotIndex: 0
        ),
        variant: .primary
    )
    let forwardUnavailableCapabilities = capabilities(
        pixelChain,
        catalog: catalog(for: pixelGraph),
        forwardUnavailableReference: forwardUnavailableReference
    )
    let forwardUnavailableClaim = forwardUnavailableCapabilities.claim(
        pixelChain
    )
    let forwardUnavailableCapability = forwardUnavailableClaim.flatMap {
        forwardUnavailableCapabilities.resolve($0.token, for: pixelChain)
    }
    let backwardUnsupportedReference = SceneDependencyRenderPlan.Reference(
        consumerLayerID: layerID,
        providerLayerID: layerID - 1,
        slot: .init(
            effectID: chainedSecondEffect.descriptorID,
            passIndex: 0,
            slotIndex: 0
        ),
        variant: .primary
    )
    let backwardUnsupportedCapabilities = capabilities(
        pixelChain,
        catalog: catalog(for: pixelGraph),
        backwardUnsupportedReference: backwardUnsupportedReference
    )
    let backwardUnsupportedClaim = backwardUnsupportedCapabilities.claim(
        pixelChain
    )
    // A script-owned effect visibility target must not reject the layer;
    // the effect keeps its authored value until a typed producer exists.
    let scriptVisibilityCapabilities = capabilities(
        pixelChain,
        catalog: catalog(for: pixelGraph),
        dynamicEffectVisibilityOwners: [
            .init(layerID: layerID, effectIndex: chainedSecondEffect.effectIndex),
        ]
    )
    let scriptVisibilityClaim = scriptVisibilityCapabilities.claim(pixelChain)
    let scriptVisibilityCapability = scriptVisibilityClaim.flatMap {
        scriptVisibilityCapabilities.resolve($0.token, for: pixelChain)
    }
    let backwardUnsupportedCapability = backwardUnsupportedClaim.flatMap {
        backwardUnsupportedCapabilities.resolve($0.token, for: pixelChain)
    }
    var chainedStagesPrepared = false
    var chainedStagesEncoded = false
    var chainedStagesGPUCompleted = false
    var chainedStagePixelsPreserved = false
    var chainedMiddleProgramKey: String?
    var pixelChainFailure = "setup"
    let pixelClaim = pixelCapabilities.claim(pixelChain)
    let pixelCapability = pixelClaim.flatMap {
        pixelCapabilities.resolve($0.token, for: pixelChain)
    }
    let pixelLeases = pixelCapability.flatMap {
        makeChainedLeases($0, device: device)
    }
    if let claim = pixelClaim,
       let leases = pixelLeases,
       let executor = Executor(device: device, capabilities: pixelCapabilities),
       let command = queue.makeCommandBuffer() {
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(1),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )
        pixelChainFailure = failureCode(preparation)
        if case let .success(prepared) = preparation,
           prepared.stages.count == 3,
           prepared.stages.map(\.effect) == [
                chainedFirstEffect,
                chainedSecondEffect,
                chainedThirdEffect,
           ],
           prepared.stages[1].pairStep.inputIdentity
                == prepared.stages[0].pairStep.outputIdentity,
           prepared.stages[2].pairStep.inputIdentity
                == prepared.stages[1].pairStep.outputIdentity,
           prepared.stages[0].effectOutputResource.publication.texture
                === executor.pairTexture(
                    lease: leases[1],
                    member: prepared.stages[1].pairStep.inputMember
                ),
           prepared.stages[1].effectOutputResource.publication.texture
                === executor.pairTexture(
                    lease: leases[2],
                    member: prepared.stages[2].pairStep.inputMember
                ),
           prepared.stages[0].effectOutputResource.publication.texture
                === prepared.stages[2]
                    .effectOutputResource.publication.texture {
            chainedStagesPrepared = true
            chainedMiddleProgramKey = prepared.stages[1].programCacheKeys.first
            var observedStageIndices: [Int] = []
            var stageReadbacks: [Readback] = []
            chainedStagesEncoded = executor.encode(
                prepared,
                commandBuffer: command,
                stageBoundaryObserver: { stageIndex, transition, buffer in
                    guard let readback = appendReadback(
                        transition.effectOutputResource.publication.texture,
                        commandBuffer: buffer
                    ) else { return false }
                    observedStageIndices.append(stageIndex)
                    stageReadbacks.append(readback)
                    return true
                }
            )
            if chainedStagesEncoded,
               let finalRead = appendReadback(
                    prepared.finalTexture,
                    commandBuffer: command
               ) {
                command.commit()
                command.waitUntilCompleted()
                chainedStagesGPUCompleted = command.status == .completed
                    && command.error == nil
                let expectedPixels: [[UInt8]] = [
                    [255, 0, 0, 255],
                    [0, 255, 0, 255],
                    [0, 0, 255, 255],
                ]
                chainedStagePixelsPreserved = observedStageIndices
                    == [0, 1, 2] && stageReadbacks.count == 3
                    && zip(stageReadbacks, expectedPixels).allSatisfy {
                        matches($0.firstPixel, $1)
                            && matches($0.lastPixel, $1)
                    }
                    && matches(finalRead.firstPixel, expectedPixels[2])
                    && matches(finalRead.lastPixel, expectedPixels[2])
            }
        }
    } else if pixelCapability != nil && pixelLeases == nil {
        pixelChainFailure = "leases"
    }

    let dormantGraph = dormantGraphInputChainGraph()
    let dormantChain = orderedLayerGraph(dormantGraph)
    let dormantCapabilities = capabilities(
        dormantChain,
        catalog: catalog(
            for: dormantGraph,
            dormantGraphInputNodes: [0, 1],
            pixelTransformsByNode: [0: 1, 1: 2]
        )
    )
    let dormantClaim = dormantCapabilities.claim(dormantChain)
    let dormantCapability = dormantClaim.flatMap {
        dormantCapabilities.resolve($0.token, for: dormantChain)
    }
    var dormantGraphInputChainPrepared = false
    var dormantGraphInputProgramsPrepared = false
    var dormantGraphInputExactSourcesPublished = false
    var dormantGraphInputEncoded = false
    var dormantGraphInputGPUCompleted = false
    var dormantGraphInputPixelsPreserved = false
    var dormantGraphInputNextFrameClosed = false
    var dormantGraphInputFailure = "setup"
    if let claim = dormantClaim,
       let capability = dormantCapability,
       let leases = makeChainedLeases(
           capability,
           device: device,
           generation: 31
       ), let executor = Executor(
           device: device,
           capabilities: dormantCapabilities
       ), let command = queue.makeCommandBuffer() {
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(1),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 31,
            resetGeneration: 31
        )
        dormantGraphInputFailure = failureCode(preparation)
        if case let .success(prepared) = preparation,
           prepared.stages.count == 2 {
            let first = prepared.stages[0]
            let second = prepared.stages[1]
            dormantGraphInputChainPrepared =
                prepared.stages.map(\.effect) == [
                    chainedFirstEffect,
                    chainedSecondEffect,
                ]
                && first.pairStep.inputIdentity == input
                && first.pairStep.outputIdentity == chainedFirstOutput
                && second.pairStep.inputIdentity == chainedFirstOutput
                && second.pairStep.outputIdentity == chainedSecondOutput
                && first.pairStep.inputMember != first.pairStep.outputMember
                && second.pairStep.inputMember != second.pairStep.outputMember
            dormantGraphInputProgramsPrepared = prepared.stages.allSatisfy {
                $0.programCacheKeys.count == 1
                    && $0.programCacheKeys.allSatisfy {
                        !$0.hasPrefix("dedicated:")
                            && !$0.hasPrefix("visual-failure-passthrough:")
                    }
            }
            dormantGraphInputExactSourcesPublished =
                first.effectOutputResource.publication.requestIdentity
                    == .graph(chainedFirstOutput)
                && second.effectOutputResource.publication.requestIdentity
                    == .graph(chainedSecondOutput)
                && first.effectOutputResource.publication.texture
                    === executor.pairTexture(
                        lease: leases[1],
                        member: second.pairStep.inputMember
                    )
                && prepared.finalResource.publication.isSameAtom(
                    as: second.effectOutputResource.publication
                )
            var observedStageIndices: [Int] = []
            var stageReadbacks: [Readback] = []
            dormantGraphInputEncoded = executor.encode(
                prepared,
                commandBuffer: command,
                stageBoundaryObserver: { stageIndex, transition, buffer in
                    guard let readback = appendReadback(
                        transition.effectOutputResource.publication.texture,
                        commandBuffer: buffer
                    ) else { return false }
                    observedStageIndices.append(stageIndex)
                    stageReadbacks.append(readback)
                    return true
                }
            )
            if dormantGraphInputEncoded,
               let finalReadback = appendReadback(
                   prepared.finalTexture,
                   commandBuffer: command
               ) {
                command.commit()
                command.waitUntilCompleted()
                dormantGraphInputGPUCompleted =
                    command.status == .completed && command.error == nil
                let expectedPixels: [[UInt8]] = [
                    [255, 0, 0, 255],
                    [0, 255, 0, 255],
                ]
                dormantGraphInputPixelsPreserved =
                    observedStageIndices == [0, 1]
                    && stageReadbacks.count == 2
                    && zip(stageReadbacks, expectedPixels).allSatisfy {
                        matches($0.firstPixel, $1)
                            && matches($0.lastPixel, $1)
                    }
                    && matches(finalReadback.firstPixel, expectedPixels[1])
                    && matches(finalReadback.lastPixel, expectedPixels[1])
                if let nextCommand = queue.makeCommandBuffer() {
                    let previousStates = Dictionary(
                        uniqueKeysWithValues: prepared.stages.map {
                            ($0.effect, $0.transition.nextState)
                        }
                    )
                    let previousResources = Dictionary(
                        uniqueKeysWithValues: prepared.stages.map {
                            ($0.effect, $0.persistentResources)
                        }
                    )
                    let nextPreparation = executor.prepare(
                        token: claim.token,
                        leases: leases,
                        historyRehydrateCopiesByEffect: [:],
                        frame: frame(2),
                        sourceTexture: source,
                        sourceUniforms: .neutral(),
                        sourcePipeline: sourcePipeline,
                        frameInputs: .init(),
                        commandBuffer: nextCommand,
                        previousStates: previousStates,
                        previousGraphResources: previousResources,
                        effectGeneration: 31,
                        resetGeneration: 31
                    )
                    if case let .success(nextPrepared) = nextPreparation,
                       nextPrepared.stages.count == 2,
                       nextPrepared.stages[0].pairStep.inputIdentity == input,
                       nextPrepared.stages[1].pairStep.inputIdentity
                            == chainedFirstOutput,
                       nextPrepared.finalResource.publication.isSameAtom(
                           as: nextPrepared.stages[1]
                               .effectOutputResource.publication
                       ), executor.encode(
                           nextPrepared,
                           commandBuffer: nextCommand
                       ), let nextReadback = appendReadback(
                           nextPrepared.finalTexture,
                           commandBuffer: nextCommand
                       ) {
                        nextCommand.commit()
                        nextCommand.waitUntilCompleted()
                        dormantGraphInputNextFrameClosed =
                            nextCommand.status == .completed
                            && nextCommand.error == nil
                            && matches(
                                nextReadback.firstPixel,
                                expectedPixels[1]
                            )
                            && matches(
                                nextReadback.lastPixel,
                                expectedPixels[1]
                            )
                    }
                }
            }
        }
    }

    let dynamicNode = pixelGraph.nodes[1]
    let dynamicTarget = dynamicUniformTarget(dynamicNode)
    let dynamicDefinition = SceneDynamicTargetDefinition(
        target: dynamicTarget,
        valueType: .scalar,
        authoredValue: .scalar(1)
    )
    let results: [String: Bool] = [
        "orderedStagesPreparedTogether": chainedStagesPrepared,
        "orderedStagesEncodedTogether": chainedStagesEncoded,
        "orderedStagesGPUCompleted": chainedStagesGPUCompleted,
        "orderedStagesPreservePriorPixelContribution":
            chainedStagePixelsPreserved,
        "mixedForwardAndSecondaryKeepsOnlyForwardOwner":
            mixedForwardUnavailableKeys == [chainedSecondEffect],
        // A backward provider has no binding contract in this launch;
        // only the exact single-pass effect holding the reference fails
        // soft while the rest of the chain stays admitted.
        "scriptOwnedEffectVisibilityKeepsLayerAdmitted":
            scriptVisibilityClaim != nil
                && scriptVisibilityCapability?.stages.count
                    == pixelGraph.effects.count
                && scriptVisibilityCapability?.stages.allSatisfy({
                    if case .resolved = $0.execution { return true }
                    return false
                }) == true,
        "nonImmediateSecondaryCannotBeShadowed":
            nonImmediateMixedForwardUnavailableKeys == nil
                && !SceneResolvedMaterialExactPreviousInputShadow.accepts(
                    .init(providerLayerID: layerID, variant: .secondary),
                    input: input,
                    consumer: chainedFirstEffect
                ),
        "dormantGraphInputTwoEffectChainPrepared":
            dormantGraphInputChainPrepared,
        "dormantGraphInputProgramsPrepared":
            dormantGraphInputProgramsPrepared,
        "dormantGraphInputExactSourcesAndTerminalPublished":
            dormantGraphInputExactSourcesPublished,
        "dormantGraphInputTwoEffectChainEncoded":
            dormantGraphInputEncoded,
        "dormantGraphInputTwoEffectChainGPUCompleted":
            dormantGraphInputGPUCompleted,
        "dormantGraphInputTwoEffectPixelsPreserved":
            dormantGraphInputPixelsPreserved,
        "dormantGraphInputNextFrameClosed":
            dormantGraphInputNextFrameClosed,
    ]
    return (
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
        results
    )
}
