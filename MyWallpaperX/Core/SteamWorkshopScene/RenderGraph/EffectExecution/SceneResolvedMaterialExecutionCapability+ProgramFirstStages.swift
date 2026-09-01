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

    private struct SceneBackgroundCandidate {
        let product: SceneGraphAdmissionProduct
        let key: MaterialKey
        let slot: Int
        let consumerLayerID: Int
        let selected: Bool
    }

    private static func sceneBackgroundRequirement(
        admitted: SceneResolvedMaterialAdmittedLayer,
        stages: [StageCapability]
    ) -> Result<SceneBackgroundRequirement?, Rejection> {
        var candidates: [SceneBackgroundCandidate] = []
        for stage in stages {
            guard case let .resolved(product, materials, _) = stage else { continue }
            for material in materials.values {
                for slot in material.template.textureSlots.compactMap({ $0 }) {
                    for (index, candidate) in slot.candidates.enumerated() {
                        guard case let .provider(.sceneBackground(consumerLayerID)) =
                                candidate.reference else { continue }
                        candidates.append(.init(
                            product: product,
                            key: material.key,
                            slot: slot.index,
                            consumerLayerID: consumerLayerID,
                            selected: index == slot.candidates.index(
                                before: slot.candidates.endIndex
                            )
                        ))
                    }
                }
            }
        }
        guard !candidates.isEmpty else { return .success(nil) }
        guard candidates.count == 1,
              let candidate = candidates.first,
              candidate.selected else {
            return .failure(rejection("scene-background-provider-ambiguous"))
        }
        let graph = candidate.product.graph
        let nodes = graph.nodes.sorted { $0.nodeIndex < $1.nodeIndex }
        guard candidate.consumerLayerID == admitted.layerID,
              admitted.sourceRoute == .capturedLayerTexture,
              admitted.dependencyOwnership == .none,
              graph.layerID == admitted.layerID,
              graph.effects.count == 1,
              graph.renderTargets.isEmpty,
              graph.blockers.isEmpty,
              nodes.count == 2,
              let effect = graph.effects.first,
              candidate.key.effect == effect.key,
              candidate.key.nodeIndex == nodes[0].nodeIndex,
              candidate.slot == 1,
              nodes[0].kind == .material,
              nodes[1].kind == .material,
              nodes[0].effect == effect.key,
              nodes[1].effect == effect.key,
              nodes[0].target == effect.output,
              nodes[1].target == effect.output,
              nodes[0].compose == .bool(true),
              nodes[1].compose == nil || nodes[1].compose == .bool(false),
              nodes.allSatisfy({ node in
                  node.bindings.allSatisfy { $0.texture == effect.input }
              }),
              let pairStep = admitted.pairPlan.effects.first(where: {
                  $0.effect == effect.key
              }),
              pairStep.composeTransitionCount == 1,
              pairStep.fullFrameOutputWriteCount == 2,
              pairStep.inputMember == pairStep.outputMember else {
            return .failure(rejection("scene-background-compose-shape"))
        }
        return .success(.init(
            layerID: admitted.layerID,
            effect: effect.key,
            nodeIndex: candidate.key.nodeIndex,
            slot: candidate.slot
        ))
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

    /// Product Timeline admission conserves the exact typed definition and
    /// author fallback. Identity-only catalogs remain available to legacy
    /// standalone harnesses, but product launch always supplies definitions.
    static func timelineDefinitionMatches(
        _ dynamic: Template.DynamicUniform,
        producers: DynamicProducerCatalog
    ) -> Bool {
        guard !producers.timelineDefinitions.isEmpty else {
            return producers.timelineTargets.contains(dynamic.target)
        }
        let matches = producers.timelineDefinitions.filter {
            $0.target == dynamic.target
        }
        guard matches.count == 1,
              let definition = matches.first,
              let fallback = dynamic.authoredFallback,
              let authoredBits = timelineAuthoredBitPatterns(definition) else {
            return false
        }
        return fallback.componentBitPatterns == authoredBits
    }

    private static func timelineAuthoredBitPatterns(
        _ definition: SceneDynamicTargetDefinition
    ) -> [UInt64]? {
        guard definition.authoredValue.valueType == definition.valueType,
              definition.authoredValue.isFinite else { return nil }
        let components: [Double]
        switch definition.authoredValue {
        case let .scalar(x): components = [x]
        case let .vector2(x, y): components = [x, y]
        case let .vector3(x, y, z): components = [x, y, z]
        case let .vector4(x, y, z, w): components = [x, y, z, w]
        case .bool, .string: return nil
        }
        return components.map(\.bitPattern)
    }

    static func soleUserPropertyProducerMatches(
        _ propertyKey: String,
        dynamic: Template.DynamicUniform,
        producers: DynamicProducerCatalog
    ) -> Bool {
        let targetProducers = producers.userProperties.filter {
            $0.target == dynamic.target
        }
        guard targetProducers.count == 1,
              let producer = targetProducers.first else { return false }
        return producer.propertyKey == propertyKey
            && userPropertyValueTypeMatches(producer.valueType, dynamic: dynamic)
    }

    /// Exact direct bindings conserve the producer type before Program claims
    /// product output. Legacy/test catalogs without a type retain the previous
    /// identity-only behavior; product launch always publishes the real type.
    static func userPropertyValueTypeMatches(
        _ producerType: SceneDynamicValueType?,
        dynamic: Template.DynamicUniform
    ) -> Bool {
        guard let producerType else { return true }
        guard let fallback = dynamic.authoredFallback,
              fallback.valueKind.localizedLowercase == "binding",
              SceneResolvedMaterialDirectUserBindingContract.matches(
                  dynamic: dynamic,
                  fallback: fallback
              ) else {
            return true
        }
        let expected: SceneDynamicValueType
        switch fallback.componentBitPatterns.count {
        case 1: expected = .scalar
        case 2: expected = .vector2
        case 3: expected = .vector3
        case 4: expected = .vector4
        default: return true
        }
        return producerType == expected
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
        let resolvedBindings = resolvedDependencyStages.map(\.bindingDependency)
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
            let matchingBindings = potentialBindings.filter {
                $0.consumerLayerID == layerID
                    && matches(resolvedBindings, binding: $0)
            }
            guard matchingBindings.count == 1,
                  let binding = matchingBindings.first else {
                return nil
            }
            return .externalPrimary(binding)

        case .graphInternal:
            guard potentialBindings.isEmpty,
                  resolvedDependencyStages.isEmpty else { return nil }
            return ownership

        case let .externalPrimary(binding):
            guard potentialBindings.isEmpty,
                  binding.consumerLayerID == layerID else { return nil }
            let passthroughDependencyStages = stages.flatMap {
                visualFailureExternalDependencies(in: $0, binding: binding)
            }
            let ordinaryDependencyStages = resolvedBindings
                + passthroughDependencyStages
            return matches(ordinaryDependencyStages, binding: binding)
                ? ownership : nil
        }
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
        for material in materials.values {
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
                      && item.reference.providerLayerID
                          == candidate.reference.providerLayerID
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
        return .exact(result)
    }
}

nonisolated extension SceneResolvedMaterialDependencyOwnership {
    /// Returns the external provider slots owned by this exact single-effect
    /// stage. `nil` means the dependency owner cannot authorize a visual
    /// fallback for the stage. Empty slots mean this stage is independent of
    /// the layer's external dependency; it may use the ordinary framebuffer
    /// rollback proof without consuming or publishing that provider.
    func preEncodeVisualFailureSlots(
        in graph: SceneAuthoredEffectRenderPlan
    ) -> [SceneEffectPassSlot]? {
        switch self {
        case .none, .graphInternal:
            return []
        case let .externalPrimary(binding):
            guard graph.effects.count == 1,
                  let effect = graph.effects.first,
                  graph.layerID == binding.consumerLayerID,
                  effect.key.layerID == binding.consumerLayerID else {
                return nil
            }
            let slots = binding.referenceSlots.filter {
                $0.effectID == effect.key.descriptorID
            }
            guard !slots.isEmpty else { return [] }
            guard graph.renderTargets.isEmpty else { return nil }
            guard Set(slots).count == slots.count,
                  slots.allSatisfy({ slot in
                      graph.nodes.filter({ node in
                          node.effect == effect.key
                              && node.kind == .material
                              && node.instancePassIndex == slot.passIndex
                              && node.materialOrdinal != nil
                      }).count == 1
                  }) else { return nil }
            return slots
        }
    }
}
