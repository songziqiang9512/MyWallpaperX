import CryptoKit
import Foundation

/// Exact Workshop 3347128360 six-color circular effect contract.
/// Other shapes, color counts, blend modes, perspective, masks, and constants stay closed.
enum SceneAuthoredWorkshopGradientPlanner {
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
    ) -> SceneWorkshopGradientExecutionPlan? {
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
              let instance = validInstance(effect: effect, layer: layer),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved),
              validCombos(instance.combos),
              validCombos(resolved.combos),
              validConstants(instance.constantShaderValues),
              validConstants(resolved.constants) else {
            return nil
        }
        return .init(layerID: graph.layerID, effectKey: effect.key, renderGraph: graph)
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
        guard matches.count == 1,
              let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "gradient_generator",
              definition.name == "Gradient Generator",
              definition.description == nil,
              definition.group == "localeffects",
              definition.performance == nil,
              definition.previewPath == nil,
              definition.editable == false,
              definition.framebuffers.isEmpty,
              definition.dependencies.map(normalized) == dependencies,
              definition.functions == nil,
              definition.gizmos != nil,
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

    private nonisolated static func validNode(_ node: Graph.Node, effect: Graph.Effect) -> Bool {
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
        let matches = descriptor.materialPasses.filter { normalized($0.id) == materialPassID }
        guard matches.count == 1, let material = matches.first else { return false }
        return normalized(material.materialPath) == materialPath
            && material.materialRawSHA256 == materialSHA256
            && material.passIndex == 0
            && normalized(material.shaderPath ?? "") == normalized(shaderIdentity)
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
              pass.texturePaths.isEmpty,
              pass.textureSlots.isEmpty,
              pass.userTextureInputs.isEmpty else {
            return nil
        }
        return pass
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode
    ) -> Bool {
        normalized(material.shaderPath) == normalized(shaderIdentity)
            && material.textureSlots.allSatisfy { $0 == nil }
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validCombos(_ authored: [String: Int]) -> Bool {
        var values: [String: Int] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.uppercased()) == nil else { return false }
        }
        return values == ["NCOLORS": 24, "SHAPE": 3]
    }

    private nonisolated static func validConstants(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> Bool {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else { return false }
        }
        guard values.count == expectedConstants.count else { return false }
        return expectedConstants.allSatisfy { key, expected in
            guard let value = values[key],
                  value.userBinding == nil,
                  value.components == expected,
                  expected.allSatisfy(\.isFinite) else {
                return false
            }
            return value.valueKind.lowercased() == (expected.count == 1 ? "number" : "vector")
        }
    }

    private nonisolated static func shaderContractMatches(
        _ contracts: [SceneShaderContract]
    ) -> Bool {
        let matches = contracts.filter { normalized($0.identity) == normalized(shaderIdentity) }
        guard matches.count == 1,
              let contract = matches.first,
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
                && normalized(stage.relativePath) == normalized(fingerprint.1)
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

    private nonisolated static func effectOutput(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static let definitionPath =
        "effects/workshop/3347128360/gradient_generator/effect.json"
    private nonisolated static let materialPath =
        "materials/workshop/3347128360/effects/gradient_generator.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "b8f11556196ee64a4429da813cc007923b9426723533163e3e73152ef009d4ce"
    private nonisolated static let shaderIdentity =
        "workshop/3347128360/effects/gradient_generator"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/workshop/3347128360/effects/gradient_generator.frag",
        "shaders/workshop/3347128360/effects/gradient_generator.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "b0bcb64d5572d70bb87c33f109c199a66f15dc31bdf2d15b330eb1b1398a21c1"
    private nonisolated static let vertexPath =
        "shaders/workshop/3347128360/effects/gradient_generator.vert"
    private nonisolated static let vertexSHA256 =
        "ba22c9d41b6abbbd1c5bb73a601256d5c1f9dac50788bd7d8e51b1c300dad84e"
    private nonisolated static let fragmentPath =
        "shaders/workshop/3347128360/effects/gradient_generator.frag"
    private nonisolated static let fragmentSHA256 =
        "dd6ef3859da715d99ca008817e548a6901efb18e75af821c7e3f7718274ee3e3"
    private nonisolated static let expectedConstants: [String: [Double]] = [
        "gamma": [2.2],
        "center": [0, 0],
        "color1": [1, 0, 0],
        "color2": [1, 0.6470588235294118, 0],
        "color3": [0, 0, 1],
        "color4": [0, 1, 1],
        "color5": [1, 0, 1],
        "color6": [1, 1, 0],
        "ratio": [1],
        "rotation": [0],
        "scale": [1],
        "ui_editor_properties_feather": [1],
        "ui_editor_properties_offset": [0],
        "ui_editor_properties_opacity": [1],
    ]
}
