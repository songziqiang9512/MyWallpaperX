import Foundation
import simd

/// Fail-closed admission for the stock Fisheye profile whose warp is disabled but
/// whose `BACKGROUND=0` contract still applies a radial alpha clip.
enum SceneAuthoredFisheyeZeroDistortionPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneFisheyeZeroDistortionPlan? {
        guard graph.blockers.isEmpty,
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
        guard normalized(effect.definitionPath) == definitionPath,
              SceneFisheyeZeroDistortionShaderProfile.resolve(shaderContracts) != nil,
              validDefinition(in: descriptor, path: effect.definitionPath),
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
              constants(resolved.constants) == instance else {
            return nil
        }

        return SceneFisheyeZeroDistortionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            center: SIMD2(Float(instance.center[0]), Float(instance.center[1])),
            size: Float(instance.size)
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains { normalized($0.definitionPath) == definitionPath }
    }

    private nonisolated struct Constants: Equatable {
        let center: [Double]
        let size: Double
    }

    private nonisolated static func supportedContent(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        if let utility = layer.utilityLayer {
            return utility.kind == .composition
                && layer.childLayerIDs.isEmpty
                && layer.dependencyLayerIDs.isEmpty
        }
        return ["image", "solid", "text"].contains(layer.contentKind)
    }

    private nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            normalized($0.relativePath) == normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.rawSHA256 == definitionSHA256,
              definition.version == 1,
              definition.replacementKey == "fisheye",
              definition.name == "ui_editor_effect_fisheye_title",
              definition.description == "ui_editor_effect_fisheye_description",
              definition.group == "distort",
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
            && material.userShaderValues.isEmpty
            && material.alphaWriting == nil
            && validRenderState(material)
    }

    private nonisolated static func validInstance(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer
    ) -> Constants? {
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
              normalizedConstantKeys(pass.constantShaderValueKeys),
              validCombos(pass.combos) else {
            return nil
        }
        return constants(pass.constantShaderValues)
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

    private nonisolated static func constants(
        _ authored: [String: SceneDocument.ShaderValue]
    ) -> Constants? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard expectedConstants.contains(key.lowercased()),
                  values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        guard values.count == expectedConstants.count,
              exactVector(values["center"], expected: [0.5, 0.5]),
              exactScalar(values["distortion"], expected: 0),
              exactScalar(values["size"], expected: 1.2) else {
            return nil
        }
        return Constants(center: [0.5, 0.5], size: 1.2)
    }

    private nonisolated static func exactScalar(
        _ value: SceneDocument.ShaderValue?,
        expected: Double
    ) -> Bool {
        guard let value,
              value.valueKind.lowercased() == "number",
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              value.components == [expected],
              expected.isFinite else {
            return false
        }
        return true
    }

    private nonisolated static func exactVector(
        _ value: SceneDocument.ShaderValue?,
        expected: [Double]
    ) -> Bool {
        guard let value,
              value.valueKind.lowercased() == "vector",
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              value.components == expected,
              expected.allSatisfy(\.isFinite) else {
            return false
        }
        return true
    }

    private nonisolated static func normalizedConstantKeys(_ keys: [String]) -> Bool {
        let normalized = keys.map { $0.lowercased() }
        return normalized.count == expectedConstants.count
            && Set(normalized) == expectedConstants
    }

    private nonisolated static func validCombos(_ authored: [String: Int]) -> Bool {
        var combos: [String: Int] = [:]
        for (key, value) in authored {
            guard combos.updateValue(value, forKey: key.uppercased()) == nil else {
                return false
            }
        }
        return combos == ["BACKGROUND": 0]
    }

    private nonisolated static func validRenderState(
        _ material: SceneRenderDescriptor.MaterialPassDescriptor
    ) -> Bool {
        material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static let definitionPath = "effects/fisheye/effect.json"
    private nonisolated static let definitionSHA256 =
        "1cef719d7da1b7ed4d1c12d34092a19d8ea94ff3cd60c5374bbad80bae528a6c"
    private nonisolated static let materialPath = "materials/effects/fisheye.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "cdb481996f3e2da67a3cf42d790dbce53db43cac806b46493f1a50b77ddd416e"
    private nonisolated static let shaderIdentity = "effects/fisheye"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/fisheye.frag",
        "shaders/effects/fisheye.vert",
    ]
    private nonisolated static let expectedConstants = Set([
        "center", "distortion", "size",
    ])
}
