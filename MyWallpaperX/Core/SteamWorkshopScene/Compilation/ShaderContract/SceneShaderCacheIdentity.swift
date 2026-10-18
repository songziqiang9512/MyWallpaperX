import Foundation

/// The build hashes producer sources and helpers. Reading one small resource
/// once per process replaces manual semantic-version maintenance at each tier.
nonisolated enum SceneShaderCacheIdentity {
    private struct Identity: Decodable {
        let schemaVersion: Int
        let semantics: String
        let toolchain: String
    }

    private static let identity: Identity = {
        let bundle = Bundle.main
        let resource = bundle.url(
            forResource: "SceneShaderCacheIdentity", withExtension: "json"
        )
        // Standalone regression probes use their own executable directory.
        // An App always consumes its signed bundle resource.
        let url = resource ?? (bundle.bundleURL.pathExtension == "app" ? nil :
            bundle.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("SceneShaderCacheIdentity.json"))
        if let url,
           let values = try? url.resourceValues(forKeys: [
               .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
           ]), values.isRegularFile == true, values.isSymbolicLink != true,
           let size = values.fileSize, (1 ... 4_096).contains(size),
           let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(Identity.self, from: data),
           loaded.schemaVersion == 1,
           isDigest(loaded.semantics), isDigest(loaded.toolchain) {
            return loaded
        }
        // Missing build metadata must never silently accept an old producer.
        // Keep compilation available with a process-private, bounded cache key.
        let nonce = "process-private-" + UUID().uuidString
        return Identity(schemaVersion: 1, semantics: nonce, toolchain: nonce)
    }()

    static var semantics: String { identity.semantics }
    static var toolchain: String { identity.toolchain }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 102).contains($0)
        }
    }
}
