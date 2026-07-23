import CryptoKit
import Foundation
import simd

nonisolated struct SceneWaterWavesExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let direction: Float
    let speed: Float
    let scale: Float
    let exponent: Float
    let strength: Float
    let maskTexturePath: String
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
              let instance = instancePass(effect: effect, layer: layer),
              let maskPath = maskPath(from: instance),
              let parameters = parameters(from: instance.constantShaderValues),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(
                  resolved,
                  maskPath: maskPath,
                  parameters: parameters
              ) else {
            return nil
        }

        return SceneWaterWavesExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            direction: parameters.direction,
            speed: parameters.speed,
            scale: parameters.scale,
            exponent: parameters.exponent,
            strength: parameters.strength,
            maskTexturePath: maskPath
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
              definition.gizmos == expectedGizmos,
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

    private nonisolated static func maskPath(
        from pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> String? {
        guard pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              let path = pass.textureSlots[1],
              !path.isEmpty,
              pass.texturePaths == [path] else {
            return nil
        }
        return path
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        maskPath: String,
        parameters: Parameters
    ) -> Bool {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              assetPath(material.textureSlots[1]) == maskPath,
              material.textureSlots.enumerated().allSatisfy({
                  $0.offset == 1 || $0.element == nil
              }),
              material.combos.isEmpty,
              let resolvedParameters = self.parameters(from: material.constants),
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
        from authored: [String: SceneDocument.ShaderValue]
    ) -> Parameters? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        guard Set(values.keys) == Set(["direction", "speed", "scale", "exponent", "strength"]),
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
              component.isFinite,
              range?.contains(component) ?? true else {
            return nil
        }
        let result = Float(component)
        return result.isFinite ? result : nil
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
    private nonisolated static let shaderCanonicalSHA256 =
        "0aa56eeed43aa54d09ced6993f742c07a5dc0cfd1dcd89873f1fb22142e68831"
    private nonisolated static let vertexPath = "shaders/effects/waterwaves.vert"
    private nonisolated static let vertexSHA256 =
        "188d1e33de160e86708329ed1401cdc546426293e1f0b66b041d5cd556fe388f"
    private nonisolated static let fragmentPath = "shaders/effects/waterwaves.frag"
    private nonisolated static let fragmentSHA256 =
        "18df156687addc31957922f782ec5da44a126619b0ffd60c1b69557d2512d50e"
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
