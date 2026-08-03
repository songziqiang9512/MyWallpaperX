import CryptoKit
import Foundation
import simd

/// Fail-closed admission for the content-verified fullscreen Color Grading
/// profile whose compiled branch is `TOOLS=2`.
enum SceneAuthoredColorGradingPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private nonisolated struct AssetProfile {
        let definitionPath: String
        let materialPath: String
        let materialPassID: String
        let shaderIdentity: String
        let dependencies: [String]
    }

    private nonisolated struct Parameters {
        let luminance: Float
        let saturation: Float
        let vibrance: Float
        let opacity: Float
        let channelInfluence: SIMD3<Float>
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneColorGradingExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              layer.contentKind == "fullscreen",
              layer.utilityLayer?.kind == .fullscreen,
              layer.childLayerIDs.isEmpty,
              layer.dependencyLayerIDs.isEmpty else {
            return nil
        }

        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard let profile = assetProfile(
                  descriptor: descriptor,
                  definitionPath: effect.definitionPath,
                  shaderContracts: shaderContracts
              ),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input,
                  layerID: graph.layerID,
                  role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect, profile: profile),
              validInstance(effect: effect, layer: layer, profile: profile),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved, profile: profile),
              let parameters = parameters(resolved.constants) else {
            return nil
        }

        return SceneColorGradingExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            luminance: parameters.luminance,
            saturation: parameters.saturation,
            vibrance: parameters.vibrance,
            opacity: parameters.opacity,
            channelInfluence: parameters.channelInfluence
        )
    }

    private nonisolated static func assetProfile(
        descriptor: SceneRenderDescriptor,
        definitionPath authoredPath: String,
        shaderContracts: [SceneShaderContract]
    ) -> AssetProfile? {
        let definitionPath = normalized(authoredPath)
        let definitions = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == definitionPath
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              definition.rawSHA256 == definitionSHA256,
              definition.version == 1,
              definition.replacementKey == "color_grading",
              definition.name == "Color Grading",
              definition.description == nil,
              definition.group == "localeffects",
              definition.performance == nil,
              definition.previewPath == nil,
              definition.editable == false,
              definition.framebuffers.isEmpty,
              definition.functions == nil,
              definition.gizmos == nil,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 1,
              let pass = definition.passes.first,
              pass.passIndex == 0,
              let authoredMaterialPath = pass.materialPath,
              pass.target == nil,
              pass.bindings.isEmpty,
              pass.compose == nil,
              pass.command == nil,
              pass.source == nil,
              pass.conditions == nil,
              pass.extraFields.isEmpty else {
            return nil
        }

        let materialPath = normalized(authoredMaterialPath)
        let materialPassID = "\(materialPath)#0"
        let materials = descriptor.materialPasses.filter {
            normalized($0.id) == materialPassID
        }
        guard materials.count == 1,
              let material = materials.first,
              normalized(material.materialPath) == materialPath,
              material.materialRawSHA256 == materialSHA256,
              material.passIndex == 0,
              let authoredShaderIdentity = material.shaderPath,
              material.texturePaths.isEmpty,
              material.textureSlots.isEmpty,
              material.userTextureInputs.isEmpty,
              material.combos.isEmpty,
              material.constantShaderValues.isEmpty,
              material.userShaderValues.isEmpty,
              material.alphaWriting == nil,
              validRenderState(material) else {
            return nil
        }

        let shaderIdentity = normalized(authoredShaderIdentity)
        let dependencies = [
            materialPath,
            "shaders/\(shaderIdentity).frag",
            "shaders/\(shaderIdentity).vert",
        ]
        guard definition.dependencies.map(normalized) == dependencies,
              shaderContractMatches(
                  shaderContracts,
                  shaderIdentity: shaderIdentity
              ) else {
            return nil
        }
        return AssetProfile(
            definitionPath: definitionPath,
            materialPath: materialPath,
            materialPassID: materialPassID,
            shaderIdentity: shaderIdentity,
            dependencies: dependencies
        )
    }

    private nonisolated static func validNode(
        _ node: Graph.Node,
        effect: Graph.Effect,
        profile: AssetProfile
    ) -> Bool {
        node.effect == effect.key
            && node.definitionPassIndex == 0
            && node.materialOrdinal == 0
            && node.instancePassIndex == 0
            && node.kind == .material
            && normalized(node.materialPath ?? "") == profile.materialPath
            && normalized(node.materialPassID ?? "") == profile.materialPassID
            && node.target == effect.output
            && node.bindings.isEmpty
            && node.commandSource == nil
            && node.commandTarget == nil
            && node.compose == nil
            && node.conditions == nil
    }

    private nonisolated static func validInstance(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer,
        profile: AssetProfile
    ) -> Bool {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return false }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == profile.definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first,
              pass.passIndex == 0,
              pass.texturePaths.isEmpty,
              pass.textureSlots.isEmpty,
              pass.userTextureInputs.isEmpty,
              normalizedCombos(pass.combos) == ["TOOLS": 2],
              normalizedConstantKeys(pass.constantShaderValueKeys),
              parameters(pass.constantShaderValues) != nil else {
            return false
        }
        return true
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        profile: AssetProfile
    ) -> Bool {
        normalized(material.shaderPath) == profile.shaderIdentity
            && material.textureSlots.allSatisfy { $0 == nil }
            && normalizedCombos(material.combos) == ["TOOLS": 2]
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
            && material.renderState.alphaWriting == nil
    }

    private nonisolated static func parameters(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> Parameters? {
        guard let values = normalizedConstants(authored),
              Set(values.keys) == constantKeys,
              scalar(values["brightness"], range: -1 ... 1) != nil,
              scalar(values["contrast"], range: -1 ... 1) != nil,
              let luminance = scalar(values["luminance"], range: -1 ... 1),
              let saturation = scalar(values["saturation"], range: -1 ... 1),
              let vibrance = scalar(values["vibrance"], range: -1 ... 1),
              let opacity = scalar(values["opacity"], range: 0 ... 1),
              let influence = vector3(values["channel influence"]) else {
            return nil
        }
        return Parameters(
            luminance: luminance,
            saturation: saturation,
            vibrance: vibrance,
            opacity: opacity,
            channelInfluence: influence
        )
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>
    ) -> Float? {
        guard let value,
              value.valueKind.lowercased() == "number",
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
        _ value: SceneDocument.ShaderValue?
    ) -> SIMD3<Float>? {
        guard let value,
              value.valueKind.lowercased() == "vector",
              value.userBinding == nil,
              let components = value.components,
              components.count == 3,
              components.allSatisfy(\.isFinite) else {
            return nil
        }
        return SIMD3(Float(components[0]), Float(components[1]), Float(components[2]))
    }

    private nonisolated static func normalizedConstants(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> [String: SceneDocument.ShaderValue]? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        return values
    }

    private nonisolated static func normalizedConstantKeys(_ keys: [String]) -> Bool {
        keys.count == constantKeys.count
            && Set(keys.map { $0.lowercased() }) == constantKeys
    }

    private nonisolated static func normalizedCombos(
        _ authored: [String: Int]
    ) -> [String: Int]? {
        var values: [String: Int] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.uppercased()) == nil else {
                return nil
            }
        }
        return values
    }

    private nonisolated static func validRenderState(
        _ material: SceneRenderDescriptor.MaterialPassDescriptor
    ) -> Bool {
        material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func shaderContractMatches(
        _ contracts: [SceneShaderContract],
        shaderIdentity: String
    ) -> Bool {
        let matches = contracts.filter { normalized($0.identity) == shaderIdentity }
        guard matches.count == 1,
              let contract = matches.first,
              contract.sourceKind == .authoredSource,
              contract.diagnostics.isEmpty,
              contract.stages.count == 2,
              canonicalHash(contract) == contract.canonicalSHA256 else {
            return false
        }
        let expected: [(SceneShaderContract.StageKind, String, String)] = [
            (.vertex, "shaders/\(shaderIdentity).vert", vertexSHA256),
            (.fragment, "shaders/\(shaderIdentity).frag", fragmentSHA256),
        ]
        return zip(contract.stages, expected).allSatisfy { stage, fingerprint in
            stage.kind == fingerprint.0
                && normalized(stage.relativePath) == fingerprint.1
                && stage.rawSHA256 == fingerprint.2
        }
    }

    private nonisolated struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
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

    private nonisolated static let constantKeys: Set<String> = [
        "brightness", "channel influence", "contrast", "luminance",
        "opacity", "saturation", "vibrance",
    ]
    private nonisolated static let definitionSHA256 =
        "8d6a7a8a43f3373c25cf8d21ef4613dde9170a3f25a5c18269bfca4de6bf5112"
    private nonisolated static let materialSHA256 =
        "fc2f7c7d839ded3fbc632b58ee268b9bddd73fb93d50538e94276a331dde5c9a"
    private nonisolated static let vertexSHA256 =
        "faa7cc72454fd73cc05f0c4bc72e3790a739c060c1ec527030dc31084a93da7a"
    private nonisolated static let fragmentSHA256 =
        "a937fdbb89d040ecb71591b3da76dd47c5df819b92311ce3a8804a40c470804f"
}
