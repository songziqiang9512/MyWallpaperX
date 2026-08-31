import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability {
    var product: SceneGraphAdmissionProduct {
        switch self {
        case .resolved(let product, _, _): product
        case .visualFailurePassthrough(let product, _),
             .initiallyInactivePassthrough(let product, _):
            product
        }
    }

    var activationPolicy: SceneResolvedMaterialStageActivationPolicy? {
        guard case let .resolved(_, _, activation) = self else { return nil }
        return activation
    }

    var subject: SceneEffectExactRuntimeSubject? {
        guard let key = product.graph.effects.first?.key else { return nil }
        switch self {
        case .resolved:
            return .init(key: key, family: "resolved-material")
        case .visualFailurePassthrough:
            return .init(key: key, family: "visual-failure-passthrough")
        case .initiallyInactivePassthrough:
            return .init(key: key, family: "initially-inactive-passthrough")
        }
    }

    var visualFailureReasonCode: String? {
        guard case let .visualFailurePassthrough(_, reasonCode) = self else {
            return nil
        }
        return reasonCode
    }

    var initiallyInactivePassthroughReasonCode: String? {
        guard case let .initiallyInactivePassthrough(_, reasonCode) = self else {
            return nil
        }
        return reasonCode
    }

    var requiresInvertibleEffectTextureProjection: Bool {
        switch self {
        case .resolved(_, let materials, _):
            return materials.values.contains {
                $0.variants.requiresInvertibleEffectTextureProjection
            }
        case .visualFailurePassthrough, .initiallyInactivePassthrough:
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
    static func stageActivationPolicy(
        product: SceneGraphAdmissionProduct,
        materials: [MaterialKey: MaterialCapability],
        dynamicProducers: DynamicProducerCatalog,
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
        pairStep: SceneLayerFullFramePairPlan.EffectStep?
    ) -> SceneResolvedMaterialStageActivationPolicy? {
        guard dependencyOwnership.preEncodeVisualFailureSlots(
                  in: product.graph
              ) != nil,
              product.graph.effects.count == 1,
              let effect = product.graph.effects.first,
              product.clearFunctions.functions.isEmpty else { return nil }
        let visibilityTarget = SceneDynamicTarget.effectVisibility(
            layerID: effect.key.layerID,
            effectIndex: effect.key.effectIndex
        )
        let visibilityProducers = dynamicProducers.userProperties.filter {
            $0.target == visibilityTarget
        }
        let resolvedVisibilityTarget: SceneDynamicTarget? =
            visibilityProducers.count == 1
                && visibilityProducers.first?.valueType == .bool
                && dynamicProducers.authoredFallbackTargets.contains(
                    visibilityTarget
                )
            ? visibilityTarget : nil
        let pairLeaf = pairLeafActivationTopologyIsSupported(
            product.graph,
            effect: effect
        )
        // Reuse the already-admitted visual-failure passthrough topology: this
        // widens typed visibility activation, not graph or product ownership.
        let framebufferVisibility = resolvedVisibilityTarget != nil
            && pairStep.map {
                visualFailureFramebufferTopologyMayPassthrough(
                    product.graph,
                    effect: effect,
                    pairStep: $0
                )
            } == true
        guard pairLeaf || framebufferVisibility else { return nil }
        let pointerScalarMinimum = pairLeaf && materials.count == 1
            && materials.values.first?.variants
                .launchEnvelopeProvesSpatialWeightedPointerProvider == true
            ? spatialWeightedPointerScalarMinimum(
                effect: effect.key,
                material: materials.values.first,
                dynamicProducers: dynamicProducers
            ) : nil
        let requiresPointer = pointerScalarMinimum != nil
        guard resolvedVisibilityTarget != nil || requiresPointer else {
            return nil
        }
        return .init(
            effectVisibilityTarget: resolvedVisibilityTarget,
            effectVisibilityPropertyKey: resolvedVisibilityTarget == nil
                ? nil : visibilityProducers.first?.propertyKey,
            requiresPointerPositionProvider: requiresPointer,
            scalarMinimum: pointerScalarMinimum
        )
    }

    private static func pairLeafActivationTopologyIsSupported(
        _ graph: Graph,
        effect: Graph.Effect
    ) -> Bool {
        guard graph.nodes.count == 1,
              let node = graph.nodes.first,
              node.kind == .material,
              node.effect == effect.key,
              node.target == effect.output,
              node.compose == nil,
              node.conditions == nil,
              graph.renderTargets.isEmpty else { return false }
        return true
    }

    private static func spatialWeightedPointerScalarMinimum(
        effect: Graph.EffectKey,
        material: MaterialCapability?,
        dynamicProducers: DynamicProducerCatalog
    ) -> SceneResolvedMaterialStageActivationPolicy.ScalarMinimum? {
        guard let material else { return nil }
        let declarations = material.template.uniformDeclarations.filter {
            $0.name == "size"
        }
        guard declarations.count == 1,
              let declaration = declarations.first else { return nil }
        let target: SceneDynamicTarget?
        let fallback: Template.StaticUniformValue
        switch declaration.value {
        case let .staticExact(value):
            guard value.valueKind.localizedLowercase == "number",
                  value.authoredBindingKeys.isEmpty else { return nil }
            target = nil
            fallback = value
        case let .dynamic(dynamic):
            let expected = SceneDynamicTarget.effectConstant(
                layerID: effect.layerID,
                effectIndex: effect.effectIndex,
                passIndex: 0,
                name: "size"
            )
            guard dynamic.target == expected,
                  dynamic.valueContributors.count == 1,
                  case let .userProperty(propertyKey) =
                    dynamic.valueContributors[0],
                  dynamic.scriptAttachments.isEmpty,
                  let authored = dynamic.authoredFallback,
                  authored.valueKind.localizedLowercase == "binding",
                  SceneResolvedMaterialDirectUserBindingContract.matches(
                      dynamic: dynamic,
                      fallback: authored
                  )
            else { return nil }
            let expectedProducer = SceneDynamicUserPropertyProducer(
                propertyKey: propertyKey,
                target: expected,
                valueType: .scalar
            )
            let targetProducers = dynamicProducers.userProperties.filter {
                $0.target == expected
            }
            if targetProducers == [expectedProducer] {
                target = expected
            } else if hasAuthoredUserPropertyFallback(
                .userProperty(propertyKey),
                dynamic: dynamic,
                producers: dynamicProducers
            ) {
                target = expected
            } else {
                return nil
            }
            fallback = authored
        }
        guard fallback.componentBitPatterns.count == 1,
              let bits = fallback.componentBitPatterns.first else { return nil }
        let value = Double(bitPattern: bits)
        guard value.isFinite, (0 ... 1).contains(value) else { return nil }
        return .init(
            target: target,
            authoredFallback: value,
            authoredRange: 0 ... 1,
            minimum: 0.001
        )
    }

    static func hasAuthoredUserPropertyFallback(
        _ contributor: Template.DynamicUniformSource,
        dynamic: Template.DynamicUniform,
        producers: DynamicProducerCatalog
    ) -> Bool {
        guard case let .userProperty(propertyKey) = contributor,
              !producers.userProperties.contains(where: {
                  $0.propertyKey == propertyKey || $0.target == dynamic.target
              }),
              producers.authoredFallbackTargets.contains(dynamic.target),
              let fallback = dynamic.authoredFallback,
              fallback.valueKind.localizedLowercase == "binding",
              SceneResolvedMaterialDirectUserBindingContract.matches(
                  dynamic: dynamic,
                  fallback: fallback
              ),
              (1 ... 4).contains(fallback.componentBitPatterns.count) else {
            return false
        }
        return fallback.componentBitPatterns.allSatisfy {
            Double(bitPattern: $0).isFinite
        }
    }

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
            guard let effect = product.graph.effects.first else {
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
                let pairStep = admitted.pairPlan.effects.first {
                    $0.effect == effect.key
                }
                stages.append(.resolved(
                    product: product,
                    materials: materials,
                    activation: stageActivationPolicy(
                        product: product,
                        materials: materials,
                        dynamicProducers: dynamicProducers,
                        dependencyOwnership: admitted.dependencyOwnership,
                        pairStep: pairStep
                    )
                ))
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
        var graphTextureContentFacts: [Graph.TextureIdentity: SceneTextureContent] = [:]
        var capturedMainSourceConsumerCount = 0
        var firstCapturedMainMaterial: (node: Graph.Node, template: Template)?
        for node in product.graph.nodes {
            guard case .material = node.kind else {
                // Copy/swap semantics may change which version owns an
                // identity. Keep launch typing conservative until command
                // lowering can publish an equally typed transfer fact.
                graphTextureContentFacts.removeAll()
                continue
            }
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
                graphTextureContentFacts: graphTextureContentFacts,
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
            if let target = node.target,
               node.conditions == nil,
               node.compose == nil {
                if variants.launchEnvelopeProvesOpaqueColorOutput {
                    graphTextureContentFacts[target] =
                        .color(.resolved(.opaque))
                } else {
                    graphTextureContentFacts.removeValue(forKey: target)
                }
            } else if let target = node.target {
                graphTextureContentFacts.removeValue(forKey: target)
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
