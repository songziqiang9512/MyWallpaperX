import Foundation

/// Projects exact `{user,value}` static-model material constants into the shared
/// property program. The layer-scoped target preserves one consumer identity
/// when the same material asset is reused by multiple objects.
nonisolated enum SceneStaticModelMaterialPropertyBindingCompiler {
    static func compile(
        descriptor: SceneRenderDescriptor
    ) -> [SceneUserPropertyBinding] {
        let linksByModel = Dictionary(
            grouping: descriptor.modelMaterialLinks,
            by: { normalized($0.modelPath) }
        )
        let passesByMaterial = Dictionary(
            grouping: descriptor.materialPasses,
            by: { normalized($0.materialPath) }
        )
        return descriptor.layers.flatMap { layer -> [SceneUserPropertyBinding] in
            guard let modelPath = layer.staticModelPath,
                  let links = linksByModel[normalized(modelPath)],
                  links.count == 1,
                  let materialPath = links[0].materialPath,
                  let passes = passesByMaterial[normalized(materialPath)],
                  let pass = passes.filter({ $0.passIndex == 0 }).only else {
                return []
            }
            return pass.constantShaderValues.keys.sorted().compactMap { name in
                binding(
                    layerID: layer.id,
                    pass: pass,
                    name: name
                )
            }
        }
    }

    private static func binding(
        layerID: Int,
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        name: String
    ) -> SceneUserPropertyBinding? {
        guard let value = pass.constantShaderValues[name],
              value.bindingKeys.sorted() == ["user", "value"],
              value.userValueKind == .string,
              let propertyKey = value.userBinding,
              SceneScriptUserPropertyInputContract.validName(propertyKey),
              let fallback = fallback(name: name, components: value.components)
        else { return nil }
        return .init(
            reference: .init(key: propertyKey, condition: nil),
            fallbackValue: fallback,
            path: .init(components: [
                .key("materials"), .key(pass.materialPath),
                .key("passes"), .index(pass.passIndex),
                .key("constantshadervalues"), .key(name),
            ]),
            target: .materialShaderValue(
                layerID: layerID,
                passIndex: pass.passIndex,
                name: name,
                materialPath: pass.materialPath
            )
        )
    }

    private static func fallback(
        name: String,
        components: [Double]?
    ) -> SceneUserPropertyValue? {
        guard let components, components.allSatisfy(\.isFinite) else {
            return nil
        }
        if ["color", "emissivecolor"].contains(name) {
            guard components.count == 3 else { return nil }
            return .string(components.map { String($0) }.joined(separator: " "))
        }
        if ["alpha", "brightness", "emissivebrightness"].contains(name) {
            guard components.count == 1 else { return nil }
            return .number(components[0])
        }
        return nil
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").localizedLowercase
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
