import Foundation
import simd

/// 只把已登记 Iris shader 的单 pass、单遮罩实例接到 authored chain 末端。
/// 该 stage 明确保持 `inline-profile` 降级级别，不宣称 Iris 像素等价。
nonisolated enum SceneAuthoredIrisInlineSuffixPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct Parameters {
        let scale: SIMD2<Float>
        let speed: Float
        let rough: Float
        let noiseAmount: Float
        let phase: Float
    }

    static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole
    ) -> SceneIrisInlineSuffixPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              inputRole == .priorEffectOutput,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              layer.contentKind == "image",
              layer.effects.filter({
                  normalized($0.file) == definitionPath && $0.visible != false
              }).count == 1,
              let profile = SceneIrisShaderProfile.resolve(shaderContracts) else {
            return nil
        }
        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard normalized(effect.definitionPath) == definitionPath,
              validDefinition(in: descriptor, path: effect.definitionPath),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect),
              validMaterial(in: descriptor),
              layer.effects.indices.contains(effect.key.effectIndex) else {
            return nil
        }
        let instance = layer.effects[effect.key.effectIndex]
        guard instance.id == effect.key.descriptorID,
              normalized(instance.file) == definitionPath,
              instance.visible != false,
              instance.passes.count == 1,
              let pass = instance.passes.first,
              let maskPath = validInstance(pass, profile: profile),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node, graph: graph, descriptor: descriptor
              ).node,
              validResolved(resolved, maskPath: maskPath),
              let parameters = parameters(
                  pass.constantShaderValues, profile: profile
              ) else {
            return nil
        }
        return SceneIrisInlineSuffixPlan(
            effectKey: effect.key,
            maskTexturePath: maskPath,
            scale: parameters.scale,
            speed: parameters.speed,
            rough: parameters.rough,
            noiseAmount: parameters.noiseAmount,
            phase: parameters.phase
        )
    }

    private static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "iris",
              definition.name == "ui_editor_effect_iris_title",
              definition.description == "ui_editor_effect_iris_description",
              definition.group == "animate",
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

    private static func validNode(_ node: Graph.Node, effect: Graph.Effect) -> Bool {
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

    private static func validMaterial(in descriptor: SceneRenderDescriptor) -> Bool {
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

    private static func validInstance(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        profile: SceneIrisShaderProfile
    ) -> String? {
        guard pass.passIndex == 0,
              pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              let maskPath = pass.textureSlots[1],
              !maskPath.isEmpty,
              pass.texturePaths == [maskPath],
              pass.userTextureInputs.isEmpty,
              pass.combos.isEmpty,
              Set(pass.constantShaderValues.keys.map(normalized)).isSubset(of: constantKeys),
              parameters(pass.constantShaderValues, profile: profile) != nil else {
            return nil
        }
        return maskPath
    }

    private static func validResolved(
        _ material: SceneResolvedMaterialNode,
        maskPath: String
    ) -> Bool {
        normalized(material.shaderPath) == shaderIdentity
            && material.textureSlots.count == 8
            && assetPath(material.textureSlots[1]) == maskPath
            && material.textureSlots.enumerated().allSatisfy {
                $0.offset == 1 || $0.element == nil
            }
            && material.combos.isEmpty
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private static func parameters(
        _ values: [String: SceneDocument.ShaderValue],
        profile: SceneIrisShaderProfile
    ) -> Parameters? {
        guard let scale = vector(
            "scale", in: values, default: SIMD2(repeating: 1), range: 0.01 ... 10
        ), let speed = scalar("speed", in: values, default: 1, range: 0.01 ... 2),
           let rough = scalar("rough", in: values, default: 0.2, range: 0.01 ... 1),
           let noise = scalar(
               "noiseamount", in: values, default: 0.5, range: 0.01 ... 2
           ), let phase = scalar(
               "phase", in: values, default: 0, range: profile.phaseRange
           ) else {
            return nil
        }
        return Parameters(
            scale: scale,
            speed: speed,
            rough: rough,
            noiseAmount: noise,
            phase: phase
        )
    }

    private static func assetPath(
        _ slot: SceneResolvedMaterialNode.TextureSlot?
    ) -> String? {
        guard let slot, slot.provenance == .instance,
              case .asset(let path) = slot.source else {
            return nil
        }
        return path
    }

    private static func scalar(
        _ key: String,
        in values: [String: SceneDocument.ShaderValue],
        default fallback: Double,
        range: ClosedRange<Double>
    ) -> Float? {
        guard let value = values.first(where: { normalized($0.key) == key })?.value
        else { return Float(fallback) }
        guard value.userBinding == nil,
              value.valueKind.lowercased() == "number",
              value.components?.count == 1,
              let component = value.components?.first,
              component.isFinite,
              range.contains(component) else {
            return nil
        }
        return Float(component)
    }

    private static func vector(
        _ key: String,
        in values: [String: SceneDocument.ShaderValue],
        default fallback: SIMD2<Double>,
        range: ClosedRange<Double>
    ) -> SIMD2<Float>? {
        guard let value = values.first(where: { normalized($0.key) == key })?.value
        else { return SIMD2(Float(fallback.x), Float(fallback.y)) }
        guard value.userBinding == nil,
              value.valueKind.lowercased() == "vector",
              value.components?.count == 2,
              let components = value.components,
              components.allSatisfy({ $0.isFinite && range.contains($0) }) else {
            return nil
        }
        return SIMD2(Float(components[0]), Float(components[1]))
    }

    private static func effectOutput(_ key: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: key.layerID, effect: key, name: nil)
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static let definitionPath = "effects/iris/effect.json"
    private static let materialPath = "materials/effects/iris.json"
    private static let materialPassID = "materials/effects/iris.json#0"
    private static let materialSHA256 =
        "eef6cb3a49528d410adc237bf6154af28c2f16f8ad9ac38cf632c0f88048d34a"
    private static let shaderIdentity = "effects/iris"
    private static let dependencies = [
        materialPath,
        "shaders/effects/iris.frag",
        "shaders/effects/iris.vert",
    ]
    private static let constantKeys: Set<String> = [
        "scale", "speed", "rough", "noiseamount", "phase",
    ]
}
