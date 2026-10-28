import Foundation

nonisolated enum DownloadTaskAction: CaseIterable, Hashable, Sendable {
    case promote, pause, resume, retry, revealFile, cancel, abandon, removeHistory
}

/// A delivered progress sample, never another progress store. Sequence and
/// verified bytes come from the source so a row can preserve its speed sample.
nonisolated struct DownloadTaskProgress: Sendable {
    let phase: DownloadTaskPhase
    var statusText: String? = nil
    var fraction: Double? = nil
    var verifiedBytes: Int64? = nil
    var totalBytes: Int64? = nil
    var sequence: Int = 0
}

/// Prepared display values. Capabilities and commands still belong to the
/// source; a history record never supplies a playable path or access lease.
nonisolated struct DownloadTaskRow: Identifiable, Sendable {
    let id: DownloadTaskIdentity
    let title: String
    let phase: DownloadTaskPhase
    var statusText: String? = nil
    var recordedAt: Date? = nil
    var progress: DownloadTaskProgress? = nil
    var thumbnailKey: String? = nil
    var actions: Set<DownloadTaskAction> = []
}

nonisolated struct DownloadTaskSnapshot: Sendable {
    var active: [DownloadTaskRow] = []
    var history: [DownloadTaskRow] = []
    var notice: String? = nil

    var count: Int { active.count + history.count }
}

/// A read projection only. The caller supplies native queue order; current
/// facts win over the same attempt's history during a terminal publication.
nonisolated enum DownloadTaskProjection {
    static func snapshot(current: [DownloadTaskRow], history: [DownloadTaskRow]) -> DownloadTaskSnapshot {
        var seen: Set<DownloadTaskIdentity> = []
        let rows = (current + history).filter { seen.insert($0.id).inserted }
        let terminal = rows.enumerated().filter { $0.element.phase.isTerminal }.sorted { lhs, rhs in
            switch (lhs.element.recordedAt, rhs.element.recordedAt) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
        return DownloadTaskSnapshot(active: rows.filter { !$0.phase.isTerminal }, history: terminal)
    }
}
