import Foundation

/// A source importer reports its real per-file outcome. App organization never
/// infers success from a changed count, a path match in another source or a timer.
nonisolated struct WallpaperSourceImportResult: Sendable {
    enum Disposition: Sendable { case added, existing, failed }
    struct Item: Sendable {
        let sourceURL: URL
        let disposition: Disposition
        let organizationItem: WallpaperOrganizationItem?
        let failureMessage: String?
    }
    let items: [Item]

    var organizationItems: [WallpaperOrganizationItem] {
        var seen = Set<WallpaperReference>()
        return items.compactMap(\.organizationItem).filter {
            $0.isPublishedLocally && $0.isAvailable && seen.insert($0.reference).inserted
        }
    }
    var addedCount: Int { items.filter { $0.disposition == .added }.count }
    var existingCount: Int { items.filter { $0.disposition == .existing }.count }
    var failures: [Item] { items.filter { $0.disposition == .failed || $0.organizationItem?.isAvailable == false } }
}

/// Physical deletion is separate from relationship SQL. A failed durability
/// acknowledgement may follow an actual unlink and must not claim rollback.
nonisolated struct WallpaperSourceDeletionResult: Sendable {
    struct Item: Sendable {
        let reference: WallpaperReference
        let sourceURL: URL
        let succeeded: Bool
        let sourceFileDeleted: Bool
        let failureMessage: String?
    }
    let items: [Item]
}
