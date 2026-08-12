import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    /// Compiles each authored stage through Program first. A typed backend may
    /// fill only the exact stage whose Program compilation failed.
    static func compileProgramFirstStages(
        _ admitted: SceneResolvedMaterialAdmittedLayer,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssueKeys: Set<MaterialKey>,
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
            let singleStage = SceneResolvedMaterialAdmittedLayer(
                layerID: admitted.layerID,
                products: [product],
                pairPlan: admitted.pairPlan,
                dependencyOwnership: admitted.dependencyOwnership,
                sourceRoute: admitted.sourceRoute
            )
            let programResult = compileStages(
                singleStage,
                materialCatalog: materialCatalog,
                demandIssueKeys: demandIssueKeys,
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
                    return .failure(programFailure)
                }
                let pairLeaf = dedicatedLeafKeys.contains(effect.key)
                    && program.executionPlan.logicalRenderTargetCount == 0
                    && product.graph.nodes.count == 1
                    && product.graph.renderTargets.isEmpty
                let logicalTargetStage = dedicatedGraphStageKeys.contains(effect.key)
                    && program.executionPlan.supportsUnifiedLogicalTargetStage
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
                guard pairLeaf || logicalTargetStage || fullFrameComposeStage,
                      program.effectKey == effect.key,
                      program.stageGraph.effects.first?.key == effect.key,
                      admitted.sourceRoute != .capturedMainTargetTexture
                        || ((pairLeaf || logicalTargetStage)
                            && program.executionPlan.supportsUtilityCapture) else {
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
        switch ownership {
        case .none, .graphInternal:
            return clippingStages.isEmpty && proceduralDependencyStages.isEmpty

        case let .externalPrimary(binding):
            guard binding.consumerLayerID == layerID else { return false }
            switch binding.kind {
            case .clippingMask:
                guard binding.slot.slotIndex == 1,
                      clippingStages.count == 1,
                      proceduralDependencyStages.isEmpty,
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
            }
        }
    }
}
