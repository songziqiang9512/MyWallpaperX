import Foundation

nonisolated struct SceneCursorRippleExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let simulationResolution: Int
    let rippleScale: Float
    let decay: Float
    let speed: Float
    let strength: Float
    let maskTexturePath: String?
}

nonisolated enum SceneAuthoredCursorRipplePlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneCursorRippleExecutionPlan? {
        guard graph.effects.count == 1,
              let effect = graph.effects.first,
              normalized(effect.definitionPath) == definitionPath else {
            return nil
        }
        guard graph.blockers.isEmpty,
              graph.nodes.count == 3,
              graph.renderTargets.count == 2,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              layer.contentKind == "image",
              SceneCursorRippleShaderProfile.matches(shaderContracts) else {
            return reject(graph, reason: "shape-or-shader-profile")
        }
        guard effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              let resolution = validDefinition(
                  descriptor: descriptor,
                  effect: effect,
                  graph: graph
              ),
              validMaterials(descriptor.materialPasses),
              layer.effects.indices.contains(effect.key.effectIndex) else {
            return reject(graph, reason: "definition-or-material")
        }
        let instance = layer.effects[effect.key.effectIndex]
        guard instance.id == effect.key.descriptorID,
              normalized(instance.file) == definitionPath,
              instance.visible != false,
              instance.passes.count == 3,
              let rippleScale = scalarPass(
                  instance.passes[0], index: 0, key: "ripplescale", range: 0...2
              ),
              let maskPath = maskPath(instance.passes[1]),
              let decay = scalar(
                  instance.passes[1].constantShaderValues,
                  exactKeys: ["rippledecay", "ripplespeed"],
                  key: "rippledecay",
                  range: 0...1
              ),
              let speed = scalar(
                  instance.passes[1].constantShaderValues,
                  exactKeys: ["rippledecay", "ripplespeed"],
                  key: "ripplespeed",
                  range: 0...1
              ),
              let strength = scalarPass(
                  instance.passes[2], index: 2, key: "ripplestrength", range: 0...1
              ),
              validResolvedNodes(
                  graph.nodes,
                  graph: graph,
                  descriptor: descriptor,
                  effect: effect,
                  maskPath: maskPath.path
              ) else {
            return reject(graph, reason: "instance-or-resolved-node")
        }
        return SceneCursorRippleExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            simulationResolution: resolution,
            rippleScale: rippleScale,
            decay: decay,
            speed: speed,
            strength: strength,
            maskTexturePath: maskPath.path
        )
    }

    private nonisolated static func validDefinition(
        descriptor: SceneRenderDescriptor,
        effect: Graph.Effect,
        graph: Graph
    ) -> Int? {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == definitionPath
        }
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "cursorripple",
              definition.group == "interactive",
              definition.performance == "expensive",
              definition.previewPath == "preview/project.json",
              definition.editable == nil,
              definition.functions == nil,
              definition.gizmos != nil,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 3,
              definition.framebuffers.count == 2,
              definition.dependencies.map(normalized) == dependencies else {
            return nil
        }
        let targets = graph.renderTargets
        guard targets.allSatisfy({
            $0.texture.effect == effect.key
                && $0.extent.kind == .fit
                && ($0.extent.first == 256 || $0.extent.first == 512)
                && $0.extent.second == nil
                && normalized($0.format ?? "") == "rgba8888"
                && !$0.declaredUnique
                && $0.clear == nil && $0.uvs == nil && $0.conditions == nil
        }), Set(targets.compactMap(\.extent.first)).count == 1,
              let authoredResolution = targets.first?.extent.first.map(Int.init),
              [256, 512].contains(authoredResolution),
              validGraphNodes(graph.nodes, effect: effect) else {
            return nil
        }
        return authoredResolution
    }

    private nonisolated static func validGraphNodes(
        _ nodes: [Graph.Node],
        effect: Graph.Effect
    ) -> Bool {
        guard nodes.count == materialPaths.count else { return false }
        let buffer1 = framebuffer(effect.key, name: "_rt_EightBuffer1")
        let buffer2 = framebuffer(effect.key, name: "_rt_EightBuffer2")
        let expectedTargets = [buffer1, buffer2, effect.output]
        let expectedBindings = [[buffer2], [buffer1], [buffer2, effect.input]]
        return nodes.indices.allSatisfy { index in
            let node = nodes[index]
            return node.effect == effect.key
                && node.definitionPassIndex == index
                && node.materialOrdinal == index
                && node.instancePassIndex == index
                && node.kind == .material
                && normalized(node.materialPath ?? "") == materialPaths[index]
                && normalized(node.materialPassID ?? "") == materialPaths[index] + "#0"
                && node.target == expectedTargets[index]
                && node.bindings.map(\.texture) == expectedBindings[index]
                && node.bindings.map(\.slot) == Array(0..<expectedBindings[index].count)
                && node.commandSource == nil && node.commandTarget == nil
                && node.compose == nil && node.conditions == nil
        }
    }

    private nonisolated static func validMaterials(
        _ descriptors: [SceneRenderDescriptor.MaterialPassDescriptor]
    ) -> Bool {
        materialPaths.indices.allSatisfy { index in
            let matches = descriptors.filter {
                normalized($0.id) == materialPaths[index] + "#0"
            }
            guard matches.count == 1, let material = matches.first else { return false }
            return normalized(material.materialPath) == materialPaths[index]
                && material.materialRawSHA256 == materialHashes[index]
                && material.passIndex == 0
                && normalized(material.shaderPath ?? "") == shaderIdentities[index]
                && material.texturePaths.isEmpty && material.textureSlots.isEmpty
                && material.userTextureInputs.isEmpty && material.combos.isEmpty
                && material.constantShaderValues.isEmpty
                && material.userShaderValues.isEmpty
                && material.blending?.lowercased() == "normal"
                && material.depthTest?.lowercased() == "disabled"
                && material.depthWrite?.lowercased() == "disabled"
                && material.cullMode?.lowercased() == "nocull"
                && (index == 2
                    ? material.alphaWriting == nil
                    : material.alphaWriting?.lowercased() == "enabled")
        }
    }

    private nonisolated static func validResolvedNodes(
        _ nodes: [Graph.Node],
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        effect: Graph.Effect,
        maskPath: String?
    ) -> Bool {
        nodes.indices.allSatisfy { index in
            guard let material = SceneAuthoredMaterialResolver.resolve(
                node: nodes[index], graph: graph, descriptor: descriptor
            ).node,
                  normalized(material.shaderPath) == shaderIdentities[index],
                  material.combos.isEmpty,
                  material.renderState.blending?.lowercased() == "normal",
                  material.renderState.depthTest?.lowercased() == "disabled",
                  material.renderState.depthWrite?.lowercased() == "disabled",
                  material.renderState.cullMode?.lowercased() == "nocull" else {
                return false
            }
            let expectedConstants = index == 0
                ? ["ripplescale"] : (index == 1
                    ? ["rippledecay", "ripplespeed"] : ["ripplestrength"])
            guard Set(material.constants.keys.map { $0.lowercased() })
                    == Set(expectedConstants) else {
                return false
            }
            switch index {
            case 0:
                return graphTexture(material.textureSlots[0]) == framebuffer(
                    effect.key, name: "_rt_EightBuffer2"
                ) && allOtherSlotsEmpty(material.textureSlots, except: [0])
            case 1:
                return graphTexture(material.textureSlots[0]) == framebuffer(
                    effect.key, name: "_rt_EightBuffer1"
                ) && assetPath(material.textureSlots[1]) == maskPath
                    && allOtherSlotsEmpty(
                        material.textureSlots, except: maskPath == nil ? [0] : [0, 1]
                    )
            case 2:
                return graphTexture(material.textureSlots[0]) == framebuffer(
                    effect.key, name: "_rt_EightBuffer2"
                ) && graphTexture(material.textureSlots[1]) == effect.input
                    && allOtherSlotsEmpty(material.textureSlots, except: [0, 1])
            default:
                return false
            }
        }
    }

    private struct MaskResolution { let path: String? }

    private nonisolated static func maskPath(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> MaskResolution? {
        guard pass.passIndex == 1, pass.userTextureInputs.isEmpty, pass.combos.isEmpty else {
            return nil
        }
        if pass.textureSlots.isEmpty && pass.texturePaths.isEmpty {
            return MaskResolution(path: nil)
        }
        guard pass.textureSlots.count == 2, pass.textureSlots[0] == nil,
              let path = pass.textureSlots[1], !path.isEmpty,
              pass.texturePaths == [path] else {
            return nil
        }
        return MaskResolution(path: path)
    }

    private nonisolated static func scalarPass(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        index: Int,
        key: String,
        range: ClosedRange<Double>
    ) -> Float? {
        guard pass.passIndex == index,
              pass.textureSlots.isEmpty, pass.texturePaths.isEmpty,
              pass.userTextureInputs.isEmpty, pass.combos.isEmpty else {
            return nil
        }
        return scalar(pass.constantShaderValues, exactKeys: [key], key: key, range: range)
    }

    private nonisolated static func scalar(
        _ values: [String: SceneDocument.ShaderValue],
        exactKeys: Set<String>,
        key: String,
        range: ClosedRange<Double>
    ) -> Float? {
        let lowered = Dictionary(uniqueKeysWithValues: values.map {
            ($0.key.lowercased(), $0.value)
        })
        guard Set(lowered.keys) == exactKeys, let value = lowered[key],
              value.userBinding == nil, value.valueKind.lowercased() == "number",
              value.timeline == nil, value.timelineDiagnostics.isEmpty,
              let components = value.components, components.count == 1,
              let component = components.first, component.isFinite,
              range.contains(component) else {
            return nil
        }
        let result = Float(component)
        return result.isFinite ? result : nil
    }

    private nonisolated static func graphTexture(
        _ slot: SceneResolvedMaterialNode.TextureSlot?
    ) -> Graph.TextureIdentity? {
        guard let slot, slot.candidates.count == 1,
              slot.provenance == .explicitBinding,
              case .graph(let identity) = slot.source else {
            return nil
        }
        return identity
    }

    private nonisolated static func assetPath(
        _ slot: SceneResolvedMaterialNode.TextureSlot?
    ) -> String? {
        guard let slot else { return nil }
        guard slot.candidates.count == 1,
              slot.provenance == .instance,
              case .asset(let path) = slot.source else {
            return nil
        }
        return path
    }

    private nonisolated static func allOtherSlotsEmpty(
        _ slots: [SceneResolvedMaterialNode.TextureSlot?],
        except indices: Set<Int>
    ) -> Bool {
        slots.enumerated().allSatisfy { indices.contains($0.offset) || $0.element == nil }
    }

    private nonisolated static func framebuffer(
        _ key: Graph.EffectKey,
        name: String
    ) -> Graph.TextureIdentity {
        .init(kind: .framebuffer, layerID: key.layerID, effect: key, name: name)
    }

    private nonisolated static func effectOutput(
        _ key: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: key.layerID, effect: key, name: nil)
    }

    private nonisolated static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func reject(
        _ graph: Graph,
        reason: String
    ) -> SceneCursorRippleExecutionPlan? {
#if DEBUG
        print("MWX Cursor Ripple rejected layer=\(graph.layerID) reason=\(reason)")
#endif
        return nil
    }

    private static let definitionPath = "effects/cursorripple/effect.json"
    private static let materialPaths = [
        "materials/effects/cursorripple_apply_force.json",
        "materials/effects/cursorripple_simulate_force.json",
        "materials/effects/cursorripple_combine.json",
    ]
    private static let materialHashes = [
        "bf054f4c73d6b9e166e5b21c79c655042e97413fdaecef58b347539ef411ef3f",
        "7cab9f398eb6a4dface0835810d3969b2882175e5e0cc3843480fc3c4202ac04",
        "78c2ccd59a66010733999456432eed4c236480a0c1393ed7a0457d1efefadd90",
    ]
    private static let shaderIdentities = [
        "effects/cursorripple_apply_force",
        "effects/cursorripple_simulate_force",
        "effects/cursorripple_combine",
    ]
    private static let dependencies = [
        "materials/effects/cursorripple_apply_force.json",
        "materials/effects/cursorripple_simulate_force.json",
        "materials/effects/cursorripple_combine.json",
        "shaders/effects/cursorripple_apply_force.frag",
        "shaders/effects/cursorripple_apply_force.vert",
        "shaders/effects/cursorripple_simulate_force.frag",
        "shaders/effects/cursorripple_simulate_force.vert",
        "shaders/effects/cursorripple_combine.frag",
        "shaders/effects/cursorripple_combine.vert",
    ]
}
