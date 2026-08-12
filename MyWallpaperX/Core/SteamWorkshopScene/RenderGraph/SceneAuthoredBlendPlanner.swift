import Foundation

/// Fail-closed admission for the single-texture-v1 `effects/blend` contract.
enum SceneAuthoredBlendPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct TextureSelection {
        let assetPath: String
        let propertyKey: String?
    }

    private struct Multiply {
        let authoredValue: Float
        let alphaMultiply: Float
        let dynamicBinding: SceneTimeOfDayEffectScriptBinding?
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneBlendExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid"].contains(layer.contentKind) else {
            return nil
        }

        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard normalized(effect.definitionPath) == definitionPath,
              let shaderProfile = SceneBlendShaderProfile.resolve(shaderContracts),
              validDefinition(in: descriptor, path: effect.definitionPath),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input,
                  layerID: graph.layerID,
                  role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect),
              validMaterialDescriptor(in: descriptor),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validRenderState(resolved.renderState),
              let writesAlpha = writesAlpha(in: resolved.combos),
              validInstance(
                  effect: effect,
                  layer: layer,
                  writesAlpha: writesAlpha
              ),
              let multiply = multiply(
                  from: resolved.constants,
                  target: multiplyTarget(for: effect.key),
                  writesAlpha: writesAlpha
              ),
              let selection = textureSelection(
                  from: resolved.textureSlots,
                  texturePropertyKeys: Set(descriptor.texturePropertyKeys)
              ) else {
            return nil
        }

        return SceneBlendExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            shaderProfile: shaderProfile,
            blendMode: 0,
            multiply: multiply.authoredValue,
            alphaMultiply: multiply.alphaMultiply,
            writesAlpha: writesAlpha,
            dynamicMultiplyBinding: multiply.dynamicBinding,
            assetTexturePath: selection.assetPath,
            userPropertyKey: selection.propertyKey
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains { normalized($0.definitionPath) == definitionPath }
    }

    private nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "blend",
              definition.name == "ui_editor_effect_blend_title",
              definition.description == "ui_editor_effect_blend_description",
              definition.group == "colorize",
              definition.performance == nil,
              definition.previewPath == "preview/project.json",
              definition.editable == nil,
              definition.framebuffers.isEmpty,
              definition.dependencies.map(normalized) == dependencies,
              definition.functions == nil,
              definition.gizmos == nil,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 1,
              let pass = definition.passes.first else {
            return false
        }
        return pass.passIndex == 0
            && normalized(pass.materialPath ?? "") == materialPath
            && pass.target == nil
            && pass.bindings.isEmpty
            && pass.compose == nil
            && pass.command == nil
            && pass.source == nil
            && pass.conditions == nil
            && pass.extraFields.isEmpty
    }

    private nonisolated static func validNode(
        _ node: Graph.Node,
        effect: Graph.Effect
    ) -> Bool {
        node.effect == effect.key
            && node.definitionPassIndex == 0
            && node.materialOrdinal == 0
            && node.instancePassIndex == 0
            && node.kind == .material
            && normalized(node.materialPath ?? "") == materialPath
            && normalized(node.materialPassID ?? "") == materialPassID
            && node.target == effect.output
            && node.bindings.isEmpty
            && node.commandSource == nil
            && node.commandTarget == nil
            && node.compose == nil
            && node.conditions == nil
    }

    private nonisolated static func validMaterialDescriptor(
        in descriptor: SceneRenderDescriptor
    ) -> Bool {
        let matches = descriptor.materialPasses.filter {
            normalized($0.id) == materialPassID
        }
        guard matches.count == 1, let material = matches.first else { return false }
        return normalized(material.materialPath) == materialPath
            && material.materialRawSHA256 == materialSHA256
            && material.passIndex == 0
            && normalized(material.shaderPath ?? "") == shaderIdentity
            && material.texturePaths.isEmpty
            && material.textureSlots.isEmpty
            && material.userTextureInputs.isEmpty
            && material.combos.isEmpty
            && material.constantShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validInstance(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer,
        writesAlpha expectedWritesAlpha: Bool
    ) -> Bool {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return false }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first,
              pass.passIndex == 0,
              pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              let path = pass.textureSlots[1],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pass.texturePaths == [path],
              validUserTextureInputs(pass.userTextureInputs),
              writesAlpha(in: pass.combos) == expectedWritesAlpha,
              multiply(
                  from: pass.constantShaderValues,
                  target: multiplyTarget(for: effect.key),
                  writesAlpha: expectedWritesAlpha
              ) != nil else {
            return false
        }
        return SceneNamedTextureReference.parse(path) == nil
    }

    private nonisolated static func validUserTextureInputs(
        _ inputs: [SceneEffectTextureInput?]
    ) -> Bool {
        if inputs.isEmpty { return true }
        guard inputs.count == 2, inputs[0] == nil, let input = inputs[1] else { return false }
        return input.kind == .property && !input.value.isEmpty
    }

    private nonisolated static func textureSelection(
        from slots: [SceneResolvedMaterialNode.TextureSlot?],
        texturePropertyKeys: Set<String>
    ) -> TextureSelection? {
        guard slots.indices.contains(1),
              let slot = slots[1],
              slot.index == 1,
              slots.enumerated().allSatisfy({ $0.offset == 1 || $0.element == nil }),
              (1...2).contains(slot.candidates.count),
              slot.candidates[0].provenance == .instance,
              case .asset(let assetPath) = slot.candidates[0].source,
              !assetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              SceneNamedTextureReference.parse(assetPath) == nil else {
            return nil
        }
        guard slot.candidates.count == 2 else {
            return TextureSelection(assetPath: assetPath, propertyKey: nil)
        }
        let propertyCandidate = slot.candidates[1]
        guard propertyCandidate.provenance == .userTexture,
              case .userTexture(let input) = propertyCandidate.source,
              input.kind == .property,
              texturePropertyKeys.contains(input.value) else {
            return nil
        }
        return TextureSelection(assetPath: assetPath, propertyKey: input.value)
    }

    private nonisolated static func validRenderState(
        _ state: SceneResolvedMaterialNode.RenderState
    ) -> Bool {
        state.blending?.lowercased() == "normal"
            && state.depthTest?.lowercased() == "disabled"
            && state.depthWrite?.lowercased() == "disabled"
            && state.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func writesAlpha(
        in authored: [String: Int]
    ) -> Bool? {
        var combos: [String: Int] = [:]
        for (key, value) in authored {
            guard combos.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        let allowed = Set([
            "BLENDMODE", "TRANSFORMUV", "TRANSFORMREPEAT", "WRITEALPHA",
            "NUMBLENDTEXTURES", "OPACITYMASK",
        ])
        guard combos.keys.allSatisfy(allowed.contains)
            && combos["BLENDMODE"] == 0
            && combos["TRANSFORMUV", default: 0] == 0
            && combos["TRANSFORMREPEAT", default: 0] == 0
            && (0...1).contains(combos["WRITEALPHA", default: 0])
            && combos["NUMBLENDTEXTURES", default: 1] == 1
            && combos["OPACITYMASK", default: 0] == 0 else {
            return nil
        }
        return combos["WRITEALPHA", default: 0] == 1
    }

    private nonisolated static func multiply(
        from constants: [String: SceneDocument.ShaderValue],
        target: SceneDynamicTarget,
        writesAlpha: Bool
    ) -> Multiply? {
        var normalized: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in constants {
            guard normalized.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        let allowed = Set(["multiply", "alpha", "blendangle", "blendoffset", "blendscale"])
        let alphaRange: ClosedRange<Float> = writesAlpha ? 0...1 : 1...1
        guard normalized.keys.allSatisfy(allowed.contains),
              let alphaMultiply = number(
                  normalized["alpha"], range: alphaRange, default: 1
              ),
              number(normalized["blendangle"], range: 0...0, default: 0) != nil,
              number(normalized["blendscale"], range: 1...1, default: 1) != nil,
              validNeutralOffset(normalized["blendoffset"]) else {
            return nil
        }
        if let multiply = number(normalized["multiply"], range: 0...2) {
            return Multiply(
                authoredValue: multiply,
                alphaMultiply: alphaMultiply,
                dynamicBinding: nil
            )
        }
        guard let value = normalized["multiply"],
              let binding = SceneTimeOfDayEffectScriptCompiler.compile(
                  value: value, target: target
              ),
              case let .scalar(authored) = binding.definition.authoredValue else {
            return nil
        }
        return Multiply(
            authoredValue: Float(authored),
            alphaMultiply: alphaMultiply,
            dynamicBinding: binding
        )
    }

    private nonisolated static func multiplyTarget(
        for effect: Graph.EffectKey
    ) -> SceneDynamicTarget {
        .effectConstant(
            layerID: effect.layerID,
            effectIndex: effect.effectIndex,
            passIndex: 0,
            name: "multiply"
        )
    }

    private nonisolated static func number(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Float>,
        default defaultValue: Float? = nil
    ) -> Float? {
        guard let value else { return defaultValue }
        guard value.userBinding == nil,
              value.valueKind.lowercased() == "number",
              let components = value.components,
              components.count == 1,
              let raw = components.first,
              raw.isFinite else {
            return nil
        }
        let result = Float(raw)
        return range.contains(result) ? result : nil
    }

    private nonisolated static func validNeutralOffset(
        _ value: SceneDocument.ShaderValue?
    ) -> Bool {
        guard let value else { return true }
        guard value.userBinding == nil,
              value.valueKind.lowercased() == "vector",
              let components = value.components,
              components.count == 2 else {
            return false
        }
        return components.allSatisfy { $0.isFinite && abs($0) < 0.000_001 }
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static let definitionPath = "effects/blend/effect.json"
    private nonisolated static let materialPath = "materials/effects/blend.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "c2478eb0d0692751dcb504995efb02a684d21ced44de1ea04212eb221e824fa7"
    private nonisolated static let shaderIdentity = "effects/blend"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/blend.frag",
        "shaders/effects/blend.vert",
    ]
}
