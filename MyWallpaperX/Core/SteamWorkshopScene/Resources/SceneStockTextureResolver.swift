import Foundation

nonisolated struct SceneStockTextureResolver: Sendable {
    private struct Catalog: Decodable {
        struct Texture: Decodable {
            let officialPath: String
            let projectPath: String

            enum CodingKeys: String, CodingKey {
                case officialPath = "official_path"
                case projectPath = "project_path"
            }
        }

        let textures: [Texture]
    }

    private let bundleRoot: URL
    private let projectPathByReference: [String: String]

    init?(bundleRoot: URL) {
        let catalogURL = bundleRoot.appendingPathComponent("texture-catalog.json")
        guard let data = try? Data(contentsOf: catalogURL),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
            return nil
        }

        var mappings: [String: String] = [:]
        var ambiguousReferences: Set<String> = []
        for texture in catalog.textures {
            guard Self.isSafeCatalogPath(texture.projectPath) else { continue }
            for alias in Self.aliases(for: texture) {
                if let existing = mappings[alias], existing != texture.projectPath {
                    ambiguousReferences.insert(alias)
                    mappings.removeValue(forKey: alias)
                } else if !ambiguousReferences.contains(alias) {
                    mappings[alias] = texture.projectPath
                }
            }
        }

        self.bundleRoot = bundleRoot.standardizedFileURL
        self.projectPathByReference = mappings
    }

    func textureURL(for rawReference: String) -> URL? {
        guard let reference = Self.normalizedReference(rawReference),
              let projectPath = projectPathByReference[reference] else {
            return nil
        }
        let candidate = bundleRoot.appendingPathComponent(projectPath).standardizedFileURL
        guard candidate.path.hasPrefix(bundleRoot.path + "/"),
              FileManager.default.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    static func defaultBundleRoot(in bundle: Bundle = .main) -> URL? {
        if let bundled = bundle.url(forResource: "SceneStockTextures", withExtension: "bundle") {
            return bundled
        }
        guard let resourceURL = bundle.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent(
            "SceneStockTextures.bundle",
            isDirectory: true
        )
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private static func aliases(for texture: Catalog.Texture) -> Set<String> {
        var values: Set<String> = []
        for rawPath in [texture.officialPath, texture.projectPath] {
            guard let path = normalizedReference(rawPath) else { continue }
            values.insert(path)
            values.insert(removingTextureExtension(from: path))

            guard path.hasPrefix("assets/") else { continue }
            let withoutAssets = String(path.dropFirst("assets/".count))
            values.insert(withoutAssets)
            values.insert(removingTextureExtension(from: withoutAssets))

            if withoutAssets.hasPrefix("materials/particle/") {
                let particlePath = String(withoutAssets.dropFirst("materials/".count))
                values.insert(particlePath)
                values.insert(removingTextureExtension(from: particlePath))
            }
        }
        return values
    }

    private static func normalizedReference(_ rawReference: String) -> String? {
        var value = rawReference
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        while value.hasPrefix("./") { value.removeFirst(2) }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return value
    }

    private static func removingTextureExtension(from path: String) -> String {
        for suffix in [".tex", ".png"] where path.hasSuffix(suffix) {
            return String(path.dropLast(suffix.count))
        }
        return path
    }

    private static func isSafeCatalogPath(_ path: String) -> Bool {
        guard let normalized = normalizedReference(path),
              normalized.hasPrefix("assets/"),
              normalized.hasSuffix(".png") else {
            return false
        }
        return true
    }
}
