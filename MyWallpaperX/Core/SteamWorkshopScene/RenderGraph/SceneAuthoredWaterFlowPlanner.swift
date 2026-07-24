import CryptoKit
import Foundation

nonisolated struct SceneWaterFlowExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let speed: Float
    let strength: Float
    let phaseScale: Float
    let flowTexturePath: String
    let phaseTexturePath: String
}

enum SceneAuthoredWaterFlowPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct Parameters {
        let speed: Float
        let strength: Float
        let phaseScale: Float
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
    ) -> SceneWaterFlowExecutionPlan? {
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
              let textures = texturePaths(from: instance),
              let parameters = parameters(from: instance.constantShaderValues),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(
                  resolved,
                  textures: textures,
                  parameters: parameters
              ) else {
            return nil
        }

        return SceneWaterFlowExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            speed: parameters.speed,
            strength: parameters.strength,
            phaseScale: parameters.phaseScale,
            flowTexturePath: textures.flow,
            phaseTexturePath: textures.phase
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
              definition.replacementKey == "waterflow",
              definition.name == "ui_editor_effect_water_flow_title",
              definition.description == "ui_editor_effect_water_flow_description",
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
            && material.texturePaths == [phaseTexturePath]
            && material.textureSlots == [nil, nil, phaseTexturePath]
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

    private nonisolated static func texturePaths(
        from pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> (flow: String, phase: String)? {
        guard pass.textureSlots.count == 3,
              pass.textureSlots[0] == nil,
              let flow = pass.textureSlots[1],
              let phase = pass.textureSlots[2],
              !flow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !phase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pass.texturePaths == [flow, phase] else {
            return nil
        }
        return (flow, phase)
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        textures: (flow: String, phase: String),
        parameters: Parameters
    ) -> Bool {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              assetPath(material.textureSlots[1], provenance: .instance) == textures.flow,
              assetPath(material.textureSlots[2], provenance: .instance) == textures.phase,
              material.textureSlots.enumerated().allSatisfy({
                  $0.offset == 1 || $0.offset == 2 || $0.element == nil
              }),
              material.combos.isEmpty,
              let resolvedParameters = self.parameters(from: material.constants),
              resolvedParameters.speed == parameters.speed,
              resolvedParameters.strength == parameters.strength,
              resolvedParameters.phaseScale == parameters.phaseScale else {
            return false
        }
        return material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func assetPath(
        _ slot: SceneResolvedMaterialNode.TextureSlot?,
        provenance: SceneResolvedMaterialNode.TextureProvenance
    ) -> String? {
        guard let slot, slot.provenance == provenance,
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
        guard Set(values.keys) == Set(["speed", "strength", "phasescale"]),
              let speed = scalar(values["speed"], range: 0.01...2),
              let strength = scalar(values["strength"], range: 0.01...2),
              let phaseScale = scalar(values["phasescale"], range: 0.01...10) else {
            return nil
        }
        return Parameters(speed: speed, strength: strength, phaseScale: phaseScale)
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>
    ) -> Float? {
        guard let value,
              value.userBinding == nil,
              value.valueKind.lowercased() == "number",
              let components = value.components,
              components.count == 1,
              let component = components.first,
              component.isFinite,
              range.contains(component) else {
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

    private nonisolated static let definitionPath = "effects/waterflow/effect.json"
    private nonisolated static let materialPath = "materials/effects/waterflow.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "984bbaf1fdab98cb1b4169ff239a3ddbdeef83cfa0d71c286e8ea6435292066f"
    private nonisolated static let shaderIdentity = "effects/waterflow"
    private nonisolated static let phaseTexturePath = "effects/waterflowphase"
    private nonisolated static let dependencies = [
        materialPath,
        "materials/effects/waterflowphase.png",
        "materials/effects/waterflowphase.tex-json",
        "shaders/effects/waterflow.frag",
        "shaders/effects/waterflow.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "63ef341dd11eb804ecc05196ff86e5802b950cec8d3dcf29b4bc20872595c2e3"
    private nonisolated static let vertexPath = "shaders/effects/waterflow.vert"
    private nonisolated static let vertexSHA256 =
        "45803f340c80659ca4726cdea107eb017e7638a64a1b9ff7d30093d1938a738e"
    private nonisolated static let fragmentPath = "shaders/effects/waterflow.frag"
    private nonisolated static let fragmentSHA256 =
        "20928cfc8b69497820cd70dc98d18f32398ba473707e1c72363670707af6dc7f"
}
