import Foundation
import Combine

extension SteamWorkshopService {
    struct SceneShortcutPropertyPending {
        let configuration: ScenePlaybackShortcutConfiguration
        let encodedConfiguration: Data
        let completion: @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void
    }

    private func sceneShortcutStoreKey(_ record: SteamWorkshopDownloadRecord) -> String {
        "SteamWorkshop.sceneUserShortcuts." + record.id
    }

    /// Display the accepted local choice even if its bookmark no longer resolves.
    /// It is deliberately separate from the executable reference projection.
    func storedSceneShortcutConfiguration(
        for record: SteamWorkshopDownloadRecord
    ) -> ScenePlaybackShortcutConfiguration {
        guard let data = defaults.data(forKey: sceneShortcutStoreKey(record)),
              let value = try? JSONDecoder().decode(ScenePlaybackShortcutConfiguration.self, from: data)
        else { return .empty }
        return value
    }

    func sceneShortcutReference(
        forKey key: String, record: SteamWorkshopDownloadRecord
    ) -> ScenePlaybackShortcutReference? {
        storedSceneShortcutConfiguration(for: record).references[key]
    }

    func sceneShortcutConfiguration(
        for record: SteamWorkshopDownloadRecord
    ) -> ScenePlaybackShortcutConfiguration {
        resolvedSceneShortcutConfiguration(storedSceneShortcutConfiguration(for: record))
    }

    private func resolvedSceneShortcutConfiguration(
        _ stored: ScenePlaybackShortcutConfiguration
    ) -> ScenePlaybackShortcutConfiguration {
        .init(revision: stored.revision, references: stored.references.compactMapValues {
            guard $0.isValid else { return nil }
            if $0.kind == .webURL { return $0 }
            guard let bookmark = $0.bookmarkData else { return nil }
            var stale = false
            let resolved = (try? URL(resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                bookmarkDataIsStale: &stale))
                ?? (try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI],
                    relativeTo: nil, bookmarkDataIsStale: &stale))
            guard let url = resolved, url.isFileURL else { return nil }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
            let data = stale ? Self.sceneShortcutBookmark(for: url) : bookmark
            guard let data else { return nil }
            return ScenePlaybackShortcutReference(kind: .file, url: url, bookmarkData: data)
        })
    }

    private nonisolated static func sceneShortcutBookmark(for url: URL) -> Data? {
        (try? url.bookmarkData(options: [.withSecurityScope],
            includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    func updateSceneShortcutPropertyURL(
        _ url: URL?, definition: SceneUserPropertyDefinition,
        record: SteamWorkshopDownloadRecord,
        completion: @escaping @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void
    ) {
        guard definition.kind == .userShortcut, !definition.key.isEmpty else {
            completion(.failed("此属性不能配置快捷方式")); return
        }
        let reference: ScenePlaybackShortcutReference?
        if let url {
            if url.isFileURL {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard FileManager.default.isReadableFile(atPath: url.path),
                      let bookmark = Self.sceneShortcutBookmark(for: url) else {
                    completion(.failed("无法读取所选文件或目录，请重新选择")); return
                }
                reference = .init(kind: .file, url: url, bookmarkData: bookmark)
            } else { reference = .init(kind: .webURL, url: url, bookmarkData: nil) }
            guard reference?.isValid == true else {
                completion(.failed("仅支持本机文件、目录或不含账户信息的 HTTP(S) 网址")); return
            }
        } else { reference = nil }
        var references = pendingSceneShortcutProperties[record.id]?.configuration.references
            ?? storedSceneShortcutConfiguration(for: record).references
        references[definition.key] = reference
        submitSceneShortcutReferences(references, record: record, completion: completion)
    }

    func resetSceneShortcutProperties(
        for record: SteamWorkshopDownloadRecord,
        completion: @escaping @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void
    ) {
        submitSceneShortcutReferences([:], record: record, completion: completion)
    }

    private func submitSceneShortcutReferences(
        _ references: [String: ScenePlaybackShortcutReference],
        record: SteamWorkshopDownloadRecord,
        completion: @escaping @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void
    ) {
        let previous = pendingSceneShortcutProperties[record.id]
        let stored = storedSceneShortcutConfiguration(for: record)
        let revision = max(scenePropertyCommandRevision, stored.revision,
            previous?.configuration.revision ?? 0).addingReportingOverflow(1)
        guard !revision.overflow else { completion(.failed("快捷方式配置版本已耗尽")); return }
        scenePropertyCommandRevision = revision.partialValue
        let configuration = ScenePlaybackShortcutConfiguration(
            revision: revision.partialValue, references: references)
        guard let encoded = try? JSONEncoder().encode(configuration) else {
            completion(.failed("无法保存快捷方式配置")); return
        }
        pendingSceneShortcutProperties[record.id] = .init(configuration: configuration,
            encodedConfiguration: encoded, completion: completion)
        previous?.completion(.superseded)
        // A completion may submit another key/reset synchronously. Never send
        // the displaced configuration after that newer intent.
        guard pendingSceneShortcutProperties[record.id]?.configuration.revision == configuration.revision else { return }
        let finish: @MainActor (ScenePlaybackShortcutUpdateOutcome) -> Void = { [weak self] outcome in
            guard let self, let pending = self.pendingSceneShortcutProperties[record.id],
                  pending.configuration.revision == configuration.revision else { return }
            self.pendingSceneShortcutProperties.removeValue(forKey: record.id)
            if outcome == .applied {
                self.defaults.set(pending.encodedConfiguration, forKey: self.sceneShortcutStoreKey(record))
                self.objectWillChange.send()
            }
            pending.completion(outcome)
        }
        guard SceneDaemonClient.shared.hasIntent(for: record.id) else { finish(.applied); return }
        let update = ScenePlaybackShortcutUpdate(
            configuration: resolvedSceneShortcutConfiguration(configuration), recordID: record.id)
        if !PlaybackCommandMultiplexer.shared.applyUserShortcutUpdate(update, completion: finish) {
            finish(.unavailable)
        }
    }
}
