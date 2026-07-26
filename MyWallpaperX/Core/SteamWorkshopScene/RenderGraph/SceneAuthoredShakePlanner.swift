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
    let audio: SceneAudioResponse.Parameters?
}

enum SceneAuthoredShakePlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan

    private struct Parameters {
        let bounds: SIMD2<Float>
        let friction: SIMD2<Float>
        let speed: Float
        let strength: Float
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
        guard let shaderProfile = SceneShakeShaderProfile.resolve(shaderContracts),
              normalized(effect.definitionPath) == definitionPath,
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
              validMaterialDescriptor(in: descriptor, profile: shaderProfile),
              let instance = instancePass(
                  effect: effect,
                  layer: layer,
                  profile: shaderProfile
              ),
              let paths = texturePaths(from: instance, profile: shaderProfile),
              let parameters = parameters(
                  from: instance.constantShaderValues,
                  profile: shaderProfile
              ),
              let audio = audioParameters(instance, profile: shaderProfile),
              let resolved = SceneAuthoredMaterialResolver.resolve(
                node: node,
                graph: graph,
                descriptor: descriptor
              ).node,
              validResolvedMaterial(
                resolved,
                flowPath: paths.flow,
                phasePath: paths.phase,
                profile: shaderProfile
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
            phaseTexturePath: paths.phase,
            audio: audio.parameters
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
        in descriptor: SceneRenderDescriptor,
        profile: SceneShakeShaderProfile
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
            && validCombos(material.combos, profile: profile)
            && material.constantShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func instancePass(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer,
        profile: SceneShakeShaderProfile
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
              validCombos(pass.combos, profile: profile) else {
            return nil
        }
        return pass
    }

    private nonisolated static func texturePaths(
        from pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor,
        profile: SceneShakeShaderProfile
    ) -> (flow: String, phase: String?)? {
        let supportsOmittedPhase = profile == .timeOffsetCombo
            && normalizedComboValue("TIMEOFFSET", in: pass.combos) != 1
        guard pass.textureSlots.count == 3
                || (supportsOmittedPhase && pass.textureSlots.count == 2),
              pass.textureSlots[0] == nil,
              let flow = pass.textureSlots[1],
              !flow.isEmpty else {
            return nil
        }
        let phase = pass.textureSlots.indices.contains(2) ? pass.textureSlots[2] : nil
        guard phase?.isEmpty != true else { return nil }
        if profile == .timeOffsetCombo {
            let usesPhase = normalizedComboValue("TIMEOFFSET", in: pass.combos) == 1
            guard usesPhase == (phase != nil) else { return nil }
        }
        let expected = [flow] + (phase.map { [$0] } ?? [])
        guard pass.texturePaths == expected else { return nil }
        // legacy 实例把 phase 显式写成 shader 注解默认 `util/white`（stock 资产，白=2π≡0）。
        // 显式默认与缺省语义相同，归一为 nil 走 pipeline 内置 R8 白回退，
        // 避免解码 BGRA white.tex 撞 pipeline 的 R8 phase 格式合同。
        if profile == .legacyUnconditionalPhase,
           let explicitPhase = phase,
           normalized(explicitPhase) == "util/white" {
            return (flow, nil)
        }
        return (flow, phase)
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode,
        flowPath: String,
        phasePath: String?,
        profile: SceneShakeShaderProfile
    ) -> Bool {
        // 归一后的 nil phase 在 resolved material 侧仍可能是显式 `util/white` 槽。
        let resolvedPhase = assetPath(material.textureSlots[2])
        let phaseMatches = resolvedPhase == phasePath
            || (profile == .legacyUnconditionalPhase
                && phasePath == nil
                && resolvedPhase.map(normalized) == "util/white")
        guard normalized(material.shaderPath) == shaderIdentity,
              material.textureSlots.count == 8,
              assetPath(material.textureSlots[1]) == flowPath,
              phaseMatches,
              material.textureSlots.enumerated().allSatisfy({
                  [1, 2].contains($0.offset) || $0.element == nil
              }),
              validCombos(material.combos, profile: profile),
              parameters(from: material.constants, profile: profile) != nil else {
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
        from authored: [String: SceneDocument.ShaderValue],
        profile: SceneShakeShaderProfile
    ) -> Parameters? {
        var values: [String: SceneDocument.ShaderValue] = [:]
        for (key, value) in authored {
            guard values.updateValue(value, forKey: key.lowercased()) == nil else {
                return nil
            }
        }
        // The legacy corpus authors only the deltas and relies on the shader
        // annotation defaults (g_Bounds "0 1", g_Friction "1 1", g_Speed 1,
        // g_Amp 0.1); every other profile keeps the exact four-key contract.
        let fillsDefaults = profile == .legacyUnconditionalPhase
        let supported = Set(["bounds", "friction", "speed", "strength"])
        let motionKeys = Set(values.keys).subtracting(audioConstantKeys)
        guard fillsDefaults
                ? motionKeys.isSubset(of: supported)
                : motionKeys == supported,
              let bounds = vector(
                  values["bounds"], range: 0...1,
                  fallback: fillsDefaults ? SIMD2(0, 1) : nil
              ),
              bounds.y > bounds.x,
              let friction = vector(
                  values["friction"], range: 0.01...10,
                  fallback: fillsDefaults ? SIMD2(1, 1) : nil
              ),
              let speed = scalar(
                  values["speed"], range: 0...10,
                  fallback: fillsDefaults ? 1 : nil
              ),
              let strength = scalar(
                  values["strength"], range: 0.01...0.5,
                  fallback: fillsDefaults ? 0.1 : nil
              ) else {
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
        range: ClosedRange<Double>,
        fallback: SIMD2<Float>?
    ) -> SIMD2<Float>? {
        guard let value else { return fallback }
        guard value.userBinding == nil,
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
        range: ClosedRange<Double>,
        fallback: Float?
    ) -> Float? {
        guard let value else { return fallback }
        guard value.userBinding == nil,
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

    private nonisolated static func validCombos(
        _ authored: [String: Int],
        profile: SceneShakeShaderProfile
    ) -> Bool {
        var normalizedValues: [String: Int] = [:]
        for (key, value) in authored {
            guard normalizedValues.updateValue(value, forKey: key.uppercased()) == nil else {
                return false
            }
        }
        return normalizedValues.allSatisfy { key, value in
            if key == "AUDIOPROCESSING" {
                return value == 0 || (audioCapable(profile) && (1 ... 3).contains(value))
            }
            if ["NOISE", "DIRECTION", "MASK"].contains(key) { return value == 0 }
            return key == "TIMEOFFSET"
                && profile == .timeOffsetCombo
                && (value == 0 || value == 1)
        }
    }

    private nonisolated static func normalizedComboValue(
        _ key: String,
        in authored: [String: Int]
    ) -> Int? {
        authored.first { $0.key.uppercased() == key }?.value
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
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
}
