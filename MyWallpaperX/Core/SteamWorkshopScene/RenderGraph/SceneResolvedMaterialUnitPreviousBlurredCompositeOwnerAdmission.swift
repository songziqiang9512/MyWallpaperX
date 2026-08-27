import Foundation

/// Temporary whole-stage owner gate for the first generic Standard Blur
/// cohort. The source-local composite fact remains reusable, but it cannot
/// authorize product output until the surrounding graph and authored scale
/// shape are inside the independently verified cohort.
nonisolated enum SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

    private enum ScaleCohort: Equatable {
        case staticExact
        case userPropertyScalarSplat(String)
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
              let stage = SceneAuthoredStandardBlurPlanner.plan(
                  graph: graph,
                  descriptor: descriptor,
                  inputRole: inputRole
              ), stage.standardBlur != nil,
              let scale = wholeStageScaleCohort(
                  graph: graph,
                  descriptor: descriptor
              ), sourceScaleCohortIsProven(
                  source: source,
                  scale: scale
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
        case (.copyPassthroughCapturedMain?, .userPropertyScalarSplat?):
            "captured-main-copy-passthrough-typed-user-scalar-splat-owner-revoked-to-material-program"
        case (.copyOnlyCapturedMain?, .staticExact?):
            "captured-main-copy-only-static-owner-revoked-to-material-program"
        case (.passthroughOnlyCapturedMain?, .staticExact?):
            "captured-main-passthrough-only-static-owner-revoked-to-material-program"
        case (.capturedMain?, .staticExact?):
            "captured-main-static-owner-revoked-to-material-program"
        case (.capturedMain?, .userPropertyScalarSplat?):
            "captured-main-typed-user-scalar-splat-owner-revoked-to-material-program"
        case (.ordinary?, .staticExact?):
            "static-owner-revoked-to-material-program"
        case (.ordinary?, .userPropertyScalarSplat?):
            "typed-user-scalar-splat-owner-revoked-to-material-program"
        case (.copyOnlyCapturedMain?, .userPropertyScalarSplat?),
             (.passthroughOnlyCapturedMain?, .userPropertyScalarSplat?),
             (nil, _), (_, nil):
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
        case (.copyOnlyCapturedMain, .userPropertyScalarSplat),
             (.passthroughOnlyCapturedMain, .userPropertyScalarSplat):
            false
        case (.ordinary, .staticExact),
             (.ordinary, .userPropertyScalarSplat),
             (.capturedMain, .staticExact),
             (.capturedMain, .userPropertyScalarSplat),
             (.copyOnlyCapturedMain, .staticExact),
             (.passthroughOnlyCapturedMain, .staticExact),
             (.copyPassthroughCapturedMain, .staticExact),
             (.copyPassthroughCapturedMain, .userPropertyScalarSplat):
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
        shaderContracts: [SceneShaderContract]
    ) -> Bool {
        guard accepts(
            key: key,
            graph: graph,
            descriptor: descriptor,
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

        if case let .userPropertyScalarSplat(propertyKey) = scaleCohort {
            guard userPropertyScalarSplatConsumersAdmit(
                propertyKey: propertyKey,
                effect: effect,
                graph: graph,
                descriptor: descriptor,
                shaderContracts: shaderContracts
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

    /// Dynamic scalar projection may revoke the incumbent only after both
    /// Gaussian consumers prove the same exact producer wrapper and an active,
    /// non-array float2 vertex ABI with an isotropic typed default.
    private static func userPropertyScalarSplatConsumersAdmit(
        propertyKey: String,
        effect: Graph.Effect,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> Bool {
        [1, 2].allSatisfy { ordinal in
            guard graph.nodes.indices.contains(ordinal) else { return false }
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
                  dynamic.valueContributors == [.userProperty(propertyKey)],
                  dynamic.scriptAttachments.isEmpty,
                  dynamic.authoredBindingKeys == ["user", "value"],
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

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func wholeStageScaleCohort(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> ScaleCohort? {
        let cohorts = [1, 2].compactMap { ordinal -> ScaleCohort? in
            guard graph.nodes.indices.contains(ordinal) else { return nil }
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
        guard scale.timeline == nil,
              scale.timelineDiagnostics.isEmpty,
              scale.scriptSource == nil else { return nil }
        guard scale.valueKind.localizedLowercase == "binding" else {
            return scale.userBinding == nil ? .staticExact : nil
        }
        guard let key = scale.userBinding,
              !key.isEmpty,
              key == key.trimmingCharacters(in: .whitespacesAndNewlines),
              scale.userValueKind == .string,
              scale.bindingKeys == ["user", "value"],
              let components = scale.components,
              components.count == 1 || components.count == 2,
              components.allSatisfy(\.isFinite),
              components.count == 1 || components[0] == components[1] else {
            return nil
        }
        return .userPropertyScalarSplat(key)
    }
}
