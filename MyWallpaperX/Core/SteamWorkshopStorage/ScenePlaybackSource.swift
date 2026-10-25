import Foundation

/// Pure facts captured with the producer's existing version lease. The lease
/// stays in the parent process; a receipt never grants access to another root.
nonisolated struct ScenePlaybackSource: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = 1
    let rootURL: URL
    let managed: ManagedBinding?

    struct ManagedBinding: Codable, Equatable, Sendable {
        let storageIdentity: String
        let generation: String
    }

    init(rootURL: URL, managed: ManagedBinding? = nil) {
        self.rootURL = rootURL
        self.managed = managed
    }

    var isValid: Bool {
        guard rootURL.isFileURL, rootURL.path.hasPrefix("/"),
              !rootURL.path.utf8.contains(0),
              rootURL.host == nil || rootURL.host == "" || rootURL.host == "localhost" else { return false }
        guard let managed else { return true }
        guard UUID(uuidString: managed.generation)?.uuidString.lowercased() == managed.generation else { return false }
        if managed.storageIdentity.hasPrefix("v1:") {
            guard managed.storageIdentity == "v1:" + managed.generation else { return false }
        } else {
            let prefix = "v2:scene:"
            let suffix = "-" + managed.generation
            guard managed.storageIdentity.hasPrefix(prefix), managed.storageIdentity.hasSuffix(suffix) else { return false }
            let item = managed.storageIdentity.dropFirst(prefix.count).dropLast(suffix.count)
            guard !item.isEmpty, item.utf8.allSatisfy({ (48...57).contains($0) }),
                  (UInt64(item) ?? 0) > 0 else { return false }
        }
        return true
    }
}

/// Retained only for decoding and preserving older commit/marker identities.
/// New publications do not create receipts and playback never opens this path.
nonisolated struct SceneSourceReceiptReference: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let relativePath: String
    let encodedByteCount: Int
    let sha256: String
    let storageIdentity: String
    let contentDigest: String
}

/// File facts used only while checking the staged download's copy digest.
/// Playback reads the current selected resources and never verifies this tree.
nonisolated enum SceneSourceManifest {
    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    struct FileFact: Codable, Equatable, Sendable {
        let path: String
        let size: Int64
        let sha256: String
    }
}
