import Foundation

/// Completed, reconstructible values only. The original cache owner supplies
/// synchronization, typed cost, in-flight work and the retained-value policy.
nonisolated struct SceneShaderCompletedCacheStorage<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let cost: Int
        var lastAccess: UInt64
    }

    let maximumBytes: Int
    let maximumEntries: Int
    private var entries: [Key: Entry] = [:]
    private var access: UInt64 = 0
    private(set) var retainedBytes = 0
    var count: Int { entries.count }

    init(maximumBytes: Int, maximumEntries: Int) {
        self.maximumBytes = max(0, maximumBytes)
        self.maximumEntries = max(0, maximumEntries)
    }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        access &+= 1
        entry.lastAccess = access
        entries[key] = entry
        return entry.value
    }

    /// Admission failure never rejects the caller's newly completed result.
    /// Oversized values also do not evict unrelated useful completed entries.
    @discardableResult
    mutating func insert(_ value: Value, for key: Key, cost: Int) -> Bool {
        if let previous = entries.removeValue(forKey: key) {
            retainedBytes -= previous.cost
        }
        guard maximumEntries > 0, cost >= 0, cost <= maximumBytes else { return false }
        if entries.count >= maximumEntries || cost > maximumBytes - retainedBytes {
            let oldest = entries.sorted {
                $0.value.lastAccess < $1.value.lastAccess
            }.map(\.key)
            for victim in oldest {
                guard entries.count >= maximumEntries || cost > maximumBytes - retainedBytes else { break }
                if let removed = entries.removeValue(forKey: victim) {
                    retainedBytes -= removed.cost
                }
            }
        }
        access &+= 1
        entries[key] = .init(value: value, cost: cost, lastAccess: access)
        retainedBytes += cost
        return true
    }
}

/// Protected by the original owner's NSCondition. Waiters retain this one
/// operation's result even if completed-cache admission fails or is evicted.
nonisolated final class SceneShaderCacheFlight<Value> {
    var result: Value?
    var waiters = 0
}

/// Explicit payload accounting with conservative per-field/container margins.
/// This weights cache ownership, including COW values shared with consumers;
/// it is not a heap/RSS measurement. Call only at completed publication.
nonisolated struct SceneShaderCacheCost {
    private(set) var bytes = 256 // cache entry, key/value boxes and LRU metadata

    mutating func add(_ amount: Int) {
        let (next, overflow) = bytes.addingReportingOverflow(amount)
        bytes = overflow || amount < 0 ? Int.max : next
    }

    mutating func string(_ value: String?) {
        guard let value else { return }
        add(64)
        add(value.utf8.count)
    }

    mutating func strings(_ values: some Sequence<String>) {
        add(64)
        for value in values { string(value) }
    }

    mutating func slots(_ count: Int) {
        let (payload, overflow) = count.multipliedReportingOverflow(by: 16)
        add(64)
        add(overflow ? Int.max : payload)
    }
}

nonisolated struct SceneShaderCompletedCacheSnapshot {
    let completedEntries: Int
    let retainedBytes: Int
    let inFlightOperations: Int
    let waitingCallers: Int
}
