private typealias SamplerFailureCheck = (
    MTLDevice, MTLCommandQueue, MTLTexture, SceneImageLayerPipeline,
    Capabilities.ClaimedLayer?, Capabilities.LayerCapability?, Capabilities,
    Capabilities.ClaimedLayer?, Capabilities.LayerCapability?, Capabilities
) -> (prepared: Bool, encoded: Bool, gpuCompleted: Bool, continued: Bool, failureCode: String)

private func executeVisualFailurePassthrough(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    claim: Capabilities.ClaimedLayer?,
    capability: Capabilities.LayerCapability?,
    capabilities: Capabilities,
    generation: UInt64,
    reason: String,
    rejectedAtLaunch: Bool = false,
    textureEntries: [
        SceneFrameTextureIdentity: SceneFrameTextureLookupStatus
    ] = [:]
) -> (
    prepared: Bool,
    encoded: Bool,
    gpuCompleted: Bool,
    continued: Bool,
    failureCode: String
) {
    guard let claim, let capability,
          !rejectedAtLaunch || (
              capability.stages.count == 3
                  && capability.stages[1].execution.visualFailureReasonCode == reason
          ),
          let leases = makeChainedLeases(
              capability,
              device: device,
              generation: generation
          ), let executor = Executor(
              device: device,
              capabilities: capabilities
          ), let command = queue.makeCommandBuffer() else {
        return (false, false, false, false, "setup")
    }
    let preparation = executor.prepare(
        token: claim.token,
        leases: leases,
        historyRehydrateCopiesByEffect: [:],
        frame: frame(
            generation,
            textureEntries: textureEntries
        ),
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
    let preparationFailureCode = failureCode(preparation)
    guard case let .success(prepared) = preparation,
          prepared.stages.count == 3,
          prepared.stages[1].programCacheKeys == [
              "visual-failure-passthrough:" + reason
          ], prepared.stages[1].effectLocalFailureReasonCode == reason,
          prepared.stages[0].programCacheKeys.allSatisfy({
              !$0.hasPrefix("visual-failure-passthrough:")
          }), prepared.stages[2].programCacheKeys.allSatisfy({
              !$0.hasPrefix("visual-failure-passthrough:")
          }), prepared.finalResource.publication.requestIdentity
            == .graph(chainedFinalOutput) else {
        return (false, false, false, false, preparationFailureCode)
    }
    var observedStageIndices: [Int] = []
    var stageReadbacks: [Readback] = []
    let encoded = executor.encode(
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
    guard encoded,
          let finalReadback = appendReadback(
              prepared.finalTexture,
              commandBuffer: command
          ) else {
        return (true, encoded, false, false, preparationFailureCode)
    }
    command.commit()
    command.waitUntilCompleted()
    let expectedPixels: [[UInt8]] = [
        [255, 0, 0, 255],
        [255, 0, 0, 255],
        [0, 255, 0, 255],
    ]
    let continued = observedStageIndices == [0, 1, 2]
        && stageReadbacks.count == 3
        && zip(stageReadbacks, expectedPixels).allSatisfy {
            matches($0.firstPixel, $1) && matches($0.lastPixel, $1)
        }
        && matches(finalReadback.firstPixel, expectedPixels[2])
        && matches(finalReadback.lastPixel, expectedPixels[2])
    return (
        true,
        encoded,
        command.status == .completed && command.error == nil,
        continued,
        preparationFailureCode
    )
}

private func runVisualFailureCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    crossLayerCapability: Capabilities.LayerCapability?,
    pixelGraph: Graph,
    pixelChain: AdmittedLayerGraph,
    forwardUnavailableCapabilities: Capabilities,
    forwardUnavailableClaim: Capabilities.ClaimedLayer?,
    forwardUnavailableCapability: Capabilities.LayerCapability?,
    backwardUnsupportedCapabilities: Capabilities,
    backwardUnsupportedClaim: Capabilities.ClaimedLayer?,
    backwardUnsupportedCapability: Capabilities.LayerCapability?,
    pixelCapability: Capabilities.LayerCapability?,
    dynamicTarget: SceneDynamicTarget,
    dynamicDefinition: SceneDynamicTargetDefinition,
    maskState: SceneAssetTextureLaunchState,
    samplerFailureCheck: SamplerFailureCheck
) -> (
    colorBlendCapabilities: Capabilities,
    colorBlendClaim: Capabilities.ClaimedLayer?,
    colorBlendCapability: Capabilities.LayerCapability?,
    colorBlendSnapshot: SceneResolvedMaterialVariantCache.LaunchEnvelopeCapabilitySnapshot?,
    colorBlendProfiles: [String],
    colorBlendOptionalMaskProof: Bool,
    systemProviderCapabilities: Capabilities,
    systemProviderClaim: Capabilities.ClaimedLayer?,
    systemProviderCapability: Capabilities.LayerCapability?,
    results: [String: Bool]
) {
    let dynamicPixelCapabilities = capabilities(
        pixelChain,
        catalog: catalog(for: pixelGraph, dynamicUniformNodes: [1]),
        dynamicProducers: .init(
            userProperties: [],
            timelineTargets: [dynamicTarget],
            sceneScriptTargets: []
        )
    )
    let dynamicPixelClaim = dynamicPixelCapabilities.claim(pixelChain)
    let dynamicPixelCapability = dynamicPixelClaim.flatMap {
        dynamicPixelCapabilities.resolve($0.token, for: pixelChain)
    }
    let staticPixelCapabilities = capabilities(
        pixelChain,
        catalog: catalog(
            for: pixelGraph,
            staticUniformMissingDefaultNodes: [1]
        )
    )
    let staticPixelClaim = staticPixelCapabilities.claim(pixelChain)
    let staticPixelCapability = staticPixelClaim.flatMap {
        staticPixelCapabilities.resolve($0.token, for: pixelChain)
    }
    let samplerSchemaPixelCapabilities = capabilities(
        pixelChain,
        catalog: catalog(
            for: pixelGraph,
            samplerSchemaInvalidNodes: [1]
        )
    )
    let samplerSchemaPixelClaim = samplerSchemaPixelCapabilities.claim(pixelChain)
    let samplerSchemaPixelCapability = samplerSchemaPixelClaim.flatMap {
        samplerSchemaPixelCapabilities.resolve($0.token, for: pixelChain)
    }
    let declarationConflictPixelCapabilities = capabilities(
        pixelChain,
        catalog: catalog(
            for: pixelGraph,
            uniformDeclarationConflictNodes: [1]
        )
    )
    let declarationConflictPixelClaim =
        declarationConflictPixelCapabilities.claim(pixelChain)
    let declarationConflictPixelCapability =
        declarationConflictPixelClaim.flatMap {
            declarationConflictPixelCapabilities.resolve($0.token, for: pixelChain)
        }
    let hostConflictPixelCapabilities = capabilities(
        pixelChain,
        catalog: catalog(
            for: pixelGraph,
            hostUniformDeclarationConflictNodes: [1]
        )
    )
    let hostConflictPixelClaim = hostConflictPixelCapabilities.claim(pixelChain)
    let hostConflictPixelCapability = hostConflictPixelClaim.flatMap {
        hostConflictPixelCapabilities.resolve($0.token, for: pixelChain)
    }
    let colorBlendCapabilities = capabilities(
        pixelChain,
        catalog: catalog(
            for: pixelGraph,
            colorBlendNodes: [1]
        ),
        assetStates: [colorBlendMaskIdentity: maskState],
        assetFormatFacts: [
            colorBlendMaskIdentity.reportToken:
                SceneShaderTextureFormat.r8.macroValue,
        ]
    )
    let colorBlendClaim = colorBlendCapabilities.claim(pixelChain)
    let colorBlendCapability = colorBlendClaim.flatMap {
        colorBlendCapabilities.resolve($0.token, for: pixelChain)
    }
    let colorBlendMaterial = colorBlendCapability?.material(
        effect: chainedSecondEffect,
        nodeIndex: 1
    )
    let colorBlendSnapshot = colorBlendMaterial?.variants
        .launchEnvelopeCapabilitySnapshot()
    let colorBlendProfiles = colorBlendSnapshot?.variants.map {
        $0.routeDecision.profile
    } ?? []
    let colorBlendOptionalMaskProof = colorBlendMaterial?.variants
        .provesEffectLocalOptionalTextureFailure(slot: 1) == true
    let systemProviderCapabilities = capabilities(
        pixelChain,
        catalog: catalog(
            for: pixelGraph,
            systemProvidersByNode: [1: systemProviderName]
        ),
        assetStates: [systemProviderFallbackIdentity: .ready(.data)],
        assetFormatFacts: [
            systemProviderFallbackIdentity.reportToken:
                SceneShaderTextureFormat.r8.macroValue,
        ]
    )
    let systemProviderClaim = systemProviderCapabilities.claim(pixelChain)
    let systemProviderCapability = systemProviderClaim.flatMap {
        systemProviderCapabilities.resolve($0.token, for: pixelChain)
    }
    let systemProviderMaterial = systemProviderCapability?.material(
        effect: chainedSecondEffect,
        nodeIndex: 1
    )
    let systemProviderSnapshot = systemProviderMaterial?.variants
        .launchEnvelopeCapabilitySnapshot()
    let systemProviderCandidateCount = systemProviderSnapshot?.template
        .textureSlots[1]?.candidates.count
    let systemProviderLaunchEnvelopeProof = systemProviderMaterial?.variants
        .provesEffectLocalSystemProviderTextureFailure(slot: 1) == true
    let systemProviderBelowAssetCapabilities = capabilities(
        pixelChain,
        catalog: catalog(
            for: pixelGraph,
            systemProvidersByNode: [1: systemProviderName],
            systemProviderBelowAssetNodes: [1]
        ),
        assetStates: [systemProviderFallbackIdentity: .ready(.data)],
        assetFormatFacts: [
            systemProviderFallbackIdentity.reportToken:
                SceneShaderTextureFormat.r8.macroValue,
        ]
    )
    let systemProviderBelowAssetProof =
        systemProviderBelowAssetCapabilities.claim(pixelChain).flatMap {
            systemProviderBelowAssetCapabilities.resolve(
                $0.token,
                for: pixelChain
            )
        }?.material(
            effect: chainedSecondEffect,
            nodeIndex: 1
        )?.variants.provesEffectLocalSystemProviderTextureFailure(slot: 1)
            == true
    let systemProviderLowerGraphCapabilities = capabilities(
        pixelChain,
        catalog: catalog(
            for: pixelGraph,
            systemProvidersByNode: [1: systemProviderName],
            systemProviderLowerReferencesByNode: [
                1: .graph(chainedFirstOutput),
            ]
        )
    )
    let systemProviderLowerGraphProofGranted =
        systemProviderLowerGraphCapabilities.claim(pixelChain).flatMap {
            systemProviderLowerGraphCapabilities.resolve(
                $0.token,
                for: pixelChain
            )
        }?.material(
            effect: chainedSecondEffect,
            nodeIndex: 1
        )?.variants.provesEffectLocalSystemProviderTextureFailure(slot: 1)
            == true
    let namedLayerTargetCannotUseSystemProviderProof =
        crossLayerCapability?.material(
            effect: effect,
            nodeIndex: 0
        )?.variants.provesEffectLocalSystemProviderTextureFailure(slot: 1)
            == false
    let graphInputCannotUseSystemProviderProof = pixelCapability?.material(
        effect: chainedSecondEffect,
        nodeIndex: 1
    )?.variants.provesEffectLocalSystemProviderTextureFailure(slot: 0)
        == false
    var dynamicUniformValidFramePrepares = false
    if let claim = dynamicPixelClaim,
       let capability = dynamicPixelCapability,
       let leases = makeChainedLeases(capability, device: device, generation: 20),
       let executor = Executor(
           device: device,
           capabilities: dynamicPixelCapabilities
       ), let command = queue.makeCommandBuffer() {
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(
                4,
                dynamicDefinitions: [dynamicDefinition],
                timelineValues: [dynamicTarget: .scalar(1)]
            ),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 4,
            resetGeneration: 4
        )
        if case let .success(prepared) = preparation {
            dynamicUniformValidFramePrepares = prepared.stages.count == 3
                && prepared.stages[1].effectLocalFailureReasonCode == nil
                && prepared.stages[1].programCacheKeys.allSatisfy {
                    !$0.hasPrefix("visual-failure-passthrough:")
                }
        }
    }


    let dynamicUniformFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: dynamicPixelClaim,
        capability: dynamicPixelCapability,
        capabilities: dynamicPixelCapabilities,
        generation: 5,
        reason: "material-finalizer-dynamic-uniform-binding"
    )

    let forwardUnavailableFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: forwardUnavailableClaim,
        capability: forwardUnavailableCapability,
        capabilities: forwardUnavailableCapabilities,
        generation: 49,
        reason: "dependency-stage-reference-unavailable"
    )

    let backwardUnsupportedFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: backwardUnsupportedClaim,
        capability: backwardUnsupportedCapability,
        capabilities: backwardUnsupportedCapabilities,
        generation: 51,
        reason: "dependency-stage-reference-unsupported"
    )

    // Static uniform errors revoke the generic owner during the launch
    // envelope. Require that early boundary, then execute the same strict
    // previous-current, suffix, GPU completion and pixel checks below.
    let staticUniformFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: staticPixelClaim,
        capability: staticPixelCapability,
        capabilities: staticPixelCapabilities,
        generation: 7,
        reason: "material-generic-owner-revoked",
        rejectedAtLaunch: true
    )

    let samplerSchemaFailure = samplerFailureCheck(
        device, queue, source, sourcePipeline,
        samplerSchemaPixelClaim, samplerSchemaPixelCapability, samplerSchemaPixelCapabilities,
        colorBlendClaim, colorBlendCapability, colorBlendCapabilities
    )

    let hostConflictFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: hostConflictPixelClaim,
        capability: hostConflictPixelCapability,
        capabilities: hostConflictPixelCapabilities,
        generation: 9,
        reason: "material-generic-owner-revoked",
        rejectedAtLaunch: true
    )
    let declarationConflictFailure = executeVisualFailurePassthrough(
        device: device,
        queue: queue,
        source: source,
        sourcePipeline: sourcePipeline,
        claim: declarationConflictPixelClaim,
        capability: declarationConflictPixelCapability,
        capabilities: declarationConflictPixelCapabilities,
        generation: 11,
        reason: "material-generic-owner-revoked",
        rejectedAtLaunch: true
    )
    let results: [String: Bool] = [
        "dynamicUniformValidFramePreparesProgram":
            dynamicUniformValidFramePrepares,
        "dynamicUniformFailurePassthroughPrepared":
            dynamicUniformFailure.prepared,
        "dynamicUniformFailurePassthroughEncoded":
            dynamicUniformFailure.encoded,
        "dynamicUniformFailurePassthroughGPUCompleted":
            dynamicUniformFailure.gpuCompleted,
        "dynamicUniformFailurePreservesPreviousAndContinuesSuffix":
            dynamicUniformFailure.continued,
        "staticUniformFailurePassthroughPrepared":
            staticUniformFailure.prepared,
        "staticUniformFailurePassthroughEncoded":
            staticUniformFailure.encoded,
        "staticUniformFailurePassthroughGPUCompleted":
            staticUniformFailure.gpuCompleted,
        "staticUniformFailurePreservesPreviousAndContinuesSuffix":
            staticUniformFailure.continued,
        "samplerSchemaFailurePassthroughPrepared":
            samplerSchemaFailure.prepared,
        "samplerSchemaFailurePassthroughEncoded":
            samplerSchemaFailure.encoded,
        "samplerSchemaFailurePassthroughGPUCompleted":
            samplerSchemaFailure.gpuCompleted,
        "samplerSchemaFailurePreservesPreviousAndContinuesSuffix":
            samplerSchemaFailure.continued,
        "hostConflictFailurePassthroughPrepared":
            hostConflictFailure.prepared,
        "hostConflictFailurePassthroughEncoded":
            hostConflictFailure.encoded,
        "hostConflictFailurePassthroughGPUCompleted":
            hostConflictFailure.gpuCompleted,
        "hostConflictFailurePreservesPreviousAndContinuesSuffix":
            hostConflictFailure.continued,
        "declarationConflictFailurePassthroughPrepared":
            declarationConflictFailure.prepared,
        "declarationConflictFailurePassthroughEncoded":
            declarationConflictFailure.encoded,
        "declarationConflictFailurePassthroughGPUCompleted":
            declarationConflictFailure.gpuCompleted,
        "declarationConflictFailurePreservesPreviousAndContinuesSuffix":
            declarationConflictFailure.continued,
        "colorBlendOptionalMaskLaunchEnvelopeProved":
            colorBlendOptionalMaskProof
                && colorBlendSnapshot?.variants.count == 2
                && colorBlendSnapshot?.allEntriesReady == true
                && Set(colorBlendProfiles) == [
                    SceneGenericShaderCapabilityProfile
                        .sourceProvenGraphInputColorBlend.rawValue,
                ],
        "systemProviderLaunchEnvelopeProved":
            systemProviderLaunchEnvelopeProof
                && systemProviderSnapshot?.hasCachedReachability == true
                && systemProviderSnapshot?.allEntriesReady == true
                && systemProviderSnapshot?.variants.isEmpty == false
                && systemProviderCandidateCount == 2,
        "systemProviderMustBeHighestPrecedenceCandidate":
            !systemProviderBelowAssetProof,
        "systemProviderLowerGraphCandidateCannotUseProof":
            !systemProviderLowerGraphProofGranted,
        "namedLayerTargetCannotUseSystemProviderProof":
            namedLayerTargetCannotUseSystemProviderProof,
        "graphInputCannotUseSystemProviderProof":
            graphInputCannotUseSystemProviderProof,
        "forwardUnavailableDependencyPreservesPreviousAndContinuesSuffix":
            forwardUnavailableFailure.prepared
                && forwardUnavailableFailure.encoded
                && forwardUnavailableFailure.gpuCompleted
                && forwardUnavailableFailure.continued
                && forwardUnavailableFailure.failureCode == "success",
        "unsupportedBackwardReferencePreservesPreviousAndContinuesSuffix":
            backwardUnsupportedFailure.prepared
                && backwardUnsupportedFailure.encoded
                && backwardUnsupportedFailure.gpuCompleted
                && backwardUnsupportedFailure.continued
                && backwardUnsupportedFailure.failureCode == "success",
    ]
    return (
        colorBlendCapabilities,
        colorBlendClaim,
        colorBlendCapability,
        colorBlendSnapshot,
        colorBlendProfiles,
        colorBlendOptionalMaskProof,
        systemProviderCapabilities,
        systemProviderClaim,
        systemProviderCapability,
        results
    )
}

private func runPassthroughCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    sourcePipeline: SceneImageLayerPipeline,
    pixelGraph: Graph,
    pixelChain: AdmittedLayerGraph
) -> (
    visualFailureObservedPixels: [[UInt8]],
    results: [String: Bool]
) {
    let passthroughCapabilities = capabilities(
        pixelChain,
        catalog: catalog(
            for: pixelGraph,
            demandIssueNodes: [1]
        )
    )
    var visualFailureCanClaimEffectLocalPassthrough = false
    var visualFailurePassthroughPrepared = false
    var visualFailurePassthroughEncoded = false
    var visualFailurePassthroughGPUCompleted = false
    var visualFailurePreservesPreviousAndContinuesSuffix = false
    var visualFailurePassthroughIsTypedAndCounted = false
    var visualFailureObservedPixels: [[UInt8]] = []
    let passthroughClaim = passthroughCapabilities.claim(pixelChain)
    let passthroughCapability = passthroughClaim.flatMap {
        passthroughCapabilities.resolve($0.token, for: pixelChain)
    }
    visualFailureCanClaimEffectLocalPassthrough = passthroughClaim != nil
        && passthroughCapability?.stages.count == 3
        && passthroughCapability?.stages[1].execution.visualFailureReasonCode
            == "material-variant-envelope-texture-purpose"
    visualFailurePassthroughIsTypedAndCounted =
        passthroughCapabilities.reportLines.contains {
            $0 == "resolved material execution capability fallback:"
                + " state=prefer-generic outcome=effect-local-passthrough"
                + " reason=material-variant-envelope-texture-purpose count=1"
        }
    let passthroughLeases = passthroughCapability.flatMap {
        makeChainedLeases($0, device: device, generation: 18)
    }
    if let claim = passthroughClaim,
       let leases = passthroughLeases,
       let executor = Executor(
           device: device,
           capabilities: passthroughCapabilities
       ),
       let command = queue.makeCommandBuffer() {
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(2),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 2,
            resetGeneration: 2
        )
        if case let .success(prepared) = preparation,
           prepared.stages.count == 3,
           prepared.stages[1].programCacheKeys == [
               "visual-failure-passthrough:"
                   + "material-variant-envelope-texture-purpose"
           ] {
            visualFailurePassthroughPrepared = true
            var observedStageIndices: [Int] = []
            var stageReadbacks: [Readback] = []
            visualFailurePassthroughEncoded = executor.encode(
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
            if visualFailurePassthroughEncoded,
               let finalReadback = appendReadback(
                   prepared.finalTexture,
                   commandBuffer: command
               ) {
                command.commit()
                command.waitUntilCompleted()
                visualFailurePassthroughGPUCompleted =
                    command.status == .completed && command.error == nil
                let expectedPixels: [[UInt8]] = [
                    [255, 0, 0, 255],
                    [255, 0, 0, 255],
                    [0, 255, 0, 255],
                ]
                visualFailureObservedPixels = stageReadbacks.map(\.firstPixel)
                    + [finalReadback.firstPixel]
                visualFailurePreservesPreviousAndContinuesSuffix =
                    observedStageIndices == [0, 1, 2]
                    && stageReadbacks.count == 3
                    && zip(stageReadbacks, expectedPixels).allSatisfy {
                        matches($0.firstPixel, $1)
                            && matches($0.lastPixel, $1)
                    }
                    && matches(finalReadback.firstPixel, expectedPixels[2])
                    && matches(finalReadback.lastPixel, expectedPixels[2])
            }
        }
    }
    let results: [String: Bool] = [
        "texturePurposeFailureCanClaimEffectLocalPassthrough":
            visualFailureCanClaimEffectLocalPassthrough,
        "texturePurposeFailurePassthroughPrepared":
            visualFailurePassthroughPrepared,
        "texturePurposeFailurePassthroughEncoded":
            visualFailurePassthroughEncoded,
        "texturePurposeFailurePassthroughGPUCompleted":
            visualFailurePassthroughGPUCompleted,
        "texturePurposeFailurePreservesPreviousAndContinuesSuffix":
            visualFailurePreservesPreviousAndContinuesSuffix,
        "texturePurposeFailurePassthroughIsTypedAndCounted":
            visualFailurePassthroughIsTypedAndCounted,
    ]
    return (
        visualFailureObservedPixels,
        results
    )
}
