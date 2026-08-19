import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    /// Compiles each authored stage through Program first. A typed backend may
    /// fill only the exact stage whose Program compilation failed.
    static func compileProgramFirstStages(
        _ admitted: SceneResolvedMaterialAdmittedLayer,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssues: Set<SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue>,
        dynamicProducers: DynamicProducerCatalog,
        assetFormatFacts: [String: Int],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        dedicatedStagePrograms: [SceneEffectStageProgram],
        dedicatedStageFamilies: [Graph.EffectKey: String],
        dedicatedLeafKeys: Set<Graph.EffectKey>,
        dedicatedGraphStageKeys: Set<Graph.EffectKey>,
        dedicatedFullFrameComposeStageKeys: Set<Graph.EffectKey>,
        maximumVariantsPerMaterial: Int
    ) -> Result<CompiledStages, Rejection> {
        let programsByKey = Dictionary(grouping: dedicatedStagePrograms, by: \.effectKey)
        guard programsByKey.values.allSatisfy({ $0.count == 1 }) else {
            return .failure(rejection("dedicated-leaf-identity-ambiguous"))
        }

        var stages: [StageCapability] = []
        var allMaterials: [MaterialKey: MaterialCapability] = [:]
        for product in admitted.products {
            guard let effect = product.graph.effects.first else {
                return .failure(rejection("stage-effect-identity-missing"))
            }
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
                sourceRoute: stageSourceRoute
            )
            if let program = externallyOwnedImageBlendProgram(
                for: effect.key,
                ownership: admitted.dependencyOwnership,
                programsByKey: programsByKey
            ) {
                guard product.clearFunctions.functions.isEmpty else {
                    return .failure(rejection("function-invocation-executor-unavailable"))
                }
                let pairLeaf = dedicatedLeafKeys.contains(effect.key)
                    && program.executionPlan.logicalRenderTargetCount == 0
                    && product.graph.nodes.count == 1
                    && product.graph.renderTargets.isEmpty
                guard pairLeaf,
                      program.effectKey == effect.key,
                      program.stageGraph.effects.first?.key == effect.key,
                      dedicatedDynamicTargetsAreExecutable(
                          program,
                          producers: dynamicProducers
                      ) else {
                    return .failure(rejection("dedicated-leaf-unsupported"))
                }
                stages.append(.dedicated(
                    product: product,
                    program: program,
                    family: dedicatedStageFamilies[effect.key] ?? "dedicated-leaf"
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
                stages.append(compiled.stages[0])
                allMaterials.merge(compiled.materials) { current, _ in current }

            case let .failure(programFailure):
                if programFailure.code == "material-generic-owner-revoked" {
                    if product.clearFunctions.functions.isEmpty,
                       visualFailureMayPassthrough(
                           programFailure,
                           product: product,
                           pairPlan: admitted.pairPlan,
                           dependencyOwnership: admitted.dependencyOwnership
                       ) {
                        stages.append(.visualFailurePassthrough(
                            product: product,
                            reasonCode: programFailure.code
                        ))
                        continue
                    }
                    return .failure(programFailure)
                }
                guard product.clearFunctions.functions.isEmpty else {
                    return .failure(rejection("function-invocation-executor-unavailable"))
                }
                guard let program = programsByKey[effect.key]?.first else {
                    if visualFailureMayPassthrough(
                        programFailure,
                        product: product,
                        pairPlan: admitted.pairPlan,
                        dependencyOwnership: admitted.dependencyOwnership
                    ) {
                        stages.append(.visualFailurePassthrough(
                            product: product,
                            reasonCode: programFailure.code
                        ))
                        continue
                    }
                    return .failure(programFailure)
                }
                let pairLeaf = dedicatedLeafKeys.contains(effect.key)
                    && program.executionPlan.logicalRenderTargetCount == 0
                    && product.graph.nodes.count == 1
                    && product.graph.renderTargets.isEmpty
                let logicalTargetStage = dedicatedGraphStageKeys.contains(effect.key)
                    && (program.executionPlan.supportsUnifiedLogicalTargetStage
                        || program.executionPlan.supportsUnifiedHistoryTargetStage)
                    && program.executionPlan.logicalRenderTargetCount > 0
                    && product.graph.nodes.count > 1
                    && product.graph.renderTargets.count
                        == program.executionPlan.logicalRenderTargetCount
                    && product.graph.renderTargets.allSatisfy { !$0.declaredUnique }
                let pairStep = admitted.pairPlan.effects.first {
                    $0.effect == effect.key
                }
                let fullFrameComposeStage =
                    dedicatedFullFrameComposeStageKeys.contains(effect.key)
                    && program.executionPlan.supportsUnifiedFullFrameComposeStage
                    && program.executionPlan.logicalRenderTargetCount == 0
                    && product.graph.nodes.count == 2
                    && product.graph.renderTargets.isEmpty
                    && pairStep?.composeTransitionCount == 1
                    && pairStep?.fullFrameOutputWriteCount == 2
                    && pairStep?.inputMember == pairStep?.outputMember
                let identityMatches = program.effectKey == effect.key
                    && program.stageGraph.effects.first?.key == effect.key
                let dynamicTargetsExecutable = dedicatedDynamicTargetsAreExecutable(
                    program,
                    producers: dynamicProducers
                )
                let sourceRouteExecutable =
                    stageSourceRoute != .capturedMainTargetTexture
                    || ((pairLeaf || logicalTargetStage)
                        && program.executionPlan.supportsUtilityCapture)
                guard pairLeaf || logicalTargetStage || fullFrameComposeStage,
                      identityMatches,
                      dynamicTargetsExecutable,
                      sourceRouteExecutable else {
                    return .failure(rejection("dedicated-leaf-unsupported"))
                }
                stages.append(.dedicated(
                    product: product,
                    program: program,
                    family: dedicatedStageFamilies[effect.key] ?? "dedicated-leaf"
                ))
            }
        }

        guard !stages.isEmpty,
              stages.count == admitted.products.count,
              dependencyOwnershipMatches(
                  admitted.dependencyOwnership,
                  layerID: admitted.layerID,
                  stages: stages
              ) else {
            return .failure(rejection("execution-stage-conservation"))
        }
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
            sceneBackgroundRequirement: background
        ))
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
            guard case let .resolved(product, materials) = stage else { continue }
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

    /// Only a launch-time visual contract or ambiguous dynamic value-owner
    /// failure may become a visual no-op. Dynamic producer availability,
    /// resource, target, dependency, state and lifecycle failures remain hard
    /// rejections. The admitted effect must be a pair-only full-frame stage so
    /// its whole transaction can preserve previous current without fabricating
    /// an authored texture, uniform value or graph resource. Multi-node stages
    /// are admitted only as one atomic effect; a failed intermediate Program
    /// never publishes a partial authored result.
    private static func visualFailureMayPassthrough(
        _ failure: Rejection,
        product: SceneGraphAdmissionProduct,
        pairPlan: SceneLayerFullFramePairPlan,
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        guard [
            "material-generic-owner-revoked",
            "material-variant-envelope-frontend",
            "material-variant-envelope-shader-preparation",
            "material-variant-envelope-color-contract",
            "material-variant-envelope-sampler-schema",
            "material-variant-envelope-uniform-schema",
            "material-dynamic-uniform-contributor-policy",
            "material-dynamic-uniform-contributor-producer-unavailable",
            "material-dynamic-uniform-script-attachment-unproven",
            "material-dynamic-uniform-producer-unavailable",
        ].contains(failure.code),
              dependencyOwnership == .none,
              product.graph.effects.count == 1,
              !product.graph.nodes.isEmpty,
              product.graph.renderTargets.isEmpty,
              product.graph.blockers.isEmpty,
              let effect = product.graph.effects.first,
              let pairStep = pairPlan.effects.first(where: {
                  $0.effect == effect.key
              }),
              pairStep.fullFrameOutputWriteCount == product.graph.nodes.count,
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

        return product.graph.nodes.allSatisfy { node in
            node.effect == effect.key
                && node.kind == .material
                && node.target == effect.output
                && node.commandSource == nil
                && node.commandTarget == nil
                && node.bindings.allSatisfy({ $0.texture == effect.input })
        }
    }

    /// Dedicated stages consume the same launch-scoped producer catalog as
    /// Program-backed materials. A typed plan may retain a dynamic target, but
    /// it cannot obtain execution ownership until exactly one proven producer
    /// family publishes that target.
    private static func dedicatedDynamicTargetsAreExecutable(
        _ program: SceneEffectStageProgram,
        producers: DynamicProducerCatalog
    ) -> Bool {
        let userTargets = Set(producers.userProperties.map(\.target))
        let available = userTargets
            .union(producers.timelineTargets)
            .union(producers.sceneScriptTargets)
        return program.executionPlan.liveConsumerTargets.isSubset(of: available)
    }

    private static func externallyOwnedImageBlendProgram(
        for effectKey: Graph.EffectKey,
        ownership: SceneResolvedMaterialDependencyOwnership,
        programsByKey: [Graph.EffectKey: [SceneEffectStageProgram]]
    ) -> SceneEffectStageProgram? {
        guard case let .externalPrimary(binding) = ownership,
              binding.kind == .imageLayerBlend,
              binding.consumerLayerID == effectKey.layerID,
              binding.slot.effectID == effectKey.descriptorID,
              binding.slot.passIndex == 0,
              binding.slot.slotIndex == 1,
              binding.blendMode == 0,
              let programs = programsByKey[effectKey],
              programs.count == 1,
              let program = programs.first,
              let blend = program.executionPlan.blend,
              blend.layerID == binding.consumerLayerID,
              blend.effectKey == effectKey,
              blend.dependencyProviderLayerID == binding.providerLayerID else {
            return nil
        }
        return program
    }

    private static func dependencyOwnershipMatches(
        _ ownership: SceneResolvedMaterialDependencyOwnership,
        layerID: Int,
        stages: [StageCapability]
    ) -> Bool {
        let resolvedDependencyStages = stages.flatMap {
            resolvedExternalDependencies(in: $0)
        }
        let proceduralDependencyStages = stages.compactMap { stage -> (
            program: SceneEffectStageProgram,
            plan: SceneProceduralNoiseExecutionPlan
        )? in
            guard case let .dedicated(_, program, _) = stage,
                  let plan = program.executionPlan.proceduralNoise,
                  plan.dependencyProviderLayerID != nil
                    || plan.dependencySlotIndex != nil else { return nil }
            return (program, plan)
        }
        let imageBlendDependencyStages = stages.compactMap { stage -> (
            program: SceneEffectStageProgram,
            plan: SceneBlendExecutionPlan
        )? in
            guard case let .dedicated(_, program, _) = stage,
                  let plan = program.executionPlan.blend,
                  plan.dependencyProviderLayerID != nil else { return nil }
            return (program, plan)
        }
        switch ownership {
        case .none, .graphInternal:
            return resolvedDependencyStages.isEmpty
                && proceduralDependencyStages.isEmpty
                && imageBlendDependencyStages.isEmpty

        case let .externalPrimary(binding):
            guard binding.consumerLayerID == layerID else { return false }
            if !resolvedDependencyStages.isEmpty,
               proceduralDependencyStages.isEmpty,
               imageBlendDependencyStages.isEmpty {
                let expected = Set(binding.referenceSlots.map { slot in
                    ResolvedExternalDependency(
                        consumerLayerID: binding.consumerLayerID,
                        providerLayerID: binding.providerLayerID,
                        slot: slot
                    )
                })
                guard expected.count == binding.referenceSlots.count,
                      Set(resolvedDependencyStages) == expected else { return false }
                return true
            }
            guard resolvedDependencyStages.isEmpty else { return false }
            switch binding.kind {
            case .resolvedMaterial:
                return false

            case .proceduralNoiseLayer:
                guard binding.slot.passIndex == 0,
                      binding.slot.slotIndex == 3,
                      binding.blendMode == 0,
                      imageBlendDependencyStages.isEmpty,
                      proceduralDependencyStages.count == 1,
                      let procedural = proceduralDependencyStages.first else {
                    return false
                }
                let program = procedural.program
                let plan = procedural.plan
                return program.effectKey == plan.effectKey
                    && program.inputRole == .layerSource
                    && program.stageGraph.effects.first?.key == plan.effectKey
                    && plan.layerID == layerID
                    && plan.effectKey.layerID == layerID
                    && plan.effectKey.descriptorID == binding.slot.effectID
                    && plan.variant == .worleyColorV1
                    && plan.dependencyProviderLayerID == binding.providerLayerID
                    && plan.dependencySlotIndex == binding.slot.slotIndex
                    && plan.renderGraph.effects.count == 1
                    && plan.renderGraph.nodes.count == 1
                    && plan.renderGraph.renderTargets.isEmpty
                    && plan.renderGraph.nodes.first?.instancePassIndex
                        == binding.slot.passIndex
            case .imageLayerBlend:
                guard binding.slot.passIndex == 0,
                      binding.slot.slotIndex == 1,
                      binding.blendMode == 0,
                      proceduralDependencyStages.isEmpty,
                      imageBlendDependencyStages.count == 1,
                      let blend = imageBlendDependencyStages.first else {
                    return false
                }
                let program = blend.program
                let plan = blend.plan
                return program.effectKey == plan.effectKey
                    && program.stageGraph.effects.first?.key == plan.effectKey
                    && plan.layerID == layerID
                    && plan.effectKey.layerID == layerID
                    && plan.effectKey.descriptorID == binding.slot.effectID
                    && plan.dependencyProviderLayerID == binding.providerLayerID
                    && plan.renderGraph.effects.count == 1
                    && plan.renderGraph.nodes.count == 1
                    && plan.renderGraph.renderTargets.isEmpty
                    && plan.renderGraph.nodes.first?.instancePassIndex
                        == binding.slot.passIndex
            }
        }
    }

    private struct ResolvedExternalDependency: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
    }

    private struct ResolvedNamedCandidate {
        let key: MaterialKey
        let slot: Int
        let reference: SceneNamedTextureReference
    }

    private static func resolvedExternalDependencies(
        in stage: StageCapability
    ) -> [ResolvedExternalDependency] {
        guard case let .resolved(product, materials) = stage else { return [] }
        var namedCandidates: [ResolvedNamedCandidate] = []
        for material in materials.values {
            for slot in material.template.textureSlots.compactMap({ $0 }) {
                guard let selected = slot.candidates.last,
                      case let .provider(.namedLayerTarget(reference)) =
                        selected.reference else { continue }
                namedCandidates.append(.init(
                    key: material.key,
                    slot: slot.index,
                    reference: reference
                ))
            }
        }
        guard let candidate = namedCandidates.first,
              candidate.reference.variant == SceneNamedTextureReference.Variant.primary,
              candidate.key.effect.layerID == product.graph.layerID,
              namedCandidates.allSatisfy({ item in
                  item.reference.variant == .primary
                      && item.reference.providerLayerID
                          == candidate.reference.providerLayerID
              }) else { return [] }
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
                  let passIndex = nodeMatches.first?.instancePassIndex else { return [] }
            result.append(.init(
                consumerLayerID: item.key.effect.layerID,
                providerLayerID: item.reference.providerLayerID,
                slot: .init(
                    effectID: item.key.effect.descriptorID,
                    passIndex: passIndex,
                    slotIndex: item.slot
                )
            ))
        }
        guard Set(result).count == result.count else { return [] }
        return result
    }
}
