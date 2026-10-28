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
        case .queued: return "等待下载"
        case .preparing: return "正在连接"
        case .transferring: return "正在下载"
        case .saving: return "正在保存"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "下载失败"
        case .cancelled: return "已取消"
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
