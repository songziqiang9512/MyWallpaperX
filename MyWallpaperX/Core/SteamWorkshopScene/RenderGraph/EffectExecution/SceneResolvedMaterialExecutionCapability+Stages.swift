import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    struct CompiledStages {
        let stages: [StageCapability]
        let materials: [MaterialKey: MaterialCapability]
    }

    static func compileStages(
        _ admitted: SceneResolvedMaterialAdmittedLayer,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssueKeys: Set<MaterialKey>,
        dynamicProducers: DynamicProducerCatalog,
        assetFormatFacts: [String: Int],
        dedicatedStagePrograms: [SceneEffectStageProgram],
        dedicatedStageFamilies: [Graph.EffectKey: String],
        dedicatedLeafKeys: Set<Graph.EffectKey>,
        maximumVariantsPerMaterial: Int
    ) -> Result<CompiledStages, Rejection> {
        guard (1 ... 256).contains(maximumVariantsPerMaterial) else {
            return .failure(rejection("material-variant-envelope-capacity"))
        }
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
            let dedicatedProgram = programsByKey[effect.key]?.first
            if let program = dedicatedProgram,
               dedicatedLeafKeys.contains(effect.key) {
                guard program.effectKey == effect.key,
                      program.stageGraph.effects.first?.key == effect.key,
                      program.executionPlan.logicalRenderTargetCount == 0,
                      admitted.sourceRoute != .capturedMainTargetTexture
                        || program.executionPlan.supportsUtilityCapture,
                      product.graph.renderTargets.isEmpty else {
                    return .failure(rejection("dedicated-leaf-unsupported"))
                }
                stages.append(.dedicated(
                    product: product,
                    program: program,
                    family: dedicatedStageFamilies[effect.key] ?? "dedicated-leaf"
                ))
                continue
            }
            if let program = dedicatedProgram,
               !program.executionPlan.yieldsToResolvedMaterialProgram {
                return .failure(rejection("dedicated-leaf-unsupported"))
            }

            switch compileMaterials(
                product,
                materialCatalog: materialCatalog,
                demandIssueKeys: demandIssueKeys,
                dynamicProducers: dynamicProducers,
                assetFormatFacts: assetFormatFacts,
                existingKeys: Set(allMaterials.keys),
                sourceRoute: admitted.sourceRoute,
                maximumVariantsPerMaterial: maximumVariantsPerMaterial
            ) {
            case .failure(let failure):
                if dedicatedProgram != nil {
                    return .failure(rejection("dedicated-leaf-unsupported"))
                }
                return .failure(failure)
            case .success(let materials):
                allMaterials.merge(materials) { _, replacement in replacement }
                stages.append(.resolved(product: product, materials: materials))
            }
        }

        guard let firstStage = stages.first,
              case .resolved = firstStage else {
            return .failure(rejection("mixed-chain-resolved-prefix-required"))
        }
        guard stages.count == admitted.products.count,
              stages.contains(where: { if case .resolved = $0 { true } else { false } })
        else { return .failure(rejection("resolved-stage-empty")) }
        return .success(.init(stages: stages, materials: allMaterials))
    }

    private static func compileMaterials(
        _ product: SceneGraphAdmissionProduct,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssueKeys: Set<MaterialKey>,
        dynamicProducers: DynamicProducerCatalog,
        assetFormatFacts: [String: Int],
        existingKeys: Set<MaterialKey>,
        sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute,
        maximumVariantsPerMaterial: Int
    ) -> Result<[MaterialKey: MaterialCapability], Rejection> {
        guard let effect = product.graph.effects.first else {
            return .failure(rejection("material-template-unsupported"))
        }
        var materials: [MaterialKey: MaterialCapability] = [:]
        for node in product.graph.nodes {
            guard case .material = node.kind else { continue }
            let key = MaterialKey(effect: node.effect, nodeIndex: node.nodeIndex)
            guard let template =
                    SceneResolvedMaterialExecutionCapabilityTemplateAdmission.resolve(
                        node: node,
                        effect: effect,
                        key: key,
                        materialCatalog: materialCatalog,
                        demandIssueKeys: demandIssueKeys,
                        existingKeys: existingKeys.union(materials.keys)
                    ) else {
                return .failure(rejection("material-template-unsupported"))
            }
            guard let variants = SceneResolvedMaterialVariantCache(
                template: template,
                maximumVariantCount: maximumVariantsPerMaterial,
                assetFormatFacts: assetFormatFacts
            ) else {
                SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics
                    .variantSchemaFailure(template: template)
                return .failure(rejection("material-variant-envelope-sampler-schema"))
            }
            if case let .failure(failure) = variants.precompileLaunchEnvelope(
                implicitFramebufferIdentity: effect.input
            ) {
                SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics
                    .launchEnvelopeFailure(template: template, failure: failure)
                return .failure(rejection(
                    "material-variant-envelope-\(failure.kind.rawValue)"
                ))
            }
            if sourceRoute == .transparentDirectDraw,
               !variants.supportsTransparentDirectDraw {
                return .failure(rejection("direct-draw-source-dependent"))
            }
            if sourceRoute == .capturedMainTargetTexture,
               !variants.hasAudioSpectrumConsumer {
                return .failure(rejection("utility-source-program-unsupported"))
            }
            guard dynamicUniformsAreExecutable(
                template,
                node: node,
                producers: dynamicProducers
            ) else { return .failure(rejection("dynamic-uniform-unavailable")) }
            materials[key] = .init(key: key, template: template, variants: variants)
        }
        guard !materials.isEmpty else {
            return .failure(rejection("material-capability-empty"))
        }
        return .success(materials)
    }
}
