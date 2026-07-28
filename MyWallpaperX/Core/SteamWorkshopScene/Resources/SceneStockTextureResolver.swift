import Foundation

nonisolated struct SceneStockTextureResolver: Sendable {
    private let bundleRoot: URL

    init?(bundleRoot: URL) {
        let standardizedRoot = bundleRoot.standardizedFileURL
        let assetsRoot = standardizedRoot.appendingPathComponent("assets", isDirectory: true)
        guard FileManager.default.fileExists(atPath: assetsRoot.path) else { return nil }
        self.bundleRoot = standardizedRoot
    }

    func textureURL(for rawReference: String) -> URL? {
        guard let reference = Self.normalizedReference(rawReference) else { return nil }
        for projectPath in Self.projectPathCandidates(for: reference) {
            let candidate = bundleRoot.appendingPathComponent(projectPath).standardizedFileURL
            guard candidate.path.hasPrefix(bundleRoot.path + "/") else { continue }
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func defaultBundleRoot(in bundle: Bundle = .main) -> URL? {
        if let bundled = bundle.url(forResource: "SceneStockAssets", withExtension: "bundle") {
            return bundled
        }
        guard let resourceURL = bundle.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent(
            "SceneStockAssets.bundle",
            isDirectory: true
        )
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private static func projectPathCandidates(for reference: String) -> [String] {
        let withExtension = reference.hasSuffix(".tex") ? reference : reference + ".tex"
        if withExtension.hasPrefix("assets/") {
            return [withExtension]
        }
        if withExtension.hasPrefix("particle/") {
            return ["assets/materials/" + withExtension]
        }
        return ["assets/materials/" + withExtension, "assets/" + withExtension]
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
}
