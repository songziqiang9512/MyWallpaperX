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
            guard let attachmentStorage = attachmentStorage(
                for: node,
                in: product.graph
            ) else { return .failure(rejection("material-target-storage-unproven")) }
            materials[key] = .init(
                key: key,
                template: template,
                variants: variants,
                attachmentStorage: attachmentStorage
            )
        }
        guard !materials.isEmpty else {
            return .failure(rejection("material-capability-empty"))
        }
        guard r8ScalarGraphIsExecutable(product.graph, materials: materials) else {
            return .failure(rejection("r8-scalar-graph-unproven"))
        }
        return .success(materials)
    }

    private static func attachmentStorage(
        for node: Graph.Node,
        in graph: Graph
    ) -> SceneResolvedMaterialAttachmentKind? {
        guard let target = node.target else { return nil }
        switch target.kind {
        case .effectOutput:
            return .color
        case .framebuffer:
            let declarations = graph.renderTargets.filter { $0.texture == target }
            guard declarations.count == 1,
                  let descriptor = SceneGraphRenderTargetPlan.targetDescriptor(
                      declarations[0],
                      inputWidth: 1,
                      inputHeight: 1
                  ) else { return nil }
            switch descriptor.format {
            case .r8:
                return .scalarRedUnorm
            case .rgbaBackbuffer, .rgba8888:
                return .color
            }
        case .layerSource, .unresolved:
            return nil
        }
    }

    /// R8 becomes a product capability only as one complete producer ->
    /// scalar publication -> red-only consumer atom. Clear/history/commands
    /// remain closed until their scalar lifecycle semantics are proven.
    private static func r8ScalarGraphIsExecutable(
        _ graph: Graph,
        materials: [MaterialKey: MaterialCapability]
    ) -> Bool {
        let targets = graph.renderTargets.filter {
            $0.format?.lowercased() == "r8"
        }
        guard !targets.isEmpty else { return true }
        for target in targets {
            guard let descriptor = SceneGraphRenderTargetPlan.targetDescriptor(
                target,
                inputWidth: 1,
                inputHeight: 1
            ), descriptor.format == .r8,
              !descriptor.isUnique,
              descriptor.initialClear == nil else { return false }
            let writers = graph.nodes.filter {
                $0.kind == .material && $0.target == target.texture
            }
            let readers = graph.nodes.filter { node in
                node.kind == .material
                    && node.bindings.contains { $0.texture == target.texture }
            }
            guard writers.count == 1,
                  let writer = writers.first,
                  materials[.init(
                      effect: writer.effect,
                      nodeIndex: writer.nodeIndex
                  )]?.attachmentStorage == .scalarRedUnorm,
                  !readers.isEmpty,
                  readers.allSatisfy({ $0.nodeIndex > writer.nodeIndex }),
                  graph.nodes.allSatisfy({ node in
                      node.commandSource != target.texture
                          && node.commandTarget != target.texture
                  }) else { return false }
            for reader in readers {
                let bindings = reader.bindings.filter {
                    $0.texture == target.texture
                }
                guard !bindings.isEmpty,
                      bindings.allSatisfy({ binding in
                          guard let slot = binding.slot,
                                let material = materials[.init(
                                    effect: reader.effect,
                                    nodeIndex: reader.nodeIndex
                                )] else { return false }
                          return material.variants.provesRedOnlyConsumer(slot: slot)
                      }) else { return false }
            }
        }
        return true
    }
}
