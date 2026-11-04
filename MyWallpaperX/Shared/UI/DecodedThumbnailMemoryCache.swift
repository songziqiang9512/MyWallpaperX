import AppKit

/// All compositions share one access-order chain and one decoded-byte budget.
nonisolated final class DecodedThumbnailMemoryCache: @unchecked Sendable {
    private final class Entry {
        let key: NSString
        let image: NSImage
        let cost: Int
        let pixels: CGSize
        let nativeSize: CGSize?
        let crop: ThumbnailRequest?
        let signature: Data?
        weak var previous: Entry?
        var next: Entry?
        init(key: NSString, image: NSImage, cost: Int, pixels: CGSize, nativeSize: CGSize?, crop: ThumbnailRequest?, signature: Data?) {
            self.key = key; self.image = image; self.cost = cost
            self.pixels = pixels; self.nativeSize = nativeSize; self.crop = crop; self.signature = signature
        }
        func covers(_ request: ThumbnailRequest?) -> Bool {
            guard let request else { return crop == nil }
            if let crop {
                guard request.mode == .fill, crop.hasSameAspect(as: request) else { return false }
                return request.isCovered(by: pixels, nativeSize: nativeSize.map { crop.cropSize(in: $0) })
            }
            return request.isCovered(by: pixels, nativeSize: nativeSize)
        }
        func dominates(_ other: Entry) -> Bool {
            guard pixels.width >= other.pixels.width, pixels.height >= other.pixels.height else { return false }
            if nativeSize == nil, other.nativeSize != nil { return false }
            if let crop { return other.crop.map { crop.hasSameAspect(as: $0) } == true }
            return true
        }
    }
    private let lock = NSLock()
    private let countLimit: Int
    private let totalCostLimit: Int
    private var entries: [NSString: [Entry]] = [:]
    private var entryCount = 0
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

    func object(forKey key: NSString, request: ThumbnailRequest? = nil, signature: Data? = nil) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = matchingEntry(forKey: key, request: request, signature: signature) else { return nil }
        detach(entry); append(entry)
        return entry.image
    }

    func containsObject(forKey key: NSString, request: ThumbnailRequest? = nil, signature: Data? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return matchingEntry(forKey: key, request: request, signature: signature) != nil
    }

    private func matchingEntry(forKey key: NSString, request: ThumbnailRequest?, signature: Data?) -> Entry? {
        var selected: Entry?
        for entry in entries[key] ?? [] {
            guard signature.map({ entry.signature == $0 }) ?? true, entry.covers(request) else { continue }
            if let current = selected, current.cost <= entry.cost { continue }
            selected = entry
        }
        return selected
    }

    /// Explicit new data replaces atomically; same-source work may preserve adequate results.
    func setObject(_ image: NSImage, forKey key: NSString, cost: Int, pixels: CGSize? = nil,
                   nativeSize: CGSize? = nil, crop: ThumbnailRequest? = nil, signature: Data? = nil,
                   preservingCompatibleResults: Bool = false) {
        let cost = max(1, cost)
        guard cost <= totalCostLimit else { return }
        let pixels = pixels ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            .map { CGSize(width: $0.width, height: $0.height) } ?? image.size
        let entry = Entry(key: key, image: image, cost: cost, pixels: pixels, nativeSize: nativeSize, crop: crop, signature: signature)
        lock.lock(); defer { lock.unlock() }
        let previous = entries[key] ?? []
        if preservingCompatibleResults {
            guard !previous.contains(where: { $0.signature == signature && $0.dominates(entry) }) else { return }
            for old in previous where old.signature != signature || entry.dominates(old) { remove(old) }
        } else {
            for old in previous { remove(old) }
        }
        entries[key, default: []].append(entry); append(entry)
        entryCount += 1; totalCost += cost
        while entryCount > countLimit || totalCost > totalCostLimit {
            guard let victim = oldest else { break }
            remove(victim)
        }
    }

    func removeObject(forKey key: NSString) {
        lock.lock(); defer { lock.unlock() }
        for entry in entries[key] ?? [] { remove(entry) }
    }

    func removeObjects(withKeyPrefix prefix: String) {
        lock.lock(); defer { lock.unlock() }
        for key in entries.keys.filter({ ($0 as String).hasPrefix(prefix) }) {
            for entry in entries[key] ?? [] { remove(entry) }
        }
    }

    func removeAllObjects() {
        lock.lock(); defer { lock.unlock() }
        // Detaching each node also avoids a recursive release of a long chain.
        while let entry = oldest { remove(entry) }
        entries.removeAll(keepingCapacity: false)
    }

    private func remove(_ entry: Entry) {
        entries[entry.key]?.removeAll { $0 === entry }
        if entries[entry.key]?.isEmpty == true { entries.removeValue(forKey: entry.key) }
        detach(entry); entryCount -= 1; totalCost -= entry.cost
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
