import CryptoKit
import Foundation

nonisolated struct SceneOpacityExecutionPlan {
    nonisolated struct DirectAlphaBinding: Equatable, Sendable {
        let propertyKey: String
        let layerID: Int
        let effectIndex: Int
        let passIndex: Int
        let constantName: String

        nonisolated var dynamicTarget: SceneDynamicTarget {
            .effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: constantName
            )
        }
    }

    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let staticOrFallbackAlpha: Float
    let directAlphaBinding: DirectAlphaBinding?
    /// Exact bounded SceneScript producer. Unlike a user-property binding, a
    /// missing or wrongly-owned frame value is not allowed to fall back to the
    /// authored scalar because that would silently invert authored UI state.
    let requiredSceneScriptAlphaTarget: SceneDynamicTarget?
    /// 官方 `opacity.frag` 的 `#if MASK` 分支读 `g_Texture1`，槽位由实例是否绑图决定。
    /// nil 表示这个实例没绑遮罩，渲染时只乘 alpha。
    let maskTexturePath: String?

    nonisolated var liveAlphaTarget: SceneDynamicTarget? {
        directAlphaBinding?.dynamicTarget ?? requiredSceneScriptAlphaTarget
    }

    nonisolated func resolvedAlpha(in snapshot: SceneDynamicSnapshot) -> Float? {
        if let target = requiredSceneScriptAlphaTarget {
            guard let resolved = snapshot[target],
                  resolved.source == .sceneScript,
                  case .scalar(let rawValue) = resolved.value else { return nil }
            let value = Float(rawValue)
            return value.isFinite && (0...1).contains(value) ? value : nil
        }
        guard let target = directAlphaBinding?.dynamicTarget,
              case .scalar(let rawValue) = snapshot[target]?.value else {
            return staticOrFallbackAlpha
        }
        let value = Float(rawValue)
        return value.isFinite && (0...1).contains(value) ? value : staticOrFallbackAlpha
    }
}

enum SceneAuthoredOpacityPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private nonisolated struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneOpacityExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid", "text", "composition"].contains(layer.contentKind) else {
            return nil
        }

        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard normalized(effect.definitionPath) == definitionPath,
              validDefinition(in: descriptor, path: effect.definitionPath),
              shaderContractMatches(shaderContracts),
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
              validInstance(effect: effect, layer: layer),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                node: node,
                graph: graph,
                descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved),
              let alpha = alpha(from: resolved.constants, effect: effect.key) else {
            return nil
        }

        return SceneOpacityExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            staticOrFallbackAlpha: alpha.value,
            directAlphaBinding: alpha.binding,
            requiredSceneScriptAlphaTarget: alpha.sceneScriptTarget,
            maskTexturePath: maskTexturePath(
                in: layer.effects[effect.key.effectIndex].passes
            )
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
              definition.replacementKey == "opacity",
              definition.name == "ui_editor_effect_opacity_title",
              definition.description == "ui_editor_effect_opacity_description",
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
            && validCombos(material.combos)
            && material.constantShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validInstance(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return false }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first else {
            return false
        }
        return pass.passIndex == 0
            && validMaskTextureBinding(
                paths: pass.texturePaths,
                slots: pass.textureSlots
            )
            && pass.userTextureInputs.isEmpty
            && validCombos(pass.combos)
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode
    ) -> Bool {
        normalized(material.shaderPath) == shaderIdentity
            && validResolvedTextureSlots(material.textureSlots)
            && validCombos(material.combos)
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validMaskTextureBinding(
        paths: [String],
        slots: [String?]
    ) -> Bool {
        if paths.isEmpty && slots.isEmpty {
            return true
        }
        guard slots.count == 2,
              slots[0] == nil,
              let maskPath = slots[1],
              !maskPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return paths == [maskPath]
    }

    /// 只在 `validInstance` 已经放行之后调用：此时 slots 要么为空，要么恰好是 `[nil, mask]`。
    private nonisolated static func maskTexturePath(
        in passes: [SceneRenderDescriptor.EffectDescriptor.PassDescriptor]
    ) -> String? {
        guard let slots = passes.first?.textureSlots, slots.count == 2 else { return nil }
        return slots[1]
    }

    private nonisolated static func validResolvedTextureSlots(
        _ slots: [SceneResolvedMaterialNode.TextureSlot?]
    ) -> Bool {
        if slots.allSatisfy({ $0 == nil }) {
            return true
        }
        guard slots.count > 1,
              slots[0] == nil,
              let mask = slots[1],
              mask.provenance == .instance,
              case .asset(let path) = mask.source,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return slots.enumerated().allSatisfy { index, slot in
            index == 1 || slot == nil
        }
    }

    private nonisolated static func validCombos(_ authored: [String: Int]) -> Bool {
        var normalizedValues: [String: Int] = [:]
        for (key, value) in authored {
            guard normalizedValues.updateValue(value, forKey: key.uppercased()) == nil else {
                return false
            }
        }
        return normalizedValues.keys.allSatisfy { $0 == "MASK" }
            && normalizedValues["MASK", default: 0] == 0
    }

    private nonisolated static func alpha(
        from constants: [String: SceneDocument.ShaderValue],
        effect: Graph.EffectKey
    ) -> (
        value: Float,
        binding: SceneOpacityExecutionPlan.DirectAlphaBinding?,
        sceneScriptTarget: SceneDynamicTarget?
    )? {
        guard constants.count == 1,
              let entry = constants.first,
              entry.key.lowercased() == "alpha",
              let components = entry.value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite,
              (0...1).contains(component) else {
            return nil
        }

        let floatValue = Float(component)
        guard floatValue.isFinite else { return nil }
        let target = SceneDynamicTarget.effectConstant(
            layerID: effect.layerID,
            effectIndex: effect.effectIndex,
            passIndex: 0,
            name: "alpha"
        )
        let binding: SceneOpacityExecutionPlan.DirectAlphaBinding?
        let sceneScriptTarget: SceneDynamicTarget?
        if let propertyKey = entry.value.userBinding?
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !propertyKey.isEmpty,
                  entry.value.valueKind.lowercased() == "binding",
                  entry.value.scriptSource == nil,
                  entry.value.timeline == nil,
                  entry.value.timelineDiagnostics.isEmpty else {
                return nil
            }
            binding = .init(
                propertyKey: propertyKey,
                layerID: effect.layerID,
                effectIndex: effect.effectIndex,
                passIndex: 0,
                constantName: "alpha"
            )
            sceneScriptTarget = nil
        } else if entry.value.scriptSource != nil {
            guard entry.value.valueKind.lowercased() == "binding",
                  entry.value.timeline == nil,
                  entry.value.timelineDiagnostics.isEmpty,
                  entry.value.bindingKeys.sorted() == ["script", "value"] else {
                return nil
            }
            binding = nil
            sceneScriptTarget = target
        } else {
            guard entry.value.valueKind.lowercased() == "number",
                  entry.value.timeline == nil,
                  entry.value.timelineDiagnostics.isEmpty,
                  entry.value.bindingKeys.isEmpty else { return nil }
            binding = nil
            sceneScriptTarget = nil
        }
        return (floatValue, binding, sceneScriptTarget)
    }

    private nonisolated static func shaderContractMatches(
        _ contracts: [SceneShaderContract]
    ) -> Bool {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1, let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.canonicalSHA256 == shaderCanonicalSHA256,
              canonicalHash(contract) == shaderCanonicalSHA256,
              contract.stages.count == 2 else {
            return false
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, vertexPath, vertexSHA256),
            (.fragment, fragmentPath, fragmentSHA256),
        ]
        return zip(contract.stages, expected).allSatisfy { stage, fingerprint in
            stage.kind == fingerprint.0
                && normalized(stage.relativePath) == fingerprint.1
                && stage.rawSHA256 == fingerprint.2
                && sha256(Data(stage.source.utf8)) == fingerprint.2
        }
    }

    private nonisolated static func canonicalHash(_ contract: SceneShaderContract) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalShaderPayload(
            identity: contract.identity,
            sourceKind: contract.sourceKind,
            stages: contract.stages,
            diagnostics: contract.diagnostics
        )
        guard let data = try? encoder.encode(payload) else { return "" }
        return sha256(data)
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static let definitionPath = "effects/opacity/effect.json"
    private nonisolated static let materialPath = "materials/effects/opacity.json"
    private nonisolated static let materialSHA256 =
        "f32a0ee2080b2c79ee395e950ea072e28778d279c5d62e1cc76adbcd2d733747"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let shaderIdentity = "effects/opacity"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/opacity.frag",
        "shaders/effects/opacity.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "89d4ee2fed510c7a81a1d1e8d0d0a353798b607fbe3d637c836fb47efb0c1cd2"
    private nonisolated static let vertexPath = "shaders/effects/opacity.vert"
    private nonisolated static let vertexSHA256 =
        "45803f340c80659ca4726cdea107eb017e7638a64a1b9ff7d30093d1938a738e"
    private nonisolated static let fragmentPath = "shaders/effects/opacity.frag"
    private nonisolated static let fragmentSHA256 =
        "418d565af5509983802c17d1ed901b24b02a6aa8183396cc511ff5f5eefbeb47"
}
