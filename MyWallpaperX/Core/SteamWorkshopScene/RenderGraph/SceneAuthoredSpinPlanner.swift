import CryptoKit
import Foundation
import simd

/// Exact stock Spin profile used by the currently verified 2.8.42 asset set.
/// Masked, noisy, non-repeating, and alternate shader variants remain closed.
enum SceneAuthoredSpinPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private nonisolated struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private nonisolated struct Parameters {
        let center: SIMD2<Float>
        let size: Float
        let feather: Float
        let speed: Float
        let ratio: Float
        let angle: Float
        let phase: Float
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneSpinExecutionPlan? {
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
              validInstance(effect: effect, layer: layer),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node,
                  graph: graph,
                  descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved),
              let parameters = parameters(from: resolved.constants) else {
            return nil
        }

        return SceneSpinExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            center: parameters.center,
            size: parameters.size,
            feather: parameters.feather,
            speed: parameters.speed,
            ratio: parameters.ratio,
            angle: parameters.angle,
            phase: parameters.phase
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
              definition.version == 2,
              definition.replacementKey == "spin",
              definition.name == "ui_editor_effect_spin_title",
              definition.description == "ui_editor_effect_spin_description",
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
    ) -> Bool {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return false }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first else {
            return false
        }
        return pass.passIndex == 0
            && pass.texturePaths.isEmpty
            && pass.textureSlots.isEmpty
            && pass.userTextureInputs.isEmpty
            && pass.combos.isEmpty
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode
    ) -> Bool {
        normalized(material.shaderPath) == shaderIdentity
            && material.textureSlots.allSatisfy { $0 == nil }
            && material.combos.isEmpty
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func parameters(
        from authored: [String: SceneDocument.ShaderValue]
    ) -> Parameters? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        guard values.count == constantKeys.count,
              values.keys.allSatisfy(constantKeys.contains),
              let center = vector2(values["center"], range: 0...1),
              let size = scalar(values["size"], range: 0...1),
              let feather = scalar(values["feather"], range: 0...0.2),
              let speed = scalar(values["speed"], range: -5...5),
              let ratio = scalar(values["ratio"], range: 0.0001...10),
              let angle = scalar(values["angle"], range: -Double.pi...Double.pi),
              let phase = scalar(values["phase"], range: 0...1) else {
            return nil
        }
        return .init(
            center: center,
            size: size,
            feather: feather,
            speed: speed,
            ratio: ratio,
            angle: angle,
            phase: phase
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

    private nonisolated static func vector2(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>
    ) -> SIMD2<Float>? {
        guard let value,
              value.valueKind.lowercased() == "vector",
              value.userBinding == nil,
              let components = value.components,
              components.count == 2,
              components.allSatisfy({ $0.isFinite && range.contains($0) }) else {
            return nil
        }
        return SIMD2(Float(components[0]), Float(components[1]))
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

    private nonisolated static let definitionPath = "effects/spin/effect.json"
    private nonisolated static let materialPath = "materials/effects/spin.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "3c5900d2d9257b3e9792bede3ac8e69e9518052740bef10d1908b5089d740f67"
    private nonisolated static let shaderIdentity = "effects/spin"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/spin.frag",
        "shaders/effects/spin.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "e9a906255acd3cbca9a6f21f08f26ecb5e6ad27fa1b30b75ca0a4043748ea97c"
    private nonisolated static let vertexPath = "shaders/effects/spin.vert"
    private nonisolated static let vertexSHA256 =
        "cb0159714e0feb4829a01fe2c73c47526b54cdba2cb4801602b298a22e6eb11c"
    private nonisolated static let fragmentPath = "shaders/effects/spin.frag"
    private nonisolated static let fragmentSHA256 =
        "70ba7d05bdef683b0cf8c763fbef92c7fade0dd6a8fde8d862cc6ca62f822bb9"
    private nonisolated static let constantKeys = Set([
        "center", "size", "feather", "speed", "ratio", "angle", "phase",
    ])
    private nonisolated static let expectedGizmos = SceneJSONValue.array([
        .object([
            "type": .string("EffectSpinUV"),
            "vars": .object([
                "center": .string("center"),
                "ratio": .string("ratio"),
                "angle": .string("angle"),
                "size": .string("size"),
            ]),
        ]),
    ])
}
