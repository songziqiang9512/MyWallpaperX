import Foundation

/// Compiles exact object origin/scale bindings for the bounded slider-to-Vec3
/// callback family. Admission is based on source shape plus owner/index/path and
/// authored fallback identity; sample, layer, path, and source hashes never
/// select behavior.
nonisolated enum ScenePropertyVectorScriptProgramCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR]
    ) -> ScenePropertyVectorScriptProgram {
        var bindings: [ScenePropertyVectorScriptBinding] = []
        for source in scriptBindings where source.owner.kind == .object
            && (source.targetKey == "origin" || source.targetKey == "scale")
        {
            guard let syntax = ScenePropertyVectorScriptSyntax.parse(source.source),
                  let binding = project(
                      source, syntax: syntax, descriptor: descriptor
                  ) else { continue }
            bindings.append(binding)
        }
        return ScenePropertyVectorScriptProgram.validated(bindings: bindings)
            ?? .empty
    }

    private static func project(
        _ source: SceneScriptBindingIR,
        syntax: ScenePropertyVectorScriptSyntax.Profile,
        descriptor: SceneRenderDescriptor
    ) -> ScenePropertyVectorScriptBinding? {
        guard source.wrapperKeys == ["script", "scriptproperties", "value"],
              source.valueType == .string,
              let authoredSource = source.authoredValue?.stringValue,
              let authored = vector3(authoredSource),
              let objectIndex = source.owner.objectIndex,
              let layerID = source.owner.objectID,
              descriptor.layers.indices.contains(objectIndex) else { return nil }
        let layer = descriptor.layers[objectIndex]
        guard layer.id == layerID, layer.layerIndex == objectIndex,
              source.targetPath == objectPath(
                  index: objectIndex, key: source.targetKey
              ), source.properties.keys.sorted() == syntax.propertyNames.sorted(),
              let descriptorValue = descriptorVector(
                  layer, targetKey: source.targetKey
              ), sameBits(authored, descriptorValue) else { return nil }

        let target: SceneDynamicTarget
        switch source.targetKey {
        case "origin": target = .layer(layerID: layerID, field: .origin)
        case "scale": target = .layer(layerID: layerID, field: .scale)
        default: return nil
        }
        let operation: ScenePropertyVectorScriptOperation
        switch syntax.operation {
        case let .scalarSplat(property):
            guard source.targetKey == "scale",
                  let input = scalarInput(source.properties[property]) else {
                return nil
            }
            operation = .scalarSplat(input)
        case let .components(components):
            let projected = components.compactMap { component in
                scalarInput(source.properties[component.property]).map {
                    ScenePropertyVectorScriptComponentBinding(
                        component: component.component, input: $0
                    )
                }
            }
            guard projected.count == components.count else { return nil }
            operation = .components(projected)
        }
        return ScenePropertyVectorScriptBinding(
            definition: SceneDynamicTargetDefinition(
                target: target,
                valueType: .vector3,
                authoredValue: .vector3(authored.x, authored.y, authored.z)
            ),
            operation: operation
        )
    }

    private static func scalarInput(
        _ value: SceneJSONValue?
    ) -> ScenePropertyVectorScriptScalarInput? {
        switch value {
        case let .number(number) where number.isFinite:
            return .init(fallback: number, userPropertyKey: nil)
        case let .object(wrapper):
            guard wrapper.keys.sorted() == ["user", "value"],
                  case let .string(key)? = wrapper["user"],
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  case let .number(number)? = wrapper["value"],
                  number.isFinite else { return nil }
            return .init(fallback: number, userPropertyKey: key)
        default:
            return nil
        }
    }

    private static func descriptorVector(
        _ layer: SceneRenderDescriptor.Layer,
        targetKey: String
    ) -> [Float]? {
        switch targetKey {
        case "origin": layer.originXYZ
        case "scale": layer.scaleXYZ
        default: nil
        }
    }

    private static func vector3(_ source: String) -> SIMD3<Double>? {
        let parts = source.split { $0.isWhitespace || $0 == "," }
        guard parts.count == 3 else { return nil }
        let values = parts.compactMap { Double($0) }
        guard values.count == 3, values.allSatisfy(\.isFinite) else { return nil }
        return SIMD3(values[0], values[1], values[2])
    }

    private static func sameBits(
        _ value: SIMD3<Double>, _ other: [Float]
    ) -> Bool {
        other.count == 3
            && Float(value.x).bitPattern == other[0].bitPattern
            && Float(value.y).bitPattern == other[1].bitPattern
            && Float(value.z).bitPattern == other[2].bitPattern
    }

    private static func objectPath(
        index: Int, key: String
    ) -> [SceneScriptBindingPathComponent] {
        [.key("objects"), .index(index), .key(key)]
    }
}
