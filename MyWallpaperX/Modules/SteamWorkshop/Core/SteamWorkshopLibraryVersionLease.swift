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
    // Reservation is made on the same actor as playback admission, before any
    // destructive I/O. Successful removals stay retired for this process so a
    // stale card cannot acquire a lease after deletion finishes.
    private var retiringDirectoryNames: Set<String> = []

    func acquire(_ commit: SteamWorkshopLibraryCommit) -> PlaybackResourceLifetime? {
        acquire(directoryNames: [commit.directoryName])
    }

    func acquire(directoryNames: Set<String>) -> PlaybackResourceLifetime? {
        let normalized = Set(directoryNames.compactMap { name -> String? in
            guard name.utf8.count == 36, UUID(uuidString: name) != nil else { return nil }
            return name.lowercased()
        })
        precondition(!normalized.isEmpty, "A Steam library lease must own at least one managed version")
        guard normalized.isDisjoint(with: retiringDirectoryNames) else { return nil }
        let lease = SteamWorkshopLibraryVersionLease(directoryNames: normalized)
        entries[lease.id] = WeakEntry(lease)
        return lease
    }

    func beginReclamation(_ directoryName: String) -> Bool {
        let name = directoryName.lowercased()
        guard !protectedDirectoryNames().contains(name),
              !retiringDirectoryNames.contains(name) else { return false }
        retiringDirectoryNames.insert(name)
        return true
    }

    func reclamationFailed(_ directoryName: String) {
        retiringDirectoryNames.remove(directoryName.lowercased())
    }

    func protectedDirectoryNames() -> Set<String> {
        entries = entries.filter { $0.value.lease != nil }
        return entries.values.reduce(into: Set<String>()) { result, entry in
            result.formUnion(entry.lease?.directoryNames ?? [])
        }
    }
}

private final class SteamWorkshopLibraryVersionLease: PlaybackResourceLifetime {
    let id = UUID()
    let directoryNames: Set<String>

    init(directoryNames: Set<String>) {
        self.directoryNames = directoryNames
    }
}
