import CryptoKit
import Foundation

nonisolated struct SceneWaterRippleExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let runtimePlan: SceneWaterRippleNormalPlan
    let maskTexturePath: String
    let normalTexturePath: String
}

enum SceneAuthoredWaterRipplePlanner {
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
    ) -> SceneWaterRippleExecutionPlan? {
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
              let paths = texturePaths(from: instance),
              let runtimePlan = SceneWaterRippleRuntimePlanner.plan(for: instance),
              validInstance(instance),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved, paths: paths) else {
            return nil
        }

        return SceneWaterRippleExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            runtimePlan: runtimePlan,
            maskTexturePath: paths.mask,
            normalTexturePath: paths.normal
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
              definition.replacementKey == "waterripple",
              definition.name == "ui_editor_effect_water_ripple_title",
              definition.description == "ui_editor_effect_water_ripple_description",
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
            && material.texturePaths == [normalTexturePath]
            && material.textureSlots == [nil, nil, normalTexturePath]
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

    private nonisolated static func texturePaths(
        from pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> (mask: String, normal: String)? {
        guard pass.textureSlots.count == 3,
              pass.textureSlots[0] == nil,
              let mask = pass.textureSlots[1],
              let normal = pass.textureSlots[2],
              !mask.isEmpty,
              normalized(normal) == normalTexturePath,
              pass.texturePaths == [mask, normal] else {
            return nil
        }
        return (mask, normal)
    }

    private nonisolated static func validInstance(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Bool {
        pass.combos.isEmpty
            && Set(pass.constantShaderValues.keys.map { $0.lowercased() }) == Set([
                "animationspeed", "ratio", "ripplestrength", "scale",
                "scrolldirection", "scrollspeed",
            ])
            && pass.constantShaderValues.values.allSatisfy {
                $0.userBinding == nil
                    && $0.valueKind.lowercased() == "number"
                    && $0.components?.count == 1
                    && $0.components?.first?.isFinite == true
            }
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        paths: (mask: String, normal: String)
    ) -> Bool {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              assetPath(material.textureSlots[1], provenance: .instance) == paths.mask,
              assetPath(material.textureSlots[2], provenance: .instance) == paths.normal,
              material.textureSlots.enumerated().allSatisfy({
                  [1, 2].contains($0.offset) || $0.element == nil
              }),
              material.combos.isEmpty,
              Set(material.constants.keys.map { $0.lowercased() }) == Set([
                  "animationspeed", "ratio", "ripplestrength", "scale",
                  "scrolldirection", "scrollspeed",
              ]) else {
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

    private nonisolated static let definitionPath = "effects/waterripple/effect.json"
    private nonisolated static let materialPath = "materials/effects/waterripple.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "27b3a48c79990eaf1731b5d4871d0138ccc79a108b967b6e9a9e204d5d5e2360"
    private nonisolated static let shaderIdentity = "effects/waterripple"
    private nonisolated static let normalTexturePath = "effects/waterripplenormal"
    private nonisolated static let dependencies = [
        materialPath,
        "materials/effects/waterripplenormal.png",
        "materials/effects/waterripplenormal.tex-json",
        "shaders/effects/waterripple.frag",
        "shaders/effects/waterripple.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "cff8420a7f1103b6123906feff9db9f3233039d9cd1d9da2e02352700048c7ce"
    private nonisolated static let vertexPath = "shaders/effects/waterripple.vert"
    private nonisolated static let vertexSHA256 =
        "e1347f6f4dbec03106514592f652e9f63e6a75dc6e6c3cd8c76138c34dc2e7a4"
    private nonisolated static let fragmentPath = "shaders/effects/waterripple.frag"
    private nonisolated static let fragmentSHA256 =
        "21bcc2216765fd09804331dec96b9aa94aa4b15e4b5957c6b001371e1e82e38a"
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
