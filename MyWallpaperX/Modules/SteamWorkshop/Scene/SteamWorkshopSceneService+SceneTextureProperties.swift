import Foundation
import Combine

extension SteamWorkshopService {
    private enum SceneTexturePropertyStore {
        static let bookmarkPrefix = "SteamWorkshop.scenePropertyBookmarks."
    }

    struct SceneTexturePropertyPending {
        let recordID: String
        let key: String
        let revision: UInt64
        let completion: @MainActor (Bool) -> Void
    }

    func updateSceneTexturePropertyURL(
        _ url: URL?,
        definition: SceneUserPropertyDefinition,
        record: SteamWorkshopDownloadRecord,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard definition.kind == .sceneTexture else { completion(false); return }
        submitSceneTexturePropertyURL(
            url, key: definition.key,
            defaultValue: definition.defaultValue ?? .string(""),
            record: record, completion: completion
        )
    }

    private func submitSceneTexturePropertyURL(
        _ url: URL?, key: String, defaultValue: SceneUserPropertyValue,
        record: SteamWorkshopDownloadRecord,
        completion: @escaping @MainActor (Bool) -> Void,
        registeredRevision: UInt64? = nil
    ) {
        let token = record.id + "\u{0}" + key
        if registeredRevision == nil { scenePropertyCommandRevision &+= 1 }
        let revision = registeredRevision ?? scenePropertyCommandRevision
        if registeredRevision != nil,
           pendingSceneTextureProperties[token]?.revision != revision { completion(false); return }
        let old = pendingSceneTextureProperties.removeValue(forKey: token)
        pendingSceneTextureProperties[token] = .init(
            recordID: record.id, key: key, revision: revision, completion: completion
        )
        if registeredRevision == nil { old?.completion(false) }
        let usesRuntime = SceneDaemonClient.shared.hasIntent(for: record.id)
        let finish: @MainActor @Sendable (ScenePlaybackTextureReference?) -> Void = { [weak self] reference in
            guard let self, self.pendingSceneTextureProperties[token]?.revision == revision else { return }
            guard url == nil || reference != nil else {
                self.finishSceneTextureProperty(token: token, revision: revision, accepted: false)
                return
            }
            let value = reference.map { SceneUserPropertyValue.string($0.url.path) } ?? defaultValue
            let update = ScenePlaybackTextureUpdate(
                references: reference.map { [key: $0] } ?? [:],
                resetKeys: reference == nil ? [key] : [], values: [key: value],
                revision: revision, recordID: record.id
            )
            let commit: @MainActor (ScenePlaybackTextureUpdateOutcome) -> Void = { [weak self] outcome in
                guard let self, self.pendingSceneTextureProperties[token]?.revision == revision else { return }
                guard outcome == .applied else {
                    self.finishSceneTextureProperty(token: token, revision: revision, accepted: false,
                        reportsFailure: outcome != .superseded)
                    return
                }
                let bookmarkKey = self.sceneTexturePropertyBookmarkKey(forKey: key, record: record)
                if let bookmark = reference?.bookmarkData { self.defaults.set(bookmark, forKey: bookmarkKey) }
                else { self.defaults.removeObject(forKey: bookmarkKey) }
                var overrides = self.scenePropertyOverrides(for: record)
                if value == defaultValue { overrides.removeValue(forKey: key) }
                else { overrides[key] = value }
                self.saveScenePropertyOverrides(overrides, for: record)
                self.objectWillChange.send()
                self.finishSceneTextureProperty(token: token, revision: revision, accepted: true)
            }
            if SceneDaemonClient.shared.hasIntent(for: record.id) {
                let accepted = PlaybackCommandMultiplexer.shared.applyUserTextureUpdate(update) { outcome in
                    if outcome == .unavailable {
                        if !PlaybackCommandMultiplexer.shared.reloadUserTextureUpdate(update, completion: commit) {
                            commit(.failed("Scene runtime cannot accept this texture update"))
                        }
                    } else { commit(outcome) }
                }
                if !accepted { commit(.failed("Scene runtime cannot accept this texture update")) }
            } else if usesRuntime {
                // A switch/stop during selection never revives the old Scene.
                commit(.superseded)
            } else { commit(.applied) }
        }
        guard let url else { finish(nil); return }
        Self.prepareSceneTextureReference(url, validateImage: !usesRuntime, completion: finish)
    }

    private func finishSceneTextureProperty(
        token: String, revision: UInt64, accepted: Bool, reportsFailure: Bool = true
    ) {
        guard pendingSceneTextureProperties[token]?.revision == revision,
              let pending = pendingSceneTextureProperties.removeValue(forKey: token) else { return }
        if !accepted && reportsFailure {
            downloadError = "Scene 纹理无法更新；已保留当前图像。请选择可读取的 PNG 或 JPEG 图像。"
        }
        pending.completion(accepted)
    }

    func resetSceneTextureProperties(
        for record: SteamWorkshopDownloadRecord,
        defaultValues: [String: SceneUserPropertyValue],
        completion: @escaping @MainActor (Set<String>) -> Void
    ) {
        let prefix = SceneTexturePropertyStore.bookmarkPrefix + record.id + "."
        let stored = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
        let keys = Set(stored).union(pendingSceneTextureProperties.values.filter {
            $0.recordID == record.id
        }.map(\.key))
        // Register the entire reset intent now. Its later requests may not
        // supersede a newer picker action while another key is preparing.
        var entries: [(String, UInt64)] = []
        var displaced: [SceneTexturePropertyPending] = []
        for key in keys.sorted() {
            scenePropertyCommandRevision &+= 1
            let revision = scenePropertyCommandRevision
            let token = record.id + "\u{0}" + key
            if let old = pendingSceneTextureProperties.removeValue(forKey: token) { displaced.append(old) }
            pendingSceneTextureProperties[token] = .init(
                recordID: record.id, key: key, revision: revision, completion: { _ in }
            )
            entries.append((key, revision))
        }
        displaced.forEach { $0.completion(false) }
        func submitNext(_ remaining: ArraySlice<(String, UInt64)>) {
            guard let (key, revision) = remaining.first else { completion(keys); return }
            submitSceneTexturePropertyURL(nil, key: key,
                defaultValue: defaultValues[key] ?? .string(""), record: record,
                completion: { _ in submitNext(remaining.dropFirst()) }, registeredRevision: revision)
        }
        submitNext(entries[...])
    }

    private nonisolated static let sceneTextureSelectionQueue = DispatchQueue(
        label: "com.mywallpaperx.scene-texture-selection", qos: .userInitiated
    )

    private nonisolated static func prepareSceneTextureReference(
        _ selectedURL: URL, validateImage: Bool,
        completion: @escaping @MainActor @Sendable (ScenePlaybackTextureReference?) -> Void
    ) {
        sceneTextureSelectionQueue.async {
            let url = selectedURL.resolvingSymlinksInPath().standardizedFileURL
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var reference: ScenePlaybackTextureReference?
            if SceneUserPropertyTextureLoader.supports(url: url),
               (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
               (!validateImage || (try? Data(contentsOf: url, options: .mappedIfSafe))
                    .flatMap { SceneImageTextureUploader.decodeSourceImage($0) } != nil),
               let bookmark = Self.makeSceneTexturePropertyBookmarkData(for: url) {
                reference = .init(url: url, bookmarkData: bookmark)
            }
            let prepared = reference
            Task { @MainActor in completion(prepared) }
        }
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

    func withResolvedSceneTexturePropertyReferences(
        for record: SteamWorkshopDownloadRecord,
        perform: ([String: ScenePlaybackTextureReference]) -> Void
    ) {
        let prefix = SceneTexturePropertyStore.bookmarkPrefix + record.id + "."
        let keys: [String] = defaults.dictionaryRepresentation().keys.compactMap { bookmarkKey in
            guard bookmarkKey.hasPrefix(prefix) else { return nil }
            let propertyKey = String(bookmarkKey.dropFirst(prefix.count))
            return propertyKey.isEmpty ? nil : propertyKey
        }
        var openedScopes: [URL] = []
        let references = keys.reduce(
            into: [String: ScenePlaybackTextureReference]()
        ) { references, key in
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
            references[key] = ScenePlaybackTextureReference(
                url: url,
                bookmarkData: defaults.data(forKey: bookmarkKey)
            )
        }
        defer { openedScopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        perform(references)
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

    private nonisolated static func makeSceneTexturePropertyBookmarkData(for url: URL) -> Data? {
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
            if let refreshedBookmark = Self.makeSceneTexturePropertyBookmarkData(for: url) {
                defaults.set(refreshedBookmark, forKey: key)
            }
        }
        return url
    }
}
