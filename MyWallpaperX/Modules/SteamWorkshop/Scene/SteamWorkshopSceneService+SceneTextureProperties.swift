import Foundation

extension SteamWorkshopService {
    private enum SceneTexturePropertyStore {
        static let bookmarkPrefix = "SteamWorkshop.scenePropertyBookmarks."
    }

    @discardableResult
    func updateSceneTexturePropertyURL(
        _ url: URL?,
        definition: SceneUserPropertyDefinition,
        record: SteamWorkshopDownloadRecord
    ) -> Bool {
        guard definition.kind == .sceneTexture else { return false }
        let bookmarkKey = sceneTexturePropertyBookmarkKey(
            forKey: definition.key,
            record: record
        )
        guard let url else {
            defaults.removeObject(forKey: bookmarkKey)
            updateScenePropertyValue(
                definition.defaultValue ?? .string(""),
                definition: definition,
                record: record
            )
            return true
        }

        let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard SceneUserPropertyTextureLoader.supports(url: normalizedURL),
              FileManager.default.fileExists(atPath: normalizedURL.path),
              let bookmark = makeSceneTexturePropertyBookmarkData(for: normalizedURL) else {
            downloadError = "Scene 纹理仅支持可读取的 PNG 或 JPEG 图像。"
            return false
        }
        defaults.set(bookmark, forKey: bookmarkKey)
        updateScenePropertyValue(
            .string(normalizedURL.path),
            definition: definition,
            record: record
        )
        return true
    }

    func resolvedSceneTexturePropertyURL(
        forKey key: String,
        record: SteamWorkshopDownloadRecord
    ) -> URL? {
        let bookmarkKey = sceneTexturePropertyBookmarkKey(forKey: key, record: record)
        guard let resolvedURL = resolvedSceneTextureBookmarkURL(forBookmarkKey: bookmarkKey) else {
            return nil
        }
        let openedScope = resolvedURL.startAccessingSecurityScopedResource()
        defer { if openedScope { resolvedURL.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            defaults.removeObject(forKey: bookmarkKey)
            return nil
        }
        return resolvedURL
    }

    func withResolvedSceneTexturePropertyURLs(
        for record: SteamWorkshopDownloadRecord,
        perform: ([String: URL]) -> Void
    ) {
        let prefix = SceneTexturePropertyStore.bookmarkPrefix + record.id + "."
        let keys: [String] = defaults.dictionaryRepresentation().keys.compactMap { bookmarkKey in
            guard bookmarkKey.hasPrefix(prefix) else { return nil }
            let propertyKey = String(bookmarkKey.dropFirst(prefix.count))
            return propertyKey.isEmpty ? nil : propertyKey
        }
        var openedScopes: [URL] = []
        let urls = keys.reduce(into: [String: URL]()) { urls, key in
            let bookmarkKey = sceneTexturePropertyBookmarkKey(forKey: key, record: record)
            guard let url = resolvedSceneTextureBookmarkURL(forBookmarkKey: bookmarkKey) else {
                return
            }
            if url.startAccessingSecurityScopedResource() {
                openedScopes.append(url)
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                defaults.removeObject(forKey: bookmarkKey)
                return
            }
            urls[key] = url
        }
        defer { openedScopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        perform(urls)
    }

    @discardableResult
    func clearSceneTexturePropertyBookmarks(for record: SteamWorkshopDownloadRecord) -> Bool {
        let prefix = SceneTexturePropertyStore.bookmarkPrefix + record.id + "."
        var removedBookmark = false
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
            removedBookmark = true
        }
        return removedBookmark
    }

    private func sceneTexturePropertyBookmarkKey(
        forKey key: String,
        record: SteamWorkshopDownloadRecord
    ) -> String {
        SceneTexturePropertyStore.bookmarkPrefix + record.id + "." + key
    }

    private func makeSceneTexturePropertyBookmarkData(for url: URL) -> Data? {
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return bookmark
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolveSceneTexturePropertyBookmarkData(
        _ data: Data,
        bookmarkDataIsStale isStale: inout Bool
    ) -> URL? {
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).resolvingSymlinksInPath().standardizedFileURL {
            return url
        }
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).resolvingSymlinksInPath().standardizedFileURL
    }

    private func resolvedSceneTextureBookmarkURL(forBookmarkKey key: String) -> URL? {
        guard let bookmarkData = defaults.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = resolveSceneTexturePropertyBookmarkData(
            bookmarkData,
            bookmarkDataIsStale: &isStale
        ), SceneUserPropertyTextureLoader.supports(url: url) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        if isStale {
            let openedScope = url.startAccessingSecurityScopedResource()
            defer { if openedScope { url.stopAccessingSecurityScopedResource() } }
            if let refreshedBookmark = makeSceneTexturePropertyBookmarkData(for: url) {
                defaults.set(refreshedBookmark, forKey: key)
            }
        }
        return url
    }
}
