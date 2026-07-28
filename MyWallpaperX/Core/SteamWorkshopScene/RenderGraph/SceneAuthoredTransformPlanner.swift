import Foundation

/// Fail-closed admission for the identity-only `effects/transform` contract.
enum SceneAuthoredTransformPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private nonisolated enum ScaleSource: Equatable {
        case constant
        case unsupportedDynamicFallback
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneTransformExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid", "text"].contains(layer.contentKind) else {
            return nil
        }

        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard normalized(effect.definitionPath) == definitionPath,
              SceneTransformShaderProfile.resolve(shaderContracts) != nil,
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
              let instanceScale = validInstance(effect: effect, layer: layer),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              let resolvedScale = validResolvedMaterial(resolved),
              instanceScale == resolvedScale else {
            return nil
        }

        let diagnostics: [SceneTransformStaticFallbackDiagnostic]
        switch resolvedScale {
        case .constant:
            diagnostics = []
        case .unsupportedDynamicFallback:
            diagnostics = [.init(
                effectIndex: effect.key.effectIndex,
                passIndex: 0,
                constantName: "scale"
            )]
        }
        return SceneTransformExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            staticFallbackDiagnostics: diagnostics
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
              definition.replacementKey == "transform",
              definition.name == "ui_editor_effect_transform_title",
              definition.description == "ui_editor_effect_transform_description",
              definition.group == "distort",
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
            && validRenderState(
                blending: material.blending,
                depthTest: material.depthTest,
                depthWrite: material.depthWrite,
                cullMode: material.cullMode
            )
    }

    private nonisolated static func validInstance(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer
    ) -> ScaleSource? {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return nil }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first,
              pass.passIndex == 0,
              pass.texturePaths.isEmpty,
              pass.textureSlots.isEmpty,
              pass.userTextureInputs.isEmpty,
              validCombos(pass.combos) else {
            return nil
        }
        return identityConstants(pass.constantShaderValues)
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode
    ) -> ScaleSource? {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.allSatisfy({ $0 == nil }),
              validCombos(material.combos),
              validRenderState(
                  blending: material.renderState.blending,
                  depthTest: material.renderState.depthTest,
                  depthWrite: material.renderState.depthWrite,
                  cullMode: material.renderState.cullMode
              ) else {
            return nil
        }
        return identityConstants(material.constants)
    }

    private nonisolated static func identityConstants(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> ScaleSource? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        guard Set(values.keys) == Set(["angle", "offset", "scale"]),
              scalarIsIdentity(values["angle"]),
              vectorIsIdentity(values["offset"], expected: [0, 0]),
              let scale = scaleSource(values["scale"]) else {
            return nil
        }
        return scale
    }

    private nonisolated static func scalarIsIdentity(
        _ value: SceneDocument.ShaderValue?
    ) -> Bool {
        guard let value,
              value.valueKind.lowercased() == "number",
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              value.components == [0] else {
            return false
        }
        return true
    }

    private nonisolated static func vectorIsIdentity(
        _ value: SceneDocument.ShaderValue?,
        expected: [Double]
    ) -> Bool {
        guard let value,
              value.valueKind.lowercased() == "vector",
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              value.components == expected else {
            return false
        }
        return true
    }

    private nonisolated static func scaleSource(
        _ value: SceneDocument.ShaderValue?
    ) -> ScaleSource? {
        guard let value,
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              value.components == [1, 1] else {
            return nil
        }
        switch value.valueKind.lowercased() {
        case "vector":
            return .constant
        case "binding":
            return .unsupportedDynamicFallback
        default:
            return nil
        }
    }

    private nonisolated static func validCombos(_ authored: [String: Int]) -> Bool {
        var combos: [String: Int] = [:]
        for (key, value) in authored {
            guard combos.updateValue(value, forKey: key.uppercased()) == nil else { return false }
        }
        return combos.keys.allSatisfy({ ["MODE", "CLAMP"].contains($0) })
            && combos["MODE"] == 1
            && combos["CLAMP", default: 1] == 1
    }

    private nonisolated static func validRenderState(
        blending: String?,
        depthTest: String?,
        depthWrite: String?,
        cullMode: String?
    ) -> Bool {
        blending?.lowercased() == "normal"
            && depthTest?.lowercased() == "disabled"
            && depthWrite?.lowercased() == "disabled"
            && cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static let definitionPath = "effects/transform/effect.json"
    private nonisolated static let materialPath = "materials/effects/transform.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "995444d008b2b699c8a98fd530a4528f75938a9f8596ae42c7da3adf1a8821d9"
    private nonisolated static let shaderIdentity = "effects/transform"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/transform.frag",
        "shaders/effects/transform.vert",
    ]
}
