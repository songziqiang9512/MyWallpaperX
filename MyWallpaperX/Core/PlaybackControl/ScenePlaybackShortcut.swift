import Foundation

/// User-selected native actions are control-plane resources, never authored
/// string values or texture inputs. File URLs without a bookmark cannot execute.
nonisolated struct ScenePlaybackShortcutReference: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case file, webURL }
    let kind: Kind
    let url: URL
    let bookmarkData: Data?

    var isValid: Bool {
        switch kind {
        case .file:
            return url.isFileURL && !url.path.isEmpty && bookmarkData?.isEmpty == false
        case .webURL:
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                && url.host?.isEmpty == false && url.user == nil && url.password == nil
                && bookmarkData == nil
        }
    }

    var displayName: String { kind == .file ? url.lastPathComponent : url.absoluteString }
}

nonisolated struct ScenePlaybackShortcutConfiguration: Codable, Equatable, Sendable {
    let revision: UInt64
    let references: [String: ScenePlaybackShortcutReference]

    static let empty = Self(revision: 0, references: [:])

    var isValid: Bool {
        (references.isEmpty || revision > 0)
            && references.allSatisfy { !$0.key.isEmpty && $0.value.isValid }
    }
}

nonisolated struct ScenePlaybackShortcutUpdate: Equatable, Sendable {
    let configuration: ScenePlaybackShortcutConfiguration
    let recordID: String
}

nonisolated enum ScenePlaybackShortcutUpdateOutcome: Equatable, Sendable {
    case applied
    case failed(String)
    case superseded
    case unavailable
}

/// Created only by the existing AppKit pointer ingress, retained unchanged
/// across surface projections and queued callbacks. A new configuration never
/// inherits an old click's authority.
nonisolated struct ScenePlaybackShortcutGesture: Equatable, Sendable {
    let requestID: UUID
    let configurationRevision: UInt64
    let gestureID: UInt64
}
