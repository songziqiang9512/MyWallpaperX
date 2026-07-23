import Foundation

nonisolated struct SceneAuthoredEffectExecutionPlan {
    enum Backend {
        case preciseGaussian(SceneGaussianBlurPlan)
        case standardBlur(SceneStandardBlurPlan)
        case localContrast(SceneLocalContrastPlan)
    }

    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let backend: Backend
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole

    init(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        backend: Backend,
        materialNodeCount: Int,
        logicalRenderTargetCount: Int,
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) {
        self.layerID = layerID
        self.renderGraph = renderGraph
        self.backend = backend
        self.materialNodeCount = materialNodeCount
        self.logicalRenderTargetCount = logicalRenderTargetCount
        self.inputRole = inputRole
    }

    var gaussianBlur: SceneGaussianBlurPlan? {
        guard case .preciseGaussian(let plan) = backend else { return nil }
        return plan
    }

    var standardBlur: SceneStandardBlurPlan? {
        guard case .standardBlur(let plan) = backend else { return nil }
        return plan
    }

    var localContrast: SceneLocalContrastPlan? {
        guard case .localContrast(let plan) = backend else { return nil }
        return plan
    }

    var liveConsumerTarget: SceneDynamicTarget? {
        localContrast?.liveStrengthTarget
    }

    func localContrastStrength(in snapshot: SceneDynamicSnapshot) -> Float? {
        localContrast?.resolvedStrength(in: snapshot)
    }

    var requiresExactInputExtent: Bool {
        if case .preciseGaussian = backend { return true }
        return false
    }
}

nonisolated struct SceneAuthoredEffectExecutionCatalog {
    let chainsByLayerID: [Int: SceneAuthoredEffectExecutionChain]
    let hiddenEligibleLayerIDs: [Int]
    let legacyGaussianBlurBlockedLayerIDs: Set<Int>

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
        for (layerID, candidates) in grouped where candidates.count == 1 {
            let graph = candidates[0]
            guard let chain = SceneAuthoredEffectChainPlanner.plan(
                graph: graph,
                descriptor: descriptor,
                shaderContracts: shaderContracts
            ) else { continue }
            eligible[layerID] = chain
        }
        chainsByLayerID = eligible.filter { visible.contains($0.key) }
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
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 2,
              graph.renderTargets.count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid", "text"].contains(layer.contentKind) else {
            return nil
        }
        let effect = graph.effects[0]
        let horizontalNode = graph.nodes[0]
        let verticalNode = graph.nodes[1]
        let target = graph.renderTargets[0]
        guard effect.nodeIndices == [horizontalNode.nodeIndex, verticalNode.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              target.texture.kind == .framebuffer,
              target.texture.effect == effect.key,
              target.extent.kind == .input,
              target.extent.first == nil,
              target.extent.second == nil,
              target.format?.lowercased() == "rgba_backbuffer",
              !target.declaredUnique,
              target.clear == nil,
              target.uvs == nil,
              target.conditions == nil,
              validNode(horizontalNode, ordinal: 0, effect: effect.key),
              validNode(verticalNode, ordinal: 1, effect: effect.key),
              horizontalNode.target == target.texture,
              verticalNode.target == effect.output,
              horizontalNode.bindings.isEmpty,
              verticalNode.bindings.count == 2,
              binding(verticalNode.bindings, slot: 0)?.texture == target.texture,
              binding(verticalNode.bindings, slot: 1)?.texture == effect.input else {
            return nil
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
              supportedCombos(horizontalMaterial.combos, vertical: false),
              supportedCombos(verticalMaterial.combos, vertical: true),
              horizontalMaterial.textureSlots.allSatisfy({ $0 == nil }),
              graphSlot(verticalMaterial.textureSlots[0]) == target.texture,
              graphSlot(verticalMaterial.textureSlots[1]) == effect.input,
              verticalMaterial.textureSlots.dropFirst(2).allSatisfy({ $0 == nil }),
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
            logicalRenderTargetCount: 1,
            inputRole: inputRole
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
        vertical: Bool
    ) -> Bool {
        var normalized: [String: Int] = [:]
        for (key, value) in combos {
            guard normalized.updateValue(value, forKey: key.uppercased()) == nil else {
                return false
            }
        }
        guard normalized.keys.allSatisfy({ ["ENABLEMASK", "VERTICAL"].contains($0) }),
              normalized["VERTICAL", default: 0] == (vertical ? 1 : 0),
              normalized["ENABLEMASK", default: 0] == (vertical ? 1 : 0),
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

    private nonisolated static func binding(
        _ bindings: [Graph.Binding],
        slot: Int
    ) -> Graph.Binding? {
        let matches = bindings.filter { $0.slot == slot }
        return matches.count == 1 ? matches[0] : nil
    }

    private nonisolated static func graphSlot(
        _ slot: SceneResolvedMaterialNode.TextureSlot?
    ) -> Graph.TextureIdentity? {
        guard let slot, case .graph(let texture) = slot.source else { return nil }
        return texture
    }

    private nonisolated static func layerSource(layerID: Int) -> Graph.TextureIdentity {
        .init(kind: .layerSource, layerID: layerID, effect: nil, name: nil)
    }

    private nonisolated static func effectOutput(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }
}
