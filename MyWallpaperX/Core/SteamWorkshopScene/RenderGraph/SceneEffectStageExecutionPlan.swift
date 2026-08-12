import Foundation

nonisolated struct SceneEffectStageExecutionPlan {
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
}

enum SceneEffectStageExecutionPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneEffectStageExecutionPlan? {
        let materialNodes = graph.nodes.filter { $0.kind == .material }
        let commandNodes = graph.nodes.filter { $0.kind == .copy || $0.kind == .swap }
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              materialNodes.count == 2,
              commandNodes.count <= 1,
              graph.nodes.count == materialNodes.count + commandNodes.count,
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
        guard let topology = preciseBlurTopology(
            horizontalNode: horizontalNode,
            verticalNode: verticalNode,
            effect: effect,
            commandNodeCount: commandNodes.count
        ) else {
            return nil
        }
        guard effect.nodeIndices == graph.nodes.map(\.nodeIndex),
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
        switch topology {
        case .fullFrameCompose:
            guard commandNodes.isEmpty,
                  graph.renderTargets.isEmpty,
                  graph.nodes[0].nodeIndex == horizontalNode.nodeIndex,
                  graph.nodes[1].nodeIndex == verticalNode.nodeIndex else {
                return nil
            }
        case let .authoredIntermediate(horizontalTarget, verticalInput):
            guard graph.renderTargets.count == 1 + commandNodes.count else {
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
                let commandTargetsMustBeUnique = commandNode.kind == .swap
                guard targetsByIdentity[horizontalTarget]?.declaredUnique
                        == commandTargetsMustBeUnique,
                      targetsByIdentity[verticalInput]?.declaredUnique
                        == commandTargetsMustBeUnique else {
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
              let horizontalKernel = supportedKernel(
                  horizontalMaterial.combos,
                  vertical: false,
                  fullFrameCompose: topology.usesFullFrameCompose
              ),
              let verticalKernel = supportedKernel(
                  verticalMaterial.combos,
                  vertical: true,
                  fullFrameCompose: topology.usesFullFrameCompose
              ),
              horizontalKernel == verticalKernel,
              validMaterialSlots(
                  horizontal: horizontalMaterial,
                  vertical: verticalMaterial,
                  effectInput: effect.input,
                  topology: topology
              ),
              horizontalMaterial.constants.keys.allSatisfy({ $0.lowercased() == "scale" }),
              verticalMaterial.constants.keys.allSatisfy({ $0.lowercased() == "scale" }),
              let horizontalScale = scale(horizontalMaterial.constants, component: 0),
              let verticalScale = scale(verticalMaterial.constants, component: 1) else {
            return nil
        }

        return SceneEffectStageExecutionPlan(
            layerID: graph.layerID,
            renderGraph: graph,
            backend: .preciseGaussian(SceneGaussianBlurPlan(
                horizontalStep: horizontalScale,
                verticalStep: verticalScale,
                sampleResolutionScale: 1,
                isPrecise: true,
                kernel: horizontalKernel
            )),
            materialNodeCount: 2,
            logicalRenderTargetCount: graph.renderTargets.count,
            inputRole: inputRole
        )
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

    private nonisolated static func supportedKernel(
        _ combos: [String: Int],
        vertical: Bool,
        fullFrameCompose: Bool
    ) -> SceneGaussianBlurKernel? {
        var normalized: [String: Int] = [:]
        for (key, value) in combos {
            guard normalized.updateValue(value, forKey: key.uppercased()) == nil else {
                return nil
            }
        }
        guard normalized.keys.allSatisfy({
                  ["ENABLEMASK", "KERNEL", "VERTICAL"].contains($0)
              }),
              normalized["VERTICAL", default: 0] == (vertical ? 1 : 0),
              normalized["ENABLEMASK", default: 0]
                == (vertical && !fullFrameCompose ? 1 : 0),
              let kernel = SceneGaussianBlurKernel(
                  rawValue: normalized["KERNEL", default: 0]
              ) else {
            return nil
        }
        return kernel
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
