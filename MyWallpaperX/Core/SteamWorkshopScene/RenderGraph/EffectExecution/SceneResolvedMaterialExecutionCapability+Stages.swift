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
        maximumVariantsPerMaterial: Int
    ) -> Result<CompiledStages, Rejection> {
        guard (1 ... 256).contains(maximumVariantsPerMaterial) else {
            return .failure(rejection("material-variant-envelope-capacity"))
        }

        var stages: [StageCapability] = []
        var allMaterials: [MaterialKey: MaterialCapability] = [:]
        for product in admitted.products {
            guard product.graph.effects.first != nil else {
                return .failure(rejection("stage-effect-identity-missing"))
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
                return .failure(failure)
            case .success(let materials):
                allMaterials.merge(materials) { _, replacement in replacement }
                stages.append(.resolved(product: product, materials: materials))
            }
        }

        guard !stages.isEmpty,
              stages.count == admitted.products.count else {
            return .failure(rejection("resolved-stage-empty"))
        }
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
