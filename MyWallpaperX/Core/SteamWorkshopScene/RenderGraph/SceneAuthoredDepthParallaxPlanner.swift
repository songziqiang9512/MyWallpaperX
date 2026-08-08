import Foundation
import simd

nonisolated enum SceneDepthParallaxQuality: Int {
    case basic = 0
    case occlusionPerformance = 1
    case occlusionQuality = 2

    var sampleCount: Int {
        switch self {
        case .basic: 1
        case .occlusionPerformance: 24
        case .occlusionQuality: 64
        }
    }
}

nonisolated struct SceneDepthParallaxExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let depthTexturePath: String
    let scale: SIMD2<Float>
    let sensitivity: Float
    let center: Float
    let quality: SceneDepthParallaxQuality
}

enum SceneAuthoredDepthParallaxPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneDepthParallaxExecutionPlan? {
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
              validDefinition(in: descriptor, path: effect.definitionPath),
              SceneDepthParallaxShaderProfile.resolve(shaderContracts) != nil,
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
              let values = instanceValues(instance),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved, values: values) else {
            return nil
        }

        return SceneDepthParallaxExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            depthTexturePath: values.depthPath,
            scale: values.scale,
            sensitivity: values.sensitivity,
            center: values.center,
            quality: values.quality
        )
    }

    private struct InstanceValues {
        let depthPath: String
        let scale: SIMD2<Float>
        let sensitivity: Float
        let center: Float
        let quality: SceneDepthParallaxQuality
    }

    private nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.rawSHA256 == definitionSHA256,
              definition.version == 1,
              definition.replacementKey == "iris",
              definition.name == "ui_editor_effect_depth_parallax_title",
              definition.description == "ui_editor_effect_depth_parallax_description",
              definition.group == "interactive",
              definition.performance == "expensive",
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
            && material.userShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
            && material.alphaWriting == nil
    }

    private nonisolated static func instancePass(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer
    ) -> SceneRenderDescriptor.EffectDescriptor.PassDescriptor? {
        guard layer.effects.indices.contains(effect.key.effectIndex) else {
            return nil
        }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first,
              pass.passIndex == 0 else {
            return nil
        }
        return pass
    }

    private nonisolated static func instanceValues(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> InstanceValues? {
        guard pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              let depthPath = pass.textureSlots[1],
              !depthPath.isEmpty,
              pass.texturePaths == [depthPath],
              pass.userTextureInputs.isEmpty,
              let quality = quality(pass.combos),
              Set(pass.constantShaderValues.keys.map { $0.lowercased() })
                == constantKeys,
              let scale = vector2(pass.constantShaderValues["scale"]),
              scale.x != 0,
              scale.y != 0,
              (-2...2).contains(scale.x),
              (-2...2).contains(scale.y),
              let sensitivity = scalar(
                  pass.constantShaderValues["sens"],
                  range: -5...5
              ),
              let center = scalar(
                  pass.constantShaderValues["center"],
                  range: 0...1
              ) else {
            return nil
        }
        return InstanceValues(
            depthPath: depthPath,
            scale: scale,
            sensitivity: sensitivity,
            center: center,
            quality: quality
        )
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        values: InstanceValues
    ) -> Bool {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              assetPath(material.textureSlots[1]) == values.depthPath,
              material.textureSlots.enumerated().allSatisfy({
                  $0.offset == 1 || $0.element == nil
              }),
              quality(material.combos) == values.quality,
              Set(material.constants.keys.map { $0.lowercased() }) == constantKeys,
              vector2(material.constants["scale"]) == values.scale,
              scalar(material.constants["sens"], range: -5...5)
                == values.sensitivity,
              scalar(material.constants["center"], range: 0...1)
                == values.center else {
            return false
        }
        return material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
            && material.renderState.alphaWriting == nil
    }

    private nonisolated static func assetPath(
        _ slot: SceneResolvedMaterialNode.TextureSlot?
    ) -> String? {
        guard let slot,
              slot.candidates.count == 1,
              slot.provenance == .instance,
              case .asset(let path) = slot.source else {
            return nil
        }
        return path
    }

    private nonisolated static func quality(
        _ combos: [String: Int]
    ) -> SceneDepthParallaxQuality? {
        if combos.isEmpty { return .occlusionPerformance }
        guard combos.count == 1,
              let entry = combos.first,
              entry.key.uppercased() == "QUALITY" else {
            return nil
        }
        return SceneDepthParallaxQuality(rawValue: entry.value)
    }

    private nonisolated static func vector2(
        _ value: SceneDocument.ShaderValue?
    ) -> SIMD2<Float>? {
        guard let value,
              value.valueKind.lowercased() == "vector",
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              let components = value.components,
              components.count == 2,
              components.allSatisfy(\.isFinite) else {
            return nil
        }
        return SIMD2(Float(components[0]), Float(components[1]))
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Float>
    ) -> Float? {
        guard let value,
              value.valueKind.lowercased() == "number",
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              let components = value.components,
              components.count == 1 else {
            return nil
        }
        let scalar = Float(components[0])
        return scalar.isFinite && range.contains(scalar) ? scalar : nil
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(
            kind: .effectOutput,
            layerID: effect.layerID,
            effect: effect,
            name: nil
        )
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static let definitionPath =
        "effects/depthparallax/effect.json"
    private nonisolated static let definitionSHA256 =
        "438775d010e2e35bbf7044766a736955d442542348fc4aff1510e982e07fc303"
    private nonisolated static let materialPath =
        "materials/effects/depthparallax.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "468a2a9fdb812bfa527e720426f69141cb99b2ae996e3fa951eaa74413874b3f"
    private nonisolated static let shaderIdentity = "effects/depthparallax"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/depthparallax.frag",
        "shaders/effects/depthparallax.vert",
    ]
    private nonisolated static let constantKeys = Set([
        "center", "scale", "sens",
    ])
}
