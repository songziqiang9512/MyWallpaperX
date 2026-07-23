import Foundation

struct ScenePkgCacheExtractionResult {
    let outputURL: URL
    let index: ScenePkgIndex
    let extractedPaths: [String]
}

struct ScenePkgCacheExtractor {
    private let fileManager = FileManager.default

    func extract(packageURL: URL, projectRootURL: URL) throws -> ScenePkgCacheExtractionResult {
        let index = try ScenePkgReader().readIndex(packageURL: packageURL)
        let outputURL = cacheDirectoryURL(for: packageURL, projectRootURL: projectRootURL)

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

        var extractedPaths: [String] = []
        for entry in index.entries where shouldExtract(entry.path) {
            guard let relativePath = safeRelativePath(entry.path) else { continue }
            let data = try ScenePkgReader().readEntryData(entry, in: packageURL)
            let destinationURL = outputURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: [.atomic])
            extractedPaths.append(relativePath)
        }

        return ScenePkgCacheExtractionResult(
            outputURL: outputURL,
            index: index,
            extractedPaths: extractedPaths.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        )
    }

    private func cacheDirectoryURL(for packageURL: URL, projectRootURL: URL) -> URL {
        let attributes = try? fileManager.attributesOfItem(atPath: packageURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let keySource = [
            projectRootURL.standardizedFileURL.path,
            packageURL.standardizedFileURL.path,
            String(size),
            String(Int(modifiedAt))
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
}
