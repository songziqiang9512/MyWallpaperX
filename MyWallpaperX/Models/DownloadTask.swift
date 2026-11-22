import Foundation

/// The source's attempt identity, shared with terminal consumers. It is not
/// a queue, a local-publication receipt or permission to open a file.
nonisolated struct DownloadTaskIdentity: Hashable, Codable, Sendable {
    let reference: WallpaperReference
    let attemptID: String
}

nonisolated enum DownloadTaskPhase: String, Sendable {
    case queued, preparing, transferring, saving, paused
    case completed, failed, cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .queued: return String(localized: "Waiting to Download")
        case .preparing: return String(localized: "Connecting")
        case .transferring: return String(localized: "Downloading")
        case .saving: return String(localized: "Saving")
        case .paused: return String(localized: "Paused")
        case .completed: return String(localized: "Completed")
        case .failed: return String(localized: "Download Failed")
        case .cancelled: return String(localized: "Canceled")
        }
    }
}

nonisolated enum DownloadTerminalOutcome: String, Codable, Equatable, Sendable {
    case completed, failed, cancelled
    /// A real existing publication with no claimed transfer attempt/time.
    case existingLocal

    var phase: DownloadTaskPhase {
        switch self {
        case .completed, .existingLocal: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }
}

/// The source emits a real terminal result. No credentials, CDN URL or local
/// path crosses this boundary; the manifest remains the publication authority.
nonisolated struct DownloadTerminalReceipt: Codable, Equatable, Sendable, Identifiable {
    let id: DownloadTaskIdentity
    let title: String
    let outcome: DownloadTerminalOutcome
    let recordedAt: Date?
    var failureMessage: String? = nil
}
