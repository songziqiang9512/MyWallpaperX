import Foundation
import simd

/// Strict stock profiles for standalone direct-draw Light Shafts quads.
enum SceneAuthoredLightShaftsPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private nonisolated struct Parameters {
        let profile: SceneLightShaftsProfile
        let points: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
        let startColor: SIMD3<Float>
        let endColor: SIMD3<Float>
        let feather: SIMD2<Float>
        let scale: SIMD2<Float>
        let radius: Float
        let noiseAmount: Float
        let noiseScale: Float
        let smoothness: Float
        let speed: Float
        let intensity: Float
        let exponent: Float
        let startAngle: Float
        let endAngle: Float
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
              let profile = profile(from: resolved.combos),
              let parameters = parameters(from: resolved.constants, profile: profile),
              let effectUVTransform = SceneLightShaftsPerspectiveTransform.make(
                  points: parameters.points
              ) else {
            return nil
        }

        return SceneLightShaftsExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            profile: parameters.profile,
            points: parameters.points,
            effectUVTransform: effectUVTransform,
            startColor: parameters.startColor,
            endColor: parameters.endColor,
            feather: parameters.feather,
            scale: parameters.scale,
            radius: parameters.radius,
            noiseAmount: parameters.noiseAmount,
            noiseScale: parameters.noiseScale,
            smoothness: parameters.smoothness,
            speed: parameters.speed,
            intensity: parameters.intensity,
            exponent: parameters.exponent,
            startAngle: parameters.startAngle,
            endAngle: parameters.endAngle,
            noiseTexturePath: noiseTexturePath,
            gradientTexturePath: gradientTexturePath
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains { normalized($0.definitionPath) == definitionPath }
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
              let pass = descriptor.passes.first,
              let profile = profile(from: pass.combos) else {
            return false
        }
        return pass.passIndex == 0
            && pass.texturePaths.isEmpty
            && pass.textureSlots.isEmpty
            && pass.userTextureInputs.isEmpty
            && parameters(from: pass.constantShaderValues, profile: profile) != nil
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode
    ) -> Bool {
        guard let profile = profile(from: material.combos) else { return false }
        return normalized(material.shaderPath) == shaderIdentity
            && material.textureSlots.allSatisfy { $0 == nil }
            && parameters(from: material.constants, profile: profile) != nil
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func profile(
        from authored: [String: Int]
    ) -> SceneLightShaftsProfile? {
        var values: [String: Int] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        if values == ["DIRECTDRAW": 1, "RENDERING": 1] { return .linearGradient }
        if values == ["DIRECTDRAW": 1, "RAYMODE": 1] { return .radialColor }
        return nil
    }

    private nonisolated static func parameters(
        from authored: [String: SceneDocument.ShaderValue],
        profile: SceneLightShaftsProfile
    ) -> Parameters? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else { return nil }
        }
        var expectedKeys = constantKeys
        if profile == .radialColor {
            expectedKeys.formUnion(["rayzstartangle", "rayzzendangle"])
        }
        let exponentRange: ClosedRange<Double> =
            profile == .radialColor ? 0...10 : 0.01...10
        guard Set(values.keys) == expectedKeys,
              let startColor = vector(values["colorastart"], count: 3, range: 0...1),
              let endColor = vector(values["colorend"], count: 3, range: 0...1),
              let noiseAmount = scalar(values["noiseamount"], range: 0...1),
              let noiseScale = scalar(values["noisescale"], range: 0...10),
              let radius = scalar(values["rayradius"], range: 0...2),
              let point0 = vector2(values["point0"], range: -2...3),
              let point1 = vector2(values["point1"], range: -2...3),
              let point2 = vector2(values["point2"], range: -2...3),
              let point3 = vector2(values["point3"], range: -2...3),
              let feather = vector2(values["rayfeather"], range: 0...1),
              let scale = vector2(values["rayscale"], range: 0.001...10),
              let smoothness = scalar(values["raysmoothness"], range: 0...1),
              let speed = scalar(values["rayspeed"], range: -10...10),
              let intensity = scalar(values["colorwintensity"], range: 0...10),
              let exponent = scalar(values["colorwexponent"], range: exponentRange) else {
            return nil
        }
        let angles: SIMD2<Float>
        if profile == .radialColor {
            guard let start = scalar(values["rayzstartangle"], range: 0...1),
                  let end = scalar(values["rayzzendangle"], range: 0...1),
                  start <= end else {
                return nil
            }
            angles = SIMD2(start, end)
        } else {
            angles = SIMD2(0, 1)
        }
        return .init(
            profile: profile,
            points: (point0, point1, point2, point3),
            startColor: SIMD3(
                Float(startColor[0]), Float(startColor[1]), Float(startColor[2])
            ),
            endColor: SIMD3(
                Float(endColor[0]), Float(endColor[1]), Float(endColor[2])
            ),
            feather: feather,
            scale: scale,
            radius: radius,
            noiseAmount: noiseAmount,
            noiseScale: noiseScale,
            smoothness: smoothness,
            speed: speed,
            intensity: intensity,
            exponent: exponent,
            startAngle: angles.x,
            endAngle: angles.y
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

    private nonisolated static func effectOutput(_ effect: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static let constantKeys = Set([
        "colorastart", "colorend", "colorwexponent", "colorwintensity",
        "noiseamount", "noisescale", "point0", "point1", "point2", "point3",
        "rayfeather", "rayradius", "rayscale", "raysmoothness", "rayspeed",
    ])
    nonisolated static let noiseTexturePath = "materials/util/noise"
    nonisolated static let gradientTexturePath =
        "materials/gradient/gradient_iridescent"
}
