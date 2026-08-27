import Foundation

/// Exact whole-stage graph contract for the shared blurred/current composite
/// MaterialProgram profile. This is an admission predicate only: it does not
/// plan, render, or own product output.
nonisolated enum SceneResolvedMaterialUnitPreviousBlurredCompositeGraphAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func accepts(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        inputRole: SceneAuthoredEffectInputRole
    ) -> Bool {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 4,
              graph.renderTargets.count == 2,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              supportedContentKinds.contains(layer.contentKind) else {
            return false
        }

        let effect = graph.effects[0]
        let nodes = graph.nodes
        guard isBlurDefinition(effect.definitionPath),
              effect.nodeIndices == nodes.map(\.nodeIndex),
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input,
                  layerID: graph.layerID,
                  role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              nodes.indices.allSatisfy({
                  validNode(nodes[$0], ordinal: $0, effect: effect.key)
              }),
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
            return false
        }

        let resolutions = nodes.map {
            SceneAuthoredMaterialResolver.resolve(
                node: $0,
                graph: graph,
                descriptor: descriptor
            )
        }
        guard resolutions.allSatisfy(\.isResolved) else { return false }
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
              supportedCombine(
                  materials[3],
                  blurred: quarterA,
                  previous: effect.input
              ),
              let horizontalScale = scalePair(materials[1].constants),
              let verticalScale = scalePair(materials[2].constants),
              approximatelyEqual(horizontalScale.x, verticalScale.x),
              approximatelyEqual(horizontalScale.y, verticalScale.y) else {
            return false
        }
        return true
    }

    private static let supportedContentKinds = Set([
        "image", "solid", "text", "composition", "project", "fullscreen",
    ])

    private static func validNode(
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

    private static func validTarget(
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

    private static func bindings(
        _ node: Graph.Node,
        equal expected: [(Int, Graph.TextureIdentity)]
    ) -> Bool {
        guard node.bindings.count == expected.count else { return false }
        return expected.allSatisfy { slot, texture in
            let matches = node.bindings.filter { $0.slot == slot }
            return matches.count == 1 && matches[0].texture == texture
        }
    }

    private static func supportedDownsample(
        _ material: SceneResolvedMaterialNode,
        source: Graph.TextureIdentity
    ) -> Bool {
        normalizedCombos(material.combos)?.isEmpty == true
            && normalizedConstants(material.constants)?.isEmpty == true
            && textureSlots(material.textureSlots, equal: [0: source])
    }

    private static func supportedGaussian(
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

    private static func supportedCombine(
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
              [0, 1].contains(combos["MASK", default: 0]),
              let constants = normalizedConstants(material.constants),
              constants.keys.allSatisfy({
                  ["compositealpha", "compositeoffset", "compositecolor"].contains($0)
              }),
              defaultScalar(constants["compositealpha"], fallback: 1) == 1,
              defaultVector(constants["compositeoffset"], fallback: [0, 0]) == [0, 0],
              defaultVector(constants["compositecolor"], fallback: [1, 1, 1]) == [1, 1, 1],
              textureSlots(
                  material.textureSlots,
                  equal: [0: blurred, 2: previous],
                  allowingAssetAt: 1
              ) else {
            return false
        }
        guard let maskSlot = material.textureSlots[1] else {
            return combos["MASK", default: 0] == 0
        }
        guard maskSlot.provenance == .instance,
              case .asset(let maskPath) = maskSlot.source else {
            return false
        }
        return !maskPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func textureSlots(
        _ slots: [SceneResolvedMaterialNode.TextureSlot?],
        equal expected: [Int: Graph.TextureIdentity],
        allowingAssetAt allowedAssetIndex: Int? = nil
    ) -> Bool {
        for index in slots.indices {
            guard let expectedTexture = expected[index] else {
                if index == allowedAssetIndex,
                   let slot = slots[index],
                   slot.provenance == .instance,
                   case .asset(let path) = slot.source,
                   !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }
                if slots[index] != nil { return false }
                continue
            }
            guard let slot = slots[index],
                  case .graph(let texture) = slot.source,
                  texture == expectedTexture else {
                return false
            }
        }
        return true
    }

    private static func supportedState(
        _ state: SceneResolvedMaterialNode.RenderState
    ) -> Bool {
        state.blending?.lowercased() == "normal"
            && state.depthTest?.lowercased() == "disabled"
            && state.depthWrite?.lowercased() == "disabled"
            && state.cullMode?.lowercased() == "nocull"
    }

    private static func shader(
        _ material: SceneResolvedMaterialNode,
        is expected: String
    ) -> Bool {
        normalizedPath(material.shaderPath) == expected
    }

    private static func normalizedCombos(
        _ authored: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else {
                return nil
            }
        }
        return result
    }

    private static func normalizedConstants(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> [String: SceneDocument.ShaderValue]? {
        var result: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        return result
    }

    private static func scalePair(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> (x: Double, y: Double)? {
        guard let values = normalizedConstants(authored),
              Set(values.keys) == ["scale"],
              let components = values["scale"]?.components,
              components.count == 1 || components.count == 2,
              components.allSatisfy({ $0.isFinite && (0.01 ... 2).contains($0) }) else {
            return nil
        }
        return (components[0], components.count == 1 ? components[0] : components[1])
    }

    private static func defaultScalar(
        _ value: SceneDocument.ShaderValue?,
        fallback: Double
    ) -> Double? {
        guard let value else { return fallback }
        guard value.userBinding == nil,
              let components = value.components,
              components.count == 1,
              components[0].isFinite else {
            return nil
        }
        return components[0]
    }

    private static func defaultVector(
        _ value: SceneDocument.ShaderValue?,
        fallback: [Double]
    ) -> [Double]? {
        guard let value else { return fallback }
        guard value.userBinding == nil,
              let components = value.components,
              components.count == fallback.count,
              components.allSatisfy(\.isFinite) else {
            return nil
        }
        return components
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.000_001
    }

    private static func isBlurDefinition(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return normalized == "effects/blur/effect.json"
            || normalized.hasSuffix("/effects/blur/effect.json")
    }

    private static func normalizedPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func effectOutput(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }
}
