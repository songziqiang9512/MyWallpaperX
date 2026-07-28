import CryptoKit
import Foundation
import simd

/// Strict stock profile for a standalone quad using linear, direct-draw,
/// gradient Light Shafts. Radial/corner, color rendering, masks, bindings,
/// alternate assets, and chained effects remain closed.
enum SceneAuthoredLightShaftsPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private nonisolated struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private nonisolated struct Parameters {
        let points: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
        let feather: SIMD2<Float>
        let scale: SIMD2<Float>
        let smoothness: Float
        let speed: Float
        let intensity: Float
        let exponent: Float
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneLightShaftsExecutionPlan? {
        guard inputRole == .layerSource,
              graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              layer.contentKind == "quad",
              layer.childLayerIDs.isEmpty,
              layer.dependencyLayerIDs.isEmpty,
              !layer.hasInlineScript,
              layer.effects.count == 1 else {
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

        return SceneLightShaftsExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            points: parameters.points,
            feather: parameters.feather,
            scale: parameters.scale,
            smoothness: parameters.smoothness,
            speed: parameters.speed,
            intensity: parameters.intensity,
            exponent: parameters.exponent,
            noiseTexturePath: noiseTexturePath,
            gradientTexturePath: gradientTexturePath
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
              definition.replacementKey == "lightshafts",
              definition.name == "ui_editor_effect_light_shafts_title",
              definition.description == "ui_editor_effect_light_shafts_description",
              definition.group == "colorize",
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
            && material.userShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
            && material.alphaWriting == nil
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
            && validCombos(pass.combos)
            && parameters(from: pass.constantShaderValues) != nil
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode
    ) -> Bool {
        normalized(material.shaderPath) == shaderIdentity
            && material.textureSlots.allSatisfy { $0 == nil }
            && validCombos(material.combos)
            && parameters(from: material.constants) != nil
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validCombos(_ authored: [String: Int]) -> Bool {
        var values: [String: Int] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.uppercased()) == nil else { return false }
        }
        return values == ["DIRECTDRAW": 1, "RENDERING": 1]
    }

    private nonisolated static func parameters(
        from authored: [String: SceneDocument.ShaderValue]
    ) -> Parameters? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        guard Set(values.keys) == constantKeys,
              vector(values["colorastart"], count: 3, range: 0...1) != nil,
              vector(values["colorend"], count: 3, range: 0...1) != nil,
              scalar(values["noiseamount"], range: 0...1) != nil,
              scalar(values["noisescale"], range: 0...10) != nil,
              scalar(values["rayradius"], range: 0...2) != nil,
              let point0 = vector2(values["point0"], range: -2...3),
              let point1 = vector2(values["point1"], range: -2...3),
              let point2 = vector2(values["point2"], range: -2...3),
              let point3 = vector2(values["point3"], range: -2...3),
              let feather = vector2(values["rayfeather"], range: 0...1),
              let scale = vector2(values["rayscale"], range: 0.001...10),
              let smoothness = scalar(values["raysmoothness"], range: 0...1),
              let speed = scalar(values["rayspeed"], range: -10...10),
              let intensity = scalar(values["colorwintensity"], range: 0...10),
              let exponent = scalar(values["colorwexponent"], range: 0.01...10) else {
            return nil
        }
        return .init(
            points: (point0, point1, point2, point3),
            feather: feather,
            scale: scale,
            smoothness: smoothness,
            speed: speed,
            intensity: intensity,
            exponent: exponent
        )
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>
    ) -> Float? {
        guard let components = vector(value, count: 1, range: range) else { return nil }
        return Float(components[0])
    }

    private nonisolated static func vector2(
        _ value: SceneDocument.ShaderValue?,
        range: ClosedRange<Double>
    ) -> SIMD2<Float>? {
        guard let components = vector(value, count: 2, range: range) else { return nil }
        return SIMD2(Float(components[0]), Float(components[1]))
    }

    private nonisolated static func vector(
        _ value: SceneDocument.ShaderValue?,
        count: Int,
        range: ClosedRange<Double>
    ) -> [Double]? {
        guard let value,
              value.userBinding == nil,
              value.valueKind.lowercased() == (count == 1 ? "number" : "vector"),
              let components = value.components,
              components.count == count,
              components.allSatisfy({ $0.isFinite && range.contains($0) }) else {
            return nil
        }
        return components
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

    private nonisolated static let definitionPath = "effects/lightshafts/effect.json"
    private nonisolated static let materialPath = "materials/effects/lightshafts.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "87c0abe860543b15dbc04606034484c7d1061e526af08388bd6945869985a078"
    private nonisolated static let shaderIdentity = "effects/lightshafts"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/lightshafts.frag",
        "shaders/effects/lightshafts.vert",
    ]
    private nonisolated static let shaderCanonicalSHA256 =
        "0d833edfb2b35e86cba517f392d2d28ca0d9fd52fbfb136632ce23f1ce2ce58a"
    private nonisolated static let vertexPath = "shaders/effects/lightshafts.vert"
    private nonisolated static let vertexSHA256 =
        "fc65a0011fcae963679c3411c017da95c3c5ddcc9808b0777196f0334547e471"
    private nonisolated static let fragmentPath = "shaders/effects/lightshafts.frag"
    private nonisolated static let fragmentSHA256 =
        "3e03ff559af5a8eb7951d1be590c48976a78f2e159bcc6778a9e48923d48d940"
    private nonisolated static let constantKeys = Set([
        "colorastart", "colorend", "colorwexponent", "colorwintensity",
        "noiseamount", "noisescale", "point0", "point1", "point2", "point3",
        "rayfeather", "rayradius", "rayscale", "raysmoothness", "rayspeed",
    ])
    private nonisolated static let expectedGizmos = SceneJSONValue.array([
        .object([
            "type": .string("EffectPerspectiveUV"),
            "vars": .object([
                "p0": .string("point0"),
                "p1": .string("point1"),
                "p2": .string("point2"),
                "p3": .string("point3"),
            ]),
        ]),
    ])
    nonisolated static let noiseTexturePath = "materials/util/noise"
    nonisolated static let gradientTexturePath =
        "materials/gradient/gradient_iridescent"
}
