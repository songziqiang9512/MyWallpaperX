import Foundation
import UniformTypeIdentifiers
import CryptoKit

nonisolated struct SceneResourceIndex: Sendable {
    enum ResourceKind: String, Sendable {
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

    struct Resource: Identifiable, Sendable {
        let relativePath: String
        /// Only directory-backed entries have a physical file location.
        let directoryURL: URL?
        let kind: ResourceKind
        let fileSize: Int64

        init(relativePath: String, url: URL, kind: ResourceKind, fileSize: Int64) {
            self.init(relativePath: relativePath, directoryURL: url, kind: kind, fileSize: fileSize)
        }

        init(relativePath: String, directoryURL: URL?, kind: ResourceKind, fileSize: Int64) {
            self.relativePath = relativePath; self.directoryURL = directoryURL
            self.kind = kind; self.fileSize = fileSize
        }

        var id: String { relativePath }
    }

    let directoryURL: URL?
    let resources: [Resource]

    init(rootURL: URL, resources: [Resource]) {
        directoryURL = rootURL; self.resources = resources
    }

    init(resources: [Resource]) { directoryURL = nil; self.resources = resources }

    nonisolated func count(kind: ResourceKind) -> Int {
        resources.filter { $0.kind == kind }.count
    }
}

nonisolated struct SceneResourceIndexBuilder {
    static let bundledManifestFilename = "SceneStockIndex.json"
    static let maximumBundledManifestBytes = 4 * 1024 * 1024

    private nonisolated struct ManifestEntry: Codable {
        let relativePath: String
        let fileSize: Int64
    }

    private nonisolated struct BundledManifest: Codable {
        let schemaVersion: Int
        let payload: Data
        let sha256: String
    }

    struct BuildResult {
        let index: SceneResourceIndex
        let isComplete: Bool
    }

    nonisolated init() {}

    nonisolated func build(rootURL: URL) -> SceneResourceIndex {
        buildWithCompleteness(rootURL: rootURL).index
    }

    /// Build-time producer: called after stock packaging exclusions. Use the
    /// same enumeration as playback; never infer visibility from file suffixes.
    nonisolated func bundledManifestData(rootURL: URL) throws -> Data {
        let built = buildWithCompleteness(rootURL: rootURL)
        guard built.isComplete else {
            throw NSError(domain: "SceneStockIndex", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Stock enumeration was incomplete"])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let entries = built.index.resources.map {
            ManifestEntry(relativePath: $0.relativePath, fileSize: $0.fileSize)
        }
        let payload = try encoder.encode(entries)
        let data = try encoder.encode(BundledManifest(
            schemaVersion: 1, payload: payload, sha256: Self.manifestSHA256(payload)))
        guard data.count <= Self.maximumBundledManifestBytes else {
            throw NSError(domain: "SceneStockIndex", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Stock index exceeds the manifest budget"])
        }
        return data
    }

    /// Optional metadata from our build-time producer. Only the default
    /// in-App stock caller may use it; author and mutable roots still enumerate.
    /// Missing/invalid data returns nil so that caller retains the original path.
    nonisolated func loadBundledManifest(rootURL: URL, manifestURL: URL) -> SceneResourceIndex? {
        let metadata = try? manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard metadata?.isRegularFile == true, metadata?.isSymbolicLink != true,
              let fileSize = metadata?.fileSize, fileSize <= Self.maximumBundledManifestBytes else { return nil }
        guard let file = try? FileHandle(forReadingFrom: manifestURL) else { return nil }
        defer { try? file.close() }
        // Producer: generate-scene-stock-index.swift. A truncated, old, or
        // oversized packaged sidecar must never establish a complete Root.
        guard let data = try? file.read(upToCount: Self.maximumBundledManifestBytes + 1),
              data.count <= Self.maximumBundledManifestBytes,
              let manifest = try? JSONDecoder().decode(BundledManifest.self, from: data),
              manifest.schemaVersion == 1,
              Self.manifestSHA256(manifest.payload) == manifest.sha256,
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: manifest.payload)
        else { return nil }

        var paths: Set<String> = []
        for entry in entries {
            let path = entry.relativePath
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard entry.fileSize >= 0, !path.contains("\\"), !path.contains("\0"),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  let first = components.first,
                  !(first.count == 2 && first.last == ":" && first.first?.isLetter == true),
                  paths.insert(path).inserted else { return nil }
        }
        let sorted = entries.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        // A build-machine tie order cannot define the user's firstWins choice.
        // Preserve the original filesystem enumeration for ambiguous collation.
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            if a.relativePath.localizedStandardCompare(b.relativePath) == .orderedSame { return nil }
        }
        return SceneResourceIndex(rootURL: rootURL, resources: sorted.map {
            SceneResourceIndex.Resource(relativePath: $0.relativePath,
                url: rootURL.appendingPathComponent($0.relativePath),
                kind: Self.kind(for: $0.relativePath), fileSize: $0.fileSize)
        })
    }

    nonisolated private static func manifestSHA256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Preserve the existing best-effort namespace for this request, while
    /// preventing an interrupted enumeration from becoming a shared snapshot.
    nonisolated func buildWithCompleteness(rootURL: URL) -> BuildResult {
        let fileManager = FileManager.default
        var isComplete = true
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                isComplete = false
                return true
            }
        ) else {
            return BuildResult(
                index: SceneResourceIndex(rootURL: rootURL, resources: []),
                isComplete: false
            )
        }

        var resources: [SceneResourceIndex.Resource] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == nil { isComplete = false }
            guard values?.isRegularFile ?? true else { continue }
            if values?.fileSize == nil { isComplete = false }
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

        return BuildResult(
            index: SceneResourceIndex(
                rootURL: rootURL,
                resources: resources.sorted {
                    $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                }
            ),
            isComplete: isComplete
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

    nonisolated static func kind(for relativePath: String) -> SceneResourceIndex.ResourceKind {
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

    /// A PKG has names, not filesystem hidden flags. Preserve the fresh-file
    /// index projection: dot-hidden paths and descendants of public directory
    /// package types stay literal-only. Directory backing uses FileManager's
    /// actual attributes and never calls this projection.
    nonisolated static func isOrdinaryPackagePath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0.hasPrefix(".") }) else { return false }
        return !components.dropLast().contains { component in
            let ext = (component as NSString).pathExtension
            return !ext.isEmpty && (UTType(filenameExtension: ext, conformingTo: .directory)?.conforms(to: .package) ?? false)
        }
    }

}
