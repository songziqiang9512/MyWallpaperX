private func failureCode(
    _ result: Result<Executor.PreparedGraph, Executor.Failure>
) -> String {
    switch result {
    case .success: "success"
    case let .failure(failure): failure.rawValue
    }
}

private func launchEnvelopeFailureCode(
    _ result: Result<[UInt8], SceneResolvedMaterialVariantCache.LaunchEnvelopeFailure>
) -> String {
    switch result {
    case .success: return "success"
    case .failure(.capacity): return "capacity"
    case let .failure(.material(failure)):
        return "\(failure.phase.rawValue):\(failure.code.rawValue):\(failure.boundedDetails.joined(separator: ","))"
    }
}

private func intentKinds(
    _ admittedGraph: Executor.PreparedGraph
) -> [String] {
    admittedGraph.stages.flatMap { value in
        value.transition.transaction.intents.map { intent in
            switch intent {
            case .initialize: "initialize"
            case .material: "material"
            case .copy: "copy"
            case .swap: "swap"
            }
        }
    }
}

private func capabilities(
    _ admittedGraph: AdmittedLayerGraph,
    catalog: SceneResolvedMaterialRuntimeCatalog,
    dynamicProducers: Capabilities.DynamicProducerCatalog = .empty,
    namedProvider: SceneNamedTextureReference? = nil,
    dependencyBinding: SceneDependencyRenderPlan.Binding? = nil,
    potentialOptionalNamedFallback: Bool = false,
    additionalPotentialNamedReferences: [
        SceneDependencyRenderPlan.Reference
    ] = [],
    additionalPotentialDependencyBindings: [
        SceneDependencyRenderPlan.Binding
    ] = [],
    additionalNamedProvider: SceneNamedTextureReference? = nil,
    additionalDependencyBinding: SceneDependencyRenderPlan.Binding? = nil,
    forwardUnavailableReference: SceneDependencyRenderPlan.Reference? = nil,
    secondarySelfUnavailableReference:
        SceneDependencyRenderPlan.Reference? = nil,
    backwardUnsupportedReference: SceneDependencyRenderPlan.Reference? = nil,
    dynamicEffectVisibilityOwners: Set<
        SceneResolvedMaterialExecutionCapabilityAdmission.DynamicEffectVisibilityOwner
    > = [],
    functionsByEffect: [Graph.EffectKey: SceneJSONValue] = [:],
    assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:],
    assetFormatFacts: [String: Int] = [:],
    capturedMainTarget: Bool = false,
    contentKind: String = "image",
    parentID: Int? = nil,
    terminalReplayBlendMode: Int = 0,
    forcedInitiallyInactiveEffectKeys: Set<Graph.EffectKey> = []
) -> Capabilities {
    let graph = admittedGraph.renderGraph
    let materialNodes = graph.nodes.filter { $0.kind == .material }
        .sorted { ($0.materialOrdinal ?? -1) < ($1.materialOrdinal ?? -1) }
    let instancePasses = Dictionary(grouping: materialNodes, by: \.effect)
        .mapValues { nodes in
            nodes.map {
                SceneRenderDescriptor.PassDescriptor(
                    passIndex: $0.instancePassIndex!,
                    combos: [:]
                )
            }
        }
    let materialPasses = materialNodes.map {
        SceneRenderDescriptor.MaterialPassDescriptor(
            id: $0.materialPassID!,
            materialPath: $0.materialPath!,
            combos: [:]
        )
    }
    var consumer = SceneRenderDescriptor.Layer(
            id: graph.layerID,
            effects: graph.effects.map {
                .init(
                    id: $0.key.descriptorID,
                    file: $0.definitionPath,
                    visible: true,
                    passes: instancePasses[$0.key] ?? []
                )
            }
        )
    if capturedMainTarget { consumer.utilityLayer = .init(kind: .fullscreen) }
    consumer.contentKind = contentKind
    consumer.parentID = parentID
    consumer.colorBlendMode = terminalReplayBlendMode
    var layers: [SceneRenderDescriptor.Layer] = [consumer]
    if let namedProvider, let dependencyBinding {
        consumer.dependencyLayerIDs = [dependencyBinding.providerLayerID]
        let reference = SceneDependencyRenderPlan.Reference(
            consumerLayerID: graph.layerID,
            providerLayerID: namedProvider.providerLayerID,
            slot: dependencyBinding.slot,
            variant: namedProvider.variant
        )
        if potentialOptionalNamedFallback {
            consumer.potentialNamedReferences = [reference]
            consumer.potentialNamedBindings = [dependencyBinding]
        } else {
            consumer.namedReferences = [reference]
            consumer.namedBindings = [dependencyBinding]
        }
        consumer.potentialNamedReferences.append(
            contentsOf: additionalPotentialNamedReferences
        )
        consumer.potentialNamedBindings.append(
            contentsOf: additionalPotentialDependencyBindings
        )
        var providerLayerIDs: Set<Int> = [dependencyBinding.providerLayerID]
        providerLayerIDs.formUnion(
            additionalPotentialDependencyBindings.map(\.providerLayerID)
        )
        consumer.dependencyLayerIDs = Array(providerLayerIDs).sorted()
        if let additionalNamedProvider,
           let additionalDependencyBinding {
            consumer.dependencyLayerIDs.append(
                additionalDependencyBinding.providerLayerID
            )
            consumer.namedReferences.append(.init(
                consumerLayerID: graph.layerID,
                providerLayerID: additionalNamedProvider.providerLayerID,
                slot: additionalDependencyBinding.slot,
                variant: additionalNamedProvider.variant
            ))
            consumer.namedBindings.append(additionalDependencyBinding)
            providerLayerIDs.insert(additionalDependencyBinding.providerLayerID)
        }
        layers = providerLayerIDs.sorted().map {
            .init(id: $0, effects: [])
        } + [consumer]
    } else if let secondarySelfUnavailableReference {
        consumer.namedReferences = [secondarySelfUnavailableReference]
        layers = [consumer]
    } else if let forwardUnavailableReference {
        consumer.dependencyLayerIDs = [
            forwardUnavailableReference.providerLayerID
        ]
        consumer.namedReferences = [forwardUnavailableReference]
        layers = [
            consumer,
            .init(
                id: forwardUnavailableReference.providerLayerID,
                effects: []
            ),
        ]
    } else if let backwardUnsupportedReference {
        // The provider precedes the consumer, so the forward contract does
        // not apply; no binding shape exists either, leaving only the
        // effect-local unsupported-reference passthrough.
        consumer.dependencyLayerIDs = [
            backwardUnsupportedReference.providerLayerID
        ]
        consumer.namedReferences = [backwardUnsupportedReference]
        layers = [
            .init(
                id: backwardUnsupportedReference.providerLayerID,
                effects: []
            ),
            consumer,
        ]
    }
    let descriptor = SceneRenderDescriptor(
        layers: parentID.map { id in
            var parent = SceneRenderDescriptor.Layer(id: id, effects: [])
            parent.childLayerIDs = [consumer.id]
            return [parent] + layers
        } ?? layers,
        materialPasses: materialPasses,
        effectDefinitions: graph.effects.map {
            .init(
                relativePath: $0.definitionPath,
                functions: functionsByEffect[$0.key]
            )
        }
    )
    var candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor,
        authoredPlans: [graph],
        dynamicEffectVisibilityOwners: dynamicEffectVisibilityOwners
    )
    for candidate in candidates {
        if case let .failure(failure) = candidate.result {
            debugLastCandidateFailureCode = failure.code
        }
    }
    if !forcedInitiallyInactiveEffectKeys.isEmpty {
        // D2a seam: simulates the frozen D2b route-admission carve-out, which
        // will mark script-gated initially-inactive effects on dependency
        // consumers that the current route filter still rejects.
        candidates = candidates.map { candidate in
            guard case let .success(admitted) = candidate.result else {
                return candidate
            }
            let marked = SceneResolvedMaterialAdmittedLayer(
                layerID: admitted.layerID,
                products: admitted.products,
                pairPlan: admitted.pairPlan,
                dependencyOwnership: admitted.dependencyOwnership,
                potentialExternalPrimaryBindings:
                    admitted.potentialExternalPrimaryBindings,
                unavailableDependencyStageReasons:
                    admitted.unavailableDependencyStageReasons,
                initiallyInactiveEffectKeys:
                    admitted.initiallyInactiveEffectKeys
                    .union(forcedInitiallyInactiveEffectKeys),
                sourceRoute: admitted.sourceRoute,
                isTopLevelTextSource: admitted.isTopLevelTextSource,
                isVisibleExecutionRoot: admitted.isVisibleExecutionRoot,
                isGraphOutputProvider: admitted.isGraphOutputProvider,
                requiresGraphOutputProvider: admitted.requiresGraphOutputProvider,
                terminalReplayBlendMode: admitted.terminalReplayBlendMode
            )
            return .init(layerID: candidate.layerID, result: .success(marked))
        }
    }
    return try! .init(
        admissionCandidates: candidates,
        materialCatalog: catalog,
        dynamicProducers: dynamicProducers,
        assetFormatFacts: assetFormatFacts,
        assetStates: assetStates
    )
}

private func mixedForwardUnavailableEffectKeys(
    graph: Graph,
    secondaryReference: SceneDependencyRenderPlan.Reference
) -> Set<Graph.EffectKey>? {
    let providerLayerID = layerID + 1
    var consumer = SceneRenderDescriptor.Layer(
        id: layerID,
        effects: graph.effects.map { effect in
            .init(
                id: effect.key.descriptorID,
                file: effect.definitionPath,
                visible: true,
                passes: [.init(passIndex: 0, combos: [:])]
            )
        }
    )
    consumer.dependencyLayerIDs = [providerLayerID]
    let provider = SceneRenderDescriptor.Layer(id: providerLayerID, effects: [])
    let descriptor = SceneRenderDescriptor(
        layers: [consumer, provider],
        materialPasses: [],
        effectDefinitions: []
    )
    let forwardReference = SceneDependencyRenderPlan.Reference(
        consumerLayerID: layerID,
        providerLayerID: providerLayerID,
        slot: .init(
            effectID: chainedSecondEffect.descriptorID,
            passIndex: 0,
            slotIndex: 0
        ),
        variant: .primary
    )
    return SceneResolvedMaterialDependencyOwnershipCompiler
        .forwardUnavailableEffectKeys(
            layer: consumer,
            graph: graph,
            descriptor: descriptor,
            references: [forwardReference, secondaryReference],
            binding: nil
        )
}

private func unsupportedReferenceEffectKeys(
    graph: Graph,
    referenceEffect: Graph.EffectKey,
    providerLayerID: Int,
    slotIndex: Int = 0
) -> Set<Graph.EffectKey>? {
    var consumer = SceneRenderDescriptor.Layer(
        id: layerID,
        effects: graph.effects.map { effect in
            .init(
                id: effect.key.descriptorID,
                file: effect.definitionPath,
                visible: true,
                passes: [.init(passIndex: 0, combos: [:])]
            )
        }
    )
    consumer.dependencyLayerIDs = providerLayerID == layerID ? [] : [providerLayerID]
    let reference = SceneDependencyRenderPlan.Reference(
        consumerLayerID: layerID,
        providerLayerID: providerLayerID,
        slot: .init(
            effectID: referenceEffect.descriptorID,
            passIndex: 0,
            slotIndex: slotIndex
        ),
        variant: .primary
    )
    return SceneResolvedMaterialDependencyOwnershipCompiler
        .unsupportedReferenceEffectKeys(
            layer: consumer,
            graph: graph,
            references: [reference],
            binding: nil
        )
}

private func compilerCounts(
    _ capability: Capabilities.LayerCapability
) -> (shader: Int, frontend: Int) {
    capability.materials.values.reduce(into: (0, 0)) { result, material in
        let counters = material.variants.counters
        result.0 += counters.shaderPreparationCount
        result.1 += counters.frontendCompilationCount
    }
}

private struct CrossLayerRejectedPreparation {
    let failureCode: String
    let previousCurrentPreserved: Bool
    let safeSuffixCompleted: Bool
}

private func rejectedCrossLayerPreparation(
    device: MTLDevice,
    queue: MTLCommandQueue,
    sourcePipeline: SceneImageLayerPipeline,
    admittedGraph: AdmittedLayerGraph,
    capabilities: Capabilities,
    dependency: SceneDependencyEffectInput?
) -> CrossLayerRejectedPreparation {
    guard let claim = capabilities.claim(admittedGraph),
          let capability = capabilities.resolve(claim.token, for: admittedGraph),
          let leases = makeChainedLeases(capability, device: device, generation: 61),
          let firstStep = capability.pairPlan.effects.first,
          let executor = Executor(device: device, capabilities: capabilities),
          let command = queue.makeCommandBuffer() else {
        return .init(
            failureCode: "setup",
            previousCurrentPreserved: false,
            safeSuffixCompleted: false
        )
    }
    let previousCurrent = executor.pairTexture(
        lease: leases[0],
        member: firstStep.inputMember
    )
    guard fill(
        previousCurrent,
        color: MTLClearColorMake(0, 0, 1, 1),
        queue: queue
    ) else {
        return .init(
            failureCode: "fill",
            previousCurrentPreserved: false,
            safeSuffixCompleted: false
        )
    }
    let preparation = executor.prepare(
        token: claim.token,
        leases: leases,
        historyRehydrateCopiesByEffect: [:],
        frame: frame(60),
        sourceTexture: makeSource(device, width: 2, height: 2),
        sourceUniforms: .neutral(),
        sourcePipeline: sourcePipeline,
        frameInputs: .init(
            dependencyEffects: dependency.map { [$0] } ?? []
        ),
        commandBuffer: command,
        previousStates: [:],
        previousGraphResources: [:],
        effectGeneration: 1,
        resetGeneration: 1
    )
    guard case .failure = preparation,
          let readback = appendReadback(previousCurrent, commandBuffer: command) else {
        return .init(
            failureCode: failureCode(preparation),
            previousCurrentPreserved: false,
            safeSuffixCompleted: false
        )
    }
    command.commit()
    command.waitUntilCompleted()
    let completed = command.status == .completed && command.error == nil
    return .init(
        failureCode: failureCode(preparation),
        previousCurrentPreserved: completed
            && readback.firstPixel == [255, 0, 0, 255],
        safeSuffixCompleted: completed
    )
}
