import CryptoKit
import Foundation

struct SceneAssetCatalog {
    struct ModelAsset: Identifiable {
        let relativePath: String
        let materialPath: String?
        let autosize: Bool?
        let isSolidLayer: Bool
        let cropOffsetXY: [Float]?
        let puppetPath: String?
        let puppetAttachments: [SceneMdlPuppetAttachment]

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
        let rawSHA256: String
        /// Canonical material JSON with every pass-local shader identity replaced by a
        /// stable marker. Strict planners can use this together with an independently
        /// validated shader path/contract to recognize a byte-identical material shape
        /// after an author relocates the effect into another resource namespace.
        let shaderPathIndependentSHA256: String
        let passes: [Pass]

        var id: String { relativePath }
    }

    let rootURL: URL
    let models: [ModelAsset]
    let materials: [MaterialAsset]
    let effectDefinitions: [SceneEffectDefinition]
    let effectDefinitionDiagnostics: [SceneEffectDefinitionDiagnostic]
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

struct SceneAssetCatalogLoader {
    nonisolated func load(
        project: SceneProject,
        packageReport: ScenePkgExtractionReport?,
        referencedResourcePaths: [String] = [],
        stockAssetsRootURL: URL? = SceneResourceView.defaultStockAssetsRootURL()
    ) throws -> SceneAssetCatalog {
        let resourceView = SceneResourceView(
            projectRootURL: project.rootURL,
            packageRootURL: packageReport?.outputURL,
            stockAssetsRootURL: stockAssetsRootURL
        )
        return try load(
            resourceView: resourceView,
            referencedResourcePaths: referencedResourcePaths
        )
    }

    nonisolated func load(
        resourceView: SceneResourceView,
        referencedResourcePaths: [String]
    ) throws -> SceneAssetCatalog {
        let rootURL = resourceView.primaryRootURL
        var resources = resourceView.authorResources
        for path in referencedResourcePaths {
            guard let resource = resourceView.resource(forReference: path) else { continue }
            if resourceView.source(containing: resource.url) != .stock || resource.kind == .model {
                append(resource, to: &resources)
            }
        }

        let modelResources = resources.filter {
            $0.kind == .model && $0.relativePath.localizedLowercase.hasSuffix(".json")
        }
        let models = modelResources.compactMap {
            loadModel($0, resourceView: resourceView)
        }
        for model in models {
            if !model.isSolidLayer && !Self.isUtilityModelPath(model.relativePath) {
                append(model.materialPath.flatMap(resourceView.resource(relativePath:)), to: &resources)
            }
            append(model.puppetPath.flatMap(resourceView.resource(relativePath:)), to: &resources)
        }

        let effectResources = resources.filter { $0.kind == .effectDefinition }
        let effectResults = effectResources.map(loadEffectDefinition)
        let effectDefinitions = effectResults.compactMap(\.definition)
        for definition in effectDefinitions {
            for path in definition.passes.compactMap(\.materialPath) + definition.dependencies {
                append(resourceView.resource(forReference: path), to: &resources)
            }
        }

        let materialResources = resources.filter {
            $0.kind == .material && $0.relativePath.localizedLowercase.hasSuffix(".json")
        }
        let materials = materialResources.compactMap(loadMaterial)
        let shaderReferences = SceneAssetCatalog.uniqueSorted(materials.flatMap { material in
            material.passes.compactMap(\.shader)
        })

        return SceneAssetCatalog(
            rootURL: rootURL,
            models: models,
            materials: materials,
            effectDefinitions: effectDefinitions,
            effectDefinitionDiagnostics: effectResults.compactMap(\.diagnostic),
            shaderContracts: shaderReferences.flatMap { reference in
                SceneShaderContractLoader().load(
                    shaderReferences: [reference],
                    rootURL: shaderRootURL(
                        for: reference,
                        resourceView: resourceView,
                        fallback: rootURL
                    )
                )
            }
        )
    }

    nonisolated private func append(
        _ resource: SceneResourceIndex.Resource?,
        to resources: inout [SceneResourceIndex.Resource]
    ) {
        guard let resource else { return }
        let identity = resource.relativePath.localizedLowercase
        guard !resources.contains(where: { $0.relativePath.localizedLowercase == identity }) else {
            return
        }
        resources.append(resource)
    }

    nonisolated private func shaderRootURL(
        for reference: String,
        resourceView: SceneResourceView,
        fallback: URL
    ) -> URL {
        var identity = reference.replacingOccurrences(of: "\\", with: "/")
        for suffix in [".vert", ".frag", ".json"]
        where identity.localizedLowercase.hasSuffix(suffix) {
            identity.removeLast(suffix.count)
            break
        }
        for suffix in [".vert", ".frag"] {
            if let resource = resourceView.resource(
                relativePath: "shaders/" + identity + suffix
            ), let rootURL = resourceView.rootURL(containing: resource.url) {
                return rootURL
            }
        }
        return fallback
    }

    nonisolated private static func isUtilityModelPath(_ path: String) -> Bool {
        [
            "models/util/composelayer.json",
            "models/util/projectlayer.json",
            "models/util/fullscreenlayer.json",
        ].contains(path.localizedLowercase)
    }

    nonisolated private func loadEffectDefinition(
        _ resource: SceneResourceIndex.Resource
    ) -> (definition: SceneEffectDefinition?, diagnostic: SceneEffectDefinitionDiagnostic?) {
        do {
            let definition = try SceneEffectDefinitionLoader().load(
                from: resource.url,
                relativePath: resource.relativePath
            )
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
        } catch {
            return (
                nil,
                .init(
                    code: .invalidDefinition,
                    effectPath: resource.relativePath,
                    layerID: nil,
                    effectIndex: nil,
                    detail: error.localizedDescription
                )
            )
        }
    }

    nonisolated private func loadModel(
        _ resource: SceneResourceIndex.Resource,
        resourceView: SceneResourceView
    ) -> SceneAssetCatalog.ModelAsset? {
        guard let root = loadJSON(resource.url) else { return nil }
        let puppetPath = normalizedPath(root["puppet"] as? String)
        let puppetAttachments = puppetPath
            .flatMap(resourceView.resource(relativePath:))
            .flatMap { try? Data(contentsOf: $0.url) }
            .flatMap { try? SceneMdlPuppetAttachmentReader.read(data: $0) } ?? []
        return SceneAssetCatalog.ModelAsset(
            relativePath: resource.relativePath,
            materialPath: normalizedPath(root["material"] as? String),
            autosize: root["autosize"] as? Bool,
            isSolidLayer: root["solidlayer"] as? Bool ?? false,
            cropOffsetXY: parsedVector(root["cropoffset"], length: 2),
            puppetPath: puppetPath,
            puppetAttachments: puppetAttachments
        )
    }

    nonisolated private func loadMaterial(_ resource: SceneResourceIndex.Resource) -> SceneAssetCatalog.MaterialAsset? {
        guard let data = try? Data(contentsOf: resource.url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let rawPasses = root["passes"] as? [[String: Any]] ?? []
        let passes = rawPasses.map { pass in
            SceneAssetCatalog.MaterialAsset.Pass(
                shader: normalizedPath(pass["shader"] as? String),
                textures: texturePaths(in: pass),
                textureSlots: textureSlots(in: pass),
                userTextureInputs: userTextureInputs(in: pass),
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
        return SceneAssetCatalog.MaterialAsset(
            relativePath: resource.relativePath,
            rawSHA256: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined(),
            shaderPathIndependentSHA256: shaderPathIndependentSHA256(root),
            passes: passes
        )
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
            let rawValue = (keyed["value"] as? String) ?? "\(keyed)"
            let components = numericComponents(in: rawValue)
            return SceneDocument.ShaderValue(rawValue: rawValue, valueKind: "binding", userBinding: keyed["user"] as? String, components: components.isEmpty ? nil : components)
        }
        return SceneDocument.ShaderValue(rawValue: "\(value)", valueKind: "unknown", userBinding: nil, components: nil)
    }

    nonisolated private func numericComponents(in string: String) -> [Double] {
        string
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
            .compactMap { Double($0) }
    }

    nonisolated private func loadJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
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
        in pass: [String: Any]
    ) -> [SceneEffectTextureInput?] {
        (pass["usertextures"] as? [Any] ?? []).map(SceneEffectTextureInput.parse)
    }

    nonisolated private func parsedVector(_ value: Any?, length: Int) -> [Float]? {
        guard let values = SceneDocumentLoader.floatVector(value) else { return nil }
        let trimmed = Array(values.prefix(length))
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.isEmpty ? nil : normalized
    }
}
