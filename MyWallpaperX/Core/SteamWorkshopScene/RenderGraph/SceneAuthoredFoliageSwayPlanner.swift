import Foundation

nonisolated struct SceneFoliageSwayExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let runtimePlan: SceneFoliageSwayPlan
    let maskTexturePath: String
    let noiseTexturePath: String
}

enum SceneAuthoredFoliageSwayPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneFoliageSwayExecutionPlan? {
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
              let profile = SceneFoliageSwayShaderProfile.resolve(shaderContracts),
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
              let maskPath = SceneEffectMaskSemantics.maskPath(in: instance),
              let noisePath = noisePath(in: instance, profile: profile),
              validInstance(instance, maskPath: maskPath, profile: profile),
              let runtimePlan = SceneFoliageSwayRuntimePlanner.plan(for: instance),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(
                  resolved,
                  maskPath: maskPath,
                  noisePath: noisePath,
                  profile: profile
              ) else {
            return nil
        }

        return SceneFoliageSwayExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            runtimePlan: runtimePlan,
            maskTexturePath: maskPath,
            noiseTexturePath: noisePath
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
              definition.version == 2,
              definition.replacementKey == "foliagesway",
              definition.name == "ui_editor_effect_foliage_sway_title",
              definition.description == "ui_editor_effect_foliage_sway_description",
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
              pass.userTextureInputs.isEmpty else {
            return nil
        }
        return pass
    }

    private nonisolated static func validInstance(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        maskPath: String,
        profile: SceneFoliageSwayShaderProfile
    ) -> Bool {
        let expectedSlots: [String?] = profile.expectsExplicitNoise
            ? [nil, maskPath, noiseAssetPath]
            : [nil, maskPath, nil]
        let expectedPaths = profile.expectsExplicitNoise
            ? [maskPath, noiseAssetPath]
            : [maskPath]
        return pass.textureSlots == expectedSlots
            && pass.texturePaths == expectedPaths
            && pass.combos.allSatisfy {
                $0.key.uppercased() == "MODE" && $0.value == 0
            }
            && validConstantKeys(pass.constantShaderValues.keys, profile: profile)
            && pass.constantShaderValues.values.allSatisfy {
                $0.userBinding == nil
                    && $0.valueKind.lowercased() == "number"
                    && $0.components?.count == 1
                    && $0.components?.first?.isFinite == true
                    && $0.timeline == nil
                    && $0.timelineDiagnostics.isEmpty
            }
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        maskPath: String,
        noisePath: String,
        profile: SceneFoliageSwayShaderProfile
    ) -> Bool {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              assetPath(material.textureSlots[1]) == maskPath,
              material.textureSlots.enumerated().allSatisfy({
                  $0.offset == 1
                      || (profile.expectsExplicitNoise
                          && $0.offset == 2
                          && assetPath($0.element) == noisePath)
                      || $0.element == nil
              }),
              material.combos.allSatisfy({
                  $0.key.uppercased() == "MODE" && $0.value == 0
              }),
              validConstantKeys(material.constants.keys, profile: profile) else {
            return false
        }
        return material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func noisePath(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        profile: SceneFoliageSwayShaderProfile
    ) -> String? {
        guard profile.expectsExplicitNoise else { return noiseAssetPath }
        guard pass.textureSlots.indices.contains(2),
              let path = pass.textureSlots[2],
              normalized(path) == noiseAssetPath else {
            return nil
        }
        return path
    }

    private nonisolated static func validConstantKeys(
        _ keys: some Collection<String>,
        profile: SceneFoliageSwayShaderProfile
    ) -> Bool {
        let actual = Set(keys.map { $0.lowercased() })
        return profile.acceptsSparseConstants
            ? actual.isSubset(of: constantKeys)
            : actual == constantKeys
    }

    private nonisolated static func assetPath(
        _ slot: SceneResolvedMaterialNode.TextureSlot?
    ) -> String? {
        guard let slot, slot.provenance == .instance,
              case .asset(let path) = slot.source else {
            return nil
        }
        return path
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static let definitionPath = "effects/foliagesway/effect.json"
    private nonisolated static let materialPath = "materials/effects/foliagesway.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "95896dcaa058cf8d80b6e0bc1f531a2e533c2da886023a5c22d336224e16e51d"
    private nonisolated static let shaderIdentity = "effects/foliagesway"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/foliagesway.frag",
        "shaders/effects/foliagesway.vert",
    ]
    nonisolated static let noiseAssetPath = "util/noise"
    private nonisolated static let constantKeys = Set([
        "phase", "power", "ratio", "scale", "scrolldirection",
        "speeduv", "strength",
    ])
}
