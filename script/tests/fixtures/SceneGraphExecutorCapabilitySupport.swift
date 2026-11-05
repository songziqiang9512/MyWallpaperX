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
    startupInactiveTargets: Set<SceneDynamicTarget> = [],
    descriptorOverride: SceneRenderDescriptor? = nil
) -> Capabilities {
    let graph = admittedGraph.renderGraph
    let materialNodes = graph.nodes.filter { $0.kind == .material }
        .sorted { ($0.materialOrdinal ?? -1) < ($1.materialOrdinal ?? -1) }
    let instancePasses = Dictionary(grouping: materialNodes, by: \.effect)
        .mapValues { nodes in
            nodes.compactMap { node -> SceneRenderDescriptor.PassDescriptor? in
                guard let passIndex = node.instancePassIndex else { return nil }
                return SceneRenderDescriptor.PassDescriptor(
                    passIndex: passIndex,
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
                    visible: !startupInactiveTargets.contains(.effectVisibility(
                        layerID: $0.key.layerID, effectIndex: $0.key.effectIndex)),
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
    let descriptor = descriptorOverride ?? SceneRenderDescriptor(
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
    let candidates = SceneResolvedMaterialExecutionCapabilityAdmission.compile(
        descriptor: descriptor,
        authoredPlans: [graph],
        dynamicEffectVisibilityOwners: dynamicEffectVisibilityOwners,
        startupInactiveEffectVisibilityTargets: startupInactiveTargets
    )
    for candidate in candidates {
        if case let .failure(failure) = candidate.result {
            debugLastCandidateFailureCode = failure.code
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
