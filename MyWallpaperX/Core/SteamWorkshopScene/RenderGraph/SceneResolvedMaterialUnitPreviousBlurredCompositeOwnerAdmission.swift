import Foundation

/// Temporary whole-stage owner gate for the first generic Standard Blur
/// cohort. The source-local composite fact remains reusable, but it cannot
/// authorize product output until the surrounding graph and authored scale
/// shape are inside the independently verified cohort.
nonisolated enum SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func accepts(
        key: SceneResolvedMaterialRuntimeCatalog.Key,
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        inputRole requiredInputRole: SceneAuthoredEffectInputRole? = nil
    ) -> Bool {
        guard graph.effects.count == 1,
              graph.effects[0].key == key.effect,
              graph.effects[0].nodeIndices.last == key.nodeIndex,
              let inputRole = SceneAuthoredEffectInputValidator.role(
                  for: graph.effects[0].input,
                  layerID: graph.layerID
              ), requiredInputRole == nil || requiredInputRole == inputRole,
              let stage = SceneAuthoredStandardBlurPlanner.plan(
                  graph: graph,
                  descriptor: descriptor,
                  inputRole: inputRole
              ), stage.standardBlur != nil else { return false }
        return [1, 2].allSatisfy { ordinal in
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: graph.nodes[ordinal], graph: graph, descriptor: descriptor
            )
            guard resolution.isResolved,
                  let material = resolution.node,
                  material.constants.count == 1,
                  let scale = material.constants.first?.value else { return false }
            return scale.valueKind.localizedLowercase != "binding"
                && scale.userBinding == nil
                && scale.timeline == nil
                && scale.timelineDiagnostics.isEmpty
                && scale.scriptSource == nil
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
        ), let effect = graph.effects.first,
           let terminalNodeIndex = effect.nodeIndices.last,
           let terminalNode = graph.nodes.first(where: {
               $0.nodeIndex == terminalNodeIndex
           }) else { return false }

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
        var inheritedInactiveCombos = Set<String>()
        for node in graph.nodes where node.effect == effect.key {
            let nodeResolution = SceneAuthoredMaterialResolver.resolve(
                node: node,
                graph: graph,
                descriptor: descriptor
            )
            guard nodeResolution.isResolved,
                  let resolvedNode = nodeResolution.node else { return false }
            inheritedInactiveCombos.formUnion(resolvedNode.combos.keys)
        }
        inheritedInactiveCombos.subtract(material.combos.keys)
        guard case let .success(template) =
                SceneResolvedMaterialTemplateCompiler.compile(
                    material: material,
                    graph: graph,
                    shaderContract: contract,
                    inheritedInactiveCombos: inheritedInactiveCombos,
                    unitPreviousBlurredCompositeGenericOwnerEligible: true
                ) else { return false }

        let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
            ($0, true)
        })
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
                ), case let .straightAlphaPreserving(sourceSlot) =
                    SceneAuthoredShaderColorTransferAnalyzer.analyze(
                        fragmentSource: compilerSources.fragment
                    ), sourceSlot == slots.blurred else { return false }
        return true
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
