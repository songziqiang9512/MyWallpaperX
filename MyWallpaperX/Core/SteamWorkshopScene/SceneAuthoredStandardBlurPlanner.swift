import Foundation

nonisolated struct SceneStandardBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
    let renderTargetScale: Int
}

enum SceneAuthoredStandardBlurPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> SceneAuthoredEffectExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 4,
              graph.renderTargets.count == 2,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              supportedContentKinds.contains(layer.contentKind) else {
            return nil
        }

        let effect = graph.effects[0]
        let nodes = graph.nodes
        guard isStandardBlurDefinition(effect.definitionPath),
              effect.nodeIndices == nodes.map(\.nodeIndex),
              effect.input == layerSource(layerID: graph.layerID),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              nodes.indices.allSatisfy({ validNode(nodes[$0], ordinal: $0, effect: effect.key) }),
              let quarterA = nodes[0].target,
              let quarterB = nodes[1].target,
              quarterA != quarterB,
              nodes[2].target == quarterA,
              nodes[3].target == effect.output,
              validTarget(quarterA, effect: effect.key, graph: graph),
              validTarget(quarterB, effect: effect.key, graph: graph),
              bindings(nodes[0], equal: [(0, effect.input)]),
              bindings(nodes[1], equal: [(0, quarterA)]),
              bindings(nodes[2], equal: [(0, quarterB)]),
              bindings(nodes[3], equal: [(0, quarterA), (2, effect.input)]) else {
            return nil
        }

        let resolutions = nodes.map {
            SceneAuthoredMaterialResolver.resolve(node: $0, graph: graph, descriptor: descriptor)
        }
        guard resolutions.allSatisfy(\.isResolved) else { return nil }
        let materials = resolutions.compactMap(\.node)
        guard materials.count == 4,
              shader(materials[0], is: "effects/blur_downsample4"),
              shader(materials[1], is: "effects/blur_gaussian"),
              shader(materials[2], is: "effects/blur_gaussian"),
              shader(materials[3], is: "effects/blur_combine"),
              materials.allSatisfy({ supportedState($0.renderState) }),
              supportedDownsample(materials[0], source: effect.input),
              supportedGaussian(materials[1], source: quarterA, vertical: false),
              supportedGaussian(materials[2], source: quarterB, vertical: true),
              supportedCombine(materials[3], blurred: quarterA, previous: effect.input),
              let horizontalScale = scalePair(materials[1].constants),
              let verticalScale = scalePair(materials[2].constants),
              approximatelyEqual(horizontalScale.x, verticalScale.x),
              approximatelyEqual(horizontalScale.y, verticalScale.y) else {
            return nil
        }

        return SceneAuthoredEffectExecutionPlan(
            layerID: graph.layerID,
            renderGraph: graph,
            backend: .standardBlur(SceneStandardBlurPlan(
                horizontalStep: Float(horizontalScale.x),
                verticalStep: Float(verticalScale.y),
                renderTargetScale: 4
            )),
            materialNodeCount: 4,
            logicalRenderTargetCount: 2
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains { isStandardBlurDefinition($0.definitionPath) }
    }

    private nonisolated static let supportedContentKinds = Set([
        "image", "solid", "text", "composition", "project", "fullscreen",
    ])

    private nonisolated static func validNode(
        _ node: Graph.Node,
        ordinal: Int,
        effect: Graph.EffectKey
    ) -> Bool {
        node.kind == .material
            && node.effect == effect
            && node.definitionPassIndex == ordinal
            && node.materialOrdinal == ordinal
            && node.compose == nil
            && node.conditions == nil
            && node.commandSource == nil
            && node.commandTarget == nil
            && node.bindings.allSatisfy { $0.conditions == nil }
    }

    private nonisolated static func validTarget(
        _ texture: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        graph: Graph
    ) -> Bool {
        guard texture.kind == .framebuffer,
              texture.layerID == graph.layerID,
              texture.effect == effect,
              texture.name?.isEmpty == false else {
            return false
        }
        let matches = graph.renderTargets.filter { $0.texture == texture }
        guard matches.count == 1, let target = matches.first else { return false }
        return target.extent.kind == .scale
            && target.extent.first == 4
            && target.extent.second == nil
            && target.format?.lowercased() == "rgba_backbuffer"
            && !target.declaredUnique
            && target.clear == nil
            && target.uvs == nil
            && target.conditions == nil
    }

    private nonisolated static func bindings(
        _ node: Graph.Node,
        equal expected: [(Int, Graph.TextureIdentity)]
    ) -> Bool {
        guard node.bindings.count == expected.count else { return false }
        return expected.allSatisfy { slot, texture in
            let matches = node.bindings.filter { $0.slot == slot }
            return matches.count == 1 && matches[0].texture == texture
        }
    }

    private nonisolated static func supportedDownsample(
        _ material: SceneResolvedMaterialNode,
        source: Graph.TextureIdentity
    ) -> Bool {
        normalizedCombos(material.combos)?.isEmpty == true
            && normalizedConstants(material.constants)?.isEmpty == true
            && textureSlots(material.textureSlots, equal: [0: source])
    }

    private nonisolated static func supportedGaussian(
        _ material: SceneResolvedMaterialNode,
        source: Graph.TextureIdentity,
        vertical: Bool
    ) -> Bool {
        guard let combos = normalizedCombos(material.combos),
              combos.keys.allSatisfy({ ["KERNEL", "VERTICAL"].contains($0) }),
              combos["KERNEL", default: 0] == 0,
              combos["VERTICAL", default: 0] == (vertical ? 1 : 0),
              let constants = normalizedConstants(material.constants),
              Set(constants.keys) == ["scale"] else {
            return false
        }
        return textureSlots(material.textureSlots, equal: [0: source])
    }

    private nonisolated static func supportedCombine(
        _ material: SceneResolvedMaterialNode,
        blurred: Graph.TextureIdentity,
        previous: Graph.TextureIdentity
    ) -> Bool {
        guard let combos = normalizedCombos(material.combos),
              combos.keys.allSatisfy({
                  ["COMPOSITE", "BLENDMODE", "COMPOSITEMONO", "BLURALPHA", "MASK"]
                      .contains($0)
              }),
              combos["COMPOSITE", default: 0] == 0,
              combos["BLENDMODE", default: 0] == 0,
              combos["COMPOSITEMONO", default: 0] == 0,
              combos["BLURALPHA", default: 1] == 1,
              combos["MASK", default: 0] == 0,
              let constants = normalizedConstants(material.constants),
              constants.keys.allSatisfy({
                  ["compositealpha", "compositeoffset", "compositecolor"].contains($0)
              }),
              defaultScalar(constants["compositealpha"], fallback: 1) == 1,
              defaultVector(constants["compositeoffset"], fallback: [0, 0]) == [0, 0],
              defaultVector(constants["compositecolor"], fallback: [1, 1, 1]) == [1, 1, 1] else {
            return false
        }
        return textureSlots(material.textureSlots, equal: [0: blurred, 2: previous])
    }

    private nonisolated static func textureSlots(
        _ slots: [SceneResolvedMaterialNode.TextureSlot?],
        equal expected: [Int: Graph.TextureIdentity]
    ) -> Bool {
        for index in slots.indices {
            guard let expectedTexture = expected[index] else {
                if slots[index] != nil { return false }
                continue
            }
            guard let slot = slots[index], case .graph(let texture) = slot.source,
                  texture == expectedTexture else {
                return false
            }
        }
        return true
    }

    private nonisolated static func supportedState(
        _ state: SceneResolvedMaterialNode.RenderState
    ) -> Bool {
        state.blending?.lowercased() == "normal"
            && state.depthTest?.lowercased() == "disabled"
            && state.depthWrite?.lowercased() == "disabled"
            && state.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func shader(
        _ material: SceneResolvedMaterialNode,
        is expected: String
    ) -> Bool {
        normalizedPath(material.shaderPath) == expected
    }

    private nonisolated static func normalizedCombos(
        _ authored: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        return result
    }

    private nonisolated static func normalizedConstants(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> [String: SceneDocument.ShaderValue]? {
        var result: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        return result
    }

    private nonisolated static func scalePair(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> (x: Double, y: Double)? {
        guard let values = normalizedConstants(authored),
              Set(values.keys) == ["scale"],
              let components = values["scale"]?.components,
              components.count == 1 || components.count == 2,
              components.allSatisfy({ $0.isFinite && (0.01...2).contains($0) }) else {
            return nil
        }
        return (components[0], components.count == 1 ? components[0] : components[1])
    }

    private nonisolated static func defaultScalar(
        _ value: SceneDocument.ShaderValue?,
        fallback: Double
    ) -> Double? {
        guard let value else { return fallback }
        guard value.userBinding == nil, let components = value.components,
              components.count == 1, components[0].isFinite else { return nil }
        return components[0]
    }

    private nonisolated static func defaultVector(
        _ value: SceneDocument.ShaderValue?,
        fallback: [Double]
    ) -> [Double]? {
        guard let value else { return fallback }
        guard value.userBinding == nil, let components = value.components,
              components.count == fallback.count,
              components.allSatisfy(\.isFinite) else { return nil }
        return components
    }

    private nonisolated static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.000_001
    }

    private nonisolated static func isStandardBlurDefinition(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return normalized == "effects/blur/effect.json"
            || normalized.hasSuffix("/effects/blur/effect.json")
    }

    private nonisolated static func normalizedPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func layerSource(layerID: Int) -> Graph.TextureIdentity {
        .init(kind: .layerSource, layerID: layerID, effect: nil, name: nil)
    }

    private nonisolated static func effectOutput(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }
}
