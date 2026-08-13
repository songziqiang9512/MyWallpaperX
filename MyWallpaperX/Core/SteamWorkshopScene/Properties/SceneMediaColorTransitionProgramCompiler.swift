import Foundation

/// Projects lossless pass-owned SceneScript IR onto exact effect constants,
/// then delegates source semantics to the bounded media-color compiler.
nonisolated enum SceneMediaColorTransitionProgramCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR]
    ) -> SceneMediaColorTransitionProgram? {
        var compiled: [SceneMediaColorTransitionBinding] = []
        for binding in scriptBindings {
            guard let projection = projection(binding, descriptor: descriptor),
                  let result = SceneMediaColorTransitionCompiler.compile(
                      value: projection.value,
                      target: projection.target,
                      properties: binding.properties
                  ) else { continue }
            compiled.append(result)
        }
        return SceneMediaColorTransitionProgram.validated(bindings: compiled)
    }

    private typealias Projection = (
        value: SceneDocument.ShaderValue,
        target: SceneDynamicTarget
    )

    private nonisolated static func projection(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor
    ) -> Projection? {
        guard binding.owner.kind == .pass,
              binding.valueType == .string,
              case let .string(authored)? = binding.authoredValue,
              let authoredComponents = vector3(authored),
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
              value.rawValue == authored,
              value.scriptSource == binding.source,
              value.bindingKeys.sorted() == ["script", "scriptproperties", "value"],
              let components = value.components,
              components.count == 3,
              components[0].bitPattern == authoredComponents.x.bitPattern,
              components[1].bitPattern == authoredComponents.y.bitPattern,
              components[2].bitPattern == authoredComponents.z.bitPattern else {
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

    private nonisolated static func vector3(_ source: String) -> SIMD3<Double>? {
        let spellings = source.split { character in
            character.isWhitespace || character == ","
        }
        guard spellings.count == 3 else { return nil }
        let values = spellings.compactMap { Double($0) }
        guard values.count == 3, values.allSatisfy(\.isFinite) else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }

    private nonisolated static func expectedPath(
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
