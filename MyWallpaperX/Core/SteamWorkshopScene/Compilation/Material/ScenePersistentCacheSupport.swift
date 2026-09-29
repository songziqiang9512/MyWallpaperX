import Foundation

/// Shared on-disk plumbing for the Scene persistent analysis tiers. Each
/// tier keeps its own envelope, digest and schema version; this home owns
/// the single copy of directory resolution, entry reading and pruning so new
/// tiers cannot regrow duplicate bodies of these helpers.
/// Length-prefixed digest accumulator shared by the persistent tiers so
/// each tier's key digest stays a single field sequence without regrowing
/// duplicate framing bodies.
nonisolated struct ScenePersistentCacheDigest {
    private var data = Data()

    mutating func append(_ value: String) {
        let encoded = Data(value.utf8)
        var length = UInt64(encoded.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(encoded)
    }

    func sha256Hex() -> String? {
        SceneGenericShaderProgramArtifact.sha256(data)
    }
}

nonisolated enum ScenePersistentCacheSupport {

    /// Resolves the tier's versioned cache directory. An environment override
    /// root is scoped by a private versioned subdirectory so one tier's
    /// pruning can never remove a sibling tier's entries; the default root
    /// lives under the app's Caches directory. Read paths never create the
    /// directory.
    static func versionedCacheDirectory(
        environmentKey: String,
        versionedName: String,
        createIfNeeded: Bool
    ) -> URL? {
        if let rawRoot = ProcessInfo.processInfo.environment[environmentKey] {
            guard let root = validatedDirectory(rawRoot) else { return nil }
            let scoped = root.appendingPathComponent(
                versionedName, isDirectory: true
            )
            if createIfNeeded {
                do {
                    try FileManager.default.createDirectory(
                        at: scoped, withIntermediateDirectories: true
                    )
                } catch {
                    return nil
                }
            }
            return validatedDirectory(scoped.path)
        }
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first else { return nil }
        let root = caches
            .appendingPathComponent(
                "com.songziqiang.MyWallpaperX", isDirectory: true
            )
            .appendingPathComponent(versionedName, isDirectory: true)
            .standardizedFileURL
        if createIfNeeded {
            do {
                try FileManager.default.createDirectory(
                    at: root, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                return nil
            }
        }
        return validatedDirectory(root.path)
    }

    static func validatedDirectory(_ rawPath: String) -> URL? {
        guard !rawPath.isEmpty else { return nil }
        let url = URL(
            fileURLWithPath: rawPath, isDirectory: true
        ).standardizedFileURL
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        guard values?.isDirectory == true,
              values?.isSymbolicLink != true else { return nil }
        return url
    }

    static func regularFileData(
        _ url: URL,
        maximumBytes: Int
    ) -> Data? {
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              let size = values?.fileSize,
              (1 ... maximumBytes).contains(size) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func prune(
        _ directory: URL,
        retainedEntryLimit: Int
    ) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        var dated: [(URL, Date)] = []
        for url in entries where url.pathExtension == "json" {
            guard let date = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate else { continue }
            dated.append((url, date))
        }
        guard dated.count > retainedEntryLimit else { return }
        dated.sort { $0.1 < $1.1 }
        for (url, _) in dated.prefix(dated.count - retainedEntryLimit) {
            try? fileManager.removeItem(at: url)
        }
    }
}
