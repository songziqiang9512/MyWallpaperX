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
            return plan.xRay != nil
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
        var capturedMainSourceConsumerCount = 0
        var firstCapturedMainMaterial: (node: Graph.Node, template: Template)?
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
                return .failure(envelopeRejection(
                    envelope,
                    node: node,
                    template: template
                ))
            }
            if case let .failure(failure) = variants.precompileLaunchEnvelope(
                implicitFramebufferIdentity: effect.input,
                outputStorage: outputStorage(for: attachment.storage),
                outputIsRGBA8Unorm:
                    attachment.storage == .color
                        && attachment.format == .rgba8888,
                graphTextureFormatFacts: graphTextureFormatFacts,
                assetStates: assetStates
            ) {
                SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics
                    .launchEnvelopeFailure(template: template, failure: failure)
                if case let .material(materialFailure) = failure,
                   materialFailure.code == .genericProductOwnerDeferred {
                    return .failure(envelopeRejection(
                        failure,
                        node: node,
                        template: template,
                        reasonCode:
                            "material-generic-incumbent-owner-deferred"
                    ))
                }
                if case let .material(materialFailure) = failure,
                   materialFailure.mapsToGenericOwnerRevokedVisualFailure {
                    return .failure(envelopeRejection(
                        failure,
                        node: node,
                        template: template,
                        reasonCode: "material-generic-owner-revoked"
                    ))
                }
                return .failure(envelopeRejection(
                    failure,
                    node: node,
                    template: template
                ))
            }
            guard let activeTextureSlots = variants.launchEnvelopeActiveTextureSlots else {
                return .failure(rejection("material-variant-envelope-invariant"))
            }
            if firstCapturedMainMaterial == nil {
                firstCapturedMainMaterial = (node, template)
            }
            let activeDemandIssues = demandIssues.filter {
                $0.key == key && activeTextureSlots.contains($0.slot)
            }
            if !activeDemandIssues.isEmpty {
                SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics
                    .materialTemplateFailure(node: node, reason: "active-resource-demand")
                guard let reasonCode = activeDemandIssueReasonCode(
                    activeDemandIssues
                ) else {
                    return .failure(rejection("material-variant-envelope-invariant"))
                }
                return .failure(rejection(reasonCode))
            }
            if sourceRoute == .transparentDirectDraw,
               !variants.supportsTransparentDirectDraw {
                return .failure(sourceRouteRejection(
                    "direct-draw-source-dependent",
                    cause: .directDrawSourceDependent,
                    node: node,
                    template: template
                ))
            }
            if sourceRoute == .capturedMainTargetTexture {
                if variants.capturedMainTargetSourceSlot(
                    node: node,
                    effect: effect
                ) != nil {
                    capturedMainSourceConsumerCount += 1
                } else if !variants.supportsCapturedMainTargetInternalProgram(
                    node: node,
                    effect: effect
                ) {
                    return .failure(sourceRouteRejection(
                        "utility-source-program-unsupported",
                        cause: .capturedMainTargetTextureUnsupported,
                        node: node,
                        template: template
                    ))
                }
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
        if sourceRoute == .capturedMainTargetTexture,
           capturedMainSourceConsumerCount == 0 {
            guard let first = firstCapturedMainMaterial else {
                return .failure(rejection("utility-source-program-unsupported"))
            }
            return .failure(sourceRouteRejection(
                "utility-source-program-unsupported",
                cause: .capturedMainTargetTextureUnsupported,
                node: first.node,
                template: first.template
            ))
        }
        if let failure = preservedChannelGraphRejection(
            product.graph,
            materials: materials
        ) {
#if DEBUG
            print(failure.reportLine)
#endif
            return .failure(rejection(failure.reasonCode))
        }
        return .success(materials)
    }

    private static func activeDemandIssueReasonCode(
        _ issues: Set<SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue>
    ) -> String? {
        guard !issues.isEmpty else { return nil }
        if issues.contains(where: { $0.code == .samplerSchemaUnavailable }) {
            return "material-variant-envelope-sampler-schema"
        }
        guard issues.allSatisfy({ $0.code == .purposeUnproven }) else { return nil }
        return "material-variant-envelope-texture-purpose"
    }

    private static func envelopeRejection(
        _ failure: SceneResolvedMaterialVariantCache.LaunchEnvelopeFailure,
        node: Graph.Node,
        template: Template,
        reasonCode: String? = nil
    ) -> Rejection {
        let code = reasonCode
            ?? "material-variant-envelope-\(failure.kind.rawValue)"
        return rejection(
            code,
            programFailureAttribution: .init(
                effect: node.effect,
                nodeIndex: node.nodeIndex,
                materialPath: node.materialPath ?? "<missing>",
                materialPassID: node.materialPassID ?? "<missing>",
                shaderPath: template.diagnosticProvenance.authoredShaderPath,
                reasonCode: code,
                cause: .launchEnvelope(failure)
            )
        )
    }

    private static func sourceRouteRejection(
        _ code: String,
        cause: Rejection.ProgramFailureAttribution.SourceRouteFailure,
        node: Graph.Node,
        template: Template
    ) -> Rejection {
        rejection(
            code,
            programFailureAttribution: .init(
                effect: node.effect,
                nodeIndex: node.nodeIndex,
                materialPath: node.materialPath ?? "<missing>",
                materialPassID: node.materialPassID ?? "<missing>",
                shaderPath: template.diagnosticProvenance.authoredShaderPath,
                reasonCode: code,
                cause: .sourceRoute(cause)
            )
        )
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

}
