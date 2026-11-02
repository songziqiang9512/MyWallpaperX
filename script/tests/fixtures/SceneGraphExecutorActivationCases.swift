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

    // 反门 (documented fail-closed): the same consumer shape with NO
    // sceneScript producer - the activation policy fails to construct
    // and the initially-inactive stage must downgrade, but a
    // named-consuming leaf stage does not satisfy the passthrough
    // topology (only effect-input or .unresolved bindings do), so the
    // whole layer fails closed. This is the recorded D2b constraint:
    // the carve-out must guarantee the policy constructs.
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
    // The observable rejection code is execution-stage-conservation:
    // the passthrough-unsafe stage is omitted first, and the stage-count
    // guard masks the inner code. Both mean the same fail-closed layer.
    let unproducedNamedSlotConsumerFailsClosed =
        dependencyNoProducerCapability == nil
        && dependencyNoProducerCapabilities.reportLines.contains {
            $0.contains("execution-stage-conservation")
        }

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
            isGraphOutputProvider: false,
            requiresGraphOutputProvider: false
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

    // Registered boundary (review P2-1): a script-gated stage whose
    // resolved named dependency points at a provider OUTSIDE the
    // layer's externalPrimary binding fails the pre-proof, and the
    // downgrade is rejected by the passthrough topology (the stage's
    // bindings carry a named texture, which the leaf branch does not
    // accept) - the whole layer fails closed. The corpus does not
    // contain this shape; this fixture pins the fail-closed behavior.
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
    let mismatchedScriptStageFailsClosed =
        mismatchedScriptStageCapability == nil

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
        "dependencyActivationStageCompileAndFinalizeClose":
            dependencyActivationFinalized,
        "inactiveDependencyActivationPublishesPreviousCurrent":
            dependencyActivationFinalized
                && inactiveDependencyActivation.prepared
                && inactiveDependencyActivation.encoded
                && inactiveDependencyActivation.gpu
                && inactiveDependencyActivation.pixelsPreserved
                && inactiveDependencyActivation.fallbackFree,
        "unproducedNamedSlotConsumerFailsClosed":
            unproducedNamedSlotConsumerFailsClosed,
        "parallelStagePreparationPreservesAuthoredResult":
            parallelStagePreparationPreservesAuthoredResult,
        "downgradeWithActiveSiblingResolvesPassthrough":
            downgradeWithActiveSiblingResolvesPassthrough,
        "mismatchedScriptStageFailsClosed":
            mismatchedScriptStageFailsClosed,
    ]
    return (
        sourcePipeline,
        results
    )
}
