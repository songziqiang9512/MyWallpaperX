import Foundation

struct SceneAssetCatalog {
    struct ModelAsset: Identifiable {
        let relativePath: String
        let materialPath: String?
        let autosize: Bool?
        let isSolidLayer: Bool
        let cropOffsetXY: [Float]?
        let puppetPath: String?

        var id: String { relativePath }
    }

    struct MaterialAsset: Identifiable {
        struct Pass {
            let shader: String?
            let textures: [String]
            let textureSlots: [String?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
            let blending: String?
            let depthTest: String?
            let depthWrite: String?
            let cullMode: String?
        }

        let relativePath: String
        let passes: [Pass]

        var id: String { relativePath }
    }

    let rootURL: URL
    let models: [ModelAsset]
    let materials: [MaterialAsset]

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

    nonisolated private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}

struct SceneAssetCatalogLoader {
    nonisolated func load(project: SceneProject, packageReport: ScenePkgExtractionReport?) throws -> SceneAssetCatalog {
        let rootURL = packageReport?.outputURL ?? project.rootURL
        let resourceIndex = SceneResourceIndexBuilder().build(rootURL: rootURL)

        let modelResources = resourceIndex.resources.filter {
            $0.kind == .model && $0.relativePath.localizedLowercase.hasSuffix(".json")
        }
        let materialResources = resourceIndex.resources.filter {
            $0.kind == .material && $0.relativePath.localizedLowercase.hasSuffix(".json")
        }

        return SceneAssetCatalog(
            rootURL: rootURL,
            models: modelResources.compactMap(loadModel),
            materials: materialResources.compactMap(loadMaterial)
        )
    }

    nonisolated private func loadModel(_ resource: SceneResourceIndex.Resource) -> SceneAssetCatalog.ModelAsset? {
        guard let root = loadJSON(resource.url) else { return nil }
        return SceneAssetCatalog.ModelAsset(
            relativePath: resource.relativePath,
            materialPath: normalizedPath(root["material"] as? String),
            autosize: root["autosize"] as? Bool,
            isSolidLayer: root["solidlayer"] as? Bool ?? false,
            cropOffsetXY: parsedVector(root["cropoffset"], length: 2),
            puppetPath: normalizedPath(root["puppet"] as? String)
        )
    }

    nonisolated private func loadMaterial(_ resource: SceneResourceIndex.Resource) -> SceneAssetCatalog.MaterialAsset? {
        guard let root = loadJSON(resource.url) else { return nil }
        let rawPasses = root["passes"] as? [[String: Any]] ?? []
        let passes = rawPasses.map { pass in
            SceneAssetCatalog.MaterialAsset.Pass(
                shader: normalizedPath(pass["shader"] as? String),
                textures: texturePaths(in: pass),
                textureSlots: textureSlots(in: pass),
                combos: pass["combos"] as? [String: Int] ?? [:],
                constantShaderValues: materialConstantShaderValues(in: pass),
                blending: pass["blending"] as? String,
                depthTest: pass["depthtest"] as? String,
                depthWrite: pass["depthwrite"] as? String,
                cullMode: pass["cullmode"] as? String
            )
        }
        return SceneAssetCatalog.MaterialAsset(
            relativePath: resource.relativePath,
            passes: passes
        )
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

    nonisolated private func parsedVector(_ value: Any?, length: Int) -> [Float]? {
        guard let values = SceneDocumentLoader.floatVector(value) else { return nil }
        let trimmed = Array(values.prefix(length))
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let normalized = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        return normalized.isEmpty ? nil : normalized
    }
}
