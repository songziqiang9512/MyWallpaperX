import CryptoKit
import Foundation
import simd

/// Exact stock 2.8.42 Color Key profile. Unknown definitions, shader bytes,
/// bindings, texture slots, constants, and combos remain fail-closed.
enum SceneAuthoredColorKeyPlanner {
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
    ) -> SceneColorKeyExecutionPlan? {
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
              validInstance(effect: effect, layer: layer),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved),
              let parameters = parameters(from: resolved.constants),
              let combos = combos(from: resolved.combos) else {
            return nil
        }

        return SceneColorKeyExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            keyAlpha: parameters.alpha,
            fuzziness: parameters.fuzziness,
            tolerance: parameters.tolerance,
            keyColor: parameters.color,
            invert: combos.invert,
            flatten: combos.flatten
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
              definition.replacementKey == "colorkey",
              definition.name == "ui_editor_effect_color_key_title",
              definition.description == "ui_editor_effect_color_key_description",
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

    private nonisolated struct Parameters {
        let alpha: Float
        let fuzziness: Float
        let tolerance: Float
        let color: SIMD3<Float>
    }

    private nonisolated static func parameters(
        from authored: [String: SceneDocument.ShaderValue]
    ) -> Parameters? {
        guard let constants = normalizedConstants(authored),
              constants.keys.allSatisfy({ constantKeys.contains($0) }),
              let alpha = scalar(constants["alpha"], default: 0, range: 0...1),
              let fuzz = scalar(constants["fuzziness"], default: 0, range: 0...3),
              let tolerance = scalar(constants["tolerance"], default: 0.1, range: 0...3),
              let color = vector3(constants["color"], default: SIMD3(repeating: 1)) else {
            return nil
        }
        return Parameters(alpha: alpha, fuzziness: fuzz, tolerance: tolerance, color: color)
    }

    private nonisolated static func normalizedConstants(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> [String: SceneDocument.ShaderValue]? {
        var result: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        return result
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        default defaultValue: Float,
        range: ClosedRange<Double>
    ) -> Float? {
        guard let value else { return defaultValue }
        guard value.valueKind.lowercased() == "number",
              value.userBinding == nil,
              value.components?.count == 1,
              let component = value.components?.first,
              component.isFinite,
              range.contains(component) else {
            return nil
        }
        return Float(component)
    }

    private nonisolated static func vector3(
        _ value: SceneDocument.ShaderValue?,
        default defaultValue: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard let value else { return defaultValue }
        guard value.valueKind.lowercased() == "vector",
              value.userBinding == nil,
              let components = value.components,
              components.count == 3,
              components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return nil
        }
        return SIMD3(Float(components[0]), Float(components[1]), Float(components[2]))
    }

    private nonisolated struct Combos {
        let invert: Bool
        let flatten: Bool
    }

    private nonisolated static func combos(from authored: [String: Int]) -> Combos? {
        guard let values = normalizedCombos(authored),
              values.keys.allSatisfy({ comboKeys.contains($0) }),
              [values["INVERT", default: 0], values["FLATTEN", default: 0]]
                .allSatisfy({ $0 == 0 || $0 == 1 }) else {
            return nil
        }
        return Combos(
            invert: values["INVERT", default: 0] == 1,
            flatten: values["FLATTEN", default: 0] == 1
        )
    }

    private nonisolated static func validCombos(_ authored: [String: Int]) -> Bool {
        combos(from: authored) != nil
    }

    private nonisolated static func normalizedCombos(
        _ authored: [String: Int]
    ) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        return result
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

    private nonisolated static let definitionPath = "effects/colorkey/effect.json"
    private nonisolated static let materialPath = "materials/effects/colorkey.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "02d5f948d42690e5a697be56d9b43f59ab30e633db7dd042f4ac9d20537b4a0c"
    private nonisolated static let shaderIdentity = "effects/colorkey"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/colorkey.frag",
        "shaders/effects/colorkey.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "aa6e7d600fb192b638a16bc7f6f62bbfe1c8981c58b16802f46865bd8b137af4"
    private nonisolated static let vertexPath = "shaders/effects/colorkey.vert"
    private nonisolated static let vertexSHA256 =
        "0b346bf8e6d1fb2aafee37d80d46ec4821c08d3fc62b11c42b23112a4b8739cb"
    private nonisolated static let fragmentPath = "shaders/effects/colorkey.frag"
    private nonisolated static let fragmentSHA256 =
        "e05cc509f3a286f9ecee63063280b7f8ce22cee7d8b705b74cee0b133ef71bed"
    private nonisolated static let constantKeys: Set<String> = [
        "alpha", "color", "fuzziness", "tolerance",
    ]
    private nonisolated static let comboKeys: Set<String> = ["INVERT", "FLATTEN"]
}
