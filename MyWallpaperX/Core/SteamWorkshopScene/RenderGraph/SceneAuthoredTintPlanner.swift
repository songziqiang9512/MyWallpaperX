import Foundation
import simd

/// Tint 的 fail-closed 准入器。
///
/// definition -> material -> shader 的路径由作者资产自身推导；material 与 shader 源仍按
/// [SceneTintAssetProfile](SceneTintAssetProfile.swift) / [SceneTintShaderProfile]
/// 的精确内容指纹准入。
///
/// 槽位 1 遮罩按 shader 指纹分流：stock 语义先用 `g_BlendAlpha`，再乘遮罩 R；legacy
/// 语义由遮罩 R 覆盖。遮罩只作为 `ApplyBlending` 权重，不改 alpha 通道。
enum SceneAuthoredTintPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

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
        guard let assets = SceneTintAssetProfile.resolve(
                  descriptor: descriptor,
                  definitionPath: effect.definitionPath,
                  shaderContracts: shaderContracts
              ),
              validDefinition(in: descriptor, assets: assets),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input,
                  layerID: graph.layerID,
                  role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect, assets: assets),
              validMaterialDescriptor(in: descriptor, assets: assets),
              let maskPath = maskTexturePath(effect: effect, layer: layer, assets: assets),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved, maskPath: maskPath.path, assets: assets),
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
            shaderProfile: assets.shaderProfile,
            blendMode: blendMode,
            staticOrFallbackColor: color.value,
            staticOrFallbackAlpha: alpha.value,
            colorBinding: color.source.binding,
            alphaBinding: alpha.source.binding,
            maskTexturePath: maskPath.path
        )
    }

    private nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        assets: SceneTintAssetProfile
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == assets.definitionPath
        }
        let validReplacementKeys: [String?] = assets.shaderProfile.acceptsMissingReplacementKey
            ? ["tint", nil]
            : ["tint"]
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              validReplacementKeys.contains(definition.replacementKey),
              definition.name == "ui_editor_effect_tint_title",
              definition.description == "ui_editor_effect_tint_description",
              definition.group == "colorize",
              definition.performance == nil,
              definition.previewPath == "preview/project.json",
              definition.editable == nil,
              definition.framebuffers.isEmpty,
              definition.dependencies.map(normalized) == assets.dependencies,
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
            && normalized(pass.materialPath ?? "") == assets.materialPath
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
        effect: Graph.Effect,
        assets: SceneTintAssetProfile
    ) -> Bool {
        node.effect == effect.key
            && node.definitionPassIndex == 0
            && node.materialOrdinal == 0
            && node.instancePassIndex == 0
            && node.kind == .material
            && normalized(node.materialPath ?? "") == assets.materialPath
            && normalized(node.materialPassID ?? "") == assets.materialPassID
            && node.target == effect.output
            && node.bindings.isEmpty
            && node.commandSource == nil
            && node.commandTarget == nil
            && node.compose == nil
            && node.conditions == nil
    }

    private nonisolated static func validMaterialDescriptor(
        in descriptor: SceneRenderDescriptor,
        assets: SceneTintAssetProfile
    ) -> Bool {
        let matches = descriptor.materialPasses.filter {
            normalized($0.id) == assets.materialPassID
        }
        guard matches.count == 1, let material = matches.first else { return false }
        return normalized(material.materialPath) == assets.materialPath
            && material.materialRawSHA256 == assets.materialSHA256
            && material.passIndex == 0
            && normalized(material.shaderPath ?? "") == assets.shaderIdentity
            && material.texturePaths.isEmpty
            && material.textureSlots.isEmpty
            && material.userTextureInputs.isEmpty
            && validCombos(material.combos)
            && material.constantShaderValues.isEmpty
            && material.userShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
            && material.alphaWriting == nil
    }

    /// 区分「拒绝」（nil）与「合法无遮罩」（`.path == nil`）。官方 tint.frag 的遮罩挂在
    /// 槽位 1（`g_Texture1`），编辑器按绑图在编译期自动置 `MASK`（E-MASK-SLOT-COMBO，
    /// 语料 0 次显式声明），语义为 `mask = g_BlendAlpha * tex.r`（stock）/ `tex.r` 覆盖
    /// （legacy），是 `ApplyBlending` 的混合权重，不动 alpha 通道。
    private struct MaskResolution {
        let path: String?
    }

    private nonisolated static func maskTexturePath(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer,
        assets: SceneTintAssetProfile
    ) -> MaskResolution? {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return nil }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == assets.definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first,
              pass.passIndex == 0,
              pass.userTextureInputs.isEmpty,
              validCombos(pass.combos)
        else {
            return nil
        }
        if pass.texturePaths.isEmpty && pass.textureSlots.isEmpty {
            return MaskResolution(path: nil)
        }
        guard pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              let maskPath = pass.textureSlots[1],
              !maskPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pass.texturePaths == [maskPath]
        else {
            return nil
        }
        return MaskResolution(path: maskPath)
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        maskPath: String?,
        assets: SceneTintAssetProfile
    ) -> Bool {
        guard normalized(material.shaderPath) == assets.shaderIdentity,
              validCombos(material.combos),
              material.renderState.blending?.lowercased() == "normal",
              material.renderState.depthTest?.lowercased() == "disabled",
              material.renderState.depthWrite?.lowercased() == "disabled",
              material.renderState.cullMode?.lowercased() == "nocull"
        else {
            return false
        }
        guard let maskPath else {
            return material.textureSlots.allSatisfy { $0 == nil }
        }
        guard material.textureSlots.count > 1,
              material.textureSlots[0] == nil,
              let slot = material.textureSlots[1],
              slot.provenance == .instance,
              case .asset(let path) = slot.source,
              path == maskPath
        else {
            return false
        }
        return material.textureSlots.enumerated().allSatisfy { index, slot in
            index == 1 || slot == nil
        }
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

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    /// stock 与 legacy 两个指纹的 `[COMBO]` 注解逐字符一致，默认值不按 profile 分流。
    private nonisolated static let defaultBlendMode = 30
    private nonisolated static let defaultAlpha: Float = 1
}
