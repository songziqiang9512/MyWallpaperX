import CryptoKit
import Foundation

nonisolated struct SceneXRayExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let declaration: SceneXRayRuntimePlanner.Declaration

    var liveConsumerTargets: Set<SceneDynamicTarget> {
        SceneXRayRuntimePlanner.liveConsumerTargets(for: declaration)
    }
}

enum SceneAuthoredXRayPlanner {
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
    ) -> SceneXRayExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              supportedContentKinds.contains(layer.contentKind),
              let declaration = SceneXRayRuntimePlanner.declaration(for: layer) else {
            debugRejection(graph: graph, reason: "shape-or-declaration")
            return nil
        }

        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard declaration.effectIndex == effect.key.effectIndex,
              declaration.effectID == effect.key.descriptorID,
              normalized(effect.definitionPath) == definitionPath else {
            debugRejection(graph: graph, reason: "effect-identity")
            return nil
        }
        guard validDefinition(in: descriptor, path: effect.definitionPath) else {
            debugRejection(graph: graph, reason: "definition-contract")
            return nil
        }
        guard shaderContractMatches(shaderContracts) else {
            debugRejection(graph: graph, reason: "shader-contract")
            return nil
        }
        guard
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input,
                  layerID: graph.layerID,
                  role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect) else {
            debugRejection(graph: graph, reason: "graph-topology")
            return nil
        }
        guard validMaterialDescriptor(in: descriptor) else {
            debugRejection(graph: graph, reason: "material-contract")
            return nil
        }
        guard
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved, declaration: declaration) else {
            debugRejection(graph: graph, reason: "resolved-material")
            return nil
        }

        return SceneXRayExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            declaration: declaration
        )
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
              definition.replacementKey == "xray",
              definition.name == "ui_editor_effect_xray_title",
              definition.description == "ui_editor_effect_xray_description",
              definition.group == "interactive",
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
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        declaration: SceneXRayRuntimePlanner.Declaration
    ) -> Bool {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              validTextureSlot(
                  material.textureSlots[1],
                  assetPath: declaration.blendTexturePath,
                  propertyKey: declaration.blendPropertyKey
              ),
              validTextureSlot(
                  material.textureSlots[2],
                  assetPath: declaration.haloTexturePath,
                  propertyKey: declaration.haloPropertyKey
              ),
              validTextureSlot(
                  material.textureSlots[3],
                  assetPath: declaration.opacityMaskPath,
                  propertyKey: nil
              ),
              material.textureSlots.enumerated().allSatisfy({
                  [1, 2, 3].contains($0.offset) || $0.element == nil
              }),
              validCombos(material.combos),
              Set(material.constants.keys.map { $0.lowercased() })
                == Set(["multiply", "size"]) else {
            return false
        }
        return material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validTextureSlot(
        _ slot: SceneResolvedMaterialNode.TextureSlot?,
        assetPath: String?,
        propertyKey: String?
    ) -> Bool {
        guard assetPath != nil || propertyKey != nil else { return slot == nil }
        guard let slot else { return false }
        let expectedCount = propertyKey == nil ? 1 : 2
        guard slot.candidates.count == expectedCount,
              case .asset(let authoredPath) = slot.candidates[0].source,
              slot.candidates[0].provenance == .instance,
              authoredPath == assetPath else {
            return false
        }
        guard let propertyKey else { return true }
        let property = slot.candidates[1]
        guard property.provenance == .userTexture,
              case .userTexture(let input) = property.source else {
            return false
        }
        return input.kind == .property && input.value == propertyKey
    }

    private nonisolated static func validCombos(_ combos: [String: Int]) -> Bool {
        combos.allSatisfy { key, value in
            switch key.uppercased() {
            case "BLENDMODE":
                value == 0
            case "OPACITYMASK":
                value == 0 || value == 1
            default:
                false
            }
        }
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

    private nonisolated static func debugRejection(graph: Graph, reason: String) {
#if DEBUG
        guard graph.effects.contains(where: {
            normalized($0.definitionPath) == definitionPath
        }) else { return }
        print("MWX authored X-Ray rejected layer=\(graph.layerID) reason=\(reason)")
#endif
    }

    private nonisolated static let definitionPath = "effects/xray/effect.json"
    private nonisolated static let supportedContentKinds = Set([
        "image", "solid", "text", "composition", "project", "fullscreen",
    ])
    private nonisolated static let materialPath = "materials/effects/xray.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "79b16f1ff55144ad29c216ef7c80b825fb277d521e687cf46c15773a107b254f"
    private nonisolated static let shaderIdentity = "effects/xray"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/xray.frag",
        "shaders/effects/xray.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "ae769d9b366c49d19957a5f9254bb113a0250c648e3df1e477160e407e652e00"
    private nonisolated static let vertexPath = "shaders/effects/xray.vert"
    private nonisolated static let vertexSHA256 =
        "5d4e6a303e1d10b417b352dd2f06040ae8f2328dbd1ba3d3a666e5d572d90039"
    private nonisolated static let fragmentPath = "shaders/effects/xray.frag"
    private nonisolated static let fragmentSHA256 =
        "d884d586e20bca2ecf2bef48280da1d4e226d1116010f642fe36de944c2e7525"
}
