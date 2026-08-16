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
        return .success(.init(stages: stages, materials: allMaterials))
    }

    /// Only a launch-time shader/frontend/color or static uniform-schema
    /// failure may become a visual no-op. Dynamic producer availability,
    /// resource, target, dependency, state and lifecycle failures remain hard
    /// rejections. The admitted effect must be one current-in/current-out leaf
    /// so an exact full-frame copy preserves the previous current without
    /// fabricating an authored texture, uniform value or graph resource.
    private static func visualFailureMayPassthrough(
        _ failure: Rejection,
        product: SceneGraphAdmissionProduct,
        pairPlan: SceneLayerFullFramePairPlan,
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership
    ) -> Bool {
        guard [
            "material-variant-envelope-frontend",
            "material-variant-envelope-shader-preparation",
            "material-variant-envelope-color-contract",
            "material-variant-envelope-uniform-schema",
        ].contains(failure.code),
              dependencyOwnership == .none,
              product.graph.effects.count == 1,
              product.graph.nodes.count == 1,
              product.graph.renderTargets.isEmpty,
              product.graph.blockers.isEmpty,
              let effect = product.graph.effects.first,
              let node = product.graph.nodes.first,
              node.effect == effect.key,
              node.kind == .material,
              node.target == effect.output,
              node.bindings.allSatisfy({ $0.texture == effect.input }),
              let pairStep = pairPlan.effects.first(where: {
                  $0.effect == effect.key
              }),
              pairStep.inputMember != pairStep.outputMember,
              pairStep.composeTransitionCount == 0 else { return false }
        return true
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
        let clippingStages = stages.compactMap { stage -> (
            program: SceneEffectStageProgram,
            plan: SceneClippingMaskExecutionPlan
        )? in
            guard case let .dedicated(_, program, _) = stage,
                  let plan = program.executionPlan.clippingMask else { return nil }
            return (program, plan)
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
            return clippingStages.isEmpty
                && proceduralDependencyStages.isEmpty
                && imageBlendDependencyStages.isEmpty

        case let .externalPrimary(binding):
            guard binding.consumerLayerID == layerID else { return false }
            switch binding.kind {
            case .clippingMask:
                guard binding.slot.slotIndex == 1,
                      clippingStages.count == 1,
                      proceduralDependencyStages.isEmpty,
                      imageBlendDependencyStages.isEmpty,
                      let clipping = clippingStages.first else { return false }
                let program = clipping.program
                let plan = clipping.plan
                return program.effectKey == plan.effectKey
                    && program.stageGraph.effects.first?.key == plan.effectKey
                    && plan.layerID == layerID
                    && plan.effectKey.layerID == layerID
                    && plan.effectKey.descriptorID == binding.slot.effectID
                    && plan.providerLayerID == binding.providerLayerID
                    && plan.blendMode == binding.blendMode
                    && plan.renderGraph.effects.count == 1
                    && plan.renderGraph.nodes.count == 1
                    && plan.renderGraph.nodes.first?.instancePassIndex
                        == binding.slot.passIndex

            case .proceduralNoiseLayer:
                guard binding.slot.passIndex == 0,
                      binding.slot.slotIndex == 3,
                      binding.blendMode == 0,
                      clippingStages.isEmpty,
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
                      clippingStages.isEmpty,
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
}
