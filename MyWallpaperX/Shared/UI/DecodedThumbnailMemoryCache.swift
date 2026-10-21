import AppKit

/// The decoded tier of an existing thumbnail owner. A strict byte/count budget
/// and access order keep recent cards useful without retaining an entire library.
/// Kernel memory-pressure events release this tier; there is no polling timer.
nonisolated final class DecodedThumbnailMemoryCache: @unchecked Sendable {
    private final class Entry {
        let key: NSString
        let image: NSImage
        let cost: Int
        weak var previous: Entry?
        var next: Entry?
        init(key: NSString, image: NSImage, cost: Int) {
            self.key = key; self.image = image; self.cost = cost
        }
    }
    private let lock = NSLock()
    private let countLimit: Int
    private let totalCostLimit: Int
    private var entries: [NSString: Entry] = [:]
    private var oldest: Entry?
    private var newest: Entry?
    private var totalCost = 0
    private let pressure: DispatchSourceMemoryPressure

    init(countLimit: Int, totalCostLimit: Int) {
        self.countLimit = max(1, countLimit)
        self.totalCostLimit = max(1, totalCostLimit)
        pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        pressure.setEventHandler { [weak self] in self?.removeAllObjects() }
        pressure.resume()
    }
    deinit { pressure.cancel() }

    func object(forKey key: NSString) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        detach(entry); append(entry)
        return entry.image
    }

    func setObject(_ image: NSImage, forKey key: NSString, cost: Int) {
        lock.lock(); defer { lock.unlock() }
        if let old = entries.removeValue(forKey: key) { detach(old); totalCost -= old.cost }
        let cost = max(1, cost)
        // A single oversized image must not evict the useful working set.
        guard cost <= totalCostLimit else { return }
        let entry = Entry(key: key, image: image, cost: cost)
        entries[key] = entry; append(entry); totalCost += cost
        while entries.count > countLimit || totalCost > totalCostLimit {
            guard let victim = oldest else { break }
            entries.removeValue(forKey: victim.key)
            detach(victim); totalCost -= victim.cost
        }
    }

    func removeObject(forKey key: NSString) {
        lock.lock(); defer { lock.unlock() }
        if let entry = entries.removeValue(forKey: key) { detach(entry); totalCost -= entry.cost }
    }

    func removeAllObjects() {
        lock.lock(); defer { lock.unlock() }
        // Break the chain iteratively, avoiding a recursive release for a large budget.
        while let entry = oldest { detach(entry) }
        entries.removeAll(keepingCapacity: false); totalCost = 0
    }

    private func detach(_ entry: Entry) {
        if let previous = entry.previous { previous.next = entry.next } else { oldest = entry.next }
        if let next = entry.next { next.previous = entry.previous } else { newest = entry.previous }
        entry.previous = nil; entry.next = nil
    }

    private func append(_ entry: Entry) {
        entry.previous = newest
        newest?.next = entry
        newest = entry
        if oldest == nil { oldest = entry }
    }
}
