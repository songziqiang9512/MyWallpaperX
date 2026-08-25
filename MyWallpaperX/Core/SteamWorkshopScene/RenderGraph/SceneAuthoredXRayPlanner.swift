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
        currentStockDefinitionMatches(descriptor: descriptor, path: path)
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
        currentStockMaterialMatches(descriptor: descriptor)
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
        currentStockShaderContractMatches(contracts)
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func debugRejection(graph: Graph, reason: String) {
#if DEBUG
        guard graph.effects.contains(where: {
            normalized($0.definitionPath) == definitionPath
        }) else { return }
        print("MWX authored X-Ray rejected layer=\(graph.layerID) reason=\(reason)")
#endif
    }

    nonisolated static let currentStockIdentityProfile = StockIdentityProfile(
        version: 1,
        replacementKey: "xray",
        group: "interactive",
        materialSemanticSHA256: stockMaterialSemanticSHA256,
        shaderCanonicalSHA256:
            "ae769d9b366c49d19957a5f9254bb113a0250c648e3df1e477160e407e652e00",
        shaderDependencySHA256:
            "085fdbac854d56bc33880f217065210dbb1d6d694da79ff4d66a7a86b7a911e9"
    )
    nonisolated static let legacyStockIdentityProfile = StockIdentityProfile(
        version: nil,
        replacementKey: nil,
        group: "colorize",
        materialSemanticSHA256: stockMaterialSemanticSHA256,
        shaderCanonicalSHA256:
            "2282ff824267047378841e0b504c1f20137f7527883d8de5914ea6ab942cd44e",
        shaderDependencySHA256:
            "86764cbeed420c09ca2d18eff1ba6ac217a5b14cdf8aaeba071f9cac089275c8"
    )
    nonisolated static let stockIdentityProfiles = [
        currentStockIdentityProfile,
        legacyStockIdentityProfile,
    ]
    private nonisolated static let supportedContentKinds = Set([
        "image", "solid", "text", "composition", "project", "fullscreen",
    ])
    // Sorted minimal X-Ray single-pass stock material with shader identity
    // erased. An author override or unknown field changes this digest.
    private nonisolated static let stockMaterialSemanticSHA256 =
        "f07dfa1b7f21c1c99742c66dfa14ab8c747ebc78a1a7573680329950ad40e121"
}
