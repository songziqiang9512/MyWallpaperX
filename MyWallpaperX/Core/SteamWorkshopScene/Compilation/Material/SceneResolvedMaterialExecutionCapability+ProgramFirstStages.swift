import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias MaterialKey = SceneResolvedMaterialRuntimeCatalog.Key
    typealias Template = SceneResolvedMaterialTemplate
    typealias ExactEffectSubject = SceneEffectExactRuntimeSubject

    struct DynamicProducerCatalog {
        typealias UserProperty = SceneDynamicUserPropertyProducer

        let userProperties: Set<UserProperty>
        private(set) var authoredFallbackTargets: Set<SceneDynamicTarget> = []
        let timelineDefinitions: Set<SceneDynamicTargetDefinition>
        private let legacyTimelineTargets: Set<SceneDynamicTarget>
        let sceneScriptTargets: Set<SceneDynamicTarget>

        var timelineTargets: Set<SceneDynamicTarget> {
            timelineDefinitions.isEmpty
                ? legacyTimelineTargets
                : Set(timelineDefinitions.map(\.target))
        }

        init(
            userProperties: Set<UserProperty>,
            authoredFallbackTargets: Set<SceneDynamicTarget> = [],
            timelineTargets: Set<SceneDynamicTarget> = [],
            timelineDefinitions: Set<SceneDynamicTargetDefinition> = [],
            sceneScriptTargets: Set<SceneDynamicTarget>
        ) {
            self.userProperties = userProperties
            self.authoredFallbackTargets = authoredFallbackTargets
            self.timelineDefinitions = timelineDefinitions
            legacyTimelineTargets = timelineDefinitions.isEmpty
                ? timelineTargets : []
            self.sceneScriptTargets = sceneScriptTargets
        }

        static let empty = Self(
            userProperties: [], timelineTargets: [], sceneScriptTargets: []
        )
    }

    /// Compiles every authored stage through the shared Program owner.
    static func compileProgramFirstStages(
        _ admitted: SceneResolvedMaterialAdmittedLayer,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssues: Set<SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue>,
        dynamicProducers: DynamicProducerCatalog,
        assetFormatFacts: [String: Int],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        maximumVariantsPerMaterial: Int,
        maximumStageWorkers: Int = 1
    ) -> Result<CompiledStages, Rejection> {
        // Stage inputs are immutable and do not consume another stage's
        // compiler result. Prepare independently, then fold in authored order
        // so identity checks, the first failure and dependency ownership keep
        // exactly one deterministic authority.
        let workers = min(max(maximumStageWorkers, 1), admitted.products.count)
        let resultLock = NSLock()
        var programResults = Array<Result<CompiledStages, Rejection>?>(
            repeating: nil, count: admitted.products.count
        )
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for index in stride(from: worker, to: admitted.products.count, by: workers) {
                let product = admitted.products[index]
                guard let effect = product.graph.effects.first,
                      admitted.unavailableDependencyStageReasons[effect.key] == nil else {
                    continue
                }
                let initiallyInactive = admitted.initiallyInactiveEffectKeys.contains(effect.key)
                // The renderer captures the layer/main target exactly once into
                // the pair member identified by baseCaptureIdentity. Every later
                // effect consumes the preceding effect output already resident in
                // that pair, so it must not be required to prove the original
                // layer source route again.
                let stageSourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute =
                    effect.input == admitted.pairPlan.baseCaptureIdentity
                        ? admitted.sourceRoute
                        : .capturedLayerTexture
                let singleStage = SceneResolvedMaterialAdmittedLayer(
                    layerID: admitted.layerID,
                    products: [product],
                    pairPlan: admitted.pairPlan,
                    dependencyOwnership: admitted.dependencyOwnership,
                    unavailableDependencyStageReasons:
                        admitted.unavailableDependencyStageReasons.filter {
                            $0.key == effect.key
                        },
                    initiallyInactiveEffectKeys:
                        initiallyInactive ? [effect.key] : [],
                    sourceRoute: stageSourceRoute,
                    isVisibleExecutionRoot: admitted.isVisibleExecutionRoot,
                    isGraphOutputProvider: admitted.isGraphOutputProvider,
                    requiresGraphOutputProvider:
                        admitted.requiresGraphOutputProvider
                )
                let programResult = compileStages(
                    singleStage,
                    materialCatalog: materialCatalog,
                    demandIssues: demandIssues,
                    dynamicProducers: dynamicProducers,
                    assetFormatFacts: assetFormatFacts,
                    assetStates: assetStates,
                    maximumVariantsPerMaterial: maximumVariantsPerMaterial
                )
                resultLock.withLock { programResults[index] = programResult }
            }
        }
        var stages: [StageCapability] = []
        var allMaterials: [MaterialKey: MaterialCapability] = [:]
        for (index, product) in admitted.products.enumerated() {
            guard let effect = product.graph.effects.first else {
                return .failure(rejection("stage-effect-identity-missing"))
            }
            let initiallyInactive = admitted.initiallyInactiveEffectKeys
                .contains(effect.key)
            if let reasonCode =
                    admitted.unavailableDependencyStageReasons[effect.key] {
                guard product.clearFunctions.functions.isEmpty,
                      dependencyStageFailureMayPassthrough(
                          product.graph,
                          pairStep: admitted.pairPlan.effects.first(where: {
                              $0.effect == effect.key
                          })
                      ) else {
                    return .failure(rejection(
                        "dependency-stage-visual-failure-unsafe"
                    ))
                }
                stages.append(.visualFailurePassthrough(
                    product: product,
                    reasonCode: reasonCode
                ))
                continue
            }
            guard let programResult = programResults[index] else {
                return .failure(rejection("execution-stage-conservation"))
            }
            switch programResult {
            case let .success(compiled):
                guard compiled.stages.count == 1,
                      case .resolved = compiled.stages[0],
                      Set(allMaterials.keys).isDisjoint(with: compiled.materials.keys)
                else { return .failure(rejection("material-identity-duplicate")) }
                let expectedVisibilityTarget = SceneDynamicTarget
                    .effectVisibility(
                        layerID: effect.key.layerID,
                        effectIndex: effect.key.effectIndex
                    )
                if initiallyInactive,
                   compiled.stages[0].activationPolicy?
                    .effectVisibilityTarget != expectedVisibilityTarget {
                    guard initiallyInactiveStageMayPassthrough(
                        product,
                        pairPlan: admitted.pairPlan
                    ) else {
                        return .failure(rejection(
                            "initially-inactive-stage-passthrough-unsafe"
                        ))
                    }
                    stages.append(.initiallyInactivePassthrough(
                        product: product,
                        reasonCode:
                            "initially-inactive-property-stage-passthrough"
                    ))
                    continue
                }
                if initiallyInactive,
                   compiled.stages[0].activationPolicy?
                       .effectVisibilityPropertyKey == nil {
                    // D2b script lane: pre-proof the resolved dependencies
                    // against the layer's externalPrimary binding before
                    // finalization runs. A stage outside the binding would
                    // fail finalization for the whole layer; it downgrades
                    // to the passthrough instead, keeping active siblings'
                    // dependency satisfaction intact.
                    if !dependencyPreproofMayStayResolved(
                        stage: compiled.stages[0],
                        ownership: admitted.dependencyOwnership
                    ) {
                        guard initiallyInactiveStageMayPassthrough(
                            product,
                            pairPlan: admitted.pairPlan
                        ) else {
                            return .failure(rejection(
                                "initially-inactive-stage-passthrough-unsafe"
                            ))
                        }
                        stages.append(.initiallyInactivePassthrough(
                            product: product,
                            reasonCode:
                                "script-gated-dependency-preproof-mismatch"
                        ))
                        continue
                    }
                }
                stages.append(compiled.stages[0])
                allMaterials.merge(compiled.materials) { current, _ in current }

            case let .failure(programFailure):
                if initiallyInactive {
                    guard initiallyInactiveStageMayPassthrough(
                        product,
                        pairPlan: admitted.pairPlan
                    ) else {
                        return .failure(rejection(
                            "initially-inactive-stage-passthrough-unsafe"
                        ))
                    }
                    stages.append(.initiallyInactivePassthrough(
                        product: product,
                        reasonCode:
                            "initially-inactive-property-stage-passthrough"
                    ))
                    continue
                }
                guard product.clearFunctions.functions.isEmpty,
                      visualFailureMayPassthrough(
                          programFailure,
                          product: product,
                          pairPlan: admitted.pairPlan,
                          dependencyOwnership: admitted.dependencyOwnership
                      ) else { return .failure(programFailure) }
                stages.append(.visualFailurePassthrough(
                    product: product,
                    reasonCode: programFailure.code
                ))
            }
        }

        guard !stages.isEmpty,
              stages.count == admitted.products.count else {
            return .failure(rejection("execution-stage-conservation"))
        }
        guard let dependencyOwnership = finalizeDependencyOwnership(
            admitted.dependencyOwnership,
            potentialBindings: admitted.potentialExternalPrimaryBindings,
            layerID: admitted.layerID,
            stages: stages
        ) else { return .failure(rejection("execution-stage-conservation")) }
        let background: SceneBackgroundRequirement?
        switch sceneBackgroundRequirement(
            admitted: admitted,
            stages: stages
        ) {
        case let .success(value):
            background = value
        case let .failure(failure):
            return .failure(failure)
        }
        return .success(.init(
            stages: stages,
            materials: allMaterials,
            dependencyOwnership: dependencyOwnership,
            sceneBackgroundRequirement: background
        ))
    }

    private static func initiallyInactiveStageMayPassthrough(
        _ product: SceneGraphAdmissionProduct,
        pairPlan: SceneLayerFullFramePairPlan
    ) -> Bool {
        guard product.clearFunctions.functions.isEmpty,
              let effect = product.graph.effects.first else { return false }
        return dependencyStageFailureMayPassthrough(
            product.graph,
            pairStep: pairPlan.effects.first(where: {
                $0.effect == effect.key
            })
        )
    }

    /// D2b script-lane pre-proof: a script-gated initially-inactive stage
    /// whose resolved external dependencies sit outside the layer's
    /// dependency ownership would fail finalization for the whole layer.
    /// Those stages downgrade to the passthrough instead. Stages without
    /// external dependencies stay resolved - the active siblings keep the
    /// ownership satisfied, and the union over resolved stages is
    /// unchanged. Stages with framebuffers on an externalPrimary consumer
    /// also downgrade: the runtime activation passthrough cannot serve
    /// that shape yet (preEncodeVisualFailureSlots returns nil when the
    /// stage's own effect occupies binding slots), so the FBO stage stays
    /// a compile-time passthrough until executor support exists. Effects
    /// that occupy no binding slot keep working via the empty-slot list.
    /// `.externalAggregate` stays outside this per-stage pre-proof: an
    /// aggregate's slot vector is a layer-wide equality, so a per-stage
    /// subset check would wrongly downgrade valid aggregate members; those
    /// layers keep the finalize-level fail-closed (registered narrowing).
    private static func dependencyPreproofMayStayResolved(
        stage: StageCapability,
        ownership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        guard case let .resolved(product, _, _) = stage else { return true }
        switch ownership {
        case let .externalPrimary(binding):
            guard product.graph.renderTargets.isEmpty else { return false }
            switch resolvedExternalDependencies(in: stage) {
            case .none:
                return true
            case .invalid:
                return false
            case let .exact(dependencies):
                let expected = Set(binding.referenceSlots.map { slot in
                    BindingDependency(
                        consumerLayerID: binding.consumerLayerID,
                        providerLayerID: binding.providerLayerID,
                        slot: slot
                    )
                })
                return dependencies.allSatisfy { dependency in
                    dependency.origin == .terminalNamed
                        && expected.contains(dependency.bindingDependency)
                }
            }
        case .none:
            // External dependencies under .none ownership break
            // finalization; only dependency-free stages stay resolved.
            switch resolvedExternalDependencies(in: stage) {
            case .none:
                return true
            case .invalid:
                return false
            case let .exact(dependencies):
                return dependencies.isEmpty
            }
        case .graphInternal:
            // Same-layer composite references are the owned shape; any
            // cross-layer dependency breaks finalization.
            switch resolvedExternalDependencies(in: stage) {
            case .none:
                return true
            case .invalid:
                return false
            case let .exact(dependencies):
                return dependencies.allSatisfy { dependency in
                    dependency.consumerLayerID == product.graph.layerID
                        && dependency.providerLayerID == product.graph.layerID
                }
            }
        case .externalAggregate:
            return true
        }
    }

    /// Only a launch-time visual contract, unproven texture purpose, or
    /// ambiguous dynamic value-owner failure may become a visual no-op. Live
    /// resource availability, target, dependency, state and lifecycle failures
    /// remain hard rejections. Multi-node stages are admitted only as one atomic
    /// effect; a failed intermediate Program never publishes a partial authored
    /// result.
    /// Besides the pair-only compose shape, this admits any framebuffer graph
    /// already accepted by the shared target planner. Because failure happens
    /// before authored commands encode, the executor can discard the complete
    /// candidate and retain only the effect-entry current and committed history.
    private static func visualFailureMayPassthrough(
        _ failure: Rejection,
        product: SceneGraphAdmissionProduct,
        pairPlan: SceneLayerFullFramePairPlan,
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        switch dependencyOwnership {
        case .none, .graphInternal:
            break
        case .externalPrimary:
            guard let dependencySlots = dependencyOwnership
                .preEncodeVisualFailureSlots(in: product.graph),
                  dependencySlots.isEmpty
                  || product.graph.renderTargets.isEmpty else { return false }
        case let .externalAggregate(aggregate):
            // An aggregate may contain ordinary resolved stages and stages
            // whose visual program failed at launch. A failed stage can retain
            // the aggregate owner only when its exact authored external slot
            // is proven by the same single-stage pre-encode topology used by
            // the legacy owner. Unrelated local stages remain eligible for
            // the ordinary visual-failure proof below.
            guard aggregateVisualFailureMayPassthrough(
                product: product,
                aggregate: aggregate
            ) else { return false }
        }
        let ordinaryVisualFailure = [
            "material-generic-owner-revoked",
            "material-variant-envelope-frontend",
            "material-variant-envelope-shader-preparation",
            "material-variant-envelope-color-contract",
            "material-variant-envelope-sampler-schema",
            "material-variant-envelope-uniform-schema",
            "material-variant-envelope-animated-frame-metadata",
            "material-variant-envelope-texture-purpose",
            "material-dynamic-uniform-contributor-policy",
            "material-dynamic-uniform-contributor-producer-unavailable",
            "material-dynamic-uniform-script-attachment-unproven",
            "material-dynamic-uniform-producer-unavailable",
        ].contains(failure.code)
        let framebufferPreparationLimitation = product.graph.renderTargets
            .isEmpty == false
            && failure.programFailureAttribution.map { attribution in
                guard case let .launchEnvelope(.material(materialFailure)) =
                        attribution.cause else { return false }
                return materialFailure.phase == .preparation
                    && materialFailure.code == .samplerInternalTargetUnsupported
            } == true
        guard (ordinaryVisualFailure || framebufferPreparationLimitation),
              product.graph.effects.count == 1,
              !product.graph.nodes.isEmpty,
              product.graph.blockers.isEmpty,
              let effect = product.graph.effects.first,
              let pairStep = pairPlan.effects.first(where: {
                  $0.effect == effect.key
              }),
              pairStep.nodes.count == product.graph.nodes.count else { return false }

        if !product.graph.renderTargets.isEmpty {
            return preEncodeVisualFailureGraphMayPassthrough(
                product.graph,
                effect: effect,
                pairStep: pairStep
            )
        }
        guard pairStep.fullFrameOutputWriteCount == product.graph.nodes.count,
              (pairStep.inputMember == pairStep.outputMember)
                == product.graph.nodes.count.isMultiple(of: 2) else { return false }

        let composeFlags: [Bool] = product.graph.nodes.compactMap { node in
            switch node.compose {
            case nil, .some(.bool(false)): false
            case .some(.bool(true)): true
            default: nil
            }
        }
        guard composeFlags.count == product.graph.nodes.count,
              composeFlags.last == false,
              composeFlags.dropLast().allSatisfy({ $0 }),
              pairStep.composeTransitionCount
                == max(0, product.graph.nodes.count - 1) else { return false }

        let ordinals = product.graph.nodes.compactMap(\.materialOrdinal)
        guard ordinals.count == product.graph.nodes.count,
              zip(ordinals, ordinals.dropFirst()).allSatisfy({ $0 < $1 }) else {
            return false
        }
        for (node, pairNode) in zip(product.graph.nodes, pairStep.nodes) {
            guard node.effect == effect.key,
                  node.kind == .material,
                  node.target == effect.output,
                  node.commandSource == nil,
                  node.commandTarget == nil,
                  node.bindings.allSatisfy({ $0.texture == effect.input }),
                  pairNode.nodeIndex == node.nodeIndex,
                  pairNode.definitionPassIndex == node.definitionPassIndex,
                  pairNode.kind == .material else { return false }
        }
        return true
    }

    private static func finalizeDependencyOwnership(
        _ ownership: SceneResolvedMaterialDependencyOwnership,
        potentialBindings: [SceneDependencyRenderPlan.Binding],
        layerID: Int,
        stages: [StageCapability]
    ) -> SceneResolvedMaterialDependencyOwnership? {
        var resolvedDependencyStages: [ResolvedExternalDependency] = []
        for stage in stages {
            switch resolvedExternalDependencies(in: stage) {
            case .none:
                continue
            case let .exact(dependencies):
                resolvedDependencyStages.append(contentsOf: dependencies)
            case .invalid:
                return nil
            }
        }
        switch ownership {
        case .none:
            guard !potentialBindings.isEmpty else {
                return resolvedDependencyStages.isEmpty ? ownership : nil
            }
            if resolvedDependencyStages.isEmpty {
                return ownership
            }
            guard resolvedDependencyStages.allSatisfy({
                      $0.origin == .exactMixedOptionalFallback
                  }) else { return nil }
            guard let binding = expandedPotentialBinding(
                      dependencies: resolvedDependencyStages,
                      potentialBindings: potentialBindings,
                      layerID: layerID
                  ) else { return nil }
            return .externalPrimary(binding)

        case .graphInternal:
            // Same-layer composite references are the owned shape: the
            // layer's own base source publishes the named target during
            // graph execution. Any non-self resolved dependency still has no
            // internal owner and must keep failing closed.
            guard resolvedDependencyStages.allSatisfy({
                      $0.consumerLayerID == layerID
                          && $0.providerLayerID == layerID
                  }) else { return nil }
            return ownership

        case let .externalPrimary(binding):
            guard binding.consumerLayerID == layerID else { return nil }
            let passthroughDependencyStages = stages.flatMap {
                visualFailureExternalDependencies(in: $0, binding: binding)
            }
            let directDependencyStages = resolvedDependencyStages.filter {
                $0.origin == .terminalNamed
            }.map(\.bindingDependency) + passthroughDependencyStages
            guard matches(directDependencyStages, binding: binding) else {
                return nil
            }
            let optionalDependencies = resolvedDependencyStages.filter {
                $0.origin == .exactMixedOptionalFallback
            }
            guard !optionalDependencies.isEmpty else { return ownership }
            guard let orderedDependencies = orderedStageDependencies(
                      stages,
                      binding: binding
                  ), let expanded = expandedPotentialBinding(
                      base: binding,
                      dependencies: optionalDependencies,
                      orderedDependencies: orderedDependencies,
                      potentialBindings: potentialBindings,
                      layerID: layerID
                  ) else { return nil }
            return .externalPrimary(expanded)
        case let .externalAggregate(aggregate):
            guard aggregate.referenceSlots.count >= 2,
                  let aggregateDependencies = aggregateStageDependencies(
                      stages,
                      aggregate: aggregate
                  ),
                  aggregateDependenciesMatch(
                      aggregateDependencies,
                      aggregate: aggregate
                  ) else { return nil }
            return ownership
        }
    }

    /// Promotes an all-optional same-provider vector from descriptor-only
    /// carriers after every selected Program stage proves its exact lower
    /// named candidate. No carrier can stand in for a sibling slot.
    private static func expandedPotentialBinding(
        dependencies: [ResolvedExternalDependency],
        potentialBindings: [SceneDependencyRenderPlan.Binding],
        layerID: Int
    ) -> SceneDependencyRenderPlan.Binding? {
        guard let firstDependency = dependencies.first,
              let first = exactPotentialBinding(
                  for: firstDependency,
                  in: potentialBindings,
                  layerID: layerID
              ) else { return nil }
        return expandedPotentialBinding(
            base: first,
            dependencies: dependencies,
            orderedDependencies: dependencies.map(\.bindingDependency),
            potentialBindings: potentialBindings,
            layerID: layerID
        )
    }

    /// Extends one direct external owner with the exact optional siblings that
    /// selected the same provider. The returned referenceSlots preserve the
    /// authored stage/pass/slot order used by frame reservation and Program
    /// input binding.
    private static func expandedPotentialBinding(
        base: SceneDependencyRenderPlan.Binding,
        dependencies: [ResolvedExternalDependency],
        orderedDependencies: [BindingDependency],
        potentialBindings: [SceneDependencyRenderPlan.Binding],
        layerID: Int
    ) -> SceneDependencyRenderPlan.Binding? {
        guard !dependencies.isEmpty,
              Set(dependencies).count == dependencies.count,
              Set(orderedDependencies).count == orderedDependencies.count,
              dependencies.allSatisfy({
                  $0.origin == .exactMixedOptionalFallback
              }) else { return nil }
        for dependency in dependencies {
            guard let candidate = exactPotentialBinding(
                      for: dependency,
                      in: potentialBindings,
                      layerID: layerID
                  ), compatible(candidate, with: base) else { return nil }
        }
        let referenceSlots = orderedDependencies.map(\.slot)
        guard referenceSlots.contains(base.slot),
              Set(referenceSlots).count == referenceSlots.count else {
            return nil
        }
        return .init(
            consumerLayerID: base.consumerLayerID,
            providerLayerID: base.providerLayerID,
            slot: base.slot,
            referenceSlots: referenceSlots,
            blendMode: base.blendMode,
            kind: base.kind,
            requiresForwardCapture: base.requiresForwardCapture,
            requiresResolvedMaterialProgram:
                base.requiresResolvedMaterialProgram
        )
    }

    private static func exactPotentialBinding(
        for dependency: ResolvedExternalDependency,
        in potentialBindings: [SceneDependencyRenderPlan.Binding],
        layerID: Int
    ) -> SceneDependencyRenderPlan.Binding? {
        let matches = potentialBindings.filter { candidate in
            candidate.consumerLayerID == layerID
                && candidate.providerLayerID == dependency.providerLayerID
                && candidate.slot == dependency.slot
                && candidate.referenceSlots == [dependency.slot]
                && candidate.requiresResolvedMaterialProgram
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func compatible(
        _ candidate: SceneDependencyRenderPlan.Binding,
        with base: SceneDependencyRenderPlan.Binding
    ) -> Bool {
        candidate.consumerLayerID == base.consumerLayerID
            && candidate.providerLayerID == base.providerLayerID
            && candidate.blendMode == base.blendMode
            && candidate.kind == base.kind
            && candidate.requiresForwardCapture == base.requiresForwardCapture
            && candidate.requiresResolvedMaterialProgram
                == base.requiresResolvedMaterialProgram
    }

    private static func orderedStageDependencies(
        _ stages: [StageCapability],
        binding: SceneDependencyRenderPlan.Binding
    ) -> [BindingDependency]? {
        var result: [BindingDependency] = []
        for stage in stages {
            switch resolvedExternalDependencies(in: stage) {
            case let .exact(dependencies):
                result.append(contentsOf: dependencies.map(\.bindingDependency))
            case .none:
                result.append(contentsOf: visualFailureExternalDependencies(
                    in: stage,
                    binding: binding
                ))
            case .invalid:
                return nil
            }
        }
        return result
    }

    /// Conserves one dependency atom for each aggregate slot while retaining
    /// authored stage order. Resolved stages contribute the provider selected
    /// by their admitted MaterialProgram. A visual-failure stage contributes
    /// its slot only after the exact single-stage previous-current topology is
    /// proven; an unrelated local stage contributes no aggregate dependency.
    private static func aggregateStageDependencies(
        _ stages: [StageCapability],
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate
    ) -> [BindingDependency]? {
        var result: [BindingDependency] = []
        let orderedBindings = aggregate.orderedBindings
        guard !orderedBindings.isEmpty else { return nil }
        for stage in stages {
            guard let effect = stage.product.graph.effects.first else {
                return nil
            }
            let matches = orderedBindings.filter {
                $0.slot.effectID == effect.key.descriptorID
            }
            guard matches.count <= 1 else { return nil }
            if let binding = matches.first {
                switch resolvedExternalDependencies(in: stage) {
                case let .exact(dependencies):
                    guard dependencies.count == 1 else { return nil }
                    result.append(contentsOf: dependencies.map(\.bindingDependency))
                case .none:
                    guard case .visualFailurePassthrough = stage,
                          let slots = SceneResolvedMaterialDependencyOwnership
                              .externalPrimary(binding)
                              .preEncodeVisualFailureSlots(in: stage.product.graph),
                          slots == [binding.slot] else {
                        return nil
                    }
                    result.append(.init(
                        consumerLayerID: aggregate.consumerLayerID,
                        providerLayerID: binding.providerLayerID,
                        slot: binding.slot
                    ))
                case .invalid:
                    return nil
                }
                continue
            }
            // A local stage unrelated to the aggregate may still be resolved
            // or pass through visually; only named external dependencies are
            // part of the aggregate vector.
            switch resolvedExternalDependencies(in: stage) {
            case .none:
                continue
            case let .exact(dependencies):
                result.append(contentsOf: dependencies.map(\.bindingDependency))
            case .invalid:
                return nil
            }
        }
        return result
    }

    private static func aggregateVisualFailureMayPassthrough(
        product: SceneGraphAdmissionProduct,
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate
    ) -> Bool {
        guard let effect = product.graph.effects.first else { return false }
        let matches = aggregate.orderedBindings.filter {
            $0.slot.effectID == effect.key.descriptorID
        }
        guard matches.count <= 1 else { return false }
        guard let binding = matches.first else {
            return true
        }
        guard let slots = SceneResolvedMaterialDependencyOwnership
            .externalPrimary(binding)
            .preEncodeVisualFailureSlots(in: product.graph) else {
            return false
        }
        return slots == [binding.slot]
    }

    private static func matches(
        _ dependencies: [BindingDependency],
        binding: SceneDependencyRenderPlan.Binding
    ) -> Bool {
        let expected = Set(binding.referenceSlots.map { slot in
            BindingDependency(
                consumerLayerID: binding.consumerLayerID,
                providerLayerID: binding.providerLayerID,
                slot: slot
            )
        })
        return !dependencies.isEmpty
            && expected.count == binding.referenceSlots.count
            && dependencies.count == expected.count
            && Set(dependencies) == expected
    }

    private static func aggregateDependenciesMatch(
        _ dependencies: [BindingDependency],
        aggregate: SceneDependencyRenderPlan.MultiProviderAggregate
    ) -> Bool {
        // Preserve the aggregate's authored slot vector. A set comparison
        // would accept a valid provider set routed to the wrong material
        // stage/slot and make the later frame reservation disagree with the
        // program's dependency ownership.
        let expected = aggregate.orderedBindings.flatMap { binding in
            binding.referenceSlots.map { slot in
                BindingDependency(
                    consumerLayerID: aggregate.consumerLayerID,
                    providerLayerID: binding.providerLayerID,
                    slot: slot
                )
            }
        }
        return !dependencies.isEmpty
            && dependencies == expected
    }

}
