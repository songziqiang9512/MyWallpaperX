import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    /// Compiles every authored stage through the shared Program owner.
    static func compileProgramFirstStages(
        _ admitted: SceneResolvedMaterialAdmittedLayer,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssues: Set<SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue>,
        dynamicProducers: DynamicProducerCatalog,
        assetFormatFacts: [String: Int],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        maximumVariantsPerMaterial: Int
    ) -> Result<CompiledStages, Rejection> {
        var stages: [StageCapability] = []
        var allMaterials: [MaterialKey: MaterialCapability] = [:]
        for product in admitted.products {
            guard let effect = product.graph.effects.first else {
                return .failure(rejection("stage-effect-identity-missing"))
            }
            let initiallyInactive = admitted.initiallyInactiveEffectKeys
                .contains(effect.key)
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
            let programResult = compileStages(
                singleStage,
                materialCatalog: materialCatalog,
                demandIssues: demandIssues,
                dynamicProducers: dynamicProducers,
                assetFormatFacts: assetFormatFacts,
                assetStates: assetStates,
                maximumVariantsPerMaterial: maximumVariantsPerMaterial
            )
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

    private struct BindingDependency: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
    }

    private struct ResolvedExternalDependency: Hashable {
        enum Origin: Hashable {
            case terminalNamed
            case exactMixedOptionalFallback
        }

        let materialKey: MaterialKey
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let origin: Origin

        var bindingDependency: BindingDependency {
            .init(
                consumerLayerID: consumerLayerID,
                providerLayerID: providerLayerID,
                slot: slot
            )
        }
    }

    private struct ResolvedNamedCandidate {
        let key: MaterialKey
        let slot: Int
        let reference: SceneNamedTextureReference
        let origin: ResolvedExternalDependency.Origin
    }

    private enum ResolvedExternalDependencyAnalysis {
        case none
        case exact([ResolvedExternalDependency])
        case invalid
    }

    private static func visualFailureExternalDependencies(
        in stage: StageCapability,
        binding: SceneDependencyRenderPlan.Binding
    ) -> [BindingDependency] {
        guard case let .visualFailurePassthrough(product, _) = stage,
              let slots = SceneResolvedMaterialDependencyOwnership
                .externalPrimary(binding)
                .preEncodeVisualFailureSlots(in: product.graph) else {
            return []
        }
        return slots.map {
            BindingDependency(
                consumerLayerID: binding.consumerLayerID,
                providerLayerID: binding.providerLayerID,
                slot: $0
            )
        }
    }

    private static func resolvedExternalDependencies(
        in stage: StageCapability
    ) -> ResolvedExternalDependencyAnalysis {
        guard case let .resolved(product, materials, _) = stage else {
            return .none
        }
        var namedCandidates: [ResolvedNamedCandidate] = []
        // `materials` is a dictionary keyed by material identity. Its
        // iteration order is intentionally unspecified, while an aggregate
        // dependency is an authored slot vector. Use the graph's authored
        // effect/node order rather than lexical effect IDs at both collection
        // and final-vector boundaries.
        func authoredMaterialPrecedes(
            _ lhs: MaterialCapability,
            _ rhs: MaterialCapability
        ) -> Bool {
            let lhsEffectIndex = lhs.key.effect.effectIndex
            let rhsEffectIndex = rhs.key.effect.effectIndex
            if lhsEffectIndex != rhsEffectIndex {
                return lhsEffectIndex < rhsEffectIndex
            }
            let lhsNodeOrder = product.graph.nodes.firstIndex {
                $0.nodeIndex == lhs.key.nodeIndex && $0.effect == lhs.key.effect
            } ?? Int.max
            let rhsNodeOrder = product.graph.nodes.firstIndex {
                $0.nodeIndex == rhs.key.nodeIndex && $0.effect == rhs.key.effect
            } ?? Int.max
            if lhsNodeOrder != rhsNodeOrder {
                return lhsNodeOrder < rhsNodeOrder
            }
            if lhs.key.nodeIndex != rhs.key.nodeIndex {
                return lhs.key.nodeIndex < rhs.key.nodeIndex
            }
            return lhs.key.effect.descriptorID < rhs.key.effect.descriptorID
        }
        for material in materials.values.sorted(by: authoredMaterialPrecedes) {
            for slot in material.template.textureSlots.compactMap({ $0 }) {
                let reference: SceneNamedTextureReference?
                let origin: ResolvedExternalDependency.Origin?
                if let selected = slot.candidates.last,
                   case let .provider(.namedLayerTarget(value)) =
                    selected.reference {
                    reference = value
                    origin = .terminalNamed
                } else if material.variants
                    .provesExactMixedNamedFallback(
                        slot: slot.index
                    ), slot.candidates.count == 2,
                    case let .provider(.namedLayerTarget(value)) =
                        slot.candidates[0].reference {
                    // The highest-precedence optional input may be absent at a
                    // concrete frame. The exact precompiled mixed-provider
                    // envelope then selects this lower compositor color
                    // publication, so dependency conservation must retain its
                    // provider edge even though it is not the static last
                    // candidate.
                    reference = value
                    origin = .exactMixedOptionalFallback
                } else {
                    reference = nil
                    origin = nil
                }
                guard let reference, let origin else {
                    continue
                }
                namedCandidates.append(.init(
                    key: material.key,
                    slot: slot.index,
                    reference: reference,
                    origin: origin
                ))
            }
        }
        guard !namedCandidates.isEmpty else { return .none }
        guard let candidate = namedCandidates.first,
              candidate.reference.variant == SceneNamedTextureReference.Variant.primary,
              candidate.key.effect.layerID == product.graph.layerID,
              namedCandidates.allSatisfy({ item in
                  item.reference.variant == .primary
                      && item.key.effect.layerID == product.graph.layerID
              }) else { return .invalid }
        var result: [ResolvedExternalDependency] = []
        for item in namedCandidates {
            let nodeMatches = product.graph.nodes.filter {
                $0.nodeIndex == item.key.nodeIndex
                    && $0.effect == item.key.effect
            }
            let effectMatches = product.graph.effects.filter {
                $0.key == item.key.effect
            }
            guard nodeMatches.count == 1,
                  effectMatches.count == 1,
                  let passIndex = nodeMatches.first?.instancePassIndex else {
                return .invalid
            }
            result.append(.init(
                materialKey: item.key,
                consumerLayerID: item.key.effect.layerID,
                providerLayerID: item.reference.providerLayerID,
                slot: .init(
                    effectID: item.key.effect.descriptorID,
                    passIndex: passIndex,
                    slotIndex: item.slot
                ),
                origin: item.origin
            ))
        }
        guard Set(result).count == result.count else { return .invalid }
        let orderedResult = result.sorted {
            let lhs = $0
            let rhs = $1
            // Effect index and graph node order are the authored authority;
            // descriptor IDs are arbitrary labels and must never reorder the
            // aggregate provider vector.
            if lhs.materialKey.effect.effectIndex
                != rhs.materialKey.effect.effectIndex {
                return lhs.materialKey.effect.effectIndex
                    < rhs.materialKey.effect.effectIndex
            }
            let lhsNodeOrder = product.graph.nodes.firstIndex {
                $0.nodeIndex == lhs.materialKey.nodeIndex
                    && $0.effect == lhs.materialKey.effect
            } ?? Int.max
            let rhsNodeOrder = product.graph.nodes.firstIndex {
                $0.nodeIndex == rhs.materialKey.nodeIndex
                    && $0.effect == rhs.materialKey.effect
            } ?? Int.max
            if lhsNodeOrder != rhsNodeOrder {
                return lhsNodeOrder < rhsNodeOrder
            }
            if lhs.slot.passIndex != rhs.slot.passIndex {
                return lhs.slot.passIndex < rhs.slot.passIndex
            }
            if lhs.slot.slotIndex != rhs.slot.slotIndex {
                return lhs.slot.slotIndex < rhs.slot.slotIndex
            }
            if lhs.providerLayerID != rhs.providerLayerID {
                return lhs.providerLayerID < rhs.providerLayerID
            }
            if lhs.materialKey.nodeIndex != rhs.materialKey.nodeIndex {
                return lhs.materialKey.nodeIndex < rhs.materialKey.nodeIndex
            }
            return lhs.materialKey.effect.descriptorID
                < rhs.materialKey.effect.descriptorID
        }
        return .exact(orderedResult)
    }
}
