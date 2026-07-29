import Foundation
import simd

/// 官方 `effects/pulse` 的 fail-closed 准入器。
///
/// v1 只接受 exact 单 pass、`AUDIOPROCESSING` 缺省或显式 0 的时间驱动实例，shader 源
/// 按 [ScenePulseShaderProfile](ScenePulseShaderProfile.swift) 的逐指纹白名单准入：
/// 语料 30 个 pass 里 7 个 audio 驱动（无音频输入管线）与 1 个 SceneScript 绑定继续
/// fail closed；未知常量键（语料 4 例把编辑器 label 当 key）整条拒绝，不静默忽略。
/// slot 1 noise 只接受缺省或显式 `util/noise`（语料 19 例均为该值），slot 2 遮罩按
/// per-effect 实例装载，声明了却取不到贴图时渲染层整段拒绝。
enum SceneAuthoredPulsePlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Constant = ScenePulseExecutionPlan.Constant

    nonisolated static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> ScenePulseExecutionPlan? {
        guard graph.blockers.isEmpty,
              graph.effects.count == 1,
              graph.nodes.count == 1,
              graph.renderTargets.isEmpty,
              descriptor.layers.filter({ $0.id == graph.layerID }).count == 1,
              let layer = descriptor.layers.first(where: { $0.id == graph.layerID }),
              ["image", "solid", "text"].contains(layer.contentKind)
        else {
            return nil
        }

        let effect = graph.effects[0]
        let node = graph.nodes[0]
        func reject(_ reason: String) -> ScenePulseExecutionPlan? {
#if DEBUG
            print("MWX pulse planner rejected layer=\(graph.layerID) reason=\(reason)")
#endif
            return nil
        }
        guard normalized(effect.definitionPath) == definitionPath else { return nil }
        guard let profile = ScenePulseShaderProfile.resolve(shaderContracts) else {
            return reject("shader-profile")
        }
        guard validDefinition(
            in: descriptor,
            path: effect.definitionPath,
            profile: profile
        ) else {
            return reject("definition")
        }
        guard effect.nodeIndices == [node.nodeIndex],
              SceneAuthoredEffectInputValidator.accepts(
                  effect.input,
                  layerID: graph.layerID,
                  role: inputRole
              ),
              effect.output == effectOutput(effect.key),
              graph.finalOutput == effect.output,
              validNode(node, effect: effect)
        else {
            return reject("graph-shape")
        }
        guard validMaterialDescriptor(in: descriptor, profile: profile) else { return reject("material") }
        guard validInstance(effect: effect, layer: layer, profile: profile)
        else { return reject("instance") }
        guard let resolved = SceneAuthoredMaterialResolver.resolve(
            node: node,
            graph: graph,
            descriptor: descriptor
        ).node else {
            return reject("resolver")
        }
        guard validResolvedMaterial(resolved) else { return reject("resolved-material") }
        guard let combos = resolvedCombos(resolved.combos, profile: profile)
        else { return reject("combos") }
        guard let audio = audioParameters(
            combos: resolved.combos,
            constants: resolved.constants,
            profile: profile
        ) else {
            return reject("audio")
        }
        guard let constants = resolvedConstants(
            from: resolved.constants,
            effect: effect.key,
            profile: profile,
            audioEnabled: audio.parameters != nil
        ) else {
            return reject("constants")
        }
        guard let slots = textureSlots(
            in: layer.effects[effect.key.effectIndex].passes
        ) else {
            return reject("texture-slots")
        }

        return ScenePulseExecutionPlan(
            layerID: graph.layerID,
            effectKey: effect.key,
            renderGraph: graph,
            shaderProfile: profile,
            blendMode: combos.blendMode,
            pulseColor: combos.pulseColor,
            pulseAlpha: combos.pulseAlpha,
            staticOrFallbackValues: constants.values,
            bindings: constants.bindings,
            maskTexturePath: slots.mask,
            noiseTexturePath: slots.noise,
            audio: audio.parameters
        )
    }

    nonisolated static func containsCandidate(graph: Graph) -> Bool {
        graph.effects.contains { normalized($0.definitionPath) == definitionPath }
    }

    private nonisolated static func validDefinition(
        in descriptor: SceneRenderDescriptor,
        path: String,
        profile: ScenePulseShaderProfile
    ) -> Bool {
        let matches = descriptor.effectDefinitions.filter {
              normalized($0.relativePath) == normalized(path)
        }
        guard matches.count == 1, let definition = matches.first,
              definition.version == 1,
              definition.replacementKey == "pulse"
                  || (profile.acceptsMissingReplacementKey
                      && definition.replacementKey == nil),
              definition.name == "ui_editor_effect_pulse_title",
              definition.description == "ui_editor_effect_pulse_description",
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
              let pass = definition.passes.first
        else {
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
        profile: ScenePulseShaderProfile
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
            && validAuthoredCombos(material.combos, allowsAudio: false)
            && material.constantShaderValues.isEmpty
            && material.blending?.lowercased() == "normal"
            && material.depthTest?.lowercased() == "disabled"
            && material.depthWrite?.lowercased() == "disabled"
            && material.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func validInstance(
        effect: Graph.Effect,
        layer: SceneRenderDescriptor.Layer,
        profile: ScenePulseShaderProfile
    ) -> Bool {
        guard layer.effects.indices.contains(effect.key.effectIndex) else { return false }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID,
              normalized(descriptor.file) == definitionPath,
              descriptor.visible != false,
              descriptor.passes.count == 1,
              let pass = descriptor.passes.first
        else {
            return false
        }
        return pass.passIndex == 0
            && validInstanceTextureSlots(paths: pass.texturePaths, slots: pass.textureSlots)
            && pass.userTextureInputs.isEmpty
            && validAuthoredCombos(pass.combos, allowsAudio: profile == .stock2842)
    }

    private nonisolated static func validResolvedMaterial(
        _ material: SceneResolvedMaterialNode
    ) -> Bool {
        normalized(material.shaderPath) == shaderIdentity
            && validResolvedTextureSlots(material.textureSlots)
            && material.renderState.blending?.lowercased() == "normal"
            && material.renderState.depthTest?.lowercased() == "disabled"
            && material.renderState.depthWrite?.lowercased() == "disabled"
            && material.renderState.cullMode?.lowercased() == "nocull"
    }

    private nonisolated static func effectOutput(
        _ effect: Graph.EffectKey
    ) -> Graph.TextureIdentity {
        .init(kind: .effectOutput, layerID: effect.layerID, effect: effect, name: nil)
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    nonisolated static let definitionPath = "effects/pulse/effect.json"
    nonisolated static let materialPath = "materials/effects/pulse.json"
    private nonisolated static let materialSHA256 =
        "76a64c2e4e0b72c056b7dc3e35f333ca5fbc3b04b345b3bdccbedd3f2334deee"
    nonisolated static let materialPassID = "\(materialPath)#0"
    nonisolated static let shaderIdentity = "effects/pulse"
    private nonisolated static let dependencies = [
        materialPath,
        "shaders/effects/pulse.frag",
        "shaders/effects/pulse.vert",
    ]
}
