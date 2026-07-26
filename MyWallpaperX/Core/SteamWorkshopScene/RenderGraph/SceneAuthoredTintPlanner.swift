import CryptoKit
import Foundation
import simd

/// 官方 `effects/tint` 的 fail-closed 准入器。
///
/// v1 只接受未绑定遮罩贴图的实例：去重语料（52 包 / 54 份 scene.json）里 224 个 tint pass
/// 有 30 个把遮罩贴到 `g_Texture1`，这些实例整条拒绝而不是按无遮罩渲染。
///
/// 这条拒绝是**待办欠账**，不是证据边界：`SceneEffectMaskSemantics` 与 E-MASK-SLOT-COMBO
/// 已经证明 texture-slot combo 由编辑器按槽位是否绑图在编译期自动设置（官方 59 份 shader
/// 声明 `"combo":"MASK"`，语料 0 次声明），Opacity 已按该证据执行 per-effect 遮罩。Tint
/// 跟进时官方语义是 `mask = g_BlendAlpha` 再 `mask *= tex(g_Texture1).r`，遮罩当混合权重
/// 传给 `ApplyBlending`，不动 alpha 通道。
enum SceneAuthoredTintPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private nonisolated struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    /// `nil` 表示常量形态不合法整条拒绝；`.constant` 表示静态取值、无动态目标。
    private nonisolated enum ConstantSource {
        case constant
        case bound(SceneTintExecutionPlan.ConstantBinding)

        nonisolated var binding: SceneTintExecutionPlan.ConstantBinding? {
            guard case let .bound(binding) = self else { return nil }
            return binding
        }
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneTintExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid", "text"].contains(layer.contentKind)
        else {
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
              let blendMode = blendMode(from: resolved.combos),
              let color = color(from: resolved.constants, effect: effect.key),
              let alpha = alpha(from: resolved.constants, effect: effect.key)
        else {
            return nil
        }

        return SceneTintExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            blendMode: blendMode,
            staticOrFallbackColor: color.value,
            staticOrFallbackAlpha: alpha.value,
            colorBinding: color.source.binding,
            alphaBinding: alpha.source.binding
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
              definition.replacementKey == "tint",
              definition.name == "ui_editor_effect_tint_title",
              definition.description == "ui_editor_effect_tint_description",
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
              let pass = definition.passes.first
        else {
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
              let pass = descriptor.passes.first
        else {
            return false
        }
        return pass.passIndex == 0
            && pass.texturePaths.isEmpty
            && pass.textureSlots.isEmpty
            && pass.userTextureInputs.isEmpty
            && validCombos(pass.combos)
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode
    ) -> Bool {
        normalized(material.shaderPath) == shaderIdentity
            && material.textureSlots.allSatisfy { $0 == nil }
            && validCombos(material.combos)
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func normalizedCombos(_ authored: [String: Int]) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        return result
    }

    private nonisolated static func validCombos(_ authored: [String: Int]) -> Bool {
        guard let combos = normalizedCombos(authored),
              combos.keys.allSatisfy({ ["BLENDMODE", "MASK"].contains($0) }),
              combos["MASK", default: 0] == 0
        else {
            return false
        }
        return (0 ... SceneBlendModeShaderSource.maximumMode)
            .contains(combos["BLENDMODE", default: defaultBlendMode])
    }

    /// 官方 tint.frag 的 `[COMBO]` 注解声明 `BLENDMODE` 默认 30，未声明时按 30 取。
    private nonisolated static func blendMode(from combos: [String: Int]) -> Int? {
        guard let normalized = normalizedCombos(combos) else { return nil }
        let mode = normalized["BLENDMODE", default: defaultBlendMode]
        return (0 ... SceneBlendModeShaderSource.maximumMode).contains(mode) ? mode : nil
    }

    private nonisolated static func color(
        from constants: [String: SceneDocument.ShaderValue],
        effect: Graph.EffectKey
    ) -> (value: SIMD3<Float>, source: ConstantSource)? {
        guard constants.keys.allSatisfy({ ["alpha", "color"].contains($0.lowercased()) }),
              let entry = constants.first(where: { $0.key.lowercased() == "color" }),
              let components = entry.value.components,
              components.count == 3,
              components.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }),
              let source = constantSource(
                  entry.value,
                  staticKind: "vector",
                  name: "color",
                  effect: effect
              )
        else {
            return nil
        }
        let value = SIMD3<Float>(
            Float(components[0]),
            Float(components[1]),
            Float(components[2])
        )
        return (value, source)
    }

    private nonisolated static func alpha(
        from constants: [String: SceneDocument.ShaderValue],
        effect: Graph.EffectKey
    ) -> (value: Float, source: ConstantSource)? {
        guard let entry = constants.first(where: { $0.key.lowercased() == "alpha" }) else {
            // 官方 tint.frag 声明 g_BlendAlpha 默认 1；语料里 180 个实例省略该常量。
            return (defaultAlpha, .constant)
        }
        guard let components = entry.value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite,
              (0 ... 1).contains(component),
              let source = constantSource(
                  entry.value,
                  staticKind: "number",
                  name: "alpha",
                  effect: effect
              )
        else {
            return nil
        }
        return (Float(component), source)
    }

    /// 用户绑定走 `.effectConstant` 动态目标；`script`/`animation` 形态的
    /// `valueKind == "binding"` 但 `userBinding == nil`，在这里被拒绝。
    private nonisolated static func constantSource(
        _ value: SceneDocument.ShaderValue,
        staticKind: String,
        name: String,
        effect: Graph.EffectKey
    ) -> ConstantSource? {
        guard let propertyKey = value.userBinding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return value.valueKind.lowercased() == staticKind ? .constant : nil
        }
        guard !propertyKey.isEmpty, value.valueKind.lowercased() == "binding" else { return nil }
        return .bound(SceneTintExecutionPlan.ConstantBinding(
            propertyKey: propertyKey,
            layerID: effect.layerID,
            effectIndex: effect.effectIndex,
            constantName: name
        ))
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
              contract.stages.count == 2
        else {
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

    private nonisolated static let definitionPath = "effects/tint/effect.json"
    private nonisolated static let materialPath = "materials/effects/tint.json"
    private nonisolated static let materialSHA256 =
        "d5a190abf6ebc13981b7e26ca623577d2cfe0783a343e05fc1a46dcce7cb5016"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let shaderIdentity = "effects/tint"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/tint.frag",
        "shaders/effects/tint.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "606ea00aef226fc0d7d1360f9bb4750af3c323831bc94399c64327084c9f5b36"
    private nonisolated static let vertexPath = "shaders/effects/tint.vert"
    private nonisolated static let vertexSHA256 =
        "62b2f5853fc565d706c1b6c789981385254f8195e0e1579c3d737796b41ddf2a"
    private nonisolated static let fragmentPath = "shaders/effects/tint.frag"
    private nonisolated static let fragmentSHA256 =
        "02b9397cec32de6f0d8caa2e1af7c07510752d474bd64048c9d78f55926973f1"
    private nonisolated static let defaultBlendMode = 30
    private nonisolated static let defaultAlpha: Float = 1
}
