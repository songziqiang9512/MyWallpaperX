import CryptoKit
import Foundation

struct SceneAssetCatalog {
    struct ModelAsset: Identifiable {
        let relativePath: String
        let materialPath: String?
        let autosize: Bool?
        let isSolidLayer: Bool
        /// Design size declared as scalar `width`/`height` in the model JSON.
        /// Layers referencing the model without an explicit `size` inherit it.
        let declaredSizeWH: [Float]?
        let cropOffsetXY: [Float]?
        let puppetPath: String?
        let puppetAttachments: [SceneMdlPuppetAttachment]
        /// Presence differs from a successfully parsed width/height pair.
        var hasDeclaredSizeFields: Bool = false
        /// Model metadata is distinct from a layer's config.passthrough.
        var passthrough: Bool? = nil

        var id: String { relativePath }
    }

    struct MaterialAsset: Identifiable {
        struct Pass {
            let shader: String?
            let textures: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
            let userShaderValues: [String: String]
            let blending: String?
            let depthTest: String?
            let depthWrite: String?
            let cullMode: String?
            let alphaWriting: String?
        }

        let relativePath: String
#if DEBUG
        var rawSHA256: String = ""
#endif
        /// Canonical material JSON with every pass-local shader identity replaced by a
        /// stable marker. Strict planners can use this together with an independently
        /// validated shader path/contract to recognize a byte-identical material shape
        /// after an author relocates the effect into another resource namespace.
        let shaderPathIndependentSHA256: String
        let passes: [Pass]

        var id: String { relativePath }
    }

    /// Parsed resources in the actual reference closure, including hidden and
    /// script-created templates; these counts do not enumerate author files.
    let models: [ModelAsset]
    let materials: [MaterialAsset]
    let effectDefinitions: [SceneEffectDefinition]
#if DEBUG
    var effectDefinitionDiagnostics: [SceneEffectDefinitionDiagnostic] = []
#endif
    let shaderContracts: [SceneShaderContract]

    nonisolated var materialPassCount: Int {
        materials.reduce(0) { $0 + $1.passes.count }
    }

    nonisolated var shaderReferences: [String] {
        Self.uniqueSorted(materials.flatMap { material in
            material.passes.compactMap(\.shader)
        })
    }

    nonisolated var textureReferences: [String] {
        Self.uniqueSorted(materials.flatMap { material in
            material.passes.flatMap(\.textures)
        })
    }

    nonisolated fileprivate static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}

nonisolated struct SceneAssetCatalogLoader {
    nonisolated func load(
        resourceView: SceneResourceView,
        referencedResourcePaths: [String],
        propertyCatalog: SceneUserPropertyCatalog = .empty,
        scriptSources: [String] = [],
        additionalModelPaths: [String] = [],
        additionalMaterialPaths: [String] = [],
        particlePaths: [String] = [],
        preparedParticleDefinition: (String, SceneParticleAssetGraphLoader.PreparedDefinition) -> Void = { _, _ in },
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> SceneAssetCatalog {
        try checkCancellation?()
        // Retain the complete name namespace, but read only selected consumers.
        let authorNames = resourceView.authorHandles
        var modelNames = authorNames.filter {
            $0.kind == .model && $0.relativePath.localizedLowercase.hasSuffix(".json")
        }.map(\.relativePath) + additionalModelPaths
        var order = Dictionary(uniqueKeysWithValues: authorNames.enumerated().map {
            (SceneResourceView.identity($0.element.relativePath), $0.offset)
        })
        var queue: [SceneResourceView.Handle] = []
        var seen: Set<String> = []
        func enqueue(_ path: String, reference: Bool = true) {
            let selected = reference ? resourceView.resolvedResource(forReference: path)
                : resourceView.resolvedResource(relativePath: path)
            guard let resource = selected else { return }
            let key = SceneResourceView.identity(resource.relativePath)
            guard seen.insert(key).inserted else { return }
            if order[key] == nil { order[key] = order.count }
            if resource.kind == .model && resource.source == .stock { modelNames.append(resource.relativePath) }
            queue.append(resource)
        }
        var sources: [String] = []
        var sourceIDs: [String: Int] = [:]
        var pendingSources: Set<Int> = []
        var sourcesByModel: [String: Set<Int>] = [:]
        var failedModels: Set<String> = []
        func addSource(_ source: String) {
            guard sourceIDs[source] == nil else { return }
            sourceIDs[source] = sources.count
            pendingSources.insert(sources.count)
            sources.append(source)
        }
        for source in scriptSources { addSource(source) }
        for path in referencedResourcePaths { enqueue(path) }
        for path in additionalMaterialPaths { enqueue(path, reference: false) }
        let particleMaterials = try SceneParticleAssetGraphLoader(resourceView: resourceView,
            stockTextureBundleURL: nil).prepareDefinitions(rootPaths: particlePaths,
                checkCancellation: checkCancellation) { path, value in
                    preparedParticleDefinition(path, value)
                }
        for path in particleMaterials { enqueue(path, reference: false) }
        let declaredTexturePropertyKeys = Set(propertyCatalog.definitions
            .filter { $0.kind == .sceneTexture }.map(\.key))
        var models: [SceneAssetCatalog.ModelAsset] = []
        var materials: [SceneAssetCatalog.MaterialAsset] = []
        var effectResults: [(definition: SceneEffectDefinition?, diagnostic: SceneEffectDefinitionDiagnostic?)] = []
        var next = 0
        while next < queue.count || !pendingSources.isEmpty {
            while next < queue.count {
                try checkCancellation?()
                let resource = queue[next]
                next += 1
                switch resource.kind {
                case .model where resource.relativePath.localizedLowercase.hasSuffix(".json"):
                    guard let model = try loadModel(resource, resourceView: resourceView,
                        checkCancellation: checkCancellation) else {
                        let key = SceneResourceView.identity(resource.relativePath)
                        failedModels.insert(key)
                        pendingSources.formUnion(sourcesByModel[key] ?? [])
                        continue
                    }
                    models.append(model)
                    if !Self.isUtilityModelPath(model.relativePath), let path = model.materialPath {
                        enqueue(path, reference: false)
                    }
                case .effectDefinition:
                    let result = try loadEffectDefinition(resource, checkCancellation: checkCancellation)
                    effectResults.append(result)
                    if let definition = result.definition {
                        for path in definition.passes.compactMap(\.materialPath) + definition.dependencies { enqueue(path) }
                    }
                case .material where resource.relativePath.localizedLowercase.hasSuffix(".json"):
                    if let material = try loadMaterial(resource, declaredTexturePropertyKeys: declaredTexturePropertyKeys,
                        checkCancellation: checkCancellation) {
                        materials.append(material)
                        for source in material.passes.flatMap({ $0.constantShaderValues.values.compactMap(\.scriptSource) }) {
                            addSource(source)
                        }
                    }
                default: break
                }
            }
            let available = modelNames.filter { !failedModels.contains(SceneResourceView.identity($0)) }
            let pending = pendingSources.sorted()
            pendingSources.removeAll(keepingCapacity: true)
            for index in pending {
                try checkCancellation?()
                for reference in SceneScriptDynamicImageReferenceAnalysis.references(
                    in: sources[index], availableModelPaths: available) ?? [] {
                    sourcesByModel[SceneResourceView.identity(reference.modelPath), default: []].insert(index)
                    enqueue(reference.modelPath)
                }
            }
        }
        func precedes(_ lhs: String, _ rhs: String) -> Bool {
            (order[SceneResourceView.identity(lhs)] ?? Int.max) < (order[SceneResourceView.identity(rhs)] ?? Int.max)
        }
        models.sort { precedes($0.relativePath, $1.relativePath) }
        materials.sort { precedes($0.relativePath, $1.relativePath) }
        effectResults.sort { precedes($0.definition?.relativePath ?? "", $1.definition?.relativePath ?? "") }
        let effectDefinitions = effectResults.compactMap(\.definition)
        let shaderReferences = SceneAssetCatalog.uniqueSorted(materials.flatMap { material in
            material.passes.compactMap(\.shader)
        })

        var catalog = SceneAssetCatalog(
            models: models,
            materials: materials,
            effectDefinitions: effectDefinitions,
            shaderContracts: try SceneShaderContractLoader().load(
                shaderReferences: shaderReferences,
                resourceView: resourceView, checkCancellation: checkCancellation
            )
        )
#if DEBUG
        catalog.effectDefinitionDiagnostics = effectResults.compactMap(\.diagnostic)
#endif
        return catalog
    }

    nonisolated private static func isUtilityModelPath(_ path: String) -> Bool {
        [
            "models/util/composelayer.json",
            "models/util/projectlayer.json",
            "models/util/fullscreenlayer.json",
        ].contains(path.localizedLowercase)
    }

    nonisolated private func loadEffectDefinition(
        _ resource: SceneResourceView.Handle,
        checkCancellation: (() throws -> Void)?
    ) throws -> (definition: SceneEffectDefinition?, diagnostic: SceneEffectDefinitionDiagnostic?) {
        let data: Data
        do {
            data = try resource.readBytes(checkCancellation: checkCancellation)
        } catch let error as SceneResourceView.ReadError {
            switch error {
            case .sourceChanged, .invalidHandle: throw error
            case .missing, .invalidPath, .symlinkEscape, .unreadable, .fileTooLarge:
                return invalidEffectDefinition(resource.relativePath, error: error)
            }
        }
        do {
            let definition = try SceneEffectDefinitionLoader().load(
                data: data,
                relativePath: resource.relativePath
            )
#if DEBUG
            let diagnostic: SceneEffectDefinitionDiagnostic? = definition.unknownFieldPaths.isEmpty
                ? nil
                : .init(
                    code: .unknownFields,
                    effectPath: definition.relativePath,
                    layerID: nil,
                    effectIndex: nil,
                    detail: definition.unknownFieldPaths.joined(separator: ", ")
                )
            return (definition, diagnostic)
#else
            return (definition, nil)
#endif
        } catch {
            return invalidEffectDefinition(resource.relativePath, error: error)
        }
    }

    nonisolated private func invalidEffectDefinition(
        _ relativePath: String,
        error: Error
    ) -> (definition: SceneEffectDefinition?, diagnostic: SceneEffectDefinitionDiagnostic?) {
#if DEBUG
        return (
            nil,
            .init(
                code: .invalidDefinition,
                effectPath: relativePath,
                layerID: nil,
                effectIndex: nil,
                detail: error.localizedDescription
            )
        )
#else
        return (nil, nil)
#endif
    }

    nonisolated private func loadModel(
        _ resource: SceneResourceView.Handle,
        resourceView: SceneResourceView,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneAssetCatalog.ModelAsset? {
        guard let root = try loadJSON(resource, checkCancellation: checkCancellation) else { return nil }
        let puppetPath = normalizedPath(root["puppet"] as? String)
        let puppetAttachments: [SceneMdlPuppetAttachment]
        if let puppet = puppetPath.flatMap(resourceView.resolvedResource(relativePath:)),
           let data = try readOptionalBytes(puppet, checkCancellation: checkCancellation) {
            do {
                puppetAttachments = try SceneMdlPuppetAttachmentReader.read(data: data)
            } catch {
                // Optional attachment metadata may be malformed. Only parsing
                // self-owned bytes degrades here; read failures escape above.
                puppetAttachments = []
            }
        } else {
            puppetAttachments = []
        }
        return SceneAssetCatalog.ModelAsset(
            relativePath: resource.relativePath,
            materialPath: normalizedPath(root["material"] as? String),
            autosize: root["autosize"] as? Bool,
            isSolidLayer: root["solidlayer"] as? Bool ?? false,
            declaredSizeWH: declaredModelSize(root),
            cropOffsetXY: parsedVector(root["cropoffset"], length: 2),
            puppetPath: puppetPath,
            puppetAttachments: puppetAttachments,
            hasDeclaredSizeFields: root["width"] != nil || root["height"] != nil,
            passthrough: root["passthrough"].flatMap {
                SceneJSONValue(jsonObject: $0)?.boolValue
            }
        )
    }

    nonisolated private func loadMaterial(
        _ resource: SceneResourceView.Handle,
        declaredTexturePropertyKeys: Set<String>,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneAssetCatalog.MaterialAsset? {
        guard let data = try readOptionalBytes(resource, checkCancellation: checkCancellation),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let rawPasses = root["passes"] as? [[String: Any]] ?? []
        let passes = rawPasses.map { pass in
            SceneAssetCatalog.MaterialAsset.Pass(
                shader: normalizedPath(pass["shader"] as? String),
                textures: texturePaths(in: pass),
                textureSlots: textureSlots(in: pass),
                userTextureInputs: userTextureInputs(in: pass,
                    declaredTexturePropertyKeys: declaredTexturePropertyKeys),
                combos: pass["combos"] as? [String: Int] ?? [:],
                constantShaderValues: materialConstantShaderValues(in: pass),
                userShaderValues: pass["usershadervalues"] as? [String: String] ?? [:],
                blending: pass["blending"] as? String,
                depthTest: renderState(in: pass, "depthtest", "depthtesting"),
                depthWrite: renderState(in: pass, "depthwrite", "depthwriting"),
                cullMode: renderState(in: pass, "cullmode", "culling"),
                alphaWriting: pass["alphawriting"] as? String
            )
        }
        var material = SceneAssetCatalog.MaterialAsset(
            relativePath: resource.relativePath,
            shaderPathIndependentSHA256: shaderPathIndependentSHA256(root),
            passes: passes
        )
#if DEBUG
        material.rawSHA256 = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
#endif
        return material
    }

    nonisolated private func shaderPathIndependentSHA256(
        _ root: [String: Any]
    ) -> String {
        var canonical = root
        if var passes = canonical["passes"] as? [[String: Any]] {
            for index in passes.indices where passes[index]["shader"] is String {
                passes[index]["shader"] = "$shader"
            }
            canonical["passes"] = passes
        }
        guard JSONSerialization.isValidJSONObject(canonical),
              let data = try? JSONSerialization.data(
                  withJSONObject: canonical,
                  options: [.sortedKeys]
              ) else {
            return ""
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// 随包 material 同时使用规范拼写与历史兼容拼写（`depthtesting`/`depthwriting`/`culling`），
    /// 两者必须归一到同一份 render state；规范拼写在共存时优先。
    nonisolated private func renderState(
        in pass: [String: Any],
        _ canonicalKey: String,
        _ compatibilityKey: String
    ) -> String? {
        (pass[canonicalKey] as? String) ?? (pass[compatibilityKey] as? String)
    }

    nonisolated private func materialConstantShaderValues(in pass: [String: Any]) -> [String: SceneDocument.ShaderValue] {
        guard let values = pass["constantshadervalues"] as? [String: Any] else { return [:] }
        return values.reduce(into: [String: SceneDocument.ShaderValue]()) { result, pair in
            result[pair.key] = shaderValue(from: pair.value)
        }
    }

    nonisolated private func shaderValue(from value: Any) -> SceneDocument.ShaderValue {
        if let double = value as? Double {
            return SceneDocument.ShaderValue(rawValue: String(double), valueKind: "number", userBinding: nil, components: [double])
        }
        if let int = value as? Int {
            return SceneDocument.ShaderValue(rawValue: String(int), valueKind: "number", userBinding: nil, components: [Double(int)])
        }
        if let string = value as? String {
            let components = numericComponents(in: string)
            return SceneDocument.ShaderValue(rawValue: string, valueKind: components.count > 1 ? "vector" : "string", userBinding: nil, components: components.isEmpty ? nil : components)
        }
        if let keyed = value as? [String: Any] {
            let rawValue: String
            if let string = keyed["value"] as? String { rawValue = string }
            else if let number = keyed["value"] as? Double {
                rawValue = String(number)
            } else if let number = keyed["value"] as? Int {
                rawValue = String(number)
            } else {
                rawValue = "\(keyed)"
            }
            let components = numericComponents(in: rawValue)
            return SceneDocument.ShaderValue(
                rawValue: rawValue,
                valueKind: "binding",
                userBinding: keyed["user"] as? String,
                userValueKind: keyed["user"].flatMap(
                    SceneShaderUserValueKind.init(jsonObject:)
                ),
                components: components.isEmpty ? nil : components,
                scriptSource: keyed["script"] as? String,
                scriptProperties: scriptProperties(keyed["scriptproperties"]),
                bindingKeys: SceneAssetCatalog.uniqueSorted(Array(keyed.keys))
            )
        }
        return SceneDocument.ShaderValue(rawValue: "\(value)", valueKind: "unknown", userBinding: nil, components: nil)
    }

    nonisolated private func scriptProperties(
        _ value: Any?
    ) -> [String: SceneJSONValue]? {
        guard let object = value as? [String: Any] else { return nil }
        var result: [String: SceneJSONValue] = [:]
        for (key, value) in object {
            guard let parsed = SceneJSONValue(jsonObject: value) else {
                return nil
            }
            result[key] = parsed
        }
        return result
    }

    nonisolated private func numericComponents(in string: String) -> [Double] {
        string
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
            .compactMap { Double($0) }
    }

    nonisolated private func loadJSON(
        _ resource: SceneResourceView.Handle,
        checkCancellation: (() throws -> Void)?
    ) throws -> [String: Any]? {
        guard let data = try readOptionalBytes(resource, checkCancellation: checkCancellation) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    nonisolated private func readOptionalBytes(
        _ resource: SceneResourceView.Handle,
        checkCancellation: (() throws -> Void)?
    ) throws -> Data? {
        do {
            return try resource.readBytes(checkCancellation: checkCancellation)
        } catch let error as SceneResourceView.ReadError {
            switch error {
            case .sourceChanged, .invalidHandle: throw error
            case .missing, .invalidPath, .symlinkEscape, .unreadable, .fileTooLarge: return nil
            }
        }
    }

    nonisolated private func texturePaths(in pass: [String: Any]) -> [String] {
        guard let textures = pass["textures"] as? [Any] else { return [] }
        return textures.compactMap { normalizedPath($0 as? String) }
    }

    nonisolated private func textureSlots(in pass: [String: Any]) -> [String?] {
        guard let textures = pass["textures"] as? [Any] else { return [] }
        return textures.map { normalizedPath($0 as? String) }
    }

    nonisolated private func userTextureInputs(
        in pass: [String: Any],
        declaredTexturePropertyKeys: Set<String>
    ) -> [SceneEffectTextureInput?] {
        (pass["usertextures"] as? [Any] ?? []).map {
            SceneEffectTextureInput.parse($0,
                declaredTexturePropertyKeys: declaredTexturePropertyKeys)
        }
    }

    nonisolated private func parsedVector(_ value: Any?, length: Int) -> [Float]? {
        guard let values = SceneDocumentLoader.floatVector(value) else { return nil }
        let trimmed = Array(values.prefix(length))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Models declare their design size as scalar `width`/`height` fields
    /// (e.g. models/background.json `{width: 1920, height: 1080}`); both must
    /// be present and positive for a layer to inherit them.
    nonisolated private func declaredModelSize(_ root: [String: Any]) -> [Float]? {
        guard let width = SceneDocumentLoader.floatValue(root["width"]),
              let height = SceneDocumentLoader.floatValue(root["height"]),
              width > 0, height > 0 else {
            return nil
        }
        return [width, height]
    }

    nonisolated private func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.isEmpty ? nil : normalized
    }
}
