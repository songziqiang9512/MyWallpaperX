import Foundation

/// Exact clean-room backend for verified Workshop 2084198056 Simple Audio Bars profiles.
/// Relocated assets are accepted only when every derived path and content fingerprint agrees.
/// Other shader revisions, positions, transparency modes, and combo cross-products stay closed.
enum SceneAuthoredWorkshopSimpleAudioBarsPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Parameters = SceneWorkshopAudioBarsExecutionPlan.SimpleParameters

    nonisolated struct AssetContract: Equatable, Sendable {
        enum Revision: Equatable, Sendable {
            case originalFragmentC
            case relocatedLegacy
        }

        let revision: Revision
        let definitionPath: String
        let materialPath: String
        let materialPassID: String
        let materialSHA256: String?
        let shaderIdentity: String
        let dependencies: [String]
        let vertexPath: String
        let vertexSHA256: String
        let fragmentPath: String
        let fragmentSHA256: String
        let canonicalSHA256: String?
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopAudioBarsExecutionPlan? {
        guard inputRole == .layerSource,
              graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              supportedContent(layer) else {
            return nil
        }
        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard let assets = assetContract(forDefinitionPath: effect.definitionPath),
              validDefinition(in: descriptor, path: effect.definitionPath, assets: assets),
              shaderContractMatches(shaderContracts, assets: assets),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input,
                  layerID: graph.layerID,
                  role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect, assets: assets),
              validMaterialDescriptor(in: descriptor, assets: assets),
              let instance = validInstance(effect: effect, layer: layer, assets: assets),
              let selectedProfile = profile(
                  from: instance.combos,
                  revision: assets.revision
              ),
              let instanceParameters = parameters(
                  from: instance.constantShaderValues,
                  effectKey: effect.key,
                  profile: selectedProfile
              ),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved, assets: assets),
              profile(from: resolved.combos, revision: assets.revision) == selectedProfile,
              let resolvedParameters = parameters(
                  from: resolved.constants,
                  effectKey: effect.key,
                  profile: selectedProfile
              ),
              resolvedParameters == instanceParameters else {
            return nil
        }
        return SceneWorkshopAudioBarsExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            simpleParameters: instanceParameters
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains {
            assetContract(forDefinitionPath: $0.definitionPath) != nil
        }
    }

    private nonisolated static func supportedContent(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        if let utilityLayer = layer.utilityLayer {
            return utilityLayer.kind == .composition
                && layer.childLayerIDs.isEmpty
                && layer.dependencyLayerIDs.isEmpty
        }
        return layer.contentKind == "solid"
    }

    private nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String,
        assets: AssetContract
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "Simple_Audio_Bars",
              definition.name == "Simple Audio Bars",
              definition.description
                == "Adds a cusomizable audio bar effect to the layer. Supports various "
                + "positions (left, right, both, center, etc.) and as many bars as you'd like.",
              definition.group == "localeffects",
              definition.performance == nil,
              definition.previewPath == "preview/project.json",
              validEditable(definition.editable, revision: assets.revision),
              definition.framebuffers.isEmpty,
              definition.dependencies.map(normalized) == assets.dependencies,
              definition.functions == nil,
              definition.gizmos == nil,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 1,
              let pass = definition.passes.first else {
            return false
        }
        return pass.passIndex == 0
            && normalized(pass.materialPath ?? "") == assets.materialPath
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
        effect: Graph.Effect,
        assets: AssetContract
    ) -> Bool {
        node.effect == effect.key
            && node.definitionPassIndex == 0
            && node.materialOrdinal == 0
            && node.instancePassIndex == 0
            && node.kind == .material
            && normalized(node.materialPath ?? "") == assets.materialPath
            && normalized(node.materialPassID ?? "") == assets.materialPassID
            && node.target == effect.output
            && node.bindings.isEmpty
            && node.commandSource == nil
            && node.commandTarget == nil
            && node.compose == nil
            && node.conditions == nil
    }

    private nonisolated static func validMaterialDescriptor(
        in descriptor: SceneRenderDescriptor,
        assets: AssetContract
    ) -> Bool {
        let matches = descriptor.materialPasses.filter {
            normalized($0.id) == assets.materialPassID
        }
        guard matches.count == 1, let material = matches.first else { return false }
        return normalized(material.materialPath) == assets.materialPath
            && (assets.materialSHA256.map {
                material.materialRawSHA256 == $0
            } ?? true)
            && material.passIndex == 0
            && normalized(material.shaderPath ?? "") == assets.shaderIdentity
            && material.texturePaths.isEmpty
            && material.textureSlots.isEmpty
            && material.userTextureInputs.isEmpty
            && material.combos.isEmpty
            && material.constantShaderValues.isEmpty
            && material.userShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
            && material.alphaWriting == nil
    }

    private nonisolated static func validInstance(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer,
        assets: AssetContract
    ) -> SceneRenderDescriptor.EffectDescriptor.PassDescriptor? {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return nil }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == assets.definitionPath,
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
        _ material: SceneResolvedMaterialNode,
        assets: AssetContract
    ) -> Bool {
        normalized(material.shaderPath) == assets.shaderIdentity
            && material.textureSlots.allSatisfy { $0 == nil }
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validEditable(
        _ editable: Bool?,
        revision: AssetContract.Revision
    ) -> Bool {
        switch revision {
        case .originalFragmentC:
            editable == false
        case .relocatedLegacy:
            editable == nil
        }
    }
}
