import CryptoKit
import Foundation

/// Exact authored-source Workshop 2193274282 audio profile.
/// Time-only, cursor, mask, non-average audio, and unknown constants remain closed.
enum SceneAuthoredWorkshopAudioHueShiftPlanner {
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
    ) -> SceneWorkshopAudioHueShiftExecutionPlan? {
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
              let audio = audioParameters(
                  combos: instance.combos,
                  constants: instance.constantShaderValues
              ),
              audioParameters(
                  combos: resolved.combos,
                  constants: resolved.constants
              ) == audio else {
            return nil
        }
        return .init(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            audio: audio
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
        guard matches.count == 1,
              let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "hue_shift",
              definition.name == "Hue Shift",
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
        normalized(material.shaderPath) == shaderIdentity
            && material.textureSlots.allSatisfy { $0 == nil }
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func audioParameters(
        combos: [String: Int],
        constants: [String: SceneDocument.ShaderValue]
    ) -> SceneAudioResponse.Parameters? {
        var normalizedCombos: [String: Int] = [:]
        for (key, value) in combos {
            guard normalizedCombos.updateValue(value, forKey: key.uppercased()) == nil else {
                return nil
            }
        }
        guard normalizedCombos == ["AUDIOPROCESSING": 3] else { return nil }

        var normalizedConstants: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in constants {
            guard normalizedConstants.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        let keys = Set(normalizedConstants.keys)
        guard keys.isSubset(of: SceneAudioResponseAdmission.constantKeys.union(["speed"])),
              SceneAudioResponseAdmission.constantKeys.isSubset(of: keys) else {
            return nil
        }
        if let speed = normalizedConstants["speed"] {
            guard speed.userBinding == nil,
                  speed.valueKind.lowercased() == "number",
                  speed.components?.count == 1,
                  let value = speed.components?.first,
                  value.isFinite,
                  (0...10).contains(value) else {
                return nil
            }
        }
        return SceneAudioResponseAdmission.resolve(
            comboValue: 3,
            constants: normalizedConstants,
            defaultBounds: SIMD2(0.5, 1),
            isAudioCapableProfile: true
        )?.parameters
    }

    private nonisolated static func shaderContractMatches(
        _ contracts: [SceneShaderContract]
    ) -> Bool {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
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
        "effects/workshop/2193274282/hue_shift/effect.json"
    private nonisolated static let materialPath =
        "materials/workshop/2193274282/effects/hue_shift.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "a84200743a00ab9fc1635171fcec36e3e63fa6474b6fd234fd72ead283be4dc8"
    private nonisolated static let shaderIdentity =
        "workshop/2193274282/effects/hue_shift"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/workshop/2193274282/effects/hue_shift.frag",
        "shaders/workshop/2193274282/effects/hue_shift.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "d9a9d6f004854f968dd729c9be4d671e690d7e9bf8e53358ec05607f7b78948b"
    private nonisolated static let vertexPath =
        "shaders/workshop/2193274282/effects/hue_shift.vert"
    private nonisolated static let vertexSHA256 =
        "342b538ae161d51f1e4ce7ca0db1d69bff699d3e17bf65eefa8ed551f8a5a31b"
    private nonisolated static let fragmentPath =
        "shaders/workshop/2193274282/effects/hue_shift.frag"
    private nonisolated static let fragmentSHA256 =
        "105b55940cacb108f768685c5277111882e6c1e1c3eef14b437ccd17c2b3b301"
}
