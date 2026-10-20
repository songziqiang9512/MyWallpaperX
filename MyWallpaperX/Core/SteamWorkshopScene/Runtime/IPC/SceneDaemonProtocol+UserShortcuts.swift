import Foundation

extension SceneDaemonProtocol {
    nonisolated static func shortcutConfiguration(_ raw: Any?) -> ScenePlaybackShortcutConfiguration? {
        guard let raw else { return .empty }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let configuration = try? JSONDecoder().decode(
                ScenePlaybackShortcutConfiguration.self, from: data),
              configuration.isValid else { return nil }
        return configuration
    }

    nonisolated static func shortcutObject(_ configuration: ScenePlaybackShortcutConfiguration) -> [String: Any] {
        let references = configuration.references.mapValues { reference in
            var value = ["kind": reference.kind.rawValue, "url": reference.url.absoluteString]
            if let bookmark = reference.bookmarkData { value["bookmarkData"] = bookmark.base64EncodedString() }
            return value
        }
        return ["revision": configuration.revision, "references": references]
    }
}
