import Foundation

/// Main-process lease owner for immutable Steam library versions. Entries are
/// weak so the actual playback/import consumer remains the lifetime authority.
@MainActor
final class SteamWorkshopLibraryVersionLeaseRegistry {
    private final class WeakEntry {
        weak var lease: SteamWorkshopLibraryVersionLease?

        init(_ lease: SteamWorkshopLibraryVersionLease) {
            self.lease = lease
        }
    }

    private var entries: [UUID: WeakEntry] = [:]

    func acquire(_ commit: SteamWorkshopLibraryCommit) -> PlaybackResourceLifetime {
        let lease = SteamWorkshopLibraryVersionLease(directoryName: commit.directoryName)
        entries[lease.id] = WeakEntry(lease)
        return lease
    }

    func protectedDirectoryNames() -> Set<String> {
        entries = entries.filter { $0.value.lease != nil }
        return Set(entries.values.compactMap { $0.lease?.directoryName })
    }
}

private final class SteamWorkshopLibraryVersionLease: PlaybackResourceLifetime {
    let id = UUID()
    let directoryName: String

    init(directoryName: String) {
        self.directoryName = directoryName
    }
}
