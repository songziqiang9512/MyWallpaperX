import CryptoKit
import Foundation

nonisolated struct SceneShakeExecutionPlan {
    let layerID: Int
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let renderGraph: SceneAuthoredEffectRenderPlan
    let bounds: SIMD2<Float>
    let friction: SIMD2<Float>
    let speed: Float
    let strength: Float
    let flowTexturePath: String
    let phaseTexturePath: String?
}

enum SceneAuthoredShakePlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct Parameters {
        let bounds: SIMD2<Float>
        let friction: SIMD2<Float>
        let speed: Float
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
    ) -> SceneShakeExecutionPlan? {
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
              let instance = instancePass(effect: effect, layer: layer),
              let paths = texturePaths(from: instance),
              let parameters = parameters(from: instance.constantShaderValues),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                node: node,
                graph: graph,
                descriptor: descriptor
              ).node,
              validResolvedMaterial(
                resolved,
                flowPath: paths.flow,
                phasePath: paths.phase
              ) else {
            return nil
        }

        return SceneShakeExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            bounds: parameters.bounds,
            friction: parameters.friction,
            speed: parameters.speed,
            strength: parameters.strength,
            flowTexturePath: paths.flow,
            phaseTexturePath: paths.phase
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
              definition.replacementKey == "shake",
              definition.name == "ui_editor_effect_shake_title",
              definition.description == "ui_editor_effect_shake_description",
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
            && validCombos(material.combos)
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
              validCombos(pass.combos) else {
            return nil
        }
        return pass
    }

    private nonisolated static func texturePaths(
        from pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> (flow: String, phase: String?)? {
        guard pass.textureSlots.count == 3,
              pass.textureSlots[0] == nil,
              let flow = pass.textureSlots[1],
              !flow.isEmpty else {
            return nil
        }
        let phase = pass.textureSlots[2]
        guard phase?.isEmpty != true else { return nil }
        let expected = [flow] + (phase.map { [$0] } ?? [])
        guard pass.texturePaths == expected else { return nil }
        return (flow, phase)
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        flowPath: String,
        phasePath: String?
    ) -> Bool {
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              assetPath(material.textureSlots[1]) == flowPath,
              assetPath(material.textureSlots[2]) == phasePath,
              material.textureSlots.enumerated().allSatisfy({
                  [1, 2].contains($0.offset) || $0.element == nil
              }),
              validCombos(material.combos),
              parameters(from: material.constants) != nil else {
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
        guard Set(values.keys) == Set(["bounds", "friction", "speed", "strength"]),
              let bounds = vector(values["bounds"], range: 0...1),
              bounds.y > bounds.x,
              let friction = vector(values["friction"], range: 0.01...10),
              let speed = scalar(values["speed"], range: 0...10),
              let strength = scalar(values["strength"], range: 0.01...0.5) else {
            return nil
        }
        return Parameters(
            bounds: bounds,
            friction: friction,
            speed: speed,
            strength: strength
        )
    }

    private nonisolated static func vector(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>
    ) -> SIMD2<Float>? {
        guard let value,
              value.userBinding == nil,
              value.valueKind.lowercased() == "vector",
              let components = value.components,
              components.count == 2,
              components.allSatisfy({ $0.isFinite && range.contains($0) }) else {
            return nil
        }
        return SIMD2(Float(components[0]), Float(components[1]))
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
        return Float(component)
    }

    private nonisolated static func validCombos(_ authored: [String: Int]) -> Bool {
        var normalizedValues: [String: Int] = [:]
        for (key, value) in authored {
            guard normalizedValues.updateValue(value, forKey: key.uppercased()) == nil else {
                return false
            }
        }
        return normalizedValues.keys.allSatisfy {
            ["AUDIOPROCESSING", "NOISE", "DIRECTION", "MASK"].contains($0)
        } && normalizedValues.values.allSatisfy { $0 == 0 }
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

    private nonisolated static let definitionPath = "effects/shake/effect.json"
    private nonisolated static let materialPath = "materials/effects/shake.json"
    private nonisolated static let materialSHA256 =
        "03e3f5fce8ce7b25e56e79405ba43bc150838e80c1b337c763637465369761fd"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let shaderIdentity = "effects/shake"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/shake.frag",
        "shaders/effects/shake.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "9b94cf5844faf7b0a5a01f1d81195f9a26752e6e55057aa821a8074e6187ac76"
    private nonisolated static let vertexPath = "shaders/effects/shake.vert"
    private nonisolated static let vertexSHA256 =
        "9b884c23ad3e38cb7fa76330bf98d8f7029653c3a73f7a732f1cfd3c3829c4bc"
    private nonisolated static let fragmentPath = "shaders/effects/shake.frag"
    private nonisolated static let fragmentSHA256 =
        "f8734c9237d2393bab81b06db8d54cfa6afb64d1687edbf7572db3be52ee27cf"
}
