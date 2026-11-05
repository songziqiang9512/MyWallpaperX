import Foundation

/// One small, terminal-only ledger. Progress never writes this file. Callers
/// report history failures separately from the source's successful publication.
@MainActor final class DownloadHistoryStore {
    nonisolated private struct Contents: Codable {
        let entries: [DownloadTerminalReceipt]
    }

    private(set) var entries: [DownloadTerminalReceipt]
    let persistenceURL: URL
    init(persistenceURL: URL? = nil) throws {
        self.persistenceURL = persistenceURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("MyWallpaperX/Downloads/history-v1.json")
        do {
            let data = try Data(contentsOf: self.persistenceURL)
            let contents = try JSONDecoder().decode(Contents.self, from: data)
            entries = contents.entries
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            entries = []
        }
    }

    /// The original source calls this once it knows the real terminal result.
    /// In particular, cancellation after a commit is still a completed result.
    func record(_ entry: DownloadTerminalReceipt) throws {
        if entries.first(where: { $0.id == entry.id }) == entry { return }
        try commit(Self.sortedUnique([entry] + entries))
    }

    func remove(_ id: DownloadTaskIdentity) throws {
        let next = entries.filter { $0.id != id }
        guard next.count != entries.count else { return }
        try commit(next)
    }

    /// Clearing history does not cancel, abandon or delete any source content.
    func clear() throws {
        guard !entries.isEmpty else { return }
        try commit([])
    }

    private func commit(_ next: [DownloadTerminalReceipt]) throws {
        let contents = Contents(entries: next)
        try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(contents).write(to: persistenceURL, options: .atomic)
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
