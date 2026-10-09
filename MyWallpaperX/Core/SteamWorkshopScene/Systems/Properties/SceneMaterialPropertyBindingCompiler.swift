import Foundation

/// Projects supported exact `{user,value}` material constants into the shared
/// property program. The layer-scoped target preserves one consumer identity
/// when the same material asset is reused by multiple objects.
nonisolated enum SceneMaterialPropertyBindingCompiler {
    /// Material opacity belongs to the source before its effect chain. The
    /// property Program remains the sole owner of its current frame value.
    enum SourceMaterialAlpha: Equatable, Sendable {
        case constant(Float)
        case property(target: SceneDynamicTarget, fallback: Float)

        var propertyTarget: SceneDynamicTarget? {
            guard case let .property(target, _) = self else { return nil }
            return target
        }

        func resolve(snapshot: SceneDynamicSnapshot) -> Float {
            switch self {
            case let .constant(value): return value
            case let .property(target, fallback):
                guard let resolved = snapshot[target],
                      case let .scalar(value) = resolved.value,
                      value.isFinite, (0 ... 1).contains(value) else {
                    return fallback
                }
                return Float(value)
            }
        }
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [Int: SceneDocument.SceneLayerMaterialInstance],
        provenBindings: [SceneBaseMaterialColorModulationCompiler.Binding] = [],
        modelScriptInputs: [(target: SceneDynamicTarget, inputs: [String: SceneScriptPropertyInput])] = []
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
        let provenModels = Set(provenBindings.map(\.modelPath))
        let builtinBindings = descriptor.layers.flatMap { layer -> [SceneUserPropertyBinding] in
            if let modelPath = layer.staticModelPath,
               let links = linksByModel[normalized(modelPath)] {
                return links.flatMap { link -> [SceneUserPropertyBinding] in
                    guard let materialPath = link.materialPath,
                          let passes = passesByMaterial[normalized(materialPath)],
                          let pass = passes.filter({ $0.passIndex == 0 }).only else { return [] }
                    if let channels = pass.staticModelMaterialBindings {
                        switch channels.state {
                        case .rejected: return []
                        case .authored:
                            let typed: [SceneUserPropertyBinding] = channels.bindings.compactMap { channel in
                                guard let key = channel.materialKey else { return nil }
                                return binding(
                                    layerID: layer.id, pass: pass, name: key,
                                    valueType: channel.valueType
                                )
                            }
                            let claimedKeys = Set(channels.bindings.compactMap(\.materialKey))
                            let emission = ["emissivecolor", "emissivebrightness"]
                                .filter { !claimedKeys.contains($0) }.compactMap {
                                    binding(layerID: layer.id, pass: pass, name: $0)
                                }
                            return typed + emission
                        case .hostBuiltin, .unavailable: break
                        }
                    }
                    return pass.constantShaderValues.keys.sorted().compactMap {
                        binding(layerID: layer.id, pass: pass, name: $0)
                    }
                }
            }
            let passes = imagePasses[layer.id] ?? []
            let instance = materialInstancesByLayerID[layer.id]
            var bindings: [SceneUserPropertyBinding] = []
            let hasProvenSource = layer.imagePath.map { provenModels.contains(normalized($0)) } ?? false
            if !hasProvenSource, let declaration = sourceMaterialAlphaDeclaration(
                layer: layer, instance: instance, passes: passes
            ), !declaration.isInstance,
               validAlpha(declaration.value) != nil,
               let alpha = binding(
                    layerID: layer.id, pass: declaration.pass,
                    name: "Alpha", valueType: .scalar
               ) {
                bindings.append(alpha)
            }
            guard layer.puppetMeshPath == nil,
                  supportsBuiltinImage(layer: layer, instance: instance, passes: passes),
                  instance?.scalarShaderValues?["emissivebrightness"] == nil,
                  let pass = passes.first,
                  (instance?.combos["LIGHTING"] ?? pass.combos["LIGHTING"]) == 1,
                  emissionColor(instance: instance, pass: pass) != nil,
                  let value = binding(layerID: layer.id, pass: pass, name: "emissivebrightness")
            else { return bindings }
            return bindings + [value]
        }
        let modelLayerIDs = Set(descriptor.layers.compactMap {
            $0.staticModelPath == nil ? nil : $0.id
        })
        let nestedModelBindings = modelScriptInputs.flatMap { entry -> [SceneUserPropertyBinding] in
            guard case let .materialConstant(layerID, passIndex, name, materialPath) = entry.target,
                  modelLayerIDs.contains(layerID) else { return [] }
            return scriptPropertyBindings(layerID: layerID, path: [
                .key("materials"), .key(materialPath), .key("passes"), .index(passIndex),
                .key("constantshadervalues"), .key(name),
            ], inputs: entry.inputs)
        }
        return builtinBindings + nestedModelBindings + provenPropertyBindings(
            provenBindings, descriptor: descriptor,
            materialInstancesByLayerID: materialInstancesByLayerID
        )
    }

    static func provenPropertyBindings(
        _ facts: [SceneBaseMaterialColorModulationCompiler.Binding],
        descriptor: SceneRenderDescriptor,
        materialInstancesByLayerID: [Int: SceneDocument.SceneLayerMaterialInstance]
    ) -> [SceneUserPropertyBinding] {
        let passesByMaterial = Dictionary(grouping: descriptor.materialPasses) {
            normalized($0.materialPath)
        }
        return facts.flatMap { fact -> [SceneUserPropertyBinding] in
            guard materialInstancesByLayerID[fact.sourceLayerID] == nil,
                  let pass = (passesByMaterial[normalized(fact.materialPath)] ?? [])
                    .filter({ $0.passIndex == 0 }).only else { return [] }
            var bindings: [SceneUserPropertyBinding] = []
            if fact.alphaUserPropertyKey != nil, let key = fact.alphaKey,
               let value = binding(layerID: fact.sourceLayerID, pass: pass,
                   name: key, valueType: .scalar) { bindings.append(value) }
            if fact.colorUserPropertyKey != nil,
               let value = binding(layerID: fact.sourceLayerID, pass: pass,
                   name: fact.colorKey, valueType: .vector3, allowScript: fact.scriptSource != nil) {
                bindings.append(value)
            }
            if fact.scriptSource != nil,
               let inputs = SceneScriptPropertyInputCodec.inputs(fact.scriptProperties) {
                bindings += scriptPropertyBindings(
                    layerID: fact.sourceLayerID, path: fact.colorBindingPath, inputs: inputs
                )
            }
            return bindings
        }
    }

    /// Both image and model material scripts feed the existing property transaction.
    /// These are preparation facts; the VM remains the only value producer.
    private static func scriptPropertyBindings(
        layerID: Int, path: [SceneUserPropertyPathComponent],
        inputs: [String: SceneScriptPropertyInput]
    ) -> [SceneUserPropertyBinding] {
        inputs.sorted(by: { $0.key < $1.key }).compactMap { name, input in
            guard let key = input.userPropertyKey,
                  let fallback = SceneUserPropertyValue.parse(input.fallback.jsonObject) else { return nil }
            let path = path + [.key("scriptproperties"), .key(name)]
            return .init(reference: .init(key: key, condition: input.condition),
                fallbackValue: fallback, path: .init(components: path),
                target: .scriptProperty(layerID: layerID,
                    path: SceneScriptPropertyTargetPath.encoded(path)))
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

    static func supportsBuiltinImage(
        layer: SceneRenderDescriptor.Layer,
        instance: SceneDocument.SceneLayerMaterialInstance?,
        passes: [SceneRenderDescriptor.MaterialPassDescriptor]
    ) -> Bool {
        layer.isImageRenderable && instance?.isMalformed != true && passes.count == 1
            && passes.first?.shaderPath.map(SceneBuiltinShaderIdentity.isImage) == true
    }

    /// The public stock declaration uses the exact material key `Alpha` only
    /// for these image identities. A present instance override owns the field
    /// even when it cannot be admitted; it must not expose a material writer.
    private static func sourceMaterialAlphaDeclaration(
        layer: SceneRenderDescriptor.Layer,
        instance: SceneDocument.SceneLayerMaterialInstance?,
        passes: [SceneRenderDescriptor.MaterialPassDescriptor]
    ) -> (pass: SceneRenderDescriptor.MaterialPassDescriptor,
          value: SceneDocument.ShaderValue, isInstance: Bool)? {
        guard layer.isImageRenderable, instance?.isMalformed != true,
              passes.count == 1, let pass = passes.first,
              pass.passIndex == 0, let shader = pass.shaderPath,
              ["genericimage", "genericimage2"].contains(shader.lowercased())
        else { return nil }
        if let override = instance?.scalarShaderValues?["Alpha"] {
            return (pass, override, true)
        }
        guard let value = pass.constantShaderValues["Alpha"] else { return nil }
        return (pass, value, false)
    }

    private static func validAlpha(_ value: SceneDocument.ShaderValue) -> Float? {
        // The shared vector parser preserves numeric components even when a
        // token is malformed. Alpha needs one complete scalar declaration.
        let tokens = value.rawValue.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 1, let scalar = Double(tokens[0]),
              scalar.isFinite, (0 ... 1).contains(scalar),
              let components = value.components, components == [scalar]
        else { return nil }
        return Float(scalar)
    }

    static func sourceMaterialAlpha(
        layer: SceneRenderDescriptor.Layer,
        instance: SceneDocument.SceneLayerMaterialInstance?,
        passes: [SceneRenderDescriptor.MaterialPassDescriptor],
        materialPropertyTargets: Set<SceneDynamicTarget>
    ) -> SourceMaterialAlpha? {
        guard let declaration = sourceMaterialAlphaDeclaration(
            layer: layer, instance: instance, passes: passes
        ), let fallback = validAlpha(declaration.value) else { return nil }
        if !declaration.isInstance,
           binding(
                layerID: layer.id, pass: declaration.pass,
                name: "Alpha", valueType: .scalar
           ) != nil {
            let target = SceneDynamicTarget.materialConstant(
                layerID: layer.id, passIndex: declaration.pass.passIndex,
                name: "Alpha", materialPath: normalized(declaration.pass.materialPath)
            )
            guard materialPropertyTargets.contains(target) else { return nil }
            return .property(target: target, fallback: fallback)
        }
        guard staticComponents(
            "Alpha", instance: instance, pass: declaration.pass,
            count: 1, fallback: [1]
        ) != nil else { return nil }
        return .constant(fallback)
    }

    static func staticComponents(
        _ key: String,
        instance: SceneDocument.SceneLayerMaterialInstance?,
        pass: SceneRenderDescriptor.MaterialPassDescriptor,
        count: Int,
        fallback: [Double],
        requiresCompleteScalar: Bool = false
    ) -> [Double]? {
        // Strict scalar admission is opt-in; existing image projections retain
        // their current semantics. It cannot be applied to vector components.
        guard !requiresCompleteScalar || count == 1 else { return nil }
        guard let value = instance?.scalarShaderValues?[key]
            ?? pass.constantShaderValues[key] else { return fallback }
        guard value.userBinding == nil,
              value.userValueKind == nil || value.userValueKind == .null,
              value.scriptSource == nil,
              value.timeline == nil, value.timelineDiagnostics.isEmpty,
              value.bindingKeys.allSatisfy({ $0 == "value" || $0 == "user" }),
              let components = value.components, components.count == count,
              components.allSatisfy(\.isFinite) else { return nil }
        guard !requiresCompleteScalar || Double(value.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )) == components[0] else { return nil }
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
        name: String,
        valueType: SceneStaticModelMaterialBindings.ValueType? = nil,
        allowScript: Bool = false
    ) -> SceneUserPropertyBinding? {
        guard let value = pass.constantShaderValues[name],
              value.bindingKeys.sorted() == (allowScript
                ? (value.scriptProperties == nil ? ["script", "user", "value"]
                    : ["script", "scriptproperties", "user", "value"])
                : ["user", "value"]),
              value.userValueKind == .string,
              let propertyKey = value.userBinding,
              SceneScriptUserPropertyInputContract.validName(propertyKey),
              allowScript ? value.scriptSource != nil
                : value.scriptSource == nil && value.scriptProperties == nil,
              value.timeline == nil, value.timelineDiagnostics.isEmpty,
              let fallback = fallback(
                name: name, components: value.components, valueType: valueType
              )
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
        components: [Double]?,
        valueType: SceneStaticModelMaterialBindings.ValueType?
    ) -> SceneUserPropertyValue? {
        guard let components, components.allSatisfy(\.isFinite) else {
            return nil
        }
        if let valueType {
            guard components.allSatisfy({ Float($0).isFinite }) else { return nil }
            switch valueType {
            case .vector3:
                guard components.count == 3 else { return nil }
                return .string(components.map { String($0) }.joined(separator: " "))
            case .scalar:
                guard components.count == 1 else { return nil }
                return .number(components[0])
            }
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
