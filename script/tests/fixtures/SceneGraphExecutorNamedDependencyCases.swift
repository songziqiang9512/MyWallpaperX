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
    let systemOnlyWithPotentialClaim = systemOnlyWithPotentialCapabilities.claim(crossLayerChain)
    let systemOnlyWithPotentialCapability =
        systemOnlyWithPotentialClaim.flatMap {
            systemOnlyWithPotentialCapabilities.resolve(
                $0.token,
                for: crossLayerChain
            )
        }
    var systemOnlyProbe: [String: Any] = [
        "case": "system-only-with-potential", "claim": systemOnlyWithPotentialClaim != nil,
        "resolved": systemOnlyWithPotentialCapability != nil,
        "report": Array(systemOnlyWithPotentialCapabilities.reportLines.prefix(8)),
        "bindings": (systemOnlyWithPotentialCapabilities.preparedNamedInputBindingsByConsumerLayerID[layerID] ?? []).map {
            "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)=\($0.providerLayerID)"
        },
    ]
    if let capability = systemOnlyWithPotentialCapability {
        systemOnlyProbe["ownership"] = capability.dependencyOwnership.reportKind
        systemOnlyProbe["stageReasons"] = capability.stages.map {
            $0.execution.visualFailureReasonCode ?? $0.execution.initiallyInactivePassthroughReasonCode ?? "resolved"
        }
        if let material = capability.material(effect: effect, nodeIndex: 0) {
            let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
            systemOnlyProbe["mixedProof"] = material.variants.provesExactMixedNamedFallback(slot: 1)
            systemOnlyProbe["ready"] = snapshot.allEntriesReady
            let variants: [[String: Any]] = snapshot.variants.prefix(4).map {
                ["readiness": Int($0.readinessMask), "samplers": $0.activeSamplers.keys.sorted(),
                 "frontendSlots": $0.frontendProgram.textureBindings.map(\.slot),
                 "mixedSlots": $0.textureSelectionFacts.mixedProviderSlots.keys.sorted()]
            }
            systemOnlyProbe["variants"] = variants
        }
    }
    if let data = try? JSONSerialization.data(withJSONObject: systemOnlyProbe, options: [.sortedKeys]) {
        FileHandle.standardError.write(Data("MWX TEST named-potential ".utf8) + data + Data([10]))
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
    let sameProviderVectorMissingCarrierCapabilities = capabilities(
        sameProviderVectorChain,
        catalog: sameProviderVectorCatalog,
        namedProvider: namedReference,
        dependencyBinding: sameProviderVectorDirectBinding,
        additionalPotentialNamedReferences:
            sameProviderVectorPotentialReferences,
        additionalPotentialDependencyBindings:
            Array(sameProviderVectorPotentialBindings.dropLast())
    )
    let sameProviderVectorMissingCarrierFallsBackLocally = {
        guard let claim = sameProviderVectorMissingCarrierCapabilities.claim(sameProviderVectorChain),
              let capability = sameProviderVectorMissingCarrierCapabilities.resolve(claim.token, for: sameProviderVectorChain),
              capability.stages.count == 3,
              case .resolved = capability.stages[0].execution,
              case .resolved = capability.stages[1].execution,
              case .visualFailurePassthrough = capability.stages[2].execution else { return false }
        let inputs = sameProviderVectorMissingCarrierCapabilities
            .preparedNamedInputBindingsByConsumerLayerID[layerID] ?? []
        return inputs.map(\.slot) == Array(sameProviderVectorSlots.prefix(2))
            && inputs.allSatisfy { $0.providerLayerID == namedReference.providerLayerID }
    }()
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
    let combinedNamedCapabilities = capabilities(
        conflictingChain,
        catalog: conflictingCatalog,
        namedProvider: namedReference,
        dependencyBinding: mixedExternalBinding,
        potentialOptionalNamedFallback: true,
        additionalNamedProvider: conflictingNamedReference,
        additionalDependencyBinding: conflictingBinding
    )
    let missingProgramCarrierCapabilities = capabilities(
        conflictingChain,
        catalog: conflictingCatalog,
        namedProvider: namedReference,
        dependencyBinding: mixedExternalBinding,
        potentialOptionalNamedFallback: true
    )
    let missingProgramCarrierFallsBackWithoutNamedDemand = {
        guard let claim = missingProgramCarrierCapabilities.claim(conflictingChain),
              let capability = missingProgramCarrierCapabilities.resolve(claim.token, for: conflictingChain),
              capability.stages.count == 1,
              case .visualFailurePassthrough = capability.stages[0].execution else { return false }
        return capability.materials.isEmpty
            && missingProgramCarrierCapabilities.preparedNamedInputBindingsByConsumerLayerID[layerID] == []
    }()
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
            namedReference: namedReference,
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
        "scalarMixedProgramConservesLowerNamedBinding": {
            guard let capability = systemOnlyWithPotentialCapability,
                  case let .externalPrimary(binding) = capability.dependencyOwnership,
                  let material = capability.material(effect: effect, nodeIndex: 0) else {
                return false
            }
            let snapshot = material.variants.launchEnvelopeCapabilitySnapshot()
            return binding == mixedExternalBinding
                && systemOnlyWithPotentialCapabilities.preparedNamedInputBindingsByConsumerLayerID[layerID]
                    == [mixedExternalBinding]
                && material.variants.provesExactMixedNamedFallback(slot: 1)
                && snapshot.allEntriesReady && snapshot.variants.count == 2
                && snapshot.variants.allSatisfy {
                    Set($0.activeSamplers.keys) == [0, 1]
                        && Set($0.frontendProgram.textureBindings.map(\.slot)) == [0, 1]
                        && $0.textureSelectionFacts.mixedProviderSlots[1]?.lowerNamedReference == namedReference
                }
        }(),
        "sameProviderMixedVectorConservesAuthoredSlots": {
            guard let capability = sameProviderVectorCapability else { return false }
            let vector = sameProviderVectorCapabilities.preparedNamedInputBindingsByConsumerLayerID[layerID] ?? []
            return capability.dependencyOwnership.referenceCount == 3
                && vector.map(\.slot) == sameProviderVectorSlots
                && vector.allSatisfy { $0.providerLayerID == namedReference.providerLayerID }
        }(),
        "sameProviderMissingSiblingCarrierFallsBackLocally":
            sameProviderVectorMissingCarrierFallsBackLocally,
        "potentialAndOrdinaryDependenciesKeepBothProviders":
            combinedNamedCapabilities.claim(conflictingChain) != nil
                && Set((combinedNamedCapabilities.preparedNamedInputBindingsByConsumerLayerID[layerID] ?? []).map(\.providerLayerID))
                    == [namedReference.providerLayerID, conflictingNamedReference.providerLayerID],
        "missingProgramCarrierFallsBackWithoutNamedDemand":
            missingProgramCarrierFallsBackWithoutNamedDemand,
        "crossLayerPreparedUnifiedProgram": crossLayerFailure == "success"
            && crossLayerPrepared,
        "crossLayerEncodedAndGPUCompleted": crossLayerEncoded
            && crossLayerGPUCompleted,
        "crossLayerProviderPixelsReachOutputWithoutWhiteFallback":
            crossLayerProviderChangesPixels,
        "crossLayerWrongProviderRejectedAtomically":
            wrongProvider.failureCode == Executor.Failure.graphPublicationRejected.rawValue
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

// Self-authored inputs qualify each read independently. The shader executes
// through the production Program/GraphExecutor; expected bytes live in Python.
private func runNamedInputVectorCases(
    device: MTLDevice, queue: MTLCommandQueue, sourcePipeline: SceneImageLayerPipeline
) -> [[String: Any]] {
    var rows: [[String: Any]] = []
    let controls = ["both", "A0", "B0", "swap"]
    for topology in ["same", "cross", "passes", "sameProvider"] {
        for control in controls {
            rows.append(renderNamedInputVector(topology, control: control,
                device: device, queue: queue, sourcePipeline: sourcePipeline))
        }
    }
    for topology in ["renamed", "unused", "missing", "missingSuffix", "metadata", "metadataMissing", "background"] {
        rows.append(renderNamedInputVector(topology, control: "both",
            device: device, queue: queue, sourcePipeline: sourcePipeline))
    }
    return rows
}

private func renderNamedInputVector(
    _ topology: String, control: String, device: MTLDevice,
    queue: MTLCommandQueue, sourcePipeline: SceneImageLayerPipeline
) -> [String: Any] {
    let renamed = topology == "renamed"
    let consumer = renamed ? 581 : layerID
    let providerA = SceneNamedTextureReference(providerLayerID: renamed ? 1901 : 901, variant: .primary)
    let providerB = SceneNamedTextureReference(providerLayerID: topology == "sameProvider" ? 901
        : topology == "unused" ? 999 : renamed ? 1902 : 902, variant: .primary)
    let weight = renamed ? "u_UnseenRatio" : "g_OwnWeight"
    let resource = renamed ? "retitled-resource" : "owned-vector"
    let firstKey = Graph.EffectKey(layerID: consumer, effectIndex: 0,
        descriptorID: renamed ? "sun" : "z-first")
    let secondKey = Graph.EffectKey(layerID: consumer, effectIndex: 1,
        descriptorID: renamed ? "moon" : "a-second")
    let sourceIdentity = Graph.TextureIdentity(kind: .layerSource, layerID: consumer, effect: nil, name: nil)
    let firstOutput = Graph.TextureIdentity(kind: .effectOutput, layerID: consumer, effect: firstKey, name: nil)
    let finalOutput = Graph.TextureIdentity(kind: .effectOutput, layerID: consumer, effect: secondKey, name: nil)
    let middle = Graph.TextureIdentity(kind: .framebuffer, layerID: consumer, effect: firstKey, name: "middle")
    let cross = topology == "cross" || topology == "missingSuffix"
    let passes = topology == "passes"
    func node(_ index: Int, owner: Graph.EffectKey, pass: Int,
              read: Graph.TextureIdentity, target: Graph.TextureIdentity) -> Graph.Node {
        .init(nodeIndex: index, effect: owner, definitionPassIndex: pass,
            materialOrdinal: pass, instancePassIndex: pass, kind: .material,
            materialPath: "materials/\(resource)/\(owner.descriptorID).json",
            materialPassID: "\(resource)-\(owner.effectIndex)#\(pass)", target: target,
            bindings: [binding(read)], commandSource: nil, commandTarget: nil,
            compose: nil, conditions: nil)
    }
    let nodes: [Graph.Node] = cross ? [
        node(0, owner: firstKey, pass: 0, read: sourceIdentity, target: firstOutput),
        node(1, owner: secondKey, pass: 0, read: firstOutput, target: finalOutput),
    ] : passes ? [
        node(0, owner: firstKey, pass: 0, read: sourceIdentity, target: middle),
        node(1, owner: firstKey, pass: 1, read: middle, target: firstOutput),
    ] : [node(0, owner: firstKey, pass: 0, read: sourceIdentity, target: firstOutput)]
    let effects: [Graph.Effect] = cross ? [
        .init(key: firstKey, definitionPath: "effects/\(resource)/first.json",
            input: sourceIdentity, output: firstOutput, nodeIndices: [0]),
        .init(key: secondKey, definitionPath: "effects/\(resource)/second.json",
            input: firstOutput, output: finalOutput, nodeIndices: [1]),
    ] : [.init(key: firstKey, definitionPath: "effects/\(resource)/single.json",
        input: sourceIdentity, output: firstOutput, nodeIndices: nodes.map(\.nodeIndex))]
    let candidateGraph = Graph(layerID: consumer, effects: effects,
        renderTargets: passes ? [rawTarget(middle)] : [], nodes: nodes,
        finalOutput: cross ? finalOutput : firstOutput, blockers: [])
    let chain: AdmittedLayerGraph = cross ? orderedLayerGraph(candidateGraph) : .init(
        layerID: consumer, renderGraph: candidateGraph, stagePrograms: [.init(
            effectKey: firstKey, inputRole: .layerSource, stageGraph: candidateGraph,
            executionPlan: executionPlan(for: candidateGraph))])
    var entries: [SceneResolvedMaterialRuntimeCatalog.Key: SceneResolvedMaterialRuntimeCatalog.Entry] = [:]
    var aSlots: [SceneEffectPassSlot] = [], bSlots: [SceneEffectPassSlot] = []
    for item in nodes {
        let metadata = topology == "metadata" || topology == "metadataMissing"
        let firstOfPair = (cross || passes) && item.nodeIndex == 0
        let suffix = topology == "missingSuffix" && item.nodeIndex == 1
        let readsA = !metadata && (firstOfPair || suffix || !cross && !passes)
        let readsB = !suffix && (!firstOfPair || topology == "missingSuffix")
        let own = effects.first { $0.key == item.effect }!
        var slots = Array<Template.TextureSlot?>(repeating: nil, count: 8)
        slots[0] = .init(index: 0, candidates: [.init(reference: .graph(item.bindings[0].texture), provenance: .explicitBinding)])
        let aSlot = SceneEffectPassSlot(effectID: item.effect.descriptorID,
            passIndex: item.instancePassIndex!, slotIndex: 2)
        let bSlot = SceneEffectPassSlot(effectID: item.effect.descriptorID,
            passIndex: item.instancePassIndex!, slotIndex: 5)
        if readsA {
            slots[2] = .init(index: 2, candidates: [.init(reference: .provider(.namedLayerTarget(providerA)), provenance: .instance)])
            aSlots.append(aSlot)
        }
        if readsB {
            slots[5] = .init(index: 5, candidates: [.init(reference: .provider(.namedLayerTarget(providerB)), provenance: .instance)])
            bSlots.append(bSlot)
        }
        var declarations = "varying vec2 v_TexCoord;\nuniform float \(weight); // {\"default\":0.75}\n"
        var body: String
        if metadata {
            declarations += "uniform sampler2D g_Texture5;\nuniform vec4 g_Texture5Resolution;\nuniform vec4 g_Texture5Rotation;\nuniform vec2 g_Texture5Translation;\n"
            body = "vec3 color = vec3(g_Texture5Resolution.xy / 8.0, 0.25 + g_Texture5Rotation.x + g_Texture5Translation.x);"
        } else if suffix || firstOfPair && topology != "missingSuffix" {
            declarations += "uniform sampler2D g_Texture2;\n"
            body = "vec3 color = texSample2D(g_Texture2, v_TexCoord).rgb;"
        } else if topology == "unused" {
            declarations += "uniform sampler2D g_Texture2;\nuniform sampler2D g_Texture5;\n"
            body = "vec3 color = texSample2D(g_Texture2, v_TexCoord).rgb;"
        } else {
            declarations += "uniform sampler2D \(readsA ? "g_Texture2" : "g_Texture0");\nuniform sampler2D g_Texture5;\n"
            let uvA = topology == "sameProvider" ? "vec2(0.25, 0.5)" : "v_TexCoord"
            let uvB = topology == "sameProvider" ? "vec2(0.75, 0.5)" : "v_TexCoord"
            body = "vec3 color = \(weight) * texSample2D(\(readsA ? "g_Texture2" : "g_Texture0"), \(uvA)).rgb + (1.0 - \(weight)) * texSample2D(g_Texture5, \(uvB)).rgb;"
        }
        if topology == "background" {
            slots[7] = .init(index: 7, candidates: [.init(reference: .provider(.sceneBackground(consumerLayerID: consumer)), provenance: .instance)])
            declarations += "uniform sampler2D g_Texture7; // {\"hidden\":true,\"default\":\"_rt_FullFrameBuffer\"}\n"
            body = "vec3 color = 0.5 * texSample2D(g_Texture2, v_TexCoord).rgb + 0.25 * texSample2D(g_Texture5, v_TexCoord).rgb + 0.25 * texSample2D(g_Texture7, v_TexCoord).rgb;"
        }
        let contract = shaderContract(nodeIndex: item.nodeIndex, pass: false,
            fragmentOverride: declarations + "void main() { \(body) gl_FragColor = vec4(color, 1.0); }")
        guard let value = Template.validated(textureSlots: slots, combos: [], uniformDeclarations: [],
            renderState: SceneMaterialRenderState.compile(blending: "normal", depthTest: "disabled",
                depthWrite: "disabled", cullMode: "nocull", alphaWriting: nil)!,
            graphRole: .init(effectInput: role(own.input), effectOutput: role(own.output),
                nodeTarget: role(item.target!), bindings: [.init(slot: 0, texture: role(item.bindings[0].texture))]),
            shaderContract: contract, diagnosticProvenance: .init(nodeIndex: item.nodeIndex,
                authoredShaderPath: contract.identity, contractIdentity: contract.identity,
                contractCanonicalSHA256: contract.canonicalSHA256,
                textureSources: [], uniformSources: [])) else { fatalError("named-vector-template") }
        entries[.init(effect: item.effect, nodeIndex: item.nodeIndex)] = .template(value,
            textureFormatSlots: SceneResolvedMaterialShaderSchema.textureFormatSlots(in: value))
    }
    func sourceBinding(_ provider: SceneNamedTextureReference, _ slots: [SceneEffectPassSlot]) -> SceneDependencyRenderPlan.Binding? {
        slots.first.map { .init(consumerLayerID: consumer, providerLayerID: provider.providerLayerID,
            slot: $0, referenceSlots: slots, blendMode: 0, kind: .imageLayerBlend, requiresResolvedMaterialProgram: true) }
    }
    let aBinding = sourceBinding(providerA, aSlots), bBinding = sourceBinding(providerB, bSlots)
    let primary = aBinding ?? bBinding!
    let primaryReference = aBinding == nil ? providerB : providerA
    let values = capabilities(chain, catalog: .init(entries: entries),
        namedProvider: primaryReference, dependencyBinding: primary,
        additionalNamedProvider: aBinding != nil && bBinding != nil ? providerB : nil,
        additionalDependencyBinding: aBinding != nil ? bBinding : nil,
        contentKind: topology == "cross" ? "solid" : "image")
    var row: [String: Any] = ["topology": topology, "control": control, "prepared": false]
    guard let claim = values.claim(chain), let capability = values.resolve(claim.token, for: chain),
          let leases = makeChainedLeases(capability, device: device, generation: 60),
          let executor = Executor(device: device, capabilities: values), let command = queue.makeCommandBuffer()
    else { row["failure"] = values.reportLines; return row }
    let bindings = values.preparedNamedInputBindingsByConsumerLayerID[consumer] ?? []
    row["bindings"] = bindings.map { "\($0.slot.effectID):\($0.slot.passIndex):\($0.slot.slotIndex)=\($0.providerLayerID)" }
    row["providers"] = Set(bindings.map(\.providerLayerID)).sorted()
    var a: [UInt8] = control == "A0" ? [0, 0, 0, 255] : [16, 32, 192, 255]
    var b: [UInt8] = control == "B0" ? [0, 0, 0, 255] : [64, 160, 16, 255]
    if control == "swap" { swap(&a, &b) }
    let pattern: [UInt8] = (0..<8).flatMap { $0 % 4 < 2 ? a : b }
    let aTexture = makeSource(device, width: 4, height: 2, usage: [.shaderRead, .renderTarget],
        bgra: a, pixelsBGRA: topology == "sameProvider" ? pattern : nil)
    let bTexture = makeSource(device, width: 4, height: 2, usage: [.shaderRead, .renderTarget], bgra: b)
    var dependencies: [SceneDependencyEffectInput] = []
    if let resource = SceneFrameTextureResource.reservedNamedLayerTarget(reference: providerA, frameEpoch: 60, texture: aTexture), aBinding != nil {
        dependencies.append(.init(frameEpoch: 60, texture: aTexture, namedReference: providerA, reservedMaterialResource: resource))
    }
    if bBinding != nil && providerB != providerA && topology != "missing" && topology != "missingSuffix"
        && topology != "metadataMissing" && topology != "unused",
       let resource = SceneFrameTextureResource.reservedNamedLayerTarget(reference: providerB, frameEpoch: 60, texture: bTexture) {
        dependencies.append(.init(frameEpoch: 60, texture: bTexture, namedReference: providerB, reservedMaterialResource: resource))
    }
    var frameEntries: [SceneFrameTextureIdentity: SceneFrameTextureLookupStatus] = [:]
    var sceneBackgroundResource: SceneFrameTextureResource?
    if topology == "background" {
        let background = makeSource(device, width: 2, height: 2, usage: [.shaderRead, .renderTarget], bgra: [192, 48, 32, 255])
        if let resource = SceneFrameTextureResource.sameFrameSceneBackground(consumerLayerID: consumer, frameEpoch: 60, texture: background) {
            frameEntries[.sceneBackground(consumer)] = .ready(resource)
            sceneBackgroundResource = resource
        }
    }
    let result = executor.prepare(token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
        frame: frame(60, textureEntries: frameEntries), sceneBackgroundResource: sceneBackgroundResource,
        sourceTexture: makeSource(device, bgra: [56, 40, 24, 255]),
        sourceUniforms: .neutral(), sourcePipeline: sourcePipeline,
        frameInputs: .init(dependencyEffects: dependencies), commandBuffer: command,
        previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1)
    guard case let .success(prepared) = result, executor.encode(prepared, commandBuffer: command),
          let readback = appendReadback(prepared.finalTexture, commandBuffer: command)
    else { row["failure"] = failureCode(result); return row }
    // An ordinary, independently prepared green peer shares this command.
    let peerGraph = graph(targets: [], nodes: [material(0, ordinal: 0, target: output, read: input)])
    let peerChain = admittedGraph(peerGraph)
    let peerValues = capabilities(peerChain, catalog: catalog(for: peerGraph, passNodes: [0]))
    guard let peerClaim = peerValues.claim(peerChain), let peerCapability = peerValues.resolve(peerClaim.token, for: peerChain),
          let peerLeases = makeChainedLeases(peerCapability, device: device, generation: 60),
          let peerExecutor = Executor(device: device, capabilities: peerValues),
          case let .success(peer) = peerExecutor.prepare(token: peerClaim.token, leases: peerLeases,
            historyRehydrateCopiesByEffect: [:], frame: frame(60), sourceTexture: makeSource(device, bgra: [0, 255, 0, 255]),
            sourceUniforms: .neutral(), sourcePipeline: sourcePipeline, frameInputs: .init(), commandBuffer: command,
            previousStates: [:], previousGraphResources: [:], effectGeneration: 1, resetGeneration: 1),
          peerExecutor.encode(peer, commandBuffer: command), let peerReadback = appendReadback(peer.finalTexture, commandBuffer: command)
    else { row["failure"] = "green-peer"; return row }
    command.commit()
    command.waitUntilCompleted()
    func rgba(_ bytes: [UInt8]) -> [Int] { [Int(bytes[2]), Int(bytes[1]), Int(bytes[0]), Int(bytes[3])] }
    row["prepared"] = true
    row["completed"] = command.status == .completed && command.error == nil
    row["pixel"] = rgba(readback.firstPixel)
    row["peer"] = rgba(peerReadback.firstPixel)
    row["failures"] = prepared.stages.map { $0.effectLocalFailureReasonCode ?? "" }
    row["backgroundRequired"] = capability.sceneBackgroundRequirement != nil
    return row
}
