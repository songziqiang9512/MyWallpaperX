import Foundation

/// Projects supported exact `{user,value}` material constants into the shared
/// property program. The layer-scoped target preserves one consumer identity
/// when the same material asset is reused by multiple objects.
nonisolated enum SceneMaterialPropertyBindingCompiler {
    static func compile(
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [Int: SceneDocument.SceneLayerMaterialInstance]
    ) -> [SceneUserPropertyBinding] {
        let linksByModel = Dictionary(
            grouping: descriptor.modelMaterialLinks,
            by: { normalized($0.modelPath) }
        )
        let passesByMaterial = Dictionary(
            grouping: descriptor.materialPasses,
            by: { normalized($0.materialPath) }
        )
        let imagePasses = imageMaterialPasses(descriptor: descriptor)
        return descriptor.layers.flatMap { layer -> [SceneUserPropertyBinding] in
            if let modelPath = layer.staticModelPath,
               let links = linksByModel[normalized(modelPath)] {
                return links.flatMap { link -> [SceneUserPropertyBinding] in
                    guard let materialPath = link.materialPath,
                          let passes = passesByMaterial[normalized(materialPath)],
                          let pass = passes.filter({ $0.passIndex == 0 }).only else { return [] }
                    return pass.constantShaderValues.keys.sorted().compactMap { name in
                        binding(layerID: layer.id, pass: pass, name: name)
                    }
                }
            }
            let passes = imagePasses[layer.id] ?? []
            let instance = materialInstancesByLayerID[layer.id]
            guard layer.puppetMeshPath == nil,
                  supportsBuiltinImageLighting(layer: layer, instance: instance, passes: passes),
                  instance?.scalarShaderValues?["emissivebrightness"] == nil,
                  let pass = passes.first,
                  emissionColor(instance: instance, pass: pass) != nil,
                  let value = binding(layerID: layer.id, pass: pass, name: "emissivebrightness")
            else { return [] }
            return [value]
        }
    }

    /// The image material association is prepared once per caller, with the
    /// same last material link selection used by the image asset projection.
    static func imageMaterialPasses(
        descriptor: SceneRenderDescriptor
    ) -> [Int: [SceneRenderDescriptor.MaterialPassDescriptor]] {
        let materialByModel = descriptor.modelMaterialLinks.reduce(into: [String: String]()) {
            result, link in
            if let path = link.materialPath { result[normalized(link.modelPath)] = normalized(path) }
        }
        let passesByMaterial = Dictionary(grouping: descriptor.materialPasses) {
            normalized($0.materialPath)
        }
        return descriptor.layers.reduce(into: [:]) { result, layer in
            guard layer.isImageRenderable, let image = layer.imagePath,
                  let material = materialByModel[normalized(image)] else { return }
            result[layer.id] = passesByMaterial[material] ?? []
        }
    }

    static func supportsBuiltinImageLighting(
        layer: SceneRenderDescriptor.Layer,
        instance: SceneDocument.SceneLayerMaterialInstance?,
        passes: [SceneRenderDescriptor.MaterialPassDescriptor]
    ) -> Bool {
        layer.isImageRenderable && instance?.isMalformed != true && passes.count == 1
            && passes.first?.shaderPath.map(SceneBuiltinShaderIdentity.isImage) == true
            && (instance?.combos["LIGHTING"] ?? passes.first?.combos["LIGHTING"]) == 1
    }

    static func staticComponents(
        _ key: String,
        instance: SceneDocument.SceneLayerMaterialInstance?,
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        count: Int,
        fallback: [Double]
    ) -> [Double]? {
        guard let value = instance?.scalarShaderValues?[key]
            ?? pass.constantShaderValues[key] else { return fallback }
        guard value.userBinding == nil,
              value.userValueKind == nil || value.userValueKind == .null,
              value.scriptSource == nil,
              value.timeline == nil, value.timelineDiagnostics.isEmpty,
              value.bindingKeys.allSatisfy({ $0 == "value" || $0 == "user" }),
              let components = value.components, components.count == count,
              components.allSatisfy(\.isFinite) else { return nil }
        return components
    }

    static func emissionColor(
        instance: SceneDocument.SceneLayerMaterialInstance?,
        pass: SceneRenderDescriptor.MaterialPassDescriptor
    ) -> SIMD3<Float>? {
        guard let color = staticComponents("emissivecolor", instance: instance, pass: pass,
                                           count: 3, fallback: [1, 1, 1]),
              color.allSatisfy({ $0 >= 0 && Float($0).isFinite }) else { return nil }
        return SIMD3(Float(color[0]), Float(color[1]), Float(color[2]))
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
