import Foundation
import simd

/// Stock v2 Water Caustics admission. Perspective and dynamic parameters remain fail-closed.
nonisolated enum SceneAuthoredWaterCausticsPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct Parameters: Equatable {
        let brightness: Float
        let glow: Float
        let scale: Float
        let speed: Float
        let timeOffset: Float
        let distortion: Float
        let chromatic: Float
        let blur: Float
        let colorStart: SIMD3<Float>
        let colorEnd: SIMD3<Float>
    }

    static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWaterCausticsExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              layer.contentKind == "image",
              SceneWaterCausticsAssetProfile.accepts(shaderContracts)
        else { return nil }

        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard validDefinition(in: descriptor, path: effect.definitionPath),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect),
              validMaterial(in: descriptor),
              let instance = instancePass(effect: effect, layer: layer),
              let combos = normalizedCombos(instance.combos),
              combos.keys.allSatisfy({ ["BLENDMODE", "MASK", "MODE", "PERSPECTIVE"].contains($0) }),
              combos["MASK", default: 0] == 0,
              combos["MODE", default: 0] == 0,
              combos["PERSPECTIVE", default: 0] == 0,
              (0 ... SceneBlendModeShaderSource.maximumMode)
                .contains(combos["BLENDMODE", default: 32]),
              let parameters = parameters(instance.constantShaderValues),
              let paths = texturePaths(instance),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node, graph: graph, descriptor: descriptor
              ).node,
              validResolved(resolved, pass: instance, parameters: parameters)
        else { return nil }

        return SceneWaterCausticsExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            blendMode: combos["BLENDMODE", default: 32],
            brightness: parameters.brightness,
            glow: parameters.glow,
            scale: parameters.scale,
            speed: parameters.speed,
            timeOffset: parameters.timeOffset,
            distortion: parameters.distortion,
            chromatic: parameters.chromatic,
            blur: parameters.blur,
            colorStart: parameters.colorStart,
            colorEnd: parameters.colorEnd,
            maskTexturePath: paths[1],
            patternTexturePath: paths[2] ?? "pattern/voronoi_local",
            glowTexturePath: paths[5] ?? "pattern/voronoi",
            noiseTexturePath: paths[3] ?? "util/uniform_256",
            offsetTexturePath: paths[4] ?? "util/perlin_256"
        )
    }

    static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains {
            SceneWaterCausticsAssetProfile.normalized($0.definitionPath)
                == SceneWaterCausticsAssetProfile.definitionPath
        }
    }

    private static func validDefinition(in descriptor: SceneRenderDescriptor, path: String) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
            SceneWaterCausticsAssetProfile.normalized($0.relativePath)
                == SceneWaterCausticsAssetProfile.normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.rawSHA256 == SceneWaterCausticsAssetProfile.definitionSHA256,
              definition.version == 2,
              definition.replacementKey == "caustics",
              definition.name == "ui_editor_effect_water_caustics_title",
              definition.description == "ui_editor_effect_water_caustics_description",
              definition.group == "colorize",
              definition.performance == nil,
              definition.previewPath == "preview/project.json",
              definition.editable == nil,
              definition.framebuffers.isEmpty,
              definition.dependencies.map(SceneWaterCausticsAssetProfile.normalized)
                == SceneWaterCausticsAssetProfile.dependencies,
              definition.functions == nil,
              definition.gizmos == expectedGizmos,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 1,
              let pass = definition.passes.first
        else { return false }
        return pass.passIndex == 0
            && SceneWaterCausticsAssetProfile.normalized(pass.materialPath ?? "")
                == SceneWaterCausticsAssetProfile.materialPath
            && pass.target == nil && pass.bindings.isEmpty && pass.compose == nil
            && pass.command == nil && pass.source == nil && pass.conditions == nil
            && pass.extraFields.isEmpty
    }

    private static func validNode(_ node: Graph.Node, effect: Graph.Effect) -> Bool {
        node.effect == effect.key
            && node.definitionPassIndex == 0 && node.materialOrdinal == 0
            && node.instancePassIndex == 0 && node.kind == .material
            && SceneWaterCausticsAssetProfile.normalized(node.materialPath ?? "")
                == SceneWaterCausticsAssetProfile.materialPath
            && SceneWaterCausticsAssetProfile.normalized(node.materialPassID ?? "")
                == SceneWaterCausticsAssetProfile.materialPassID
            && node.target == effect.output && node.bindings.isEmpty
            && node.commandSource == nil && node.commandTarget == nil
            && node.compose == nil && node.conditions == nil
    }

    private static func validMaterial(in descriptor: SceneRenderDescriptor) -> Bool {
        let matches = descriptor.materialPasses.filter {
            SceneWaterCausticsAssetProfile.normalized($0.id)
                == SceneWaterCausticsAssetProfile.materialPassID
        }
        guard matches.count == 1, let material = matches.first else { return false }
        return material.materialRawSHA256 == SceneWaterCausticsAssetProfile.materialSHA256
            && SceneWaterCausticsAssetProfile.normalized(material.materialPath)
                == SceneWaterCausticsAssetProfile.materialPath
            && material.passIndex == 0
            && SceneWaterCausticsAssetProfile.normalized(material.shaderPath ?? "")
                == SceneWaterCausticsAssetProfile.shaderIdentity
            && material.texturePaths.isEmpty && material.textureSlots.isEmpty
            && material.userTextureInputs.isEmpty && material.combos.isEmpty
            && material.constantShaderValues.isEmpty && material.userShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
            && material.alphaWriting == nil
    }

    private static func instancePass(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer
    ) -> SceneRenderDescriptor.EffectDescriptor.PassDescriptor? {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return nil }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              SceneWaterCausticsAssetProfile.normalized(descriptor.file)
                == SceneWaterCausticsAssetProfile.definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first,
              pass.passIndex == 0,
              pass.userTextureInputs.isEmpty
        else { return nil }
        return pass
    }

    private static func texturePaths(
        _ pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> [String?]? {
        guard pass.textureSlots.count <= 6,
              pass.textureSlots.isEmpty || pass.textureSlots[0] == nil,
              pass.texturePaths == pass.textureSlots.compactMap({ $0 }),
              pass.textureSlots.compactMap({ $0 }).allSatisfy({ !$0.isEmpty })
        else { return nil }
        return (0 ..< 6).map { pass.textureSlots.indices.contains($0) ? pass.textureSlots[$0] : nil }
    }

    private static func validResolved(
        _ material: SceneResolvedMaterialNode,
        pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        parameters expected: Parameters
    ) -> Bool {
        guard SceneWaterCausticsAssetProfile.normalized(material.shaderPath)
                == SceneWaterCausticsAssetProfile.shaderIdentity,
              material.renderState.blending?.lowercased() == "normal",
              material.renderState.depthTest?.lowercased() == "disabled",
              material.renderState.depthWrite?.lowercased() == "disabled",
              material.renderState.cullMode?.lowercased() == "nocull",
              normalizedCombos(material.combos) == normalizedCombos(pass.combos),
              let actual = parameters(material.constants),
              actual == expected,
              let expectedPaths = texturePaths(pass)
        else { return false }
        guard material.textureSlots.count >= expectedPaths.count else { return false }
        return material.textureSlots.enumerated().allSatisfy { index, slot in
            guard index < expectedPaths.count else { return slot == nil }
            guard let expectedPath = expectedPaths[index] else { return slot == nil }
            guard let slot, slot.provenance == .instance,
                  case .asset(let path) = slot.source else { return false }
            return path == expectedPath
        }
    }

    private static func parameters(_ values: [String: SceneDocument.ShaderValue]) -> Parameters? {
        var normalized: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in values {
            guard normalized.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        let keys: Set<String> = [
            "ui_editor_properties_brightness", "ui_editor_properties_glow",
            "ui_editor_properties_granularity", "ui_editor_properties_speed",
            "ui_editor_properties_time_offset", "ui_editor_properties_distortion",
            "ui_editor_properties_chromatic_aberration", "ui_editor_properties_blur",
            "ui_editor_properties_color_start", "ui_editor_properties_color_end",
        ]
        guard Set(normalized.keys).isSubset(of: keys),
              let brightness = scalar(normalized["ui_editor_properties_brightness"], 0.1 ... 5, 1),
              let glow = scalar(normalized["ui_editor_properties_glow"], 0 ... 1, 0.5),
              let scale = scalar(normalized["ui_editor_properties_granularity"], 0.1 ... 5, 2),
              let speed = scalar(normalized["ui_editor_properties_speed"], 0 ... 5, 1),
              let timeOffset = scalar(normalized["ui_editor_properties_time_offset"], -5 ... 5, 0),
              let distortion = scalar(normalized["ui_editor_properties_distortion"], 0 ... 2, 1),
              let chromatic = scalar(normalized["ui_editor_properties_chromatic_aberration"], 0 ... 2, 1),
              let blur = scalar(normalized["ui_editor_properties_blur"], 0 ... 1, 0),
              let colorStart = vector(normalized["ui_editor_properties_color_start"], SIMD3(0.7, 0.9, 1)),
              let colorEnd = vector(normalized["ui_editor_properties_color_end"], SIMD3(0.4, 0.6, 1))
        else { return nil }
        return Parameters(
            brightness: brightness, glow: glow, scale: scale, speed: speed,
            timeOffset: timeOffset, distortion: distortion, chromatic: chromatic,
            blur: blur, colorStart: colorStart, colorEnd: colorEnd
        )
    }

    private static func scalar(
        _ value: SceneDocument.ShaderValue?, _ range: ClosedRange<Float>, _ fallback: Float
    ) -> Float? {
        guard let value else { return fallback }
        guard value.userBinding == nil, value.valueKind.lowercased() == "number",
              value.bindingKeys.isEmpty, value.timeline == nil, value.timelineDiagnostics.isEmpty,
              value.scriptSource == nil, let components = value.components,
              components.count == 1, let component = components.first else { return nil }
        let result = Float(component)
        return result.isFinite && range.contains(result) ? result : nil
    }

    private static func vector(
        _ value: SceneDocument.ShaderValue?, _ fallback: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard let value else { return fallback }
        guard value.userBinding == nil, value.valueKind.lowercased() == "vector",
              value.bindingKeys.isEmpty, value.timeline == nil, value.timelineDiagnostics.isEmpty,
              value.scriptSource == nil, let c = value.components, c.count == 3,
              c.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else { return nil }
        return SIMD3(Float(c[0]), Float(c[1]), Float(c[2]))
    }

    private static func normalizedCombos(_ authored: [String: Int]) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in authored {
            guard result.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        return result
    }

    private static func effectOutput(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private static let expectedGizmos = SceneJSONValue.array([
        .object([
            "condition": .object(["PERSPECTIVE": .number(1)]),
            "type": .string("EffectPerspectiveUV"),
            "vars": .object([
                "p0": .string("point0"), "p1": .string("point1"),
                "p2": .string("point2"), "p3": .string("point3"),
            ]),
        ]),
    ])
}
