import Foundation
import simd

nonisolated struct SceneWaterWavesExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let shaderProfile: SceneWaterWavesShaderProfile
    /// 已按 profile 归一（`legacyReversedDirection` 的基向量翻转折算为 +π）。
    let direction: Float
    let speed: Float
    let scale: Float
    let exponent: Float
    let strength: Float
    /// nil 表示 legacy 实例未绑遮罩（v1 default `util/white`、v2 MASK combo 未启用，
    /// 均等价无遮罩）；stock profile 恒非 nil。
    let maskTexturePath: String?
}

enum SceneAuthoredWaterWavesPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct Parameters {
        let direction: Float
        let speed: Float
        let scale: Float
        let exponent: Float
        let strength: Float
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWaterWavesExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              layer.contentKind == "image" else {
            return nil
        }

        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard normalized(effect.definitionPath) == definitionPath,
              let profile = SceneWaterWavesShaderProfile.resolve(shaderContracts),
              validDefinition(in: descriptor, path: effect.definitionPath, profile: profile),
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
              let instance = instancePass(effect: effect, layer: layer),
              let maskPath = maskPath(from: instance, profile: profile),
              let parameters = parameters(
                  from: instance.constantShaderValues,
                  profile: profile
              ),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(
                  resolved,
                  maskPath: maskPath,
                  parameters: parameters,
                  profile: profile
              ) else {
            return nil
        }

        return SceneWaterWavesExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            shaderProfile: profile,
            direction: parameters.direction + profile.directionOffset,
            speed: parameters.speed,
            scale: parameters.scale,
            exponent: parameters.exponent,
            strength: parameters.strength,
            maskTexturePath: maskPath.path
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains { normalized($0.definitionPath) == definitionPath }
    }

    private nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String,
        profile: SceneWaterWavesShaderProfile
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "waterwaves",
              definition.name == "ui_editor_effect_water_waves_title",
              definition.description == "ui_editor_effect_water_waves_description",
              definition.group == "animate",
              definition.performance == nil,
              definition.previewPath == "preview/project.json",
              definition.editable == nil,
              definition.framebuffers.isEmpty,
              definition.dependencies.map(normalized) == dependencies,
              definition.functions == nil,
              definition.gizmos == (profile.expectsGizmos ? expectedGizmos : nil),
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

    private nonisolated static func instancePass(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer
    ) -> SceneRenderDescriptor.EffectDescriptor.PassDescriptor? {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return nil }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first,
              pass.passIndex == 0,
              pass.userTextureInputs.isEmpty,
              pass.combos.isEmpty else {
            return nil
        }
        return pass
    }

    /// 区分「拒绝」（nil）与「合法无遮罩」（`.path == nil`，仅 legacy profile）。
    private struct MaskResolution {
        let path: String?
    }

    private nonisolated static func maskPath(
        from pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        profile: SceneWaterWavesShaderProfile
    ) -> MaskResolution? {
        if pass.textureSlots.isEmpty && pass.texturePaths.isEmpty {
            return profile.requiresMaskTexture ? nil : MaskResolution(path: nil)
        }
        guard pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              let path = pass.textureSlots[1],
              !path.isEmpty,
              pass.texturePaths == [path] else {
            return nil
        }
        return MaskResolution(path: path)
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        maskPath: MaskResolution,
        parameters: Parameters,
        profile: SceneWaterWavesShaderProfile
    ) -> Bool {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              assetPath(material.textureSlots[1]) == maskPath.path,
              material.textureSlots.enumerated().allSatisfy({
                  $0.offset == 1 || $0.element == nil
              }),
              material.combos.isEmpty,
              let resolvedParameters = self.parameters(
                  from: material.constants,
                  profile: profile
              ),
              resolvedParameters.direction == parameters.direction,
              resolvedParameters.speed == parameters.speed,
              resolvedParameters.scale == parameters.scale,
              resolvedParameters.exponent == parameters.exponent,
              resolvedParameters.strength == parameters.strength else {
            return false
        }
        return material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func assetPath(
        _ slot: SceneResolvedMaterialNode.TextureSlot?
    ) -> String? {
        guard let slot, slot.candidates.count == 1,
              slot.provenance == .instance,
              case .asset(let path) = slot.source else {
            return nil
        }
        return path
    }

    private nonisolated static func parameters(
        from authored: [String: SceneDocument.ShaderValue],
        profile: SceneWaterWavesShaderProfile
    ) -> Parameters? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        guard profile.allowsOmittedConstants else {
            guard Set(values.keys)
                == Set(["direction", "speed", "scale", "exponent", "strength"]),
                let direction = scalar(values["direction"]),
                let speed = scalar(values["speed"], range: 0.01...50),
                let scale = scalar(values["scale"], range: 0.01...1000),
                let exponent = scalar(values["exponent"], range: 0.51...4),
                let strength = scalar(values["strength"], range: 0.01...1) else {
                return nil
            }
            return Parameters(
                direction: direction,
                speed: speed,
                scale: scale,
                exponent: exponent,
                strength: strength
            )
        }
        // legacy shader 无 g_Exponent；语料按旧编辑器行为省略未改动键，缺省用注解 default。
        // `perspective` 是 legacy 专有标量（range [0,0.2]），语料全部为 0，非 0 无执行
        // oracle，fail closed；执行端因此无需 perspective 修正项。
        let legacyKeys: Set<String> = ["direction", "speed", "scale", "strength", "perspective"]
        guard Set(values.keys).isSubset(of: legacyKeys),
              !profile.supportsExponent,
              let direction = scalarOrDefault(values["direction"], default: 0),
              let speed = scalarOrDefault(values["speed"], range: 0.01...50, default: 5),
              let scale = scalarOrDefault(values["scale"], range: 0.01...1000, default: 200),
              let strength = scalarOrDefault(values["strength"], range: 0.01...1, default: 0.1),
              let perspective = scalarOrDefault(values["perspective"], range: 0...0.2, default: 0),
              perspective == 0 else {
            return nil
        }
        return Parameters(
            direction: direction,
            speed: speed,
            scale: scale,
            exponent: 1,
            strength: strength
        )
    }

    private nonisolated static func scalarOrDefault(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>? = nil,
        default defaultValue: Float
    ) -> Float? {
        guard value != nil else { return defaultValue }
        return scalar(value, range: range)
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>? = nil
    ) -> Float? {
        guard let value,
              value.userBinding == nil,
              value.valueKind.lowercased() == "number",
              let components = value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite else {
            return nil
        }
        // range 按 Float 精度比较：作者值是编辑器 float32 序列化（语料
        // `2131872317` 的 scale 0.01 存成 0.009999999776…），shader 消费同为 Float。
        let result = Float(component)
        guard result.isFinite,
              range.map({ ClosedRange(
                  uncheckedBounds: (Float($0.lowerBound), Float($0.upperBound))
              ).contains(result) }) ?? true else {
            return nil
        }
        return result
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static let definitionPath = "effects/waterwaves/effect.json"
    private nonisolated static let materialPath = "materials/effects/waterwaves.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "2d465e099edb237ace15febe68a19eb833702a636972830bb43409e961c246b5"
    private nonisolated static let shaderIdentity = "effects/waterwaves"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/waterwaves.frag",
        "shaders/effects/waterwaves.vert",
    ]
    private nonisolated static let expectedGizmos = SceneJSONValue.array([
        .object([
            "condition": .object(["PERSPECTIVE": .number(1)]),
            "type": .string("EffectPerspectiveUV"),
            "vars": .object([
                "p0": .string("point0"),
                "p1": .string("point1"),
                "p2": .string("point2"),
                "p3": .string("point3"),
            ]),
        ]),
    ])
}
