import Foundation

struct SceneResourceIndex {
    enum ResourceKind: String {
        case sceneJSON
        case package
        case shader
        case shaderBlob
        case effectDefinition
        case material
        case model
        case texture
        case particle
        case font
        case script
        case other
    }

    struct Resource: Identifiable {
        let relativePath: String
        let url: URL
        let kind: ResourceKind
        let fileSize: Int64

        var id: String { relativePath }
    }

    let rootURL: URL
    let resources: [Resource]

    nonisolated func count(kind: ResourceKind) -> Int {
        resources.filter { $0.kind == kind }.count
    }
}

struct SceneResourceIndexBuilder {
    nonisolated init() {}

    nonisolated func build(rootURL: URL) -> SceneResourceIndex {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return SceneResourceIndex(rootURL: rootURL, resources: [])
        }

        var resources: [SceneResourceIndex.Resource] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile ?? true else { continue }
            let relativePath = Self.relativePath(for: url, under: rootURL)
            resources.append(
                SceneResourceIndex.Resource(
                    relativePath: relativePath,
                    url: url,
                    kind: Self.kind(for: relativePath),
                    fileSize: Int64(values?.fileSize ?? 0)
                )
            )
        }

        return SceneResourceIndex(
            rootURL: rootURL,
            resources: resources.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
        )
    }

    nonisolated private static func relativePath(for fileURL: URL, under rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    nonisolated private static func kind(for relativePath: String) -> SceneResourceIndex.ResourceKind {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/").localizedLowercase
        let ext = URL(fileURLWithPath: normalized).pathExtension

        if normalized == "scene.json" { return .sceneJSON }
        if normalized == "scene.pkg" { return .package }
        if normalized.contains("/blobssm") && ext == "dxs" { return .shaderBlob }
        if normalized.hasPrefix("shaders/") { return .shader }
        if normalized.hasPrefix("effects/") && normalized.hasSuffix("/effect.json") {
            return .effectDefinition
        }
        if normalized.hasPrefix("materials/") {
            return ext == "tex" ? .texture : .material
        }
        if normalized.hasPrefix("models/") { return .model }
        if normalized.hasPrefix("particles/") { return .particle }
        if normalized.hasPrefix("fonts/") { return .font }
        if ext == "js" { return .script }
        return .other
    }
}
