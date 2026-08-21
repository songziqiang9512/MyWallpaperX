import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability {
    var requiresInvertibleEffectTextureProjection: Bool {
        switch self {
        case .resolved(_, let materials):
            return materials.values.contains {
                $0.variants.requiresInvertibleEffectTextureProjection
            }
        case .dedicated(_, let program, _):
            let plan = program.executionPlan
            return plan.depthParallax != nil
                || plan.xRay != nil
        case .visualFailurePassthrough:
            return false
        }
    }
}

extension SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability {
    var requiresInvertibleEffectTextureProjection: Bool {
        stages.contains(where: \.requiresInvertibleEffectTextureProjection)
    }
}

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    struct CompiledStages {
        let stages: [StageCapability]
        let materials: [MaterialKey: MaterialCapability]
        let sceneBackgroundRequirement: SceneBackgroundRequirement?
    }

    static func compileStages(
        _ admitted: SceneResolvedMaterialAdmittedLayer,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssues: Set<SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue>,
        dynamicProducers: DynamicProducerCatalog,
        assetFormatFacts: [String: Int],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
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
                demandIssues: demandIssues,
                dynamicProducers: dynamicProducers,
                assetFormatFacts: assetFormatFacts,
                assetStates: assetStates,
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
        return .success(.init(
            stages: stages,
            materials: allMaterials,
            sceneBackgroundRequirement: nil
        ))
    }

    private static func compileMaterials(
        _ product: SceneGraphAdmissionProduct,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssues: Set<SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue>,
        dynamicProducers: DynamicProducerCatalog,
        assetFormatFacts: [String: Int],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        existingKeys: Set<MaterialKey>,
        sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute,
        maximumVariantsPerMaterial: Int
    ) -> Result<[MaterialKey: MaterialCapability], Rejection> {
        guard let effect = product.graph.effects.first else {
            return .failure(rejection("material-template-unsupported"))
        }
        guard let graphTextureFormatFacts = graphTextureFormatFacts(
            in: product.graph
        ) else {
            return .failure(rejection("material-target-storage-unproven"))
        }
        let preservedRGBADataTargets = preservedRGBADataTargets(in: product.graph)
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
                        existingKeys: existingKeys.union(materials.keys)
                    ) else {
                return .failure(rejection("material-template-unsupported"))
            }
            guard let attachment = attachment(
                for: node,
                in: product.graph,
                preservedRGBADataTargets: preservedRGBADataTargets
            ) else { return .failure(rejection("material-target-storage-unproven")) }
            let variants: SceneResolvedMaterialVariantCache
            switch SceneResolvedMaterialVariantCache.launchValidated(
                template: template,
                maximumVariantCount: maximumVariantsPerMaterial,
                assetFormatFacts: assetFormatFacts
            ) {
            case let .success(value):
                variants = value
            case let .failure(failure):
                let envelope = SceneResolvedMaterialVariantCache
                    .LaunchEnvelopeFailure.material(failure)
                SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics
                    .launchEnvelopeFailure(template: template, failure: envelope)
                return .failure(rejection(
                    "material-variant-envelope-\(envelope.kind.rawValue)"
                ))
            }
            if case let .failure(failure) = variants.precompileLaunchEnvelope(
                implicitFramebufferIdentity: effect.input,
                outputStorage: outputStorage(for: attachment.storage),
                graphTextureFormatFacts: graphTextureFormatFacts,
                assetStates: assetStates
            ) {
                SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics
                    .launchEnvelopeFailure(template: template, failure: failure)
                if case let .material(materialFailure) = failure,
                   materialFailure.boundedDetails.contains(
                       "bounded-frontend-owner-revoked"
                   ) {
                    return .failure(rejection("material-generic-owner-revoked"))
                }
                return .failure(rejection(
                    "material-variant-envelope-\(failure.kind.rawValue)"
                ))
            }
            guard let activeTextureSlots = variants.launchEnvelopeActiveTextureSlots else {
                return .failure(rejection("material-variant-envelope-invariant"))
            }
            let activeDemandIssues = demandIssues.filter {
                $0.key == key && activeTextureSlots.contains($0.slot)
            }
            guard activeDemandIssues.isEmpty else {
                SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics
                    .materialTemplateFailure(node: node, reason: "active-resource-demand")
                return .failure(rejection(
                    "material-variant-envelope-texture-purpose"
                ))
            }
            if sourceRoute == .transparentDirectDraw,
               !variants.supportsTransparentDirectDraw {
                return .failure(rejection("direct-draw-source-dependent"))
            }
            if sourceRoute == .capturedMainTargetTexture,
               !variants.supportsCapturedMainTargetTexture {
                return .failure(rejection("utility-source-program-unsupported"))
            }
            if let failure = dynamicUniformExecutionRejection(
                template,
                node: node,
                producers: dynamicProducers
            ) {
                return .failure(failure)
            }
            materials[key] = .init(
                key: key,
                template: template,
                variants: variants,
                attachmentStorage: attachment.storage,
                targetFormat: attachment.format
            )
        }
        guard !materials.isEmpty else {
            return .failure(rejection("material-capability-empty"))
        }
        guard preservedChannelGraphIsExecutable(
            product.graph,
            materials: materials
        ) else {
            let reasonCode = product.graph.renderTargets.compactMap { target in
                switch target.format?.lowercased() {
                case "r8": "r8-scalar-graph-unproven"
                case "rg88": "rg88-red-green-graph-unproven"
                case "r16f": "r16f-scalar-graph-unproven"
                case "rg1616f": "rg1616f-red-green-graph-unproven"
                default: nil
                }
            }.first ?? "preserved-channel-graph-unproven"
            return .failure(rejection(reasonCode))
        }
        return .success(materials)
    }

    private static func graphTextureFormatFacts(
        in graph: Graph
    ) -> [Graph.TextureIdentity: SceneShaderTextureFormat]? {
        var seen = Set<Graph.TextureIdentity>()
        var result: [Graph.TextureIdentity: SceneShaderTextureFormat] = [:]
        for target in graph.renderTargets {
            guard seen.insert(target.texture).inserted,
                  let descriptor = SceneGraphRenderTargetPlan.targetDescriptor(
                      target,
                      inputWidth: 1,
                      inputHeight: 1
                  ) else { return nil }
            switch descriptor.format {
            case .r8: result[target.texture] = .r8
            case .rg88: result[target.texture] = .rg88
            case .r16f: result[target.texture] = .r16f
            case .rg1616f: result[target.texture] = .rg1616f
            case .rgbaBackbuffer, .rgba8888: break
            }
        }
        return result
    }

    private static func attachment(
        for node: Graph.Node,
        in graph: Graph,
        preservedRGBADataTargets: Set<Graph.TextureIdentity>
    ) -> (
        storage: SceneResolvedMaterialAttachmentKind,
        format: SceneGraphRenderTargetPlan.TextureFormat
    )? {
        guard let target = node.target else { return nil }
        switch target.kind {
        case .effectOutput:
            return (.color, .rgbaBackbuffer)
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
                return (.scalarRedUnorm, .r8)
            case .rg88:
                return (.redGreenUnorm, .rg88)
            case .r16f:
                return (.scalarRedFloat16, .r16f)
            case .rg1616f:
                return (.redGreenFloat16, .rg1616f)
            case .rgbaBackbuffer, .rgba8888:
                return (
                    preservedRGBADataTargets.contains(target)
                        ? .preservedRGBAUnorm : .color,
                    descriptor.format
                )
            }
        case .layerSource, .unresolved:
            return nil
        }
    }

    private static func outputStorage(
        for attachment: SceneResolvedMaterialAttachmentKind
    ) -> SceneResolvedMaterialVariantCache.OutputStorage {
        switch attachment {
        case .color: .color
        case .scalarRedUnorm: .scalarRedUnorm
        case .redGreenUnorm: .redGreenUnorm
        case .scalarRedFloat16: .scalarRedFloat16
        case .redGreenFloat16: .redGreenFloat16
        case .preservedRGBAUnorm: .preservedRGBAUnorm
        }
    }

    /// Finds the smallest framebuffer dependency component rooted in an
    /// authored first-read-before-write RGBA8 target. The result is only a
    /// candidate storage fact: Program compilation must independently prove a
    /// whole-output raw-data shader contract before it can execute.
    private static func preservedRGBADataTargets(
        in graph: Graph
    ) -> Set<Graph.TextureIdentity> {
        SceneGraphRenderTargetPlan
            .boundedFeedbackHistoryProfile(in: graph)?.stateTargets ?? []
    }

    /// Preserved-channel targets become product capability only as one complete
    /// producer -> typed publication -> exact-channel consumer atom. Clear,
    /// history, commands and unique targets remain closed until their distinct
    /// lifecycle semantics are proven.
    private static func preservedChannelGraphIsExecutable(
        _ graph: Graph,
        materials: [MaterialKey: MaterialCapability]
    ) -> Bool {
        let targets = graph.renderTargets.filter {
            ["r8", "rg88", "r16f", "rg1616f"]
                .contains($0.format?.lowercased() ?? "")
        }
        guard !targets.isEmpty else { return true }
        for target in targets {
            guard let descriptor = SceneGraphRenderTargetPlan.targetDescriptor(
                target,
                inputWidth: 1,
                inputHeight: 1
            ), [.r8, .rg88, .r16f, .rg1616f].contains(descriptor.format),
              !descriptor.isUnique,
              descriptor.initialClear == nil else { return false }
            let expectedStorage: SceneResolvedMaterialAttachmentKind
            switch descriptor.format {
            case .r8: expectedStorage = .scalarRedUnorm
            case .rg88: expectedStorage = .redGreenUnorm
            case .r16f: expectedStorage = .scalarRedFloat16
            case .rg1616f: expectedStorage = .redGreenFloat16
            case .rgbaBackbuffer, .rgba8888: return false
            }
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
                  )]?.attachmentStorage == expectedStorage,
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
                          return descriptor.format == .r8
                              || descriptor.format == .r16f
                              ? material.variants.provesRedOnlyConsumer(slot: slot)
                              : material.variants.provesRedGreenOnlyConsumer(slot: slot)
                      }) else { return false }
            }
        }
        return true
    }
}
