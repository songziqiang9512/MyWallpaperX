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
    private var retiringStorageIdentities: Set<String> = []

    func acquire(_ commit: SteamWorkshopLibraryCommit) -> PlaybackResourceLifetime? {
        guard let identity = SteamWorkshopLibraryTransaction.storageIdentity(for: commit) else { return nil }
        return acquire(storageIdentities: [identity])
    }

    func acquire(storageIdentities: Set<String>) -> PlaybackResourceLifetime? {
        let normalized = Set(storageIdentities.compactMap { identity -> String? in
            guard SteamWorkshopLibraryTransaction.isValidStorageIdentity(identity) else { return nil }
            return identity.lowercased()
        })
        precondition(!normalized.isEmpty, "A Steam library lease must own at least one managed version")
        guard normalized.isDisjoint(with: retiringStorageIdentities) else { return nil }
        let lease = SteamWorkshopLibraryVersionLease(storageIdentities: normalized)
        entries[lease.id] = WeakEntry(lease)
        return lease
    }

    func beginReclamation(_ storageIdentity: String) -> Bool {
        let identity = storageIdentity.lowercased()
        guard SteamWorkshopLibraryTransaction.isValidStorageIdentity(identity),
              !protectedStorageIdentities().contains(identity),
              !retiringStorageIdentities.contains(identity) else { return false }
        retiringStorageIdentities.insert(identity)
        return true
    }

    func reclamationFailed(_ storageIdentity: String) {
        retiringStorageIdentities.remove(storageIdentity.lowercased())
    }

    func protectedStorageIdentities() -> Set<String> {
        entries = entries.filter { $0.value.lease != nil }
        return entries.values.reduce(into: Set<String>()) { result, entry in
            result.formUnion(entry.lease?.storageIdentities ?? [])
        }
    }
}

private final class SteamWorkshopLibraryVersionLease: PlaybackResourceLifetime {
    let id = UUID()
    let storageIdentities: Set<String>

    init(storageIdentities: Set<String>) {
        self.storageIdentities = storageIdentities
    }
}
