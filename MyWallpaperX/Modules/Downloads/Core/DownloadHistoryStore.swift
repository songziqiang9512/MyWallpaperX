import Foundation

/// One small, terminal-only ledger. Progress never writes this file. Callers
/// report history failures separately from the source's successful publication.
@MainActor final class DownloadHistoryStore {
    nonisolated private struct Contents: Codable {
        let legacyImported: Bool
        let entries: [DownloadTerminalReceipt]
    }

    private(set) var entries: [DownloadTerminalReceipt]
    let persistenceURL: URL
    private var legacyImported: Bool

    /// Missing history can accept real terminal events before the asynchronous
    /// source scans finish. Import completion belongs to this same file.
    init(persistenceURL: URL? = nil) throws {
        self.persistenceURL = persistenceURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("MyWallpaperX/Downloads/history-v1.json")
        do {
            let data = try Data(contentsOf: self.persistenceURL)
            let contents = data.isEmpty ? Contents(legacyImported: true, entries: [])
                : try JSONDecoder().decode(Contents.self, from: data)
            entries = contents.entries
            legacyImported = contents.legacyImported
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            entries = []
            legacyImported = false
        }
    }

    /// Called after the original non-Steam local scans are ready, without a
    /// network/login prerequisite. Existing real successes win over seed rows.
    func importExistingSuccesses(_ existingSuccesses: () -> [DownloadTerminalReceipt]) throws {
        guard !legacyImported else { return }
        var knownSuccesses = Set(entries.filter {
            $0.outcome == .completed || $0.outcome == .existingLocal
        }.map { $0.id.reference })
        let seeds = existingSuccesses().filter { knownSuccesses.insert($0.id.reference).inserted }
        try commit(Self.sortedUnique(entries + seeds), legacyImported: true)
    }

    /// The original source calls this once it knows the real terminal result.
    /// In particular, cancellation after a commit is still a completed result.
    func record(_ entry: DownloadTerminalReceipt) throws {
        if entries.first(where: { $0.id == entry.id }) == entry { return }
        try commit(Self.sortedUnique([entry] + entries.filter { $0.id != entry.id }), legacyImported: legacyImported)
    }

    func remove(_ id: DownloadTaskIdentity) throws {
        let next = entries.filter { $0.id != id }
        guard next.count != entries.count else { return }
        try commit(next, legacyImported: legacyImported)
    }

    /// Clearing history does not cancel, abandon or delete any source content.
    func clear() throws {
        guard !entries.isEmpty || !legacyImported else { return }
        try commit([], legacyImported: true)
    }

    private func commit(_ next: [DownloadTerminalReceipt], legacyImported: Bool) throws {
        let contents = Contents(legacyImported: legacyImported, entries: next)
        try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(contents).write(to: persistenceURL, options: .atomic)
        self.legacyImported = legacyImported
        entries = next
    }

    private static func sortedUnique(_ values: [DownloadTerminalReceipt]) -> [DownloadTerminalReceipt] {
        var seen: Set<DownloadTaskIdentity> = []
        let unique = values.enumerated().filter { seen.insert($0.element.id).inserted }.sorted { lhs, rhs in
            switch (lhs.element.recordedAt, rhs.element.recordedAt) {
            case let (left?, right?) where left != right: return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }
        return unique.map(\.element)
    }
}
