import CryptoKit
import Foundation

nonisolated struct SceneWorkshopShadowExecutionPlan: Equatable, Sendable {
    let alpha: Float
    let color: SIMD3<Float>
    let drawBorder: Float
    let offset: SIMD2<Float>
}

enum SceneAuthoredWorkshopShadowPlanner {
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
    ) -> SceneWorkshopShadowExecutionPlan? {
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
              shaderContractMatches(shaderContracts),
              validDefinition(in: descriptor, path: effect.definitionPath),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                effect.input, layerID: graph.layerID, role: inputRole
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
              let values = parameters(from: instance.constantShaderValues) else {
            return nil
        }
        return values
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
              definition.replacementKey == "shadow_____________",
              definition.name == "Shadow/\u{6dfb}\u{52a0}\u{9634}\u{5f71}",
              definition.description == nil,
              definition.group == "localeffects",
              definition.performance == nil,
              definition.previewPath == nil,
              definition.editable == false,
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
              pass.userTextureInputs.isEmpty,
              validCombos(pass.combos) else {
            return nil
        }
        return pass
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

    private nonisolated static func validCombos(_ authored: [String: Int]) -> Bool {
        var normalizedValues: [String: Int] = [:]
        for (key, value) in authored {
            guard normalizedValues.updateValue(value, forKey: key.uppercased()) == nil else {
                return false
            }
        }
        return normalizedValues.keys.allSatisfy { ["BLENDMODE", "MASK"].contains($0) }
            && normalizedValues["BLENDMODE", default: 0] == 0
            && normalizedValues["MASK", default: 0] == 0
    }

    private nonisolated static func parameters(
        from constants: [String: SceneDocument.ShaderValue]
    ) -> SceneWorkshopShadowExecutionPlan? {
        guard Set(constants.keys) == ["alpha", "shadowColor", "shadowDrawBorder", "shadowOffset"],
              let alpha = scalar(constants["alpha"], range: 0...1),
              let border = scalar(constants["shadowDrawBorder"], range: 0...1),
              let color = vector(constants["shadowColor"], count: 3),
              color == [0, 0, 0],
              let offset = vector(constants["shadowOffset"], count: 3),
              offset[0].isFinite,
              offset[1].isFinite,
              offset[2] == 0 else {
            return nil
        }
        let offsetX = Float(offset[0])
        let offsetY = Float(offset[1])
        guard offsetX.isFinite, offsetY.isFinite else { return nil }
        return SceneWorkshopShadowExecutionPlan(
            alpha: Float(alpha),
            color: SIMD3(Float(color[0]), Float(color[1]), Float(color[2])),
            drawBorder: Float(border),
            offset: SIMD2(offsetX, offsetY)
        )
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>
    ) -> Double? {
        guard let value,
              value.valueKind.lowercased() == "number",
              value.userBinding == nil,
              let components = value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite,
              range.contains(component) else {
            return nil
        }
        return component
    }

    private nonisolated static func vector(
        _ value: SceneDocument.ShaderValue?,
        count: Int
    ) -> [Double]? {
        guard let value,
              value.valueKind.lowercased() == "vector",
              value.userBinding == nil,
              let components = value.components,
              components.count == count,
              components.allSatisfy(\.isFinite) else {
            return nil
        }
        return components
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

    private nonisolated static let definitionPath =
        "effects/workshop/3488490208/shadow_____________/effect.json"
    private nonisolated static let materialPath =
        "materials/workshop/3488490208/effects/shadow_____________.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let shaderIdentity =
        "workshop/3488490208/effects/shadow_____________"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/workshop/3488490208/effects/shadow_____________.frag",
        "shaders/workshop/3488490208/effects/shadow_____________.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "4537fd70eb7502278f0a7b32cfae84b035ebd44f3198522ea15195638add3df1"
    private nonisolated static let vertexPath =
        "shaders/workshop/3488490208/effects/shadow_____________.vert"
    private nonisolated static let vertexSHA256 =
        "944be6c0cde2fa79b3462dc105cea0ffb0bf2ccd3b22241d05c68cb3411cc955"
    private nonisolated static let fragmentPath =
        "shaders/workshop/3488490208/effects/shadow_____________.frag"
    private nonisolated static let fragmentSHA256 =
        "a902c4bf452519e1de68fbff9dabf138f7bb3f108a6dc15a9ffae6034ba8a454"
}
