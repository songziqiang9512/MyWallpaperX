import Foundation

/// Whole-stage owner gate for the shared blurred/current composite cohort.
/// The shared graph contract is independent of the incumbent planner; source,
/// typed-input, and lifecycle checks remain narrower so unproven shapes keep
/// the existing product fallback.
nonisolated enum SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

    private enum ScaleCohort: Equatable {
        case staticExact
        case staticScalarProjection
        case userPropertyScalarSplat(String)
        case timelineExactVector2
    }

    private enum SourceCohort: Equatable {
        case ordinary
        case capturedMain
        case copyOnlyCapturedMain
        case passthroughOnlyCapturedMain
        case copyPassthroughCapturedMain
    }

    static func accepts(
        key: SceneResolvedMaterialRuntimeCatalog.Key,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer>,
        timelineDefinitions: Set<SceneDynamicTargetDefinition> = [],
        inputRole requiredInputRole: SceneAuthoredEffectInputRole? = nil
    ) -> Bool {
        guard graph.effects.count == 1,
              graph.effects[0].key == key.effect,
              graph.effects[0].nodeIndices.last == key.nodeIndex,
              let layer = descriptor.layers.first(where: {
                  $0.id == graph.layerID
              }), let source = sourceCohort(layer),
              let inputRole = SceneAuthoredEffectInputValidator.role(
                  for: graph.effects[0].input,
                  layerID: graph.layerID
              ), requiredInputRole == nil || requiredInputRole == inputRole,
              SceneResolvedMaterialUnitPreviousBlurredCompositeGraphAdmission
                  .accepts(
                      graph: graph,
                      descriptor: descriptor,
                      inputRole: inputRole
                  ),
              let scale = wholeStageScaleCohort(
                  graph: graph,
                  descriptor: descriptor
              ), sourceScaleCohortIsProven(
                  source: source,
                  scale: scale
              ), scaleProducerCohortIsProven(
                  scale: scale,
                  effect: graph.effects[0],
                  graph: graph,
                  descriptor: descriptor,
                  userPropertyProducers: userPropertyProducers,
                  timelineDefinitions: timelineDefinitions
              ) else { return false }
        return true
    }

    static func dedicatedRevocationDetail(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> String? {
        let source = descriptor.layers.first(where: {
            $0.id == graph.layerID
        }).flatMap(sourceCohort)
        return switch (source, wholeStageScaleCohort(
            graph: graph,
            descriptor: descriptor
        )) {
        case (.copyPassthroughCapturedMain?, .staticExact?):
            "captured-main-copy-passthrough-static-owner-revoked-to-material-program"
        case (.copyPassthroughCapturedMain?, .staticScalarProjection?):
            "captured-main-copy-passthrough-static-scalar-owner-revoked-to-material-program"
        case (.copyPassthroughCapturedMain?, .userPropertyScalarSplat?):
            "captured-main-copy-passthrough-typed-user-scalar-splat-owner-revoked-to-material-program"
        case (.copyPassthroughCapturedMain?, .timelineExactVector2?):
            "captured-main-copy-passthrough-timeline-vector2-owner-revoked-to-material-program"
        case (.copyOnlyCapturedMain?, .staticExact?):
            "captured-main-copy-only-static-owner-revoked-to-material-program"
        case (.copyOnlyCapturedMain?, .staticScalarProjection?):
            "captured-main-copy-only-static-scalar-owner-revoked-to-material-program"
        case (.copyOnlyCapturedMain?, .timelineExactVector2?):
            "captured-main-copy-only-timeline-vector2-owner-revoked-to-material-program"
        case (.passthroughOnlyCapturedMain?, .staticExact?):
            "captured-main-passthrough-only-static-owner-revoked-to-material-program"
        case (.passthroughOnlyCapturedMain?, .staticScalarProjection?):
            "captured-main-passthrough-only-static-scalar-owner-revoked-to-material-program"
        case (.passthroughOnlyCapturedMain?, .timelineExactVector2?):
            "captured-main-passthrough-only-timeline-vector2-owner-revoked-to-material-program"
        case (.capturedMain?, .staticExact?):
            "captured-main-static-owner-revoked-to-material-program"
        case (.capturedMain?, .staticScalarProjection?):
            "captured-main-static-scalar-owner-revoked-to-material-program"
        case (.capturedMain?, .userPropertyScalarSplat?):
            "captured-main-typed-user-scalar-splat-owner-revoked-to-material-program"
        case (.capturedMain?, .timelineExactVector2?):
            "captured-main-timeline-vector2-owner-revoked-to-material-program"
        case (.ordinary?, .staticExact?):
            "static-owner-revoked-to-material-program"
        case (.ordinary?, .staticScalarProjection?):
            "static-scalar-owner-revoked-to-material-program"
        case (.ordinary?, .userPropertyScalarSplat?):
            "typed-user-scalar-splat-owner-revoked-to-material-program"
        case (.ordinary?, .timelineExactVector2?):
            "timeline-vector2-owner-revoked-to-material-program"
        case (.copyOnlyCapturedMain?, .userPropertyScalarSplat?):
            "captured-main-copy-only-typed-user-scalar-splat-owner-revoked-to-material-program"
        case (.passthroughOnlyCapturedMain?, .userPropertyScalarSplat?):
            "captured-main-passthrough-only-typed-user-scalar-splat-owner-revoked-to-material-program"
        case (nil, _), (_, nil):
            nil
        }
    }

    /// The product source route resolves every childless utility flag pair to
    /// captured main. This gate preserves each authored pair as a distinct
    /// diagnostic cohort; dependency and child lifecycles remain outside.
    private static func sourceCohort(
        _ layer: SceneRenderDescriptor.Layer
    ) -> SourceCohort? {
        guard let utility = layer.utilityLayer else { return .ordinary }
        let kindMatchesContent = switch (layer.contentKind, utility.kind) {
        case ("composition", .composition), ("project", .project),
             ("fullscreen", .fullscreen):
            true
        default:
            false
        }
        guard kindMatchesContent,
              layer.childLayerIDs.isEmpty,
              layer.dependencyLayerIDs.isEmpty,
              layer.authoredDependencies.isEmpty else { return nil }
        return switch (utility.copyBackground, utility.passthrough) {
        case (false, false): .capturedMain
        case (true, true): .copyPassthroughCapturedMain
        case (true, false): .copyOnlyCapturedMain
        case (false, true): .passthroughOnlyCapturedMain
        }
    }

    private static func sourceScaleCohortIsProven(
        source: SourceCohort,
        scale: ScaleCohort
    ) -> Bool {
        switch (source, scale) {
        case (.ordinary, .staticExact),
             (.ordinary, .staticScalarProjection),
             (.ordinary, .userPropertyScalarSplat),
             (.ordinary, .timelineExactVector2),
             (.capturedMain, .staticExact),
             (.capturedMain, .staticScalarProjection),
             (.capturedMain, .userPropertyScalarSplat),
             (.capturedMain, .timelineExactVector2),
             (.copyOnlyCapturedMain, .staticExact),
             (.copyOnlyCapturedMain, .staticScalarProjection),
             (.copyOnlyCapturedMain, .userPropertyScalarSplat),
             (.copyOnlyCapturedMain, .timelineExactVector2),
             (.passthroughOnlyCapturedMain, .staticExact),
             (.passthroughOnlyCapturedMain, .staticScalarProjection),
             (.passthroughOnlyCapturedMain, .userPropertyScalarSplat),
             (.passthroughOnlyCapturedMain, .timelineExactVector2),
             (.copyPassthroughCapturedMain, .staticExact),
             (.copyPassthroughCapturedMain, .staticScalarProjection),
             (.copyPassthroughCapturedMain, .userPropertyScalarSplat),
             (.copyPassthroughCapturedMain, .timelineExactVector2):
            true
        }
    }

    /// Revokes the strict candidate only after the terminal material proves
    /// the same prepared-source, sampler, host-value, and graph contract that
    /// grants the shared product profile. Topology admission alone is not an
    /// owner handoff: a source/profile remainder must keep its incumbent.
    static func acceptsDedicatedRevocation(
        key: SceneResolvedMaterialRuntimeCatalog.Key,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        inputRole: SceneAuthoredEffectInputRole,
        shaderContracts: [SceneShaderContract],
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer>,
        timelineDefinitions: Set<SceneDynamicTargetDefinition> = []
    ) -> Bool {
        guard accepts(
            key: key,
            graph: graph,
            descriptor: descriptor,
            userPropertyProducers: userPropertyProducers,
            timelineDefinitions: timelineDefinitions,
            inputRole: inputRole
        ), let layer = descriptor.layers.first(where: {
            $0.id == graph.layerID
        }), let source = sourceCohort(layer),
           let scaleCohort = wholeStageScaleCohort(
            graph: graph,
            descriptor: descriptor
        ), let effect = graph.effects.first,
           let terminalNodeIndex = effect.nodeIndices.last,
           let terminalNode = graph.nodes.first(where: {
               $0.nodeIndex == terminalNodeIndex
           }) else { return false }

        switch scaleCohort {
        case .staticExact:
            guard staticConsumersAdmit(
                effect: effect,
                graph: graph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                scalarProjectionRequired: false
            ) else { return false }
        case .staticScalarProjection:
            guard staticConsumersAdmit(
                effect: effect,
                graph: graph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                scalarProjectionRequired: true
            ) else { return false }
        case let .userPropertyScalarSplat(propertyKey):
            guard userPropertyScalarSplatConsumersAdmit(
                propertyKey: propertyKey,
                effect: effect,
                graph: graph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                producers: userPropertyProducers
            ) else { return false }
        case .timelineExactVector2:
            guard timelineVector2ConsumersAdmit(
                effect: effect,
                graph: graph,
                descriptor: descriptor,
                shaderContracts: shaderContracts,
                definitions: timelineDefinitions
            ) else { return false }
        }

        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: terminalNode,
            graph: graph,
            descriptor: descriptor
        )
        guard resolution.isResolved, let material = resolution.node else {
            return false
        }
        let contracts = shaderContracts.filter {
            normalized($0.identity) == normalized(material.shaderPath)
        }
        guard contracts.count == 1, let contract = contracts.first else {
            return false
        }
        guard let inheritedInactiveCombos = inheritedInactiveCombos(
            effect: effect,
            material: material,
            graph: graph,
            descriptor: descriptor
        ) else { return false }
        guard case let .success(template) =
                SceneResolvedMaterialTemplateCompiler.compile(
                    material: material,
                    graph: graph,
                    shaderContract: contract,
                    inheritedInactiveCombos: inheritedInactiveCombos,
                    unitPreviousBlurredCompositeGenericOwnerEligible: true
                ) else { return false }

        let readiness = textureReadiness(template)
        let prepared: SceneShaderPreparedProgram
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: contract,
            combos: template.comboValues,
            inactiveComboProviders: Set(template.inheritedInactiveCombos),
            textureReadiness: readiness
        ) {
        case let .accepted(value): prepared = value
        case .notApplicable, .rejected: return false
        }
        let compilerSources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: prepared.vertex.source,
            fragment: prepared.fragment.source
        )
        let runtimeLoopBounds = SceneResolvedMaterialRuntimeLoopBoundResolver.resolve(
            template: template,
            prepared: prepared
        )
        guard let activeSamplerNames =
                SceneAuthoredShaderDeadBindingAnalyzer.activeSamplerNames(
                    vertexSource: compilerSources.vertex,
                    fragmentSource: compilerSources.fragment,
                    runtimeLoopBounds: runtimeLoopBounds
                ), let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(
                    prepared,
                    activeNames: activeSamplerNames
                ) else { return false }
        var graphIdentities: [Int: Graph.TextureIdentity] = [:]
        for name in activeSamplerNames {
            guard name.hasPrefix("g_Texture"),
                  let slot = Int(name.dropFirst("g_Texture".count)),
                  template.textureSlots.indices.contains(slot),
                  let candidate = template.textureSlots[slot]?.candidates.last,
                  case let .graph(identity) = candidate.reference else {
                continue
            }
            guard graphIdentities.updateValue(identity, forKey: slot) == nil else {
                return false
            }
        }
        guard let slots =
                SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility.slots(
                    fragmentSource: compilerSources.fragment,
                    prepared: prepared,
                    samplers: samplers,
                    template: template,
                    implicitFramebufferIdentity: effect.input,
                    activeGraphTextureIdentities: graphIdentities
                ) else { return false }
        guard SceneResolvedMaterialUnitPreviousBlurredCompositeEligibility
                .exactPreviousInputBinding(
                    bindings: terminalNode.bindings,
                    slot: slots.previous,
                    identity: effect.input
                ) else { return false }
        switch source {
        case .ordinary, .capturedMain:
            guard template.textureSlots.indices.contains(slots.previous),
                  template.textureSlots[slots.previous]?.candidates.count == 1
            else { return false }
        case .copyOnlyCapturedMain, .passthroughOnlyCapturedMain,
             .copyPassthroughCapturedMain:
            break
        }
        guard case let .straightAlphaPreserving(sourceSlot) =
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment
                ), sourceSlot == slots.blurred else {
            return false
        }
        return true
    }

    /// Static owner revocation preflights both Gaussian consumers. Scalar
    /// projection additionally requires exact authored-token provenance and
    /// an isotropic typed shader default; exact float2 values keep their lanes.
    private static func staticConsumersAdmit(
        effect: Graph.Effect,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        scalarProjectionRequired: Bool
    ) -> Bool {
        [1, 2].allSatisfy { ordinal in
            guard graph.nodes.indices.contains(ordinal) else { return false }
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: graph.nodes[ordinal],
                graph: graph,
                descriptor: descriptor
            )
            guard resolution.isResolved,
                  let material = resolution.node else { return false }
            let contracts = shaderContracts.filter {
                normalized($0.identity) == normalized(material.shaderPath)
            }
            guard contracts.count == 1,
                  let contract = contracts.first,
                  let inheritedInactiveCombos = inheritedInactiveCombos(
                      effect: effect,
                      material: material,
                      graph: graph,
                      descriptor: descriptor
                  ), case let .success(template) =
                    SceneResolvedMaterialTemplateCompiler.compile(
                        material: material,
                        graph: graph,
                        shaderContract: contract,
                        inheritedInactiveCombos: inheritedInactiveCombos
                    ) else { return false }
            let declarations = template.uniformDeclarations.filter {
                $0.name == "scale"
            }
            guard declarations.count == 1,
                  case let .staticExact(value) = declarations[0].value else {
                return false
            }
            let components = value.componentBitPatterns.map {
                Double(bitPattern: $0)
            }
            let valueShapeMatches = scalarProjectionRequired
                ? (components.count == 1
                    && value.authoredScalarProjectionProven)
                : components.count == 2
            guard components.allSatisfy(\.isFinite),
                  valueShapeMatches else { return false }

            let prepared: SceneShaderPreparedProgram
            switch SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: contract,
                combos: template.comboValues,
                inactiveComboProviders: Set(template.inheritedInactiveCombos),
                textureReadiness: textureReadiness(template)
            ) {
            case let .accepted(value): prepared = value
            case .notApplicable, .rejected: return false
            }
            guard let schema =
                    SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
                        materialKey: "scale",
                        type: .float2,
                        stage: .vertex,
                        prepared: prepared
                    ) else { return false }
            return !scalarProjectionRequired
                || SceneResolvedMaterialUniformProjection
                    .hasIsotropicFloat2Default(schema)
        }
    }

    /// Dynamic scalar projection may revoke the incumbent only after both
    /// Gaussian consumers prove the same exact producer wrapper and an active,
    /// non-array float2 vertex ABI with an isotropic typed default.
    private static func userPropertyScalarSplatConsumersAdmit(
        propertyKey: String,
        effect: Graph.Effect,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        producers: Set<SceneDynamicUserPropertyProducer>
    ) -> Bool {
        [1, 2].allSatisfy { ordinal in
            guard graph.nodes.indices.contains(ordinal),
                  let passIndex = graph.nodes[ordinal].instancePassIndex else {
                return false
            }
            let expectedTarget = SceneDynamicTarget.effectConstant(
                layerID: effect.key.layerID,
                effectIndex: effect.key.effectIndex,
                passIndex: passIndex,
                name: "scale"
            )
            let expectedProducer = SceneDynamicUserPropertyProducer(
                propertyKey: propertyKey,
                target: expectedTarget,
                valueType: .scalar
            )
            let targetProducers = producers.filter { $0.target == expectedTarget }
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: graph.nodes[ordinal],
                graph: graph,
                descriptor: descriptor
            )
            guard resolution.isResolved, let material = resolution.node else {
                return false
            }
            let contracts = shaderContracts.filter {
                normalized($0.identity) == normalized(material.shaderPath)
            }
            guard contracts.count == 1, let contract = contracts.first,
                  let inheritedInactiveCombos = inheritedInactiveCombos(
                      effect: effect,
                      material: material,
                      graph: graph,
                      descriptor: descriptor
                  ), case let .success(template) =
                    SceneResolvedMaterialTemplateCompiler.compile(
                        material: material,
                        graph: graph,
                        shaderContract: contract,
                        inheritedInactiveCombos: inheritedInactiveCombos
                    ) else { return false }

            let scaleDeclarations = template.uniformDeclarations.filter {
                $0.name == "scale"
            }
            guard scaleDeclarations.count == 1,
                  case let .dynamic(dynamic) = scaleDeclarations[0].value,
                  dynamic.target == expectedTarget,
                  dynamic.valueContributors == [.userProperty(propertyKey)],
                  dynamic.scriptAttachments.isEmpty,
                  dynamic.authoredBindingKeys == ["user", "value"],
                  targetProducers == [expectedProducer],
                  let fallback = dynamic.authoredFallback,
                  fallback.valueKind.localizedLowercase == "binding",
                  fallback.authoredBindingKeys == ["user", "value"] else {
                return false
            }
            let fallbackComponents = fallback.componentBitPatterns.map {
                Double(bitPattern: $0)
            }
            guard scalarOrEqualPair(fallbackComponents) else { return false }

            let prepared: SceneShaderPreparedProgram
            switch SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: contract,
                combos: template.comboValues,
                inactiveComboProviders: Set(template.inheritedInactiveCombos),
                textureReadiness: textureReadiness(template)
            ) {
            case let .accepted(value): prepared = value
            case .notApplicable, .rejected: return false
            }
            guard let schema =
                    SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
                        materialKey: "scale",
                        type: .float2,
                        stage: .vertex,
                        prepared: prepared
                    ), let consumerDefault = schema.defaultValue else {
                return false
            }
            let defaultComponents = consumerDefault.componentBitPatterns.map {
                Double(bitPattern: $0)
            }
            return defaultComponents.count == 2
                && defaultComponents.allSatisfy(\.isFinite)
                && defaultComponents[0] == defaultComponents[1]
        }
    }

    /// Exact Timeline vector values do not use scalar projection. Both
    /// Gaussian consumers must preserve the authored wrapper and fallback,
    /// resolve to one launch-scoped typed definition, and expose one active
    /// non-array vertex float2 ABI before the incumbent may be revoked.
    private static func timelineVector2ConsumersAdmit(
        effect: Graph.Effect,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        definitions: Set<SceneDynamicTargetDefinition>
    ) -> Bool {
        [1, 2].allSatisfy { ordinal in
            guard graph.nodes.indices.contains(ordinal),
                  let passIndex = graph.nodes[ordinal].instancePassIndex else {
                return false
            }
            let target = SceneDynamicTarget.effectConstant(
                layerID: effect.key.layerID,
                effectIndex: effect.key.effectIndex,
                passIndex: passIndex,
                name: "scale"
            )
            let targetDefinitions = definitions.filter { $0.target == target }
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: graph.nodes[ordinal],
                graph: graph,
                descriptor: descriptor
            )
            guard resolution.isResolved, let material = resolution.node else {
                return false
            }
            let contracts = shaderContracts.filter {
                normalized($0.identity) == normalized(material.shaderPath)
            }
            guard contracts.count == 1, let contract = contracts.first,
                  let inheritedInactiveCombos = inheritedInactiveCombos(
                      effect: effect,
                      material: material,
                      graph: graph,
                      descriptor: descriptor
                  ), case let .success(template) =
                    SceneResolvedMaterialTemplateCompiler.compile(
                        material: material,
                        graph: graph,
                        shaderContract: contract,
                        inheritedInactiveCombos: inheritedInactiveCombos
                    ) else { return false }

            let scaleDeclarations = template.uniformDeclarations.filter {
                $0.name == "scale"
            }
            guard scaleDeclarations.count == 1,
                  case let .dynamic(dynamic) = scaleDeclarations[0].value,
                  dynamic.target == target,
                  dynamic.valueContributors == [.timeline],
                  dynamic.scriptAttachments.isEmpty,
                  dynamic.authoredBindingKeys == ["animation", "value"],
                  let fallback = dynamic.authoredFallback,
                  fallback.valueKind.localizedLowercase == "binding",
                  fallback.authoredBindingKeys == ["animation", "value"],
                  targetDefinitions.count == 1,
                  let definition = targetDefinitions.first,
                  timelineDefinition(
                      definition,
                      matches: fallback.componentBitPatterns
                  ) else { return false }

            let prepared: SceneShaderPreparedProgram
            switch SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: contract,
                combos: template.comboValues,
                inactiveComboProviders: Set(template.inheritedInactiveCombos),
                textureReadiness: textureReadiness(template)
            ) {
            case let .accepted(value): prepared = value
            case .notApplicable, .rejected: return false
            }
            return SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
                materialKey: "scale",
                type: .float2,
                stage: .vertex,
                prepared: prepared
            ) != nil
        }
    }

    private static func inheritedInactiveCombos(
        effect: Graph.Effect,
        material: SceneResolvedMaterialNode,
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Set<String>? {
        var values = Set<String>()
        for node in graph.nodes where node.effect == effect.key {
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: node,
                graph: graph,
                descriptor: descriptor
            )
            guard resolution.isResolved,
                  let resolvedNode = resolution.node else { return nil }
            values.formUnion(resolvedNode.combos.keys)
        }
        values.subtract(material.combos.keys)
        return values
    }

    private static func textureReadiness(_ template: Template) -> [Int: Bool] {
        Dictionary(uniqueKeysWithValues: (0 ..< 8).map { slot in
            (
                slot,
                template.textureSlots.indices.contains(slot)
                    && template.textureSlots[slot] != nil
            )
        })
    }

    private static func scalarOrEqualPair(_ components: [Double]) -> Bool {
        components.allSatisfy(\.isFinite)
            && (components.count == 1
                || (components.count == 2 && components[0] == components[1]))
    }

    /// The owner token and dedicated revocation consume the same launch-scoped
    /// producer facts. Other targets may share the property key, but each
    /// Gaussian scale target must have exactly one scalar producer.
    private static func scaleProducerCohortIsProven(
        scale: ScaleCohort,
        effect: Graph.Effect,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer>,
        timelineDefinitions: Set<SceneDynamicTargetDefinition>
    ) -> Bool {
        switch scale {
        case let .userPropertyScalarSplat(propertyKey):
            return [1, 2].allSatisfy { ordinal in
                guard graph.nodes.indices.contains(ordinal),
                      graph.nodes[ordinal].effect == effect.key,
                      let passIndex = graph.nodes[ordinal].instancePassIndex else {
                    return false
                }
                let target = SceneDynamicTarget.effectConstant(
                    layerID: effect.key.layerID,
                    effectIndex: effect.key.effectIndex,
                    passIndex: passIndex,
                    name: "scale"
                )
                let expected = SceneDynamicUserPropertyProducer(
                    propertyKey: propertyKey,
                    target: target,
                    valueType: .scalar
                )
                return userPropertyProducers.filter {
                    $0.target == target
                } == [expected]
            }
        case .timelineExactVector2:
            return [1, 2].allSatisfy { ordinal in
                guard graph.nodes.indices.contains(ordinal),
                      graph.nodes[ordinal].effect == effect.key,
                      let passIndex = graph.nodes[ordinal].instancePassIndex else {
                    return false
                }
                let target = SceneDynamicTarget.effectConstant(
                    layerID: effect.key.layerID,
                    effectIndex: effect.key.effectIndex,
                    passIndex: passIndex,
                    name: "scale"
                )
                let targetDefinitions = timelineDefinitions.filter {
                    $0.target == target
                }
                let resolution = SceneAuthoredMaterialResolver.resolve(
                    node: graph.nodes[ordinal],
                    graph: graph,
                    descriptor: descriptor
                )
                guard resolution.isResolved,
                      let authored = resolution.node?.constants["scale"],
                      let components = authored.components,
                      targetDefinitions.count == 1,
                      let definition = targetDefinitions.first else {
                    return false
                }
                return timelineDefinition(
                    definition,
                    matches: components.map(\.bitPattern)
                )
            }
        case .staticExact, .staticScalarProjection:
            return true
        }
    }

    private static func timelineDefinition(
        _ definition: SceneDynamicTargetDefinition,
        matches componentBitPatterns: [UInt64]
    ) -> Bool {
        guard definition.valueType == .vector2,
              componentBitPatterns.count == 2,
              case let .vector2(x, y) = definition.authoredValue,
              x.isFinite, y.isFinite else { return false }
        return x.bitPattern == componentBitPatterns[0]
            && y.bitPattern == componentBitPatterns[1]
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func wholeStageScaleCohort(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> ScaleCohort? {
        let cohorts = [1, 2].compactMap { ordinal -> ScaleCohort? in
            guard graph.nodes.indices.contains(ordinal),
                  graph.nodes[ordinal].effect == graph.effects.first?.key else {
                return nil
            }
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: graph.nodes[ordinal], graph: graph, descriptor: descriptor
            )
            guard resolution.isResolved,
                  let material = resolution.node,
                  material.constants.count == 1,
                  let scale = material.constants.first?.value else { return nil }
            return scaleCohort(scale)
        }
        guard cohorts.count == 2, cohorts[0] == cohorts[1] else { return nil }
        return cohorts[0]
    }

    private static func scaleCohort(
        _ scale: SceneDocument.ShaderValue
    ) -> ScaleCohort? {
        guard scale.timelineDiagnostics.isEmpty,
              scale.scriptSource == nil,
              let components = scale.components,
              components.count == 1 || components.count == 2,
              components.allSatisfy(\.isFinite) else { return nil }
        if scale.timeline != nil {
            guard scale.valueKind.localizedLowercase == "binding",
                  scale.userBinding == nil,
                  scale.userValueKind == nil,
                  scale.bindingKeys == ["animation", "value"],
                  components.count == 2 else { return nil }
            return .timelineExactVector2
        }
        guard scale.valueKind.localizedLowercase == "binding" else {
            guard scale.userBinding == nil else { return nil }
            return components.count == 1
                ? .staticScalarProjection
                : .staticExact
        }
        guard let key = scale.userBinding,
              !key.isEmpty,
              key == key.trimmingCharacters(in: .whitespacesAndNewlines),
              scale.userValueKind == .string,
              scale.bindingKeys == ["user", "value"],
              components.count == 1 || components[0] == components[1] else {
            return nil
        }
        return .userPropertyScalarSplat(key)
    }
}
