import Foundation

nonisolated struct SceneAuthoredEffectExecutionPlan {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let backend: Backend
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let usesLegacyComposeNormalization: Bool

    init(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        backend: Backend,
        materialNodeCount: Int,
        logicalRenderTargetCount: Int,
        inputRole: SceneAuthoredEffectInputRole = .layerSource,
        usesLegacyComposeNormalization: Bool = false
    ) {
        self.layerID = layerID
        self.renderGraph = renderGraph
        self.backend = backend
        self.materialNodeCount = materialNodeCount
        self.logicalRenderTargetCount = logicalRenderTargetCount
        self.inputRole = inputRole
        self.usesLegacyComposeNormalization = usesLegacyComposeNormalization
    }

}

nonisolated struct SceneAuthoredEffectExecutionCatalog {
    let chainsByLayerID: [Int: SceneAuthoredEffectExecutionChain]
    let hiddenEligibleLayerIDs: [Int]
    let legacyGaussianBlurBlockedLayerIDs: Set<Int>
    let xRayPrefixOmittedEffectPathsByLayerID: [Int: [String]]

    var plansByLayerID: [Int: SceneAuthoredEffectExecutionPlan] {
        chainsByLayerID.compactMapValues(\.singleStage)
    }

    init(
        descriptor: SceneRenderDescriptor,
        authoredPlans: [SceneAuthoredEffectRenderPlan],
        shaderContracts: [SceneShaderContract] = []
    ) {
        let visible = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        let grouped = Dictionary(grouping: authoredPlans, by: \.layerID)
        var eligible: [Int: SceneAuthoredEffectExecutionChain] = [:]
        var xRayPrefixes: [Int: [String]] = [:]
        for (layerID, candidates) in grouped where candidates.count == 1 {
            let graph = candidates[0]
            guard let chain = SceneAuthoredEffectChainPlanner.plan(
                graph: graph,
                descriptor: descriptor,
                shaderContracts: shaderContracts
            ) else { continue }
            eligible[layerID] = chain
            if chain.stages.count < graph.effects.count {
                xRayPrefixes[layerID] = graph.effects
                    .dropFirst(chain.stages.count)
                    .map(\.definitionPath)
            }
        }
        let visibleEligible = eligible.filter { visible.contains($0.key) }
        chainsByLayerID = visibleEligible
        xRayPrefixOmittedEffectPathsByLayerID = xRayPrefixes.filter {
            visibleEligible[$0.key] != nil
        }
        hiddenEligibleLayerIDs = eligible.keys.filter { !visible.contains($0) }.sorted()
        let preciseBlurCandidateLayers = Set(authoredPlans.compactMap { graph in
            SceneAuthoredEffectExecutionPlanner.containsAuthoredPreciseBlurCandidate(
                graph: graph,
                descriptor: descriptor
            ) ? graph.layerID : nil
        })
        let standardBlurCandidateLayers = Set(authoredPlans.compactMap { graph in
            SceneAuthoredStandardBlurPlanner.containsCandidate(graph: graph)
                ? graph.layerID : nil
        })
        legacyGaussianBlurBlockedLayerIDs = preciseBlurCandidateLayers
            .union(standardBlurCandidateLayers)
            .intersection(visible)
            .subtracting(chainsByLayerID.keys)
    }

    var reportLines: [String] {
        [
            "authoredEffectGraphPlannedCount: \(chainsByLayerID.count)",
            "authoredEffectGraphMaterialNodeCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.materialNodeCount })",
            "authoredEffectGraphLogicalRTCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.logicalRenderTargetCount })",
            "authoredEffectGraphSupportLevel: \(chainsByLayerID.isEmpty ? "none" : "executed-degraded")",
            "authoredEffectGraphHiddenEligibleCount: \(hiddenEligibleLayerIDs.count)",
            "authoredEffectGraphHiddenEligibleLayerIDs: \(hiddenEligibleLayerIDs.map(String.init).joined(separator: ","))",
            "authoredEffectGraphLegacyBlurBlockedCount: \(legacyGaussianBlurBlockedLayerIDs.count)",
            "authoredEffectGraphLegacyBlurBlockedLayerIDs: \(legacyGaussianBlurBlockedLayerIDs.sorted().map(String.init).joined(separator: ","))",
            "authoredEffectGraphChainCount: \(chainsByLayerID.values.filter { $0.stages.count > 1 }.count)",
            "authoredEffectGraphStageCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.stages.count })",
            "authoredEffectGraphLocalContrastCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.localContrastCount })",
            "authoredEffectGraphOpacityCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.opacityCount })",
            "authoredEffectGraphColorKeyCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.colorKeyCount })",
            "authoredEffectGraphWorkshopShiftHueCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.workshopShiftHueCount })",
            "authoredEffectGraphWorkshopAudioBarsCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.workshopAudioBarsCount })",
            "authoredEffectGraphWorkshopShadowCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.workshopShadowCount })",
            "authoredEffectGraphShakeCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.shakeCount })",
            "authoredEffectGraphWaterFlowCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.waterFlowCount })",
            "authoredEffectGraphWaterWavesCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.waterWavesCount })",
            "authoredEffectGraphFoliageSwayCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.foliageSwayCount })",
            "authoredEffectGraphWaterRippleCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.waterRippleCount })",
            "authoredEffectGraphXRayCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.xRayCount })",
            "authoredEffectGraphTintCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.tintCount })",
            "authoredEffectGraphPulseCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.pulseCount })",
            "authoredEffectGraphGodraysCount: \(chainsByLayerID.values.reduce(0) { $0 + $1.godraysCount })",
            "authoredEffectGraphXRayPrefixCount: \(xRayPrefixOmittedEffectPathsByLayerID.count)",
            "authoredEffectGraphXRayPrefixOmittedEffects: \(xRayPrefixOmittedEffectPathsByLayerID.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value.joined(separator: ","))" }.joined(separator: ";"))",
        ]
    }

    var liveConsumerTargets: Set<SceneDynamicTarget> {
        Set(chainsByLayerID.values.flatMap(\.liveConsumerTargets))
    }
}

enum SceneAuthoredEffectExecutionPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneAuthoredEffectExecutionPlan? {
        let materialNodes = graph.nodes.filter { $0.kind == .material }
        let commandNodes = graph.nodes.filter { $0.kind == .copy || $0.kind == .swap }
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              materialNodes.count == 2,
              commandNodes.count <= 1,
              graph.nodes.count == materialNodes.count + commandNodes.count,
              graph.renderTargets.count == 1 + commandNodes.count,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid", "text"].contains(layer.contentKind) else {
            return nil
        }
        let effect = graph.effects[0]
        let horizontalNode = materialNodes[0]
        let verticalNode = materialNodes[1]
        let targetGroups = Dictionary(grouping: graph.renderTargets, by: \.texture)
        guard targetGroups.values.allSatisfy({ $0.count == 1 }) else { return nil }
        let targetsByIdentity = targetGroups.compactMapValues(\.first)
        guard let usesLegacyComposeNormalization = preciseBlurBindingProfile(
            horizontalNode: horizontalNode,
            verticalNode: verticalNode,
            effect: effect
        ) else {
            return nil
        }
        guard let horizontalTarget = horizontalNode.target,
              let verticalInput = binding(verticalNode.bindings, slot: 0)?.texture,
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              SceneAuthoredEffectInputValidator.accepts(
                effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              graph.renderTargets.allSatisfy({
                  validTarget($0, effect: effect.key)
              }),
              validNode(horizontalNode, ordinal: 0, effect: effect.key),
              validNode(verticalNode, ordinal: 1, effect: effect.key),
              verticalNode.target == effect.output else {
            return nil
        }
        if let commandNode = commandNodes.first {
            guard graph.nodes[0].nodeIndex == horizontalNode.nodeIndex,
                  graph.nodes[1].nodeIndex == commandNode.nodeIndex,
                  graph.nodes[2].nodeIndex == verticalNode.nodeIndex,
                  validCommandNode(commandNode, effect: effect.key),
                  commandNode.commandSource == horizontalTarget,
                  commandNode.commandTarget == verticalInput,
                  horizontalTarget != verticalInput,
                  targetsByIdentity[horizontalTarget] != nil,
                  targetsByIdentity[verticalInput] != nil else {
                return nil
            }
            let uniqueIdentity = commandNode.kind == .swap ? verticalInput : nil
            guard graph.renderTargets.allSatisfy({
                $0.declaredUnique == ($0.texture == uniqueIdentity)
            }) else {
                return nil
            }
        } else {
            guard graph.nodes[0].nodeIndex == horizontalNode.nodeIndex,
                  graph.nodes[1].nodeIndex == verticalNode.nodeIndex,
                  horizontalTarget == verticalInput,
                  targetsByIdentity[horizontalTarget] != nil,
                  graph.renderTargets.allSatisfy({ !$0.declaredUnique }) else {
                return nil
            }
        }

        let horizontal = SceneAuthoredMaterialResolver.resolve(
            node: horizontalNode,
            graph: graph,
            descriptor: descriptor
        )
        let vertical = SceneAuthoredMaterialResolver.resolve(
            node: verticalNode,
            graph: graph,
            descriptor: descriptor
        )
        guard horizontal.isResolved, vertical.isResolved,
              let horizontalMaterial = horizontal.node,
              let verticalMaterial = vertical.node,
              isSupportedPreciseBlurShader(horizontalMaterial.shaderPath),
              isSupportedPreciseBlurShader(verticalMaterial.shaderPath),
              normalizedShaderPath(horizontalMaterial.shaderPath)
                == normalizedShaderPath(verticalMaterial.shaderPath),
              supportedState(horizontalMaterial.renderState),
              supportedState(verticalMaterial.renderState),
              supportedCombos(
                  horizontalMaterial.combos,
                  vertical: false,
                  legacyCompose: usesLegacyComposeNormalization
              ),
              supportedCombos(
                  verticalMaterial.combos,
                  vertical: true,
                  legacyCompose: usesLegacyComposeNormalization
              ),
              validMaterialSlots(
                  horizontal: horizontalMaterial,
                  vertical: verticalMaterial,
                  effectInput: effect.input,
                  intermediate: verticalInput,
                  legacyCompose: usesLegacyComposeNormalization
              ),
              horizontalMaterial.constants.keys.allSatisfy({ $0.lowercased() == "scale" }),
              verticalMaterial.constants.keys.allSatisfy({ $0.lowercased() == "scale" }),
              let horizontalScale = scale(horizontalMaterial.constants, component: 0),
              let verticalScale = scale(verticalMaterial.constants, component: 1) else {
            return nil
        }

        return SceneAuthoredEffectExecutionPlan(
            layerID: graph.layerID,
            renderGraph: graph,
            backend: .preciseGaussian(SceneGaussianBlurPlan(
                horizontalStep: horizontalScale,
                verticalStep: verticalScale,
                sampleResolutionScale: 1,
                isPrecise: true
            )),
            materialNodeCount: 2,
            logicalRenderTargetCount: graph.renderTargets.count,
            inputRole: inputRole,
            usesLegacyComposeNormalization: usesLegacyComposeNormalization
        )
    }

    private nonisolated static func validNode(
        _ node: Graph.Node,
        ordinal: Int,
        effect: Graph.EffectKey
    ) -> Bool {
        node.kind == .material
            && node.effect == effect
            && node.materialOrdinal == ordinal
            && node.compose == nil
            && node.conditions == nil
            && node.commandSource == nil
            && node.commandTarget == nil
    }

    nonisolated static func containsRegisteredPreciseBlurShader(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        graph.nodes.contains { node in
            guard node.kind == .material, let materialID = node.materialPassID else { return false }
            let matches = descriptor.materialPasses.filter { $0.id == materialID }
            guard matches.count == 1, let shaderPath = matches[0].shaderPath else { return false }
            return isSupportedPreciseBlurShader(shaderPath)
        }
    }

    nonisolated static func containsAuthoredPreciseBlurCandidate(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        if containsRegisteredPreciseBlurShader(graph: graph, descriptor: descriptor) {
            return true
        }
        return graph.effects.contains {
            normalizedShaderPath($0.definitionPath).contains("/blurprecise/")
        }
    }

    nonisolated static func isSupportedPreciseBlurShader(_ path: String) -> Bool {
        let normalized = normalizedShaderPath(path)
        return normalized.hasSuffix("/effects/blur_precise_gaussian")
            || normalized == "effects/blur_precise_gaussian"
    }

    private nonisolated static func normalizedShaderPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func supportedState(
        _ state: SceneResolvedMaterialNode.RenderState
    ) -> Bool {
        state.blending?.lowercased() == "normal"
            && state.depthTest?.lowercased() == "disabled"
            && state.depthWrite?.lowercased() == "disabled"
            && state.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func supportedCombos(
        _ combos: [String: Int],
        vertical: Bool,
        legacyCompose: Bool
    ) -> Bool {
        var normalized: [String: Int] = [:]
        for (key, value) in combos {
            guard normalized.updateValue(value, forKey: key.uppercased()) == nil else {
                return false
            }
        }
        guard normalized.keys.allSatisfy({
                  ["ENABLEMASK", "KERNEL", "VERTICAL"].contains($0)
              }),
              normalized["VERTICAL", default: 0] == (vertical ? 1 : 0),
              normalized["ENABLEMASK", default: 0]
                == (vertical && !legacyCompose ? 1 : 0),
              normalized["KERNEL", default: 0] == 0,
              normalized["MASK", default: 0] == 0 else {
            return false
        }
        return true
    }

    private nonisolated static func scale(
        _ values: [String: SceneDocument.ShaderValue],
        component: Int
    ) -> Float? {
        let matches = values.filter { $0.key.lowercased() == "scale" }
        guard matches.count == 1,
              let value = matches.values.first,
              value.userBinding == nil,
              value.valueKind.lowercased() == "vector",
              let components = value.components,
              components.count == 2,
              components.indices.contains(component),
              components.allSatisfy({ $0.isFinite && (0.01...2).contains($0) }) else {
            return nil
        }
        let raw = components[component]
        return Float(raw)
    }

    private nonisolated static func layerSource(layerID: Int) -> Graph.TextureIdentity {
        .init(kind: .layerSource, layerID: layerID, effect: nil, name: nil)
    }

    private nonisolated static func effectOutput(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }
}
