private func runActivationCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    source: MTLTexture,
    activationGraphInput: () -> Graph,
    activationLeaseFactory: (Graph, Capabilities.LayerCapability, MTLDevice, UInt64) -> [SceneGraphRenderTargetLease]?
) throws -> (
    sourcePipeline: SceneImageLayerPipeline,
    results: [String: Bool]
) {
    // Preparation follows the layer's existing dynamic owner without
    // making the layer visible or granting script dependency privileges.
    let dormantTarget = SceneDynamicTarget.effectVisibility(layerID: 77, effectIndex: 0)
    let dormantLayerTarget = SceneDynamicTarget.layer(layerID: 77, field: .visibility)
    var dormantLayer = SceneRenderDescriptor.Layer(id: 77, effects: [
        .init(id: "dormant", file: "effects/probe/effect.json", visible: false, passes: [])
    ], visible: false)
    func dormantTargets(_ layer: SceneRenderDescriptor.Layer, owners: Set<SceneDynamicTarget>) -> Set<SceneDynamicTarget> {
        SceneDirectBoolEffectVisibilityRouteAdmission.startupInactiveTargets(
            in: .init(layers: [layer], materialPasses: [], effectDefinitions: []),
            candidates: [dormantTarget],
            dynamicLayerVisibilityOwnerTargets: owners
        )
    }
    let dormantPrepared = dormantTargets(dormantLayer, owners: [dormantLayerTarget]) == [dormantTarget]
    let unownedDormantRejected = dormantTargets(dormantLayer, owners: []).isEmpty
    let authoredVisibilityPreserved = !dormantLayer.visible
    dormantLayer.dependencyLayerIDs = [88]
    let dependencyDormantRejected = dormantTargets(dormantLayer, owners: [dormantLayerTarget]).isEmpty
    dormantLayer.dependencyLayerIDs = []
    dormantLayer.parentID = 88
    let childDormantRejected = dormantTargets(dormantLayer, owners: [dormantLayerTarget]).isEmpty
    dormantLayer.parentID = nil
    dormantLayer.utilityLayer = .init(kind: .fullscreen)
    let utilityDormantRejected = dormantTargets(dormantLayer, owners: [dormantLayerTarget]).isEmpty
    let sourcePipeline = makeSourcePipeline(device)
    let activationGraph = activationGraphInput()
    let activationChain = admittedGraph(activationGraph)
    let activationTarget = SceneDynamicTarget.effectVisibility(
        layerID: effect.layerID,
        effectIndex: effect.effectIndex
    )
    let activationCapabilities = capabilities(
        activationChain,
        catalog: catalog(for: activationGraph),
        dynamicProducers: .init(
            userProperties: [.init(
                propertyKey: "fixture-visible",
                target: activationTarget,
                valueType: .bool
            )],
            authoredFallbackTargets: [activationTarget],
            timelineTargets: [],
            sceneScriptTargets: []
        )
    )
    let activationClaim = activationCapabilities.claim(activationChain)
    let activationCapability = activationClaim.flatMap {
        activationCapabilities.resolve($0.token, for: activationChain)
    }
    let activationPolicyAttached = activationCapability?.stages.first?
        .execution.activationPolicy?.effectVisibilityTarget == activationTarget
        && activationCapabilities.liveConsumerTargets.contains(
            activationTarget
        )

    func executeActivation(
        visible: Bool,
        generation: UInt64
    ) -> (
        prepared: Bool,
        encoded: Bool,
        gpu: Bool,
        pixelsPreserved: Bool,
        fallbackFree: Bool
    ) {
        guard let claim = activationClaim,
              let capability = activationCapability,
              let leases = activationLeaseFactory(
                  activationGraph, capability, device, generation
              ), let executor = Executor(
                  device: device,
                  capabilities: activationCapabilities
              ), let command = queue.makeCommandBuffer() else {
            return (false, false, false, false, false)
        }
        let dynamic = SceneDynamicSnapshotResolver().resolve(
            frameIndex: generation,
            generation: generation,
            definitions: [.init(
                target: activationTarget,
                valueType: .bool,
                authoredValue: .bool(true)
            )],
            userValues: [activationTarget: .bool(visible)]
        ).snapshot
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(generation),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(dynamicValues: dynamic),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: generation,
            resetGeneration: generation
        )
        let reason = "effect-activation-visibility-disabled"
        guard case let .success(preparedGraph) = preparation,
              let stage = preparedGraph.stages.first else {
            return (false, false, false, false, false)
        }
        let prepared = visible
            ? stage.effectLocalActivationBypassReasonCode == nil
                && stage.effectLocalFailureReasonCode == nil
                && stage.programCacheKeys.allSatisfy {
                    !$0.hasPrefix("activation-passthrough:")
                }
            : stage.effectLocalActivationBypassReasonCode == reason
                && stage.effectLocalFailureReasonCode == nil
                && stage.programCacheKeys == [
                    "activation-passthrough:" + reason
                ]
        let encoded = executor.encode(
            preparedGraph,
            commandBuffer: command
        )
        guard encoded,
              let readback = appendReadback(
                  preparedGraph.finalTexture,
                  commandBuffer: command
              ) else {
            return (
                prepared,
                encoded,
                false,
                false,
                executor.effectLocalFallbackCounts.isEmpty
            )
        }
        command.commit()
        command.waitUntilCompleted()
        let gpu = command.status == .completed && command.error == nil
        return (
            prepared,
            encoded,
            gpu,
            gpu && matches(readback.firstPixel, [0, 0, 255, 255])
                && matches(readback.lastPixel, [0, 0, 255, 255]),
            executor.effectLocalFallbackCounts.isEmpty
        )
    }
    let inactiveActivation = executeActivation(
        visible: false,
        generation: 50
    )
    let activeActivation = executeActivation(
        visible: true,
        generation: 51
    )
    let precomputedActivationPreservesCopyAndSuffix: Bool = {
        let graph = chainedGraph()
        let chain = orderedLayerGraph(graph)
        let target = SceneDynamicTarget.effectVisibility(
            layerID: layerID, effectIndex: chainedSecondEffect.effectIndex)
        let caps = capabilities(chain, catalog: catalog(for: graph), dynamicProducers: .init(
            userProperties: [.init(propertyKey: "snapshot-visible", target: target, valueType: .bool)],
            authoredFallbackTargets: [target], timelineTargets: [], sceneScriptTargets: []))
        guard let claim = caps.claim(chain),
              let capability = caps.resolve(claim.token, for: chain),
              let leases = makeChainedLeases(capability, device: device, generation: 52),
              let executor = Executor(device: device, capabilities: caps),
              let command = queue.makeCommandBuffer() else { return false }
        let dynamic = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 52, generation: 52,
            definitions: [.init(target: target, valueType: .bool, authoredValue: .bool(true))],
            userValues: [target: .bool(false)]).snapshot
        var inputs = SceneResolvedMaterialRuntimeBridge.FrameInputs(dynamicValues: dynamic)
        let reason = "fixture-snapshot-inactive-decision"
        inputs.stageActivationDecisions[chainedSecondEffect] = .inactive(reasonCode: reason)
        let preparation = executor.prepare(
            token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
            frame: frame(52), sourceTexture: source, sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline, frameInputs: inputs, commandBuffer: command,
            previousStates: [:], previousGraphResources: [:], effectGeneration: 52, resetGeneration: 52)
        guard case let .success(prepared) = preparation,
              prepared.stages.map(\.effect) == [chainedFirstEffect, chainedSecondEffect, chainedThirdEffect],
              prepared.stages[1].effectLocalActivationBypassReasonCode == reason,
              prepared.stages[1].programCacheKeys == ["activation-passthrough:" + reason],
              prepared.stages.allSatisfy({ $0.effectLocalFailureReasonCode == nil }),
              prepared.stages[0].effectLocalActivationBypassReasonCode == nil,
              prepared.stages[2].effectLocalActivationBypassReasonCode == nil else { return false }
        var indices: [Int] = []
        var readbacks: [Readback] = []
        guard executor.encode(prepared, commandBuffer: command, stageBoundaryObserver: { index, transition, buffer in
            guard let readback = appendReadback(transition.effectOutputResource.publication.texture,
                                                commandBuffer: buffer) else { return false }
            indices.append(index)
            readbacks.append(readback)
            return true
        }), let final = appendReadback(prepared.finalTexture, commandBuffer: command) else { return false }
        command.commit()
        command.waitUntilCompleted()
        let expected: [[UInt8]] = [[255, 0, 0, 255], [255, 0, 0, 255], [0, 255, 0, 255]]
        return command.status == .completed && command.error == nil
            && indices == [0, 1, 2] && readbacks.count == 3
            && zip(readbacks, expected).allSatisfy {
                matches($0.firstPixel, $1) && matches($0.lastPixel, $1)
            }
            && matches(final.firstPixel, expected[2]) && matches(final.lastPixel, expected[2])
            && executor.effectLocalFallbackCounts.isEmpty
    }()

    // D2a: the media-toggle shape - a script-gated initially-inactive
    // effect on an externalPrimary dependency consumer. The forced
    // marking simulates the frozen D2b route carve-out (the current
    // route filter rejects dependency-consumer targets). The stage
    // consumes the provider texture through slot 1, so dependency
    // finalization must match the externalPrimary binding exactly.
    let dependencyActivationGraph = graph(
        targets: [],
        nodes: [material(0, ordinal: 0, target: output, read: input)]
    )
    let dependencyActivationChain = admittedGraph(dependencyActivationGraph)
    let dependencyActivationTarget = SceneDynamicTarget.effectVisibility(
        layerID: effect.layerID,
        effectIndex: effect.effectIndex
    )
    let dependencyNamedReference = SceneNamedTextureReference(
        providerLayerID: 879,
        variant: .primary
    )
    let dependencyExternalBinding = SceneDependencyRenderPlan.Binding(
        consumerLayerID: layerID,
        providerLayerID: dependencyNamedReference.providerLayerID,
        slot: .init(
            effectID: effect.descriptorID,
            passIndex: 0,
            slotIndex: 1
        ),
        blendMode: 0,
        kind: .resolvedMaterial
    )
    let dependencyActivationCapabilities = capabilities(
        dependencyActivationChain,
        catalog: catalog(
            for: dependencyActivationGraph,
            namedProvidersByNode: [0: dependencyNamedReference]
        ),
        dynamicProducers: .init(
            userProperties: [],
            authoredFallbackTargets: [],
            timelineTargets: [],
            sceneScriptTargets: [dependencyActivationTarget]
        ),
        namedProvider: dependencyNamedReference,
        dependencyBinding: dependencyExternalBinding,
        forcedInitiallyInactiveEffectKeys: [effect]
    )
    let dependencyActivationClaim = dependencyActivationCapabilities
        .claim(dependencyActivationChain)
    let dependencyActivationCapability = dependencyActivationClaim
        .flatMap {
            dependencyActivationCapabilities.resolve(
                $0.token,
                for: dependencyActivationChain
            )
        }
    let dependencyActivationFinalized = {
        guard let capability = dependencyActivationCapability,
              case let .externalPrimary(binding) =
                capability.dependencyOwnership else { return false }
        return binding == dependencyExternalBinding
            && capability.stages.first?.execution.activationPolicy?
                .effectVisibilityTarget == dependencyActivationTarget
    }()

    // Per-frame on the dependency consumer: the D1 seed (authored
    // hidden) evaluates inactive and publishes previous-current without
    // sampling the provider slot; the sceneScript lane overrides to
    // active and the program continues.
    // Only the inactive frame is exercised here: it is the permanent
    // no-producer steady state and needs no provider publication. The
    // active frame on a dependency consumer additionally samples the
    // provider publication (renderer-layer machinery, D3).
    func executeInactiveDependencyActivation(
        generation: UInt64
    ) -> (
        prepared: Bool,
        encoded: Bool,
        gpu: Bool,
        pixelsPreserved: Bool,
        fallbackFree: Bool
    ) {
        guard let claim = dependencyActivationClaim,
              let capability = dependencyActivationCapability,
              let leases = makeChainedLeases(
                  capability,
                  device: device,
                  generation: generation
              ), let executor = Executor(
                  device: device,
                  capabilities: dependencyActivationCapabilities
              ), let command = queue.makeCommandBuffer() else {
            return (false, false, false, false, false)
        }
        // D1 seed semantics: the authored definition carries the
        // prepared hidden seed and no sceneScript value is staged.
        let dynamic = SceneDynamicSnapshotResolver().resolve(
            frameIndex: generation,
            generation: generation,
            definitions: [.init(
                target: dependencyActivationTarget,
                valueType: .bool,
                authoredValue: .bool(false)
            )]
        ).snapshot
        let preparation = executor.prepare(
            token: claim.token,
            leases: leases,
            historyRehydrateCopiesByEffect: [:],
            frame: frame(generation),
            sourceTexture: source,
            sourceUniforms: .neutral(),
            sourcePipeline: sourcePipeline,
            frameInputs: .init(dynamicValues: dynamic),
            commandBuffer: command,
            previousStates: [:],
            previousGraphResources: [:],
            effectGeneration: generation,
            resetGeneration: generation
        )
        let reason = "effect-activation-visibility-disabled"
        guard case let .success(preparedGraph) = preparation,
              let stage = preparedGraph.stages.first else {
            return (false, false, false, false, false)
        }
        let prepared = stage.effectLocalActivationBypassReasonCode == reason
            && stage.effectLocalFailureReasonCode == nil
            && stage.programCacheKeys == [
                "activation-passthrough:" + reason
            ]
        let encoded = executor.encode(
            preparedGraph,
            commandBuffer: command
        )
        guard encoded,
              let readback = appendReadback(
                  preparedGraph.finalTexture,
                  commandBuffer: command
              ) else {
            return (
                prepared,
                encoded,
                false,
                false,
                executor.effectLocalFallbackCounts.isEmpty
            )
        }
        command.commit()
        command.waitUntilCompleted()
        let gpu = command.status == .completed && command.error == nil
        return (
            prepared,
            encoded,
            gpu,
            gpu && matches(readback.firstPixel, [0, 0, 255, 255])
                && matches(readback.lastPixel, [0, 0, 255, 255]),
            executor.effectLocalFallbackCounts.isEmpty
        )
    }
    let inactiveDependencyActivation = executeInactiveDependencyActivation(
        generation: 60
    )

    // Without a visibility producer the initially-inactive stage retains its
    // source; no compiled Program or external named demand may survive it.
    let dependencyNoProducerCapabilities = capabilities(
        dependencyActivationChain,
        catalog: catalog(
            for: dependencyActivationGraph,
            namedProvidersByNode: [0: dependencyNamedReference]
        ),
        namedProvider: dependencyNamedReference,
        dependencyBinding: dependencyExternalBinding,
        forcedInitiallyInactiveEffectKeys: [effect]
    )
    let dependencyNoProducerClaim = dependencyNoProducerCapabilities
        .claim(dependencyActivationChain)
    let dependencyNoProducerCapability = dependencyNoProducerClaim
        .flatMap {
            dependencyNoProducerCapabilities.resolve(
                $0.token,
                for: dependencyActivationChain
            )
        }
    let unproducedNamedSlotConsumerStaysInactiveWithoutDemand = {
        guard let capability = dependencyNoProducerCapability,
              capability.stages.count == 1,
              case .initiallyInactivePassthrough = capability.stages[0].execution else { return false }
        return capability.materials.isEmpty
            && dependencyNoProducerCapabilities.preparedNamedInputBindingsByConsumerLayerID[layerID] == []
    }()

    // 反门 (downgrade viability): the real corpus shape - an ACTIVE
    // sibling effect carries the externalPrimary binding while the
    // script-gated initially-inactive sibling (input-only) downgrades
    // to a passthrough. Finalize stays satisfied through the active
    // sibling's named dependency.
    let downgradeSiblingGraph = Graph(
        layerID: layerID,
        effects: [
            .init(
                key: chainedFirstEffect,
                definitionPath:
                    "effects/pixel-admittedGraph-first/effect.json",
                input: input,
                output: chainedFirstOutput,
                nodeIndices: [0]
            ),
            .init(
                key: chainedSecondEffect,
                definitionPath:
                    "effects/pixel-admittedGraph-second/effect.json",
                input: chainedFirstOutput,
                output: chainedSecondOutput,
                nodeIndices: [1]
            ),
        ],
        renderTargets: [],
        nodes: [
            material(
                0,
                ordinal: 0,
                target: chainedFirstOutput,
                read: input,
                owner: chainedFirstEffect
            ),
            material(
                1,
                ordinal: 0,
                target: chainedSecondOutput,
                read: chainedFirstOutput,
                owner: chainedSecondEffect
            ),
        ],
        finalOutput: chainedSecondOutput,
        blockers: []
    )
    // Driven directly at the stage pipeline: the current route
    // admission cannot express the D2b marking on a dependency consumer
    // (conservation rejects it before preparation), so this fixture
    // constructs the admitted layer with the marking the carve-out will
    // produce and runs compileProgramFirstStages itself.
    // The slot's effectID must name the node's owner effect for the
    // resolved dependency to match the binding exactly.
    let downgradeSiblingBinding = SceneDependencyRenderPlan.Binding(
        consumerLayerID: layerID,
        providerLayerID: dependencyNamedReference.providerLayerID,
        slot: .init(
            effectID: chainedFirstEffect.descriptorID,
            passIndex: 0,
            slotIndex: 1
        ),
        blendMode: 0,
        kind: .resolvedMaterial
    )
    let downgradeSiblingDescriptor = SceneRenderDescriptor(
        layers: [
            .init(
                id: layerID,
                effects: [
                    .init(
                        id: chainedFirstEffect.descriptorID,
                        file: "effects/pixel-admittedGraph-first/effect.json",
                        visible: true,
                        passes: [.init(passIndex: 0, combos: [:])]
                    ),
                    .init(
                        id: chainedSecondEffect.descriptorID,
                        file: "effects/pixel-admittedGraph-second/effect.json",
                        visible: false,
                        passes: [.init(passIndex: 0, combos: [:])]
                    ),
                ]
            ),
            .init(
                id: dependencyNamedReference.providerLayerID,
                effects: []
            ),
        ],
        materialPasses: downgradeSiblingGraph.nodes.compactMap { node in
            node.materialPath.map {
                SceneRenderDescriptor.MaterialPassDescriptor(
                    id: node.materialPassID!,
                    materialPath: $0,
                    combos: [:]
                )
            }
        },
        effectDefinitions: downgradeSiblingGraph.effects.map {
            .init(relativePath: $0.definitionPath, functions: nil)
        }
    )
    var downgradeProducts: [SceneGraphAdmissionProduct] = []
    var downgradeProductsValid = true
    for effect in downgradeSiblingGraph.effects {
        let stage = Graph(
            layerID: downgradeSiblingGraph.layerID,
            effects: [effect],
            renderTargets: downgradeSiblingGraph.renderTargets.filter {
                $0.texture.effect == effect.key
            },
            nodes: downgradeSiblingGraph.nodes.filter {
                effect.nodeIndices.contains($0.nodeIndex)
            },
            finalOutput: effect.output,
            blockers: []
        )
        switch SceneGraphAdmissionCompiler.compile(
            graph: stage,
            descriptor: downgradeSiblingDescriptor,
            functions: nil
        ) {
        case let .success(product): downgradeProducts.append(product)
        case .failure: downgradeProductsValid = false
        }
    }
    var downgradeAdmitted: SceneResolvedMaterialAdmittedLayer?
    if downgradeProductsValid,
       downgradeProducts.count == downgradeSiblingGraph.effects.count,
       case let .success(pair) = SceneLayerFullFramePairPlan.make(
           conditionPrunedGraphs: downgradeProducts.map(\.graph)
       ) {
        downgradeAdmitted = SceneResolvedMaterialAdmittedLayer(
            layerID: layerID,
            products: downgradeProducts,
            pairPlan: pair,
            dependencyOwnership: .externalPrimary(downgradeSiblingBinding),
            initiallyInactiveEffectKeys: [chainedSecondEffect],
            sourceRoute: .capturedLayerTexture,
            isVisibleExecutionRoot: true,
            isGraphOutputProvider: false
        )
    }
    let downgradeStageResult = try downgradeAdmitted.map {
        try SceneResolvedMaterialExecutionCapabilityCatalog
            .compileProgramFirstStages(
                $0,
                materialCatalog: catalog(
                    for: downgradeSiblingGraph,
                    namedProvidersByNode: [0: dependencyNamedReference]
                ),
                demandIssues: [],
                dynamicProducers: .empty,
                assetFormatFacts: [:],
                assetStates: [:],
                maximumVariantsPerMaterial: 16
            )
    }
    let parallelDowngradeStageResult = try downgradeAdmitted.map {
        try SceneResolvedMaterialExecutionCapabilityCatalog
            .compileProgramFirstStages(
                $0,
                materialCatalog: catalog(
                    for: downgradeSiblingGraph,
                    namedProvidersByNode: [0: dependencyNamedReference]
                ),
                demandIssues: [],
                dynamicProducers: .empty,
                assetFormatFacts: [:],
                assetStates: [:],
                maximumVariantsPerMaterial: 16,
                maximumStageWorkers: 2
            )
    }
    let parallelStagePreparationPreservesAuthoredResult = {
        guard let serial = downgradeStageResult,
              let parallel = parallelDowngradeStageResult,
              case let .success(a) = serial,
              case let .success(b) = parallel else { return false }
        return a.stages.map { $0.product.graph.effects.first?.key }
                == b.stages.map { $0.product.graph.effects.first?.key }
            && a.stages.map(\.execution.initiallyInactivePassthroughReasonCode)
                == b.stages.map(\.execution.initiallyInactivePassthroughReasonCode)
            && a.stages.map(\.execution.visualFailureReasonCode)
                == b.stages.map(\.execution.visualFailureReasonCode)
            && Set(a.materials.keys) == Set(b.materials.keys)
            && a.dependencyOwnership == b.dependencyOwnership
    }()
    let downgradeWithActiveSiblingResolvesPassthrough = {
        guard let result = downgradeStageResult,
              case let .success(compiled) = result,
              compiled.stages.count == 2,
              let first = compiled.stages.first,
              let last = compiled.stages.last,
              first.product.graph.effects.first != nil,
              last.product.graph.effects.first != nil,
              case .resolved = first.execution,
              case .initiallyInactivePassthrough = last.execution else {
            return false
        }
        return compiled.dependencyOwnership
            == .externalPrimary(downgradeSiblingBinding)
    }()

    // The script target remains correct; only the cold named carrier differs
    // from the selected provider. Its inactive fallback cannot acquire a Program.
    let mismatchedScriptStageCapabilities = capabilities(
        dependencyActivationChain,
        catalog: catalog(
            for: dependencyActivationGraph,
            namedProvidersByNode: [0: SceneNamedTextureReference(
                providerLayerID: 880,
                variant: .primary
            )]
        ),
        dynamicProducers: .init(
            userProperties: [],
            authoredFallbackTargets: [],
            timelineTargets: [],
            sceneScriptTargets: [dependencyActivationTarget]
        ),
        namedProvider: dependencyNamedReference,
        dependencyBinding: dependencyExternalBinding,
        forcedInitiallyInactiveEffectKeys: [effect]
    )
    let mismatchedScriptStageClaim = mismatchedScriptStageCapabilities
        .claim(dependencyActivationChain)
    let mismatchedScriptStageCapability = mismatchedScriptStageClaim
        .flatMap {
            mismatchedScriptStageCapabilities.resolve(
                $0.token,
                for: dependencyActivationChain
            )
        }
    let inactiveWrongProviderCarrierHasNoProgramOrNamedDemand = {
        guard let capability = mismatchedScriptStageCapability,
              capability.stages.count == 1,
              case .initiallyInactivePassthrough = capability.stages[0].execution else { return false }
        return capability.materials.isEmpty
            && mismatchedScriptStageCapabilities.preparedNamedInputBindingsByConsumerLayerID[layerID] == []
    }()

    // Coverage gap (recorded): the passthrough predicate's
    // `.unresolved` slot-binding disjunct is not reachable from a
    // standalone fixture - the pair planner rejects an unresolved
    // binding before the predicate runs - and no harness path drives a
    // compiled product through it. The corpus/replay layer is the only
    // would-be coverage owner until a dedicated fixture exists.
    let results: [String: Bool] = [
        "dormantLayerEffectPrepared": dormantPrepared,
        "unownedDormantLayerStillRejected": unownedDormantRejected,
        "preparationPreservesAuthoredVisibility": authoredVisibilityPreserved,
        "dormantDependencyStillRejected": dependencyDormantRejected,
        "dormantChildStillRejected": childDormantRejected,
        "dormantUtilityStillRejected": utilityDormantRejected,
        "activationPolicyAttachedToResolvedStage":
            activationPolicyAttached,
        "inactiveActivationPublishesPreviousCurrent":
            inactiveActivation.prepared
                && inactiveActivation.encoded
                && inactiveActivation.gpu
                && inactiveActivation.pixelsPreserved,
        "inactiveActivationIsNotVisualFallback":
            inactiveActivation.fallbackFree,
        "activeActivationContinuesThroughProgram":
            activeActivation.prepared
                && activeActivation.encoded
                && activeActivation.gpu
                && activeActivation.pixelsPreserved
                && activeActivation.fallbackFree,
        "precomputedActivationDecisionPreservesCopyAndHealthySuffix":
            precomputedActivationPreservesCopyAndSuffix,
        "dependencyActivationStageCompileAndFinalizeClose":
            dependencyActivationFinalized,
        "inactiveDependencyActivationPublishesPreviousCurrent":
            dependencyActivationFinalized
                && inactiveDependencyActivation.prepared
                && inactiveDependencyActivation.encoded
                && inactiveDependencyActivation.gpu
                && inactiveDependencyActivation.pixelsPreserved
                && inactiveDependencyActivation.fallbackFree,
        "unproducedNamedSlotConsumerStaysInactiveWithoutDemand":
            unproducedNamedSlotConsumerStaysInactiveWithoutDemand,
        "parallelStagePreparationPreservesAuthoredResult":
            parallelStagePreparationPreservesAuthoredResult,
        "downgradeWithActiveSiblingResolvesPassthrough":
            downgradeWithActiveSiblingResolvesPassthrough,
        "inactiveWrongProviderCarrierHasNoProgramOrNamedDemand":
            inactiveWrongProviderCarrierHasNoProgramOrNamedDemand,
    ]
    return (
        sourcePipeline,
        results
    )
}
