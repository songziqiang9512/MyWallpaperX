import Foundation

/// Projects lossless pass-owned SceneScript IR onto exact effect constants,
/// then delegates source semantics to the bounded fade compiler.
nonisolated enum SceneMediaPlaybackPlaceholderFadeProgramCompiler {
    static func compile(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR]
    ) -> SceneMediaPlaybackPlaceholderFadeProgram? {
        var compiled: [SceneMediaPlaybackPlaceholderFadeBinding] = []
        for binding in scriptBindings {
            guard let projection = projection(
                binding,
                descriptor: descriptor
            ), let result = SceneMediaPlaybackPlaceholderFadeCompiler.compile(
                value: projection.value,
                target: projection.target
            ) else {
                continue
            }
            compiled.append(result)
        }
        return SceneMediaPlaybackPlaceholderFadeProgram.validated(bindings: compiled)
    }

    private typealias Projection = (
        value: SceneDocument.ShaderValue,
        target: SceneDynamicTarget
    )

    private static func projection(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor
    ) -> Projection? {
        guard binding.owner.kind == .pass,
              binding.properties.isEmpty,
              binding.valueType == .number,
              let authored = binding.authoredValue?.numberValue,
              authored.isFinite,
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              let effectIndex = binding.owner.effectIndex,
              let passIndex = binding.owner.passIndex,
              descriptor.layers.indices.contains(objectIndex),
              descriptor.layers[objectIndex].id == layerID,
              descriptor.layers[objectIndex].layerIndex == objectIndex,
              descriptor.layers[objectIndex].effects.indices.contains(effectIndex) else {
            return nil
        }
        let effect = descriptor.layers[objectIndex].effects[effectIndex]
        guard effect.effectID == binding.owner.effectID,
              effect.passes.indices.contains(passIndex) else { return nil }
        let pass = effect.passes[passIndex]
        let name = binding.targetKey
        guard pass.passIndex == passIndex,
              pass.id == binding.owner.passID,
              !name.isEmpty,
              binding.targetPath == expectedPath(
                  objectIndex: objectIndex,
                  effectIndex: effectIndex,
                  passIndex: passIndex,
                  name: name
              ),
              let value = pass.constantShaderValues[name],
              value.scriptSource == binding.source,
              value.components?.count == 1,
              value.components?.first?.bitPattern == authored.bitPattern else {
            return nil
        }
        return (
            value,
            .effectConstant(
                layerID: layerID,
                effectIndex: effectIndex,
                passIndex: passIndex,
                name: name
            )
        )
    }

    private static func expectedPath(
        objectIndex: Int,
        effectIndex: Int,
        passIndex: Int,
        name: String
    ) -> [SceneScriptBindingPathComponent] {
        [
            .key("objects"), .index(objectIndex),
            .key("effects"), .index(effectIndex),
            .key("passes"), .index(passIndex),
            .key("constantshadervalues"), .key(name),
        ]
    }
}
