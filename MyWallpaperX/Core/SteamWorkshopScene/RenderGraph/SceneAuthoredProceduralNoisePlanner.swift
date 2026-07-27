import Foundation
import simd

/// Exact Workshop 2906937488 profiles exercised by the current real samples.
/// Other noise types, masks, perspective, tiling, layering, and bindings stay closed.
enum SceneAuthoredProceduralNoisePlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private nonisolated struct Parameters {
        let scale: SIMD2<Float>
        let offset: SIMD2<Float>
        let magnitude: SIMD2<Float>
        let thresholds: SIMD2<Float>
        let colorsMin: SIMD3<Float>
        let colorsMax: SIMD3<Float>
        let opacity: Float
        let exponent: Float
        let fractals: Int
        let fractalScale: Float
        let fractalInfluence: Float
        let gradient: Float
        let seed: Float
        let animationSpeed: Float
        let scrollDirection: Float
        let scrollSpeed: Float
        let thresholdOffset: Float
        let shiftAmount: Float
    }

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneProceduralNoiseExecutionPlan? {
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
              SceneProceduralNoiseShaderProfile.matches(shaderContracts),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect),
              validMaterial(in: descriptor),
              let instance = validInstance(effect: effect, layer: layer),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node, graph: graph, descriptor: descriptor
              ).node,
              validResolvedMaterial(resolved),
              let resolvedVariant = variant(for: instance.combos),
              variant(for: resolved.combos) == resolvedVariant,
              let parsed = parameters(
                  from: instance.constantShaderValues, variant: resolvedVariant
              ),
              parameters(from: resolved.constants, variant: resolvedVariant).map({
                  equal($0, parsed)
              }) == true else {
            return nil
        }
        return .init(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            variant: resolvedVariant,
            scale: parsed.scale,
            offset: parsed.offset,
            magnitude: parsed.magnitude,
            thresholds: parsed.thresholds,
            colorsMin: parsed.colorsMin,
            colorsMax: parsed.colorsMax,
            opacity: parsed.opacity,
            exponent: parsed.exponent,
            fractals: parsed.fractals,
            fractalScale: parsed.fractalScale,
            fractalInfluence: parsed.fractalInfluence,
            gradient: parsed.gradient,
            seed: parsed.seed,
            animationSpeed: parsed.animationSpeed,
            scrollDirection: parsed.scrollDirection,
            scrollSpeed: parsed.scrollSpeed,
            thresholdOffset: parsed.thresholdOffset,
            shiftAmount: parsed.shiftAmount
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
              definition.replacementKey == "procedural_noise",
              definition.name == "Procedural noise",
              definition.description == nil,
              definition.group == "localeffects",
              definition.performance == nil,
              definition.previewPath == nil,
              definition.editable == false,
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
            && pass.target == nil && pass.bindings.isEmpty && pass.compose == nil
            && pass.command == nil && pass.source == nil && pass.conditions == nil
            && pass.extraFields.isEmpty
    }

    private nonisolated static func validNode(_ node: Graph.Node, effect: Graph.Effect) -> Bool {
        node.effect == effect.key
            && node.definitionPassIndex == 0 && node.materialOrdinal == 0
            && node.instancePassIndex == 0 && node.kind == .material
            && normalized(node.materialPath ?? "") == materialPath
            && normalized(node.materialPassID ?? "") == materialPassID
            && node.target == effect.output && node.bindings.isEmpty
            && node.commandSource == nil && node.commandTarget == nil
            && node.compose == nil && node.conditions == nil
    }

    private nonisolated static func validMaterial(in descriptor: SceneRenderDescriptor) -> Bool {
        let matches = descriptor.materialPasses.filter { normalized($0.id) == materialPassID }
        guard matches.count == 1, let material = matches.first else { return false }
        return normalized(material.materialPath) == materialPath
            && material.materialRawSHA256 == materialSHA256
            && material.passIndex == 0
            && normalized(material.shaderPath ?? "") == shaderIdentity
            && material.texturePaths.isEmpty && material.textureSlots.isEmpty
            && material.userTextureInputs.isEmpty && material.combos.isEmpty
            && material.constantShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validInstance(
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
              pass.texturePaths.isEmpty,
              pass.textureSlots.isEmpty,
              pass.userTextureInputs.isEmpty else {
            return nil
        }
        return pass
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode
    ) -> Bool {
        normalized(material.shaderPath) == shaderIdentity
            && material.textureSlots.allSatisfy { $0 == nil }
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func variant(
        for authored: [String: Int]
    ) -> SceneProceduralNoiseExecutionPlan.Variant? {
        var values: [String: Int] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        switch values {
        case ["AB_TYPECOLOR": 1, "AB_TYPEUV": 4, "AC_COLORMODE": 2]:
            return .colorPerlinRGB
        case ["AA_CATEGORY": 1, "AB_TYPEUV": 4]:
            return .uvCurl
        case ["AA_CATEGORY": 1, "AB_TYPEUV": 2]:
            return .uvWorleyMix
        default:
            return nil
        }
    }

    private nonisolated static func parameters(
        from authored: [String: SceneDocument.ShaderValue],
        variant: SceneProceduralNoiseExecutionPlan.Variant
    ) -> Parameters? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        var keys = commonKeys
        if variant == .colorPerlinRGB { keys.formUnion(["colors min", "colors max"]) }
        if variant == .uvWorleyMix { keys.insert("sample shift amount") }
        guard values.count == keys.count, values.keys.allSatisfy(keys.contains),
              let scale = vector2(values["scale"], range: 0...3),
              scale.x > 0, scale.y > 0,
              let offset = vector2(values["offset"], range: -1...1),
              let magnitude = vector2(values["magnitude"], range: 0...1),
              let thresholds = vector2(values["thresholds"], range: -1...2),
              thresholds.y > thresholds.x,
              let opacity = scalar(values["opacity"], range: 0...1),
              let exponent = scalar(values["exponent"], range: 0...5),
              let fractalsValue = scalar(values["fractals"], range: 1...5),
              fractalsValue.rounded() == fractalsValue,
              let fractalScale = scalar(values["fractal scaling"], range: 1...4),
              let fractalInfluence = scalar(values["fractal influence"], range: 0...1),
              let gradient = scalar(values["gradient"], range: 0...1),
              let seed = scalar(values["seed"], range: -1...1),
              let animationSpeed = scalar(values["animationspeed"], range: 0...3),
              let scrollDirection = scalar(values["scrollirection"], range: -7...7),
              let scrollSpeed = scalar(values["scrollspeed"], range: 0...2),
              let thresholdOffset = scalar(values["thresholds offset"], range: -1...1) else {
            return nil
        }
        let colorsMin = vector3(values["colors min"], range: 0...1) ?? .zero
        let colorsMax = vector3(values["colors max"], range: 0...1) ?? SIMD3(repeating: 1)
        let shiftAmount = scalar(values["sample shift amount"], range: 0...1) ?? 1
        return .init(
            scale: scale, offset: offset, magnitude: magnitude, thresholds: thresholds,
            colorsMin: colorsMin, colorsMax: colorsMax, opacity: opacity,
            exponent: exponent, fractals: Int(fractalsValue), fractalScale: fractalScale,
            fractalInfluence: fractalInfluence, gradient: gradient, seed: seed,
            animationSpeed: animationSpeed, scrollDirection: scrollDirection,
            scrollSpeed: scrollSpeed, thresholdOffset: thresholdOffset,
            shiftAmount: shiftAmount
        )
    }

    private nonisolated static func scalar(
        _ value: SceneDocument.ShaderValue?, range: ClosedRange<Double>
    ) -> Float? {
        guard let value, value.valueKind.lowercased() == "number", value.userBinding == nil,
              value.components?.count == 1, let component = value.components?.first,
              component.isFinite, range.contains(component) else { return nil }
        return Float(component)
    }

    private nonisolated static func vector2(
        _ value: SceneDocument.ShaderValue?, range: ClosedRange<Double>
    ) -> SIMD2<Float>? {
        guard let components = vector(value, count: 2, range: range) else { return nil }
        return SIMD2(Float(components[0]), Float(components[1]))
    }

    private nonisolated static func vector3(
        _ value: SceneDocument.ShaderValue?, range: ClosedRange<Double>
    ) -> SIMD3<Float>? {
        guard let components = vector(value, count: 3, range: range) else { return nil }
        return SIMD3(Float(components[0]), Float(components[1]), Float(components[2]))
    }

    private nonisolated static func vector(
        _ value: SceneDocument.ShaderValue?, count: Int, range: ClosedRange<Double>
    ) -> [Double]? {
        guard let value, value.valueKind.lowercased() == "vector", value.userBinding == nil,
              let components = value.components, components.count == count,
              components.allSatisfy({ $0.isFinite && range.contains($0) }) else { return nil }
        return components
    }

    private nonisolated static func equal(_ lhs: Parameters, _ rhs: Parameters) -> Bool {
        lhs.scale == rhs.scale && lhs.offset == rhs.offset && lhs.magnitude == rhs.magnitude
            && lhs.thresholds == rhs.thresholds && lhs.colorsMin == rhs.colorsMin
            && lhs.colorsMax == rhs.colorsMax && lhs.opacity == rhs.opacity
            && lhs.exponent == rhs.exponent && lhs.fractals == rhs.fractals
            && lhs.fractalScale == rhs.fractalScale
            && lhs.fractalInfluence == rhs.fractalInfluence && lhs.gradient == rhs.gradient
            && lhs.seed == rhs.seed && lhs.animationSpeed == rhs.animationSpeed
            && lhs.scrollDirection == rhs.scrollDirection && lhs.scrollSpeed == rhs.scrollSpeed
            && lhs.thresholdOffset == rhs.thresholdOffset && lhs.shiftAmount == rhs.shiftAmount
    }

    private nonisolated static func effectOutput(_ key: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: key.layerID, effect: key, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static let definitionPath =
        "effects/workshop/2906937488/procedural_noise/effect.json"
    private nonisolated static let materialPath =
        "materials/workshop/2906937488/effects/procedural_noise.json"
    private nonisolated static let materialPassID = "\(materialPath)#0"
    private nonisolated static let materialSHA256 =
        "4f48c4c321b1c9058986f253a3e7dfb28febf894f6b6ddb589aa7132cb006d8a"
    private nonisolated static let shaderIdentity =
        "workshop/2906937488/effects/procedural_noise"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/workshop/2906937488/effects/procedural_noise.frag",
        "shaders/workshop/2906937488/effects/procedural_noise.vert",
    ]
    private nonisolated static let commonKeys = Set([
        "exponent", "fractal influence", "fractal scaling", "fractals", "gradient",
        "magnitude", "offset", "opacity", "scale", "seed", "thresholds",
        "thresholds offset", "animationspeed", "scrollirection", "scrollspeed",
    ])
    private nonisolated static let expectedGizmos = SceneJSONValue.array([.object([
        "condition": .object(["PERSPSWITCH": .number(1)]),
        "type": .string("EffectPerspectiveUV"),
        "vars": .object([
            "p0": .string("point0"), "p1": .string("point1"),
            "p2": .string("point2"), "p3": .string("point3"),
        ]),
    ])])
}
