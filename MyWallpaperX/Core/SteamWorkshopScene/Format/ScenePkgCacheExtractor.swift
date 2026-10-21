import CryptoKit
import Darwin
import Foundation

struct ScenePkgCacheExtractionResult {
    let outputURL: URL
    let index: ScenePkgIndex
    let extractedPaths: [String]
}

struct ScenePkgCacheExtractor {
    private struct CompletionMarker: Codable {
        struct Entry: Codable, Equatable {
            let relativePath: String
            let size: UInt32
            let contentSHA256: String
        }

        let formatVersion: Int
        let packageSHA256: String
        let entries: [Entry]
    }

    private static let markerName = ".mwx-scene-pkg-cache-v1.json"
    private let fileManager = FileManager.default

    private struct PreparedEntry {
        let marker: CompletionMarker.Entry
        let contents: Data
    }

    func extract(packageURL: URL, projectRootURL: URL) throws -> ScenePkgCacheExtractionResult {
        // The lock precedes the owning snapshot so concurrent preparations of
        // this package do not each retain its full payload. It lives outside
        // the content cache that extraction may remove and rebuild.
        let lock = try acquireExtractionLock(packageURL: packageURL, projectRootURL: projectRootURL)
        defer {
            flock(lock, LOCK_UN)
            close(lock)
        }
        guard let supportsCaseSensitiveNames = try cacheRootURL.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        ).volumeSupportsCaseSensitiveNames else {
            // Unknown volume semantics cannot safely establish destination aliases.
            throw POSIXError(.ENOTSUP)
        }
        let packageData = try Data(contentsOf: packageURL)
        let reader = ScenePkgReader()
        let index = try reader.readIndex(data: packageData)
        let packageSHA256 = Self.sha256(packageData)
        let outputURL = cacheDirectoryURL(
            for: packageURL,
            projectRootURL: projectRootURL,
            packageSHA256: packageSHA256
        )
        let entries = try preparedEntries(from: index, packageData: packageData,
            supportsCaseSensitiveNames: supportsCaseSensitiveNames)
        let expectedEntries = entries.map(\.marker).sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }

        if validCache(
            at: outputURL,
            packageSHA256: packageSHA256,
            entries: entries,
            expectedEntries: expectedEntries
        ) {
            return ScenePkgCacheExtractionResult(
                outputURL: outputURL,
                index: index,
                extractedPaths: expectedEntries.map(\.relativePath)
            )
        }
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

        var extractedPaths: [String] = []
        for entry in entries {
            let relativePath = entry.marker.relativePath
            let destinationURL = outputURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try entry.contents.write(to: destinationURL, options: [.atomic])
            extractedPaths.append(relativePath)
        }

        extractedPaths.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        let marker = CompletionMarker(
            formatVersion: 1,
            packageSHA256: packageSHA256,
            entries: expectedEntries
        )
        let markerData = try JSONEncoder().encode(marker)
        try markerData.write(
            to: outputURL.appendingPathComponent(Self.markerName),
            options: [.atomic]
        )

        return ScenePkgCacheExtractionResult(
            outputURL: outputURL,
            index: index,
            extractedPaths: extractedPaths
        )
    }

    private func validCache(
        at outputURL: URL,
        packageSHA256: String,
        entries: [PreparedEntry],
        expectedEntries: [CompletionMarker.Entry]
    ) -> Bool {
        let markerURL = outputURL.appendingPathComponent(Self.markerName)
        guard cachedFilePaths(at: outputURL) == Set(
                  expectedEntries.map(\.relativePath) + [Self.markerName]
              ),
              let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(CompletionMarker.self, from: data),
              marker.formatVersion == 1,
              marker.packageSHA256 == packageSHA256,
              marker.entries == expectedEntries,
              entries.allSatisfy({ entry in
                  guard let cachedData = try? Data(
                      contentsOf: outputURL.appendingPathComponent(entry.marker.relativePath)
                  ) else {
                      return false
                  }
                  // Equality with the validated source snapshot also rejects
                  // same-size corruption, without hashing the cache a second time.
                  return cachedData == entry.contents
              }) else {
            return false
        }
        return true
    }

    private func preparedEntries(
        from index: ScenePkgIndex,
        packageData: Data,
        supportsCaseSensitiveNames: Bool
    ) throws -> [PreparedEntry] {
        var contentsByIdentity: [String: Data] = [:]
        return try index.entries.compactMap { entry in
            guard shouldExtract(entry.path),
                  let relativePath = safeRelativePath(entry.path) else { return nil }
            // Resource-view lookup folding is not the physical cache identity:
            // case-sensitive volumes must retain both authored destinations.
            let canonicalPath = relativePath.precomposedStringWithCanonicalMapping
            let identity = supportsCaseSensitiveNames ? canonicalPath : canonicalPath.lowercased()
            guard identity != Self.markerName else {
                throw ScenePkgReader.ReadError.ambiguousPath(relativePath)
            }
            let start = index.dataStartOffset + Int(entry.offset)
            let end = start + Int(entry.size)
            // readIndex validated every payload range. A slice borrows the
            // owning package snapshot for hashing, validation and atomic output.
            let contents = packageData[start..<end]
            if let previous = contentsByIdentity[identity] {
                guard previous == contents else {
                    throw ScenePkgReader.ReadError.ambiguousPath(relativePath)
                }
                return nil
            }
            contentsByIdentity[identity] = contents
            return PreparedEntry(
                marker: .init(relativePath: relativePath, size: entry.size,
                    contentSHA256: Self.sha256(contents)),
                contents: contents
            )
        }
    }

    private func cachedFilePaths(at rootURL: URL) -> Set<String>? {
        var rootAttributes = stat()
        guard lstat(rootURL.path, &rootAttributes) == 0,
              rootAttributes.st_mode & S_IFMT == S_IFDIR else { return nil }
        // A mounted-volume enumerator can return /private/var children for a
        // /var home URL. Canonicalize only the already-checked directory root.
        guard let canonicalPath = try? rootURL.resourceValues(
            forKeys: [.canonicalPathKey]
        ).canonicalPath else { return nil }
        let canonicalURL = URL(fileURLWithPath: canonicalPath, isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: canonicalURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ) else {
            return nil
        }
        let prefix = canonicalURL.path + "/"
        var paths = Set<String>()
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]), values.isSymbolicLink != true else {
                return nil
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, url.path.hasPrefix(prefix) else { return nil }
            paths.insert(String(url.path.dropFirst(prefix.count)))
        }
        return paths
    }

    private func cacheDirectoryURL(
        for packageURL: URL,
        projectRootURL: URL,
        packageSHA256: String
    ) -> URL {
        let keySource = [
            projectRootURL.standardizedFileURL.path,
            packageURL.standardizedFileURL.path,
            packageSHA256,
        ].joined(separator: "|")
        let key = Self.fnv1a64(keySource)

        return cacheRootURL.appendingPathComponent(key, isDirectory: true)
    }

    private var cacheRootURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshopScene", isDirectory: true)
    }

    private func acquireExtractionLock(packageURL: URL, projectRootURL: URL) throws -> Int32 {
        try fileManager.createDirectory(at: cacheRootURL, withIntermediateDirectories: true)
        let identity = [projectRootURL.standardizedFileURL.path,
            packageURL.standardizedFileURL.path].joined(separator: "|")
        let lockURL = cacheRootURL.appendingPathComponent(Self.fnv1a64(identity) + ".lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw POSIXError(.EINVAL)
        }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            close(descriptor)
            throw error
        }
        return descriptor
    }

    private func shouldExtract(_ path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let pathComponents = normalized.split(separator: "/")
        let ext = (normalized as NSString).pathExtension.lowercased()
        if pathComponents.count == 1 && ext == "json" {
            return true
        }

        let allowedPrefixes = [
            "materials/",
            "models/",
            "shaders/",
            "effects/",
            "particles/",
            "fonts/",
            "img/",
            "images/",
            "textures/"
        ]
        if allowedPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg"]
        let audioExtensions: Set<String> = ["flac", "mp3", "wav", "ogg"]
        if normalized.hasPrefix("sounds/"), audioExtensions.contains(ext) {
            return true
        }
        return imageExtensions.contains(ext)
    }

    private func safeRelativePath(_ path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard normalized.hasPrefix("/") == false else { return nil }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard components.isEmpty == false else { return nil }
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return normalized
    }

    private static func fnv1a64(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func sha256<DataValue: DataProtocol>(_ data: DataValue) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
