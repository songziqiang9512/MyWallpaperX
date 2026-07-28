import CryptoKit
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

    func extract(packageURL: URL, projectRootURL: URL) throws -> ScenePkgCacheExtractionResult {
        let packageData = try Data(contentsOf: packageURL)
        let reader = ScenePkgReader()
        let index = try reader.readIndex(data: packageData)
        let packageSHA256 = Self.sha256(packageData)
        let outputURL = cacheDirectoryURL(
            for: packageURL,
            projectRootURL: projectRootURL,
            packageSHA256: packageSHA256
        )
        let expectedEntries = markerEntries(from: index, packageData: packageData)

        if validCache(
            at: outputURL,
            packageSHA256: packageSHA256,
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
        for entry in index.entries where shouldExtract(entry.path) {
            guard let relativePath = safeRelativePath(entry.path) else { continue }
            let data = try reader.readEntryData(entry, in: packageData, index: index)
            let destinationURL = outputURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: [.atomic])
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
        expectedEntries: [CompletionMarker.Entry]
    ) -> Bool {
        let markerURL = outputURL.appendingPathComponent(Self.markerName)
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(CompletionMarker.self, from: data),
              marker.formatVersion == 1,
              marker.packageSHA256 == packageSHA256,
              marker.entries == expectedEntries,
              marker.entries.allSatisfy({ entry in
                  guard safeRelativePath(entry.relativePath) != nil,
                        let cachedData = try? Data(
                            contentsOf: outputURL.appendingPathComponent(entry.relativePath)
                        ) else {
                      return false
                  }
                  return cachedData.count == Int(entry.size)
                      && Self.sha256(cachedData) == entry.contentSHA256
              }),
              cachedFilePaths(at: outputURL) == Set(
                  expectedEntries.map(\.relativePath) + [Self.markerName]
              ) else {
            return false
        }
        return true
    }

    private func markerEntries(
        from index: ScenePkgIndex,
        packageData: Data
    ) -> [CompletionMarker.Entry] {
        index.entries.compactMap { entry in
            guard shouldExtract(entry.path),
                  let relativePath = safeRelativePath(entry.path) else { return nil }
            let start = index.dataStartOffset + Int(entry.offset)
            let end = start + Int(entry.size)
            return CompletionMarker.Entry(
                relativePath: relativePath,
                size: entry.size,
                contentSHA256: Self.sha256(packageData[start..<end])
            )
        }.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    private func cachedFilePaths(at rootURL: URL) -> Set<String>? {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ) else {
            return nil
        }
        let prefix = rootURL.path + "/"
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

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("SteamWorkshopScene", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
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
