private func runNamedCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline
) -> (
    crossLayerGraph: Graph,
    crossLayerChain: AdmittedLayerGraph,
    namedReference: SceneNamedTextureReference,
    crossLayerCapabilities: Capabilities,
    crossLayerCapability: Capabilities.LayerCapability?,
    mixedPropertyNamedCapabilities: Capabilities,
    crossLayerPixel: [UInt8],
    crossLayerFailure: String,
    missingProvider: CrossLayerRejectedPreparation,
    wrongProvider: CrossLayerRejectedPreparation,
    secondaryReference: SceneNamedTextureReference,
    secondaryProvider: CrossLayerRejectedPreparation,
    staleProvider: CrossLayerRejectedPreparation,
    secondaryCapabilities: Capabilities,
    results: [String: Bool]
) {
    let crossLayerGraph = graph(
        targets: [],
        nodes: [material(0, ordinal: 0, target: output, read: input)]
    )
    let crossLayerChain = admittedGraph(crossLayerGraph)
    let namedReference = SceneNamedTextureReference(
        providerLayerID: 879,
        variant: .primary
    )
    let externalBinding = SceneDependencyRenderPlan.Binding(
        consumerLayerID: layerID,
        providerLayerID: namedReference.providerLayerID,
        slot: .init(
            effectID: effect.descriptorID,
            passIndex: 0,
            slotIndex: 1
        ),
        blendMode: 0,
        kind: .resolvedMaterial
    )
    let mixedExternalBinding = SceneDependencyRenderPlan.Binding(
        consumerLayerID: layerID,
        providerLayerID: namedReference.providerLayerID,
        slot: externalBinding.slot,
        blendMode: 0,
        kind: .imageLayerBlend,
        requiresResolvedMaterialProgram: true
    )
    let geometryExternalBinding = SceneDependencyRenderPlan.Binding(
        consumerLayerID: layerID,
        providerLayerID: namedReference.providerLayerID,
        slot: externalBinding.slot,
        blendMode: 0,
        kind: .geometryLayer,
        requiresResolvedMaterialProgram: true
    )
    let crossLayerCapabilities = capabilities(
        crossLayerChain,
        catalog: catalog(
            for: crossLayerGraph,
            namedProvidersByNode: [0: namedReference]
        ),
        namedProvider: namedReference,
        dependencyBinding: externalBinding
    )
    let crossLayerClaim = crossLayerCapabilities.claim(crossLayerChain)
    let crossLayerCapability = crossLayerClaim.flatMap {
        crossLayerCapabilities.resolve($0.token, for: crossLayerChain)
    }
    let geometryExternalCapabilities = capabilities(
        crossLayerChain,
        catalog: catalog(
            for: crossLayerGraph,
            namedProvidersByNode: [0: namedReference]
        ),
        namedProvider: namedReference,
        dependencyBinding: geometryExternalBinding
    )
    let geometryExternalCapability = geometryExternalCapabilities
        .claim(crossLayerChain).flatMap {
            geometryExternalCapabilities.resolve(
                $0.token,
                for: crossLayerChain
            )
        }
    let mixedSystemNamedCapabilities = capabilities(
        crossLayerChain,
        catalog: catalog(
            for: crossLayerGraph,
            systemProvidersByNode: [0: "$mediaThumbnail"],
            systemProviderLowerReferencesByNode: [
                0: .provider(.namedLayerTarget(namedReference)),
            ]
        ),
        namedProvider: namedReference,
        dependencyBinding: mixedExternalBinding,
        potentialOptionalNamedFallback: true
    )
    let mixedSystemNamedClaim = mixedSystemNamedCapabilities.claim(
        crossLayerChain
    )
    let mixedSystemNamedCapability = mixedSystemNamedClaim.flatMap {
        mixedSystemNamedCapabilities.resolve($0.token, for: crossLayerChain)
    }
    let mixedPropertyNamedCapabilities = capabilities(
        crossLayerChain,
        catalog: catalog(
            for: crossLayerGraph,
            userPropertyProvidersByNode: [0: "customCover"],
            systemProviderLowerReferencesByNode: [
                0: .provider(.namedLayerTarget(namedReference)),
            ]
        ),
        namedProvider: namedReference,
        dependencyBinding: mixedExternalBinding,
        potentialOptionalNamedFallback: true
    )
    let mixedPropertyNamedClaim = mixedPropertyNamedCapabilities.claim(
        crossLayerChain
    )
    let mixedPropertyNamedCapability = mixedPropertyNamedClaim.flatMap {
        mixedPropertyNamedCapabilities.resolve($0.token, for: crossLayerChain)
    }
    let systemOnlyWithPotentialCapabilities = capabilities(
        crossLayerChain,
        catalog: catalog(
            for: crossLayerGraph,
            systemProvidersByNode: [0: "$mediaThumbnail"],
            systemProviderLowerReferencesByNode: [
                0: .provider(.namedLayerTarget(namedReference)),
            ],
            nonMixedSystemNamedNodes: [0]
        ),
        namedProvider: namedReference,
        dependencyBinding: mixedExternalBinding,
        potentialOptionalNamedFallback: true
    )
    let systemOnlyWithPotentialCapability =
        systemOnlyWithPotentialCapabilities.claim(crossLayerChain).flatMap {
            systemOnlyWithPotentialCapabilities.resolve(
                $0.token,
                for: crossLayerChain
            )
        }
    let sameProviderVectorGraph = chainedGraph()
    let sameProviderVectorChain = orderedLayerGraph(sameProviderVectorGraph)
    let sameProviderVectorSlots = [
        SceneEffectPassSlot(
            effectID: chainedFirstEffect.descriptorID,
            passIndex: 0,
            slotIndex: 1
        ),
        SceneEffectPassSlot(
            effectID: chainedSecondEffect.descriptorID,
            passIndex: 0,
            slotIndex: 1
        ),
        SceneEffectPassSlot(
            effectID: chainedThirdEffect.descriptorID,
            passIndex: 0,
            slotIndex: 1
        ),
    ]
    let sameProviderVectorDirectBinding = SceneDependencyRenderPlan.Binding(
        consumerLayerID: layerID,
        providerLayerID: namedReference.providerLayerID,
        slot: sameProviderVectorSlots[0],
        blendMode: 0,
        kind: .imageLayerBlend,
        requiresResolvedMaterialProgram: true
    )
    let sameProviderVectorPotentialBindings =
        sameProviderVectorSlots.dropFirst().map { slot in
            SceneDependencyRenderPlan.Binding(
                consumerLayerID: layerID,
                providerLayerID: namedReference.providerLayerID,
                slot: slot,
                blendMode: 0,
                kind: .imageLayerBlend,
                requiresResolvedMaterialProgram: true
            )
        }
    let sameProviderVectorPotentialReferences =
        sameProviderVectorPotentialBindings.map { binding in
            SceneDependencyRenderPlan.Reference(
                consumerLayerID: binding.consumerLayerID,
                providerLayerID: binding.providerLayerID,
                slot: binding.slot,
                variant: .primary
            )
        }
    let sameProviderVectorCatalog = catalog(
        for: sameProviderVectorGraph,
        namedProvidersByNode: [0: namedReference],
        systemProvidersByNode: [
            1: "$mediaThumbnail",
            2: "$mediaPreviousThumbnail",
        ],
        systemProviderLowerReferencesByNode: [
            1: .provider(.namedLayerTarget(namedReference)),
            2: .provider(.namedLayerTarget(namedReference)),
        ]
    )
    let sameProviderVectorCapabilities = capabilities(
        sameProviderVectorChain,
        catalog: sameProviderVectorCatalog,
        namedProvider: namedReference,
        dependencyBinding: sameProviderVectorDirectBinding,
        additionalPotentialNamedReferences:
            sameProviderVectorPotentialReferences,
        additionalPotentialDependencyBindings:
            sameProviderVectorPotentialBindings
    )
    let sameProviderVectorCapability = sameProviderVectorCapabilities
        .claim(sameProviderVectorChain).flatMap {
            sameProviderVectorCapabilities.resolve(
                $0.token,
                for: sameProviderVectorChain
            )
        }
    let sameProviderVectorMissingCarrierRejected = capabilities(
        sameProviderVectorChain,
        catalog: sameProviderVectorCatalog,
        namedProvider: namedReference,
        dependencyBinding: sameProviderVectorDirectBinding,
        additionalPotentialNamedReferences:
            sameProviderVectorPotentialReferences,
        additionalPotentialDependencyBindings:
            Array(sameProviderVectorPotentialBindings.dropLast())
    ).claim(sameProviderVectorChain) == nil
    let conflictingNamedReference = SceneNamedTextureReference(
        providerLayerID: 880,
        variant: .primary
    )
    let conflictingGraph = graph(
        targets: [rawTarget(first)],
        nodes: [
            material(0, ordinal: 0, target: first, read: input),
            material(1, ordinal: 1, target: output, read: first),
        ]
    )
    let conflictingChain = admittedGraph(conflictingGraph)
    let conflictingBinding = SceneDependencyRenderPlan.Binding(
        consumerLayerID: layerID,
        providerLayerID: conflictingNamedReference.providerLayerID,
        slot: .init(
            effectID: effect.descriptorID,
            passIndex: 1,
            slotIndex: 1
        ),
        blendMode: 0,
        kind: .resolvedMaterial
    )
    let conflictingCatalog = catalog(
        for: conflictingGraph,
        namedProvidersByNode: [1: conflictingNamedReference],
        systemProvidersByNode: [0: "$mediaThumbnail"],
        systemProviderLowerReferencesByNode: [
            0: .provider(.namedLayerTarget(namedReference)),
        ]
    )
    let potentialCannotMaskOrdinaryDependency = capabilities(
        conflictingChain,
        catalog: conflictingCatalog,
        namedProvider: namedReference,
        dependencyBinding: mixedExternalBinding,
        potentialOptionalNamedFallback: true,
        additionalNamedProvider: conflictingNamedReference,
        additionalDependencyBinding: conflictingBinding
    ).claim(conflictingChain) == nil
    let invalidProgramDependencyRejected = capabilities(
        conflictingChain,
        catalog: conflictingCatalog,
        namedProvider: namedReference,
        dependencyBinding: mixedExternalBinding,
        potentialOptionalNamedFallback: true
    ).claim(conflictingChain) == nil
    var crossLayerPrepared = false
    var crossLayerEncoded = false
    var crossLayerGPUCompleted = false
    var crossLayerProviderChangesPixels = false
    var crossLayerPixel: [UInt8] = []
    var crossLayerFailure = "setup"
    let providerTexture = makeSource(
        device,
        width: 2,
        height: 2,
        usage: [.shaderRead, .renderTarget],
        bgra: [0, 255, 0, 255]
    )
    let providerResource = SceneFrameTextureResource.reservedNamedLayerTarget(
        reference: namedReference,
        frameEpoch: 60,
        texture: providerTexture
    )
    if let claim = crossLayerClaim,
       let capability = crossLayerCapability,
       let resource = providerResource,
       let leases = makeChainedLeases(capability, device: device, generation: 60),
       let executor = Executor(device: device, capabilities: crossLayerCapabilities),
       let command = queue.makeCommandBuffer() {
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(60),
            sourceTexture: makeSource(device, width: 2, height: 2),
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(dependencyEffects: [.init(
                frameEpoch: 60,
                texture: resource.publication.texture,
                namedReference: namedReference,
                reservedMaterialResource: resource
            )]),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: 1,
            resetGeneration: 1
        )
        crossLayerFailure = failureCode(preparation)
        if case let .success(prepared) = preparation,
           prepared.stages.count == 1,
           prepared.stages[0].programCacheKeys.count == 1,
           !prepared.stages[0].programCacheKeys[0].contains("passthrough") {
            crossLayerPrepared = true
            crossLayerEncoded = executor.encode(prepared, commandBuffer: command)
            if crossLayerEncoded,
               let readback = appendReadback(
                prepared.finalTexture,
                commandBuffer: command
               ) {
                command.commit()
                command.waitUntilCompleted()
                crossLayerGPUCompleted = command.status == .completed
                    && command.error == nil
                crossLayerPixel = readback.firstPixel
                crossLayerProviderChangesPixels = crossLayerGPUCompleted
                    && matches(crossLayerPixel, [0, 128, 128, 255])
                    && !matches(crossLayerPixel, [0, 0, 255, 255])
                    && !matches(crossLayerPixel, [255, 255, 255, 255])
            }
        }
    }

    let missingProvider = rejectedCrossLayerPreparation(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline,
        admittedGraph: crossLayerChain,
        capabilities: crossLayerCapabilities,
        dependency: nil
    )
    let wrongNamedReference = SceneNamedTextureReference(
        providerLayerID: namedReference.providerLayerID + 1,
        variant: .primary
    )
    let wrongProviderTexture = makeSource(
        device,
        width: 2,
        height: 2,
        usage: [.shaderRead, .renderTarget],
        bgra: [255, 0, 0, 255]
    )
    let wrongProviderResource = SceneFrameTextureResource.reservedNamedLayerTarget(
        reference: wrongNamedReference,
        frameEpoch: 60,
        texture: wrongProviderTexture
    )
    let wrongProvider = rejectedCrossLayerPreparation(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline,
        admittedGraph: crossLayerChain,
        capabilities: crossLayerCapabilities,
        dependency: .init(
            frameEpoch: 60,
            texture: wrongProviderTexture,
            namedReference: wrongNamedReference,
            reservedMaterialResource: wrongProviderResource
        )
    )
    let secondaryReference = SceneNamedTextureReference(
        providerLayerID: namedReference.providerLayerID,
        variant: .secondary
    )
    let secondaryProvider = rejectedCrossLayerPreparation(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline,
        admittedGraph: crossLayerChain,
        capabilities: crossLayerCapabilities,
        dependency: .init(
            frameEpoch: 60,
            texture: providerTexture,
            namedReference: secondaryReference,
            reservedMaterialResource:
                SceneFrameTextureResource.reservedNamedLayerTarget(
                    reference: secondaryReference,
                    frameEpoch: 60,
                    texture: providerTexture
                )
        )
    )
    let staleResource = SceneFrameTextureResource.reservedNamedLayerTarget(
        reference: namedReference,
        frameEpoch: 59,
        texture: providerTexture
    )
    let staleProvider = rejectedCrossLayerPreparation(
        device: device,
        queue: queue,
        sourcePipeline: sourcePipeline,
        admittedGraph: crossLayerChain,
        capabilities: crossLayerCapabilities,
        dependency: .init(
            frameEpoch: 59,
            texture: providerTexture,
            namedReference: namedReference,
            reservedMaterialResource: staleResource
        )
    )
    let secondaryCapabilities = capabilities(
        crossLayerChain,
        catalog: catalog(
            for: crossLayerGraph,
            namedProvidersByNode: [0: secondaryReference]
        ),
        namedProvider: secondaryReference,
        dependencyBinding: externalBinding
    )
    let results: [String: Bool] = [
        "crossLayerExactOwnershipClaimed": {
            guard let capability = crossLayerCapability,
                  case let .externalPrimary(binding) =
                    capability.dependencyOwnership else { return false }
            return binding == externalBinding
        }(),
        "geometryExternalOwnershipClaimed": {
            guard let capability = geometryExternalCapability,
                  case let .externalPrimary(binding) =
                    capability.dependencyOwnership else { return false }
            return binding == geometryExternalBinding
        }(),
        "mixedSystemNamedFallbackConservesExternalDependency": {
            guard let capability = mixedSystemNamedCapability,
                  case let .externalPrimary(binding) =
                    capability.dependencyOwnership,
                  let material = capability.material(
                      effect: effect,
                      nodeIndex: 0
                  ) else { return false }
            return binding == mixedExternalBinding
                && material.variants
                    .provesEffectLocalSystemProviderTextureFailure(slot: 1)
        }(),
        "mixedPropertyNamedFallbackConservesExternalDependency": {
            guard let capability = mixedPropertyNamedCapability,
                  case let .externalPrimary(binding) =
                    capability.dependencyOwnership,
                  let material = capability.material(
                      effect: effect,
                      nodeIndex: 0
                  ) else { return false }
            return binding == mixedExternalBinding
                && material.variants
                    .provesExactMixedNamedFallback(slot: 1)
                && material.variants
                    .provesEffectLocalUserPropertyTextureFailure(slot: 1)
        }(),
        "mixedPropertyNamedClaimCreated":
            mixedPropertyNamedClaim != nil,
        "mixedPropertyNamedCapabilityCreated":
            mixedPropertyNamedCapability != nil,
        "mixedPropertyNamedExactEnvelopeProved":
            mixedPropertyNamedCapability?.material(
                effect: effect,
                nodeIndex: 0
            )?.variants.provesExactMixedNamedFallback(slot: 1) == true,
        "unselectedPotentialDoesNotRevokeSystemOnlyProgram": {
            guard let capability = systemOnlyWithPotentialCapability,
                  case .none = capability.dependencyOwnership else {
                return false
            }
            return true
        }(),
        "sameProviderMixedVectorConservesAuthoredSlots": {
            guard let capability = sameProviderVectorCapability,
                  case let .externalPrimary(binding) =
                    capability.dependencyOwnership else { return false }
            return binding.consumerLayerID == layerID
                && binding.providerLayerID == namedReference.providerLayerID
                && binding.slot == sameProviderVectorSlots[0]
                && binding.referenceSlots == sameProviderVectorSlots
                && binding.kind == .imageLayerBlend
                && binding.requiresResolvedMaterialProgram
        }(),
        "sameProviderMixedVectorRejectsMissingSiblingCarrier":
            sameProviderVectorMissingCarrierRejected,
        "potentialCannotMaskOrdinaryDependency":
            potentialCannotMaskOrdinaryDependency,
        "invalidProgramDependencyRejected":
            invalidProgramDependencyRejected,
        "crossLayerPreparedUnifiedProgram": crossLayerFailure == "success"
            && crossLayerPrepared,
        "crossLayerEncodedAndGPUCompleted": crossLayerEncoded
            && crossLayerGPUCompleted,
        "crossLayerProviderPixelsReachOutputWithoutWhiteFallback":
            crossLayerProviderChangesPixels,
        "crossLayerMissingProviderRejectedAtomically":
            missingProvider.failureCode != "success"
                && missingProvider.previousCurrentPreserved
                && missingProvider.safeSuffixCompleted,
        "crossLayerWrongProviderRejectedAtomically":
            wrongProvider.failureCode != "success"
                && wrongProvider.previousCurrentPreserved
                && wrongProvider.safeSuffixCompleted,
        "crossLayerSecondaryRejectedAtomically":
            secondaryProvider.failureCode
                == Executor.Failure.graphPublicationRejected.rawValue
                && secondaryProvider.previousCurrentPreserved
                && secondaryProvider.safeSuffixCompleted,
        "crossLayerStaleEpochRejectedAtomically":
            staleProvider.failureCode
                == Executor.Failure.graphPublicationRejected.rawValue
                && staleProvider.previousCurrentPreserved
                && staleProvider.safeSuffixCompleted,
    ]
    return (
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
        results
    )
}
