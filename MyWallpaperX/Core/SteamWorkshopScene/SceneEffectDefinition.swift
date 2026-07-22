import Foundation

struct SceneEffectDefinition: Codable, Equatable, Identifiable, Sendable {
    struct Binding: Codable, Equatable, Sendable {
        let name: String?
        let index: Int?
        let conditions: SceneJSONValue?
        let extraFields: [String: SceneJSONValue]
    }

    struct Pass: Codable, Equatable, Identifiable, Sendable {
        let passIndex: Int
        let materialPath: String?
        let target: String?
        let bindings: [Binding]
        let compose: SceneJSONValue?
        let command: String?
        let source: String?
        let conditions: SceneJSONValue?
        let extraFields: [String: SceneJSONValue]

        var id: Int { passIndex }
    }

    struct Framebuffer: Codable, Equatable, Identifiable, Sendable {
        let name: String
        let scale: SceneJSONValue?
        let width: SceneJSONValue?
        let height: SceneJSONValue?
        let fit: SceneJSONValue?
        let format: String?
        let unique: Bool?
        let clear: SceneJSONValue?
        let uvs: SceneJSONValue?
        let conditions: SceneJSONValue?
        let extraFields: [String: SceneJSONValue]

        var id: String { name }
    }

    let relativePath: String
    let version: Int?
    let replacementKey: String?
    let name: String?
    let description: String?
    let group: String?
    let performance: String?
    let previewPath: String?
    let editable: Bool?
    let passes: [Pass]
    let framebuffers: [Framebuffer]
    let dependencies: [String]
    let functions: SceneJSONValue?
    let gizmos: SceneJSONValue?
    let extraFields: [String: SceneJSONValue]
    let unknownFieldPaths: [String]

    var id: String { relativePath }

    nonisolated var materialPassCount: Int {
        passes.filter { $0.materialPath != nil }.count
    }
}

struct SceneEffectDefinitionDiagnostic: Codable, Equatable, Identifiable, Sendable {
    enum Code: String, Codable, Sendable {
        case invalidDefinition
        case missingDefinition
        case passCountMismatch
        case unknownFields
    }

    let code: Code
    let effectPath: String
    let layerID: Int?
    let effectIndex: Int?
    let detail: String

    var id: String {
        [code.rawValue, effectPath, layerID.map(String.init) ?? "", effectIndex.map(String.init) ?? ""]
            .joined(separator: "#")
    }
}

struct SceneEffectDefinitionLoader {
    enum LoadError: LocalizedError {
        case invalidRoot(URL)

        var errorDescription: String? {
            switch self {
            case .invalidRoot(let url):
                return "Effect definition is not a JSON object: \(url.lastPathComponent)"
            }
        }
    }

    nonisolated init() {}

    nonisolated func load(from url: URL, relativePath: String) throws -> SceneEffectDefinition {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(
            with: data,
            options: [.json5Allowed]
        ) as? [String: Any] else {
            throw LoadError.invalidRoot(url)
        }

        let passes = (root["passes"] as? [[String: Any]] ?? []).enumerated().map(parsePass)
        let framebuffers = (root["fbos"] as? [[String: Any]] ?? []).compactMap(parseFramebuffer)
        let topExtras = extraFields(in: root, excluding: Self.topLevelFields)
        let unknownPaths = unknownFieldPaths(
            topExtras: topExtras,
            passes: passes,
            framebuffers: framebuffers
        )

        return SceneEffectDefinition(
            relativePath: normalizedPath(relativePath) ?? relativePath,
            version: integerValue(root["version"]),
            replacementKey: trimmedString(root["replacementkey"]),
            name: trimmedString(root["name"]),
            description: trimmedString(root["description"]),
            group: trimmedString(root["group"]),
            performance: trimmedString(root["performance"]),
            previewPath: normalizedPath(root["preview"] as? String),
            editable: boolValue(root["editable"]),
            passes: passes,
            framebuffers: framebuffers,
            dependencies: (root["dependencies"] as? [Any] ?? []).compactMap {
                normalizedPath($0 as? String)
            },
            functions: root["functions"].flatMap(SceneJSONValue.init(jsonObject:)),
            gizmos: root["gizmos"].flatMap(SceneJSONValue.init(jsonObject:)),
            extraFields: topExtras,
            unknownFieldPaths: unknownPaths
        )
    }

    nonisolated private func parsePass(
        index: Int,
        root: [String: Any]
    ) -> SceneEffectDefinition.Pass {
        SceneEffectDefinition.Pass(
            passIndex: index,
            materialPath: normalizedPath(root["material"] as? String),
            target: trimmedString(root["target"]),
            bindings: (root["bind"] as? [[String: Any]] ?? []).map(parseBinding),
            compose: root["compose"].flatMap(SceneJSONValue.init(jsonObject:)),
            command: trimmedString(root["command"]),
            source: trimmedString(root["source"]),
            conditions: root["conditions"].flatMap(SceneJSONValue.init(jsonObject:)),
            extraFields: extraFields(in: root, excluding: Self.passFields)
        )
    }

    nonisolated private func parseBinding(_ root: [String: Any]) -> SceneEffectDefinition.Binding {
        SceneEffectDefinition.Binding(
            name: trimmedString(root["name"]),
            index: integerValue(root["index"]),
            conditions: root["conditions"].flatMap(SceneJSONValue.init(jsonObject:)),
            extraFields: extraFields(in: root, excluding: Self.bindingFields)
        )
    }

    nonisolated private func parseFramebuffer(_ root: [String: Any]) -> SceneEffectDefinition.Framebuffer? {
        guard let name = trimmedString(root["name"]) else { return nil }
        return SceneEffectDefinition.Framebuffer(
            name: name,
            scale: root["scale"].flatMap(SceneJSONValue.init(jsonObject:)),
            width: root["width"].flatMap(SceneJSONValue.init(jsonObject:)),
            height: root["height"].flatMap(SceneJSONValue.init(jsonObject:)),
            fit: root["fit"].flatMap(SceneJSONValue.init(jsonObject:)),
            format: trimmedString(root["format"]),
            unique: boolValue(root["unique"]),
            clear: root["clear"].flatMap(SceneJSONValue.init(jsonObject:)),
            uvs: root["uvs"].flatMap(SceneJSONValue.init(jsonObject:)),
            conditions: root["conditions"].flatMap(SceneJSONValue.init(jsonObject:)),
            extraFields: extraFields(in: root, excluding: Self.framebufferFields)
        )
    }

    nonisolated private func extraFields(
        in root: [String: Any],
        excluding knownFields: Set<String>
    ) -> [String: SceneJSONValue] {
        root.reduce(into: [:]) { result, pair in
            guard !knownFields.contains(pair.key),
                  let value = SceneJSONValue(jsonObject: pair.value) else { return }
            result[pair.key] = value
        }
    }

    nonisolated private func unknownFieldPaths(
        topExtras: [String: SceneJSONValue],
        passes: [SceneEffectDefinition.Pass],
        framebuffers: [SceneEffectDefinition.Framebuffer]
    ) -> [String] {
        var paths = topExtras.keys.map { $0 }
        for pass in passes {
            paths += pass.extraFields.keys.map { "passes[\(pass.passIndex)].\($0)" }
            for (bindingIndex, binding) in pass.bindings.enumerated() {
                paths += binding.extraFields.keys.map {
                    "passes[\(pass.passIndex)].bind[\(bindingIndex)].\($0)"
                }
            }
        }
        for (index, framebuffer) in framebuffers.enumerated() {
            paths += framebuffer.extraFields.keys.map { "fbos[\(index)].\($0)" }
        }
        return paths.sorted()
    }

    nonisolated private func integerValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    nonisolated private func boolValue(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    nonisolated private func trimmedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private func normalizedPath(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated private static let topLevelFields = Set([
        "version", "replacementkey", "name", "description", "group", "performance",
        "preview", "editable", "passes", "fbos", "dependencies", "functions", "gizmos",
    ])
    nonisolated private static let passFields = Set([
        "material", "target", "bind", "compose", "command", "source", "conditions",
    ])
    nonisolated private static let bindingFields = Set(["name", "index", "conditions"])
    nonisolated private static let framebufferFields = Set([
        "name", "scale", "width", "height", "fit", "format", "unique", "clear", "uvs",
        "conditions",
    ])
}
