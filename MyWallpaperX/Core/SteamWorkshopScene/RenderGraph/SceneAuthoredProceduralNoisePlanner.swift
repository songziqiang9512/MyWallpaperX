import Foundation
import simd

/// Exact authored profiles exercised by the current real samples.
/// Other noise types, masks, tiling, layering, and bindings stay closed.
enum SceneAuthoredProceduralNoisePlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias ShaderProfile = SceneProceduralNoiseShaderProfile.Profile

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
              let shaderProfile = SceneProceduralNoiseShaderProfile.matchingProfile(
                  shaderContracts
              ),
              supportsLayer(layer, profile: shaderProfile) else {
            return nil
        }
        let effect = graph.effects[0]
        let node = graph.nodes[0]
        guard normalized(effect.definitionPath) == shaderProfile.definitionPath,
              validDefinition(
                  in: descriptor, path: effect.definitionPath, profile: shaderProfile
              ),
              effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input, layerID: graph.layerID, role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect, profile: shaderProfile),
              validMaterial(in: descriptor, profile: shaderProfile),
              let instance = validInstance(
                  effect: effect, layer: layer, profile: shaderProfile
              ),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                  node: node, graph: graph, descriptor: descriptor
              ).node,
              validResolvedMaterial(
                  resolved,
                  profile: shaderProfile,
                  dependencyPath: instance.dependencyPath
              ),
              let resolvedVariant = variant(
                  for: instance.pass.combos, profile: shaderProfile
              ),
              variant(for: resolved.combos, profile: shaderProfile) == resolvedVariant,
              let parsed = parameters(
                  from: instance.pass.constantShaderValues, variant: resolvedVariant
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
            shiftAmount: parsed.shiftAmount,
            depthFade: parsed.depthFade,
            perspective01: parsed.perspective01,
            perspective23: parsed.perspective23,
            dependencyProviderLayerID: instance.dependencyProviderLayerID,
            dependencySlotIndex: instance.dependencyProviderLayerID == nil ? nil : 3
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains {
            ShaderProfile.allCases.map(\.definitionPath).contains(
                normalized($0.definitionPath)
            )
        }
    }

    private nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String,
        profile: ShaderProfile
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
              definition.editable == (profile == .modern ? false : nil),
              definition.framebuffers.isEmpty,
              definition.dependencies.map(normalized) == dependencies(profile),
              definition.functions == nil,
              definition.gizmos == expectedGizmos,
              definition.extraFields.isEmpty,
              definition.unknownFieldPaths.isEmpty,
              definition.passes.count == 1,
              let pass = definition.passes.first else {
            return false
        }
        return pass.passIndex == 0
            && normalized(pass.materialPath ?? "") == profile.materialPath
            && pass.target == nil && pass.bindings.isEmpty && pass.compose == nil
            && pass.command == nil && pass.source == nil && pass.conditions == nil
            && pass.extraFields.isEmpty
    }

    private nonisolated static func validNode(
        _ node: Graph.Node,
        effect: Graph.Effect,
        profile: ShaderProfile
    ) -> Bool {
        node.effect == effect.key
            && node.definitionPassIndex == 0 && node.materialOrdinal == 0
            && node.instancePassIndex == 0 && node.kind == .material
            && normalized(node.materialPath ?? "") == profile.materialPath
            && normalized(node.materialPassID ?? "") == "\(profile.materialPath)#0"
            && node.target == effect.output && node.bindings.isEmpty
            && node.commandSource == nil && node.commandTarget == nil
            && node.compose == nil && node.conditions == nil
    }

    private nonisolated static func validMaterial(
        in descriptor: SceneRenderDescriptor,
        profile: ShaderProfile
    ) -> Bool {
        let materialPassID = "\(profile.materialPath)#0"
        let matches = descriptor.materialPasses.filter {
            normalized($0.id) == materialPassID
        }
        guard matches.count == 1, let material = matches.first else { return false }
        return normalized(material.materialPath) == profile.materialPath
            && material.materialRawSHA256 == profile.materialSHA256
            && material.passIndex == 0
            && normalized(material.shaderPath ?? "") == profile.shaderIdentity
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
        layer: SceneRenderDescriptor.Layer,
        profile: ShaderProfile
    ) -> (
        pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        dependencyPath: String?,
        dependencyProviderLayerID: Int?
    )? {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return nil }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == profile.definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first,
              pass.passIndex == 0,
              pass.userTextureInputs.isEmpty else {
            return nil
        }
        switch profile {
        case .modern:
            guard pass.texturePaths.isEmpty, pass.textureSlots.isEmpty else { return nil }
            return (pass, nil, nil)
        case .legacyWorleyColor:
            guard pass.texturePaths.count == 1,
                  pass.textureSlots.count == 4,
                  pass.textureSlots[0...2].allSatisfy({ $0 == nil }),
                  let path = pass.textureSlots[3],
                  pass.texturePaths == [path],
                  let reference = SceneNamedTextureReference.parse(path),
                  reference.variant == .primary,
                  layer.dependencyLayerIDs == [reference.providerLayerID] else {
                return nil
            }
            return (pass, path, reference.providerLayerID)
        }
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        profile: ShaderProfile,
        dependencyPath: String?
    ) -> Bool {
        let validTextures: Bool
        if let dependencyPath {
            if material.textureSlots.count == 8,
               material.textureSlots[0...2].allSatisfy({ $0 == nil }),
               material.textureSlots[4...7].allSatisfy({ $0 == nil }),
               let slot = material.textureSlots[3],
               case .asset(let path) = slot.source {
                validTextures = slot.index == 3
                    && slot.candidates.count == 1
                    && slot.provenance == .instance
                    && normalized(path) == normalized(dependencyPath)
            } else {
                validTextures = false
            }
        } else {
            validTextures = material.textureSlots.allSatisfy { $0 == nil }
        }
        return normalized(material.shaderPath) == profile.shaderIdentity
            && validTextures
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func variant(
        for authored: [String: Int],
        profile: ShaderProfile
    ) -> SceneProceduralNoiseExecutionPlan.Variant? {
        var values: [String: Int] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.uppercased()) == nil else { return nil }
        }
        switch (profile, values) {
        case (.modern, ["AB_TYPECOLOR": 1, "AB_TYPEUV": 4, "AC_COLORMODE": 2]):
            return .colorPerlinRGB
        case (.modern, ["AA_CATEGORY": 1, "AB_TYPEUV": 4]):
            return .uvCurl
        case (.modern, ["AA_CATEGORY": 1, "AB_TYPEUV": 2]):
            return .uvWorleyMix
        case (
            .legacyWorleyColor,
            ["AB_TYPECOLOR": 3, "PERSPSWITCH": 1, "WRITEALPHA": 1]
        ):
            return .legacyWorleyColor
        default:
            return nil
        }
    }

    private nonisolated static func effectOutput(_ key: Graph.EffectKey) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: key.layerID, effect: key, name: nil)
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private nonisolated static func supportsLayer(
        _ layer: SceneRenderDescriptor.Layer,
        profile: ShaderProfile
    ) -> Bool {
        if profile == .modern {
            return ["image", "solid", "text"].contains(layer.contentKind)
        }
        return layer.contentKind == "composition"
            && layer.utilityLayer?.kind == .composition
            && layer.childLayerIDs.isEmpty
            && layer.dependencyLayerIDs.count == 1
    }

    private nonisolated static func dependencies(_ profile: ShaderProfile) -> [String] {
        [
            profile.materialPath,
            "shaders/\(profile.shaderIdentity).frag",
            "shaders/\(profile.shaderIdentity).vert",
        ]
    }
    nonisolated static let expectedGizmos = SceneJSONValue.array([.object([
        "condition": .object(["PERSPSWITCH": .number(1)]),
        "type": .string("EffectPerspectiveUV"),
        "vars": .object([
            "p0": .string("point0"), "p1": .string("point1"),
            "p2": .string("point2"), "p3": .string("point3"),
        ]),
    ])])
}
