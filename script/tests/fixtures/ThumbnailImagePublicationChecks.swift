import AppKit

@MainActor enum ThumbnailImagePublicationChecks {
    static func pump(_ seconds: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        return condition()
    }
    static func holdMainUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        return condition()
    }
    static func png(_ image: NSImage) -> Data {
        NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            .representation(using: .png, properties: [:])!
    }
    static func isBlue(_ image: NSImage?) -> Bool {
        guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let color = NSBitmapImageRep(cgImage: cg).colorAt(x: 4, y: 4)?.usingColorSpace(.deviceRGB) else { return false }
        return color.blueComponent > color.redComponent
    }

    static func run() throws -> [String: Bool] {
        let redImage = demandImage(40), blueImage = demandImage(40, color: .systemBlue)
        let red = png(redImage) + Data("raw-source-red".utf8), blue = png(blueImage) + Data("raw-source-blue".utf8)
        var checks: [String: Bool] = [:]

        let tail = DemandBlockingGate(), events = DemandEvents()
        let first = ThumbnailCache(namespace: "early-image-" + UUID().uuidString, writeEncodedData: { data, url in
            try data.write(to: url)
            if data == red { events.record("raw-written") }
            else { events.record("derived-entered"); tail.wait(); events.record("derived-returned") }
        })
        weak var retiredImage: NSImage?
        autoreleasepool {
            var image: NSImage?, calls = 0, raw: Data?
            first.loadImageDataAsync(forKey: "early-still", sourceDataKey: "early-raw", loader: {
                events.record("loader"); return red
            }) { value in
                image = value; calls += 1; events.record("image-callback")
                first.loadRawDataAsync(forKey: "early-raw", loader: { events.record("unexpected-raw-loader"); return nil }) { raw = $0 }
            }
            checks["publication-derived-write-is-held"] = pump { tail.started }
            checks["publication-valid-image-arrives-once-before-derived-write-returns"] = pump(0.3) { calls == 1 && raw == red }
                && !tail.finished && image != nil
            var warm: NSImage?, inCall = true, synchronous = false
            first.loadImageDataAsync(forKey: "early-still", sourceDataKey: "early-raw", loader: {
                events.record("unexpected-warm-loader"); return nil
            }) { warm = $0; synchronous = inCall }
            inCall = false
            checks["publication-memory-warm-is-synchronous-with-no-new-producer"] = synchronous && warm === image
                && events.values.filter { $0 == "loader" }.count == 1 && !events.values.contains("unexpected-warm-loader")
            checks["publication-callback-raw-read-uses-ready-original-bytes"] = raw == red
                && events.values.firstIndex(of: "raw-written").map { $0 < (events.values.firstIndex(of: "image-callback") ?? -1) } == true
                && !events.values.contains("unexpected-raw-loader")
            tail.release()
            checks["publication-tail-drains-without-redelivery"] = pump { tail.finished && ThumbnailEncodingObservation.finished("early-still") > 0 }
                && calls == 1
            retiredImage = image
            first.imageCache.removeAllObjects()
            image = nil; warm = nil
        }
        checks["publication-worker-releases-last-image-after-tail-and-lru-exit"] = pump {
            autoreleasepool {
                retiredImage == nil && !first.hasCachedResult(forKey: "early-still")
                    && first.cachedImage(forKey: "early-still") == nil
            }
        }
        first.clearAll()

        let originalGate = DemandBlockingGate()
        let original = ThumbnailCache(namespace: "original-before-image-" + UUID().uuidString, writeEncodedData: { data, url in
            originalGate.wait(); try data.write(to: url)
        })
        var originalCalls = 0, originalRaw: Data?, originalRawDone = false
        original.loadImageDataAsync(forKey: "original-before-image", loader: { red }) { _ in
            originalCalls += 1
            original.loadRawDataAsync(forKey: "original-before-image", loader: { nil }) { originalRaw = $0; originalRawDone = true }
        }
        checks["publication-original-bytes-stage-remains-before-first-image"] = pump { originalGate.started }
            && originalCalls == 0
        originalGate.release()
        checks["publication-no-source-key-original-bytes-are-readable-inside-callback"] = pump { originalRawDone }
            && originalRaw == red && originalCalls == 1
        original.clearAll()

        for clear in [false, true] {
            let oldTail = DemandBlockingGate(), writes = DemandEvents()
            let store = ThumbnailCache(namespace: "callback-invalidation-" + UUID().uuidString, writeEncodedData: { data, url in
                try data.write(to: url)
                if data != red && data != blue && !isBlueData(data) { writes.record("old-derived"); oldTail.wait() }
                writes.record(data == red ? "raw-red" : data == blue ? "raw-blue" : "derived-written")
            })
            let label = clear ? "publication-callback-clear" : "publication-callback-remove"
            var redCalls = 0, blueCalls = 0, replacement: NSImage?
            store.loadImageDataAsync(forKey: label, sourceDataKey: label + "-raw", loader: { red }) { value in
                if value != nil { redCalls += 1 }
                if clear { store.clearAll() }
                else { store.remove(forKey: label); store.remove(forKey: label + "-raw") }
                store.loadImageDataAsync(forKey: label, sourceDataKey: label + "-raw", loader: {
                    writes.record("blue-loader"); return blue
                }) { replacement = $0; blueCalls += 1 }
            }
            // Keep the main queue still until the real old writer is blocked,
            // so invalidation happens inside the callback with a live tail.
            let blocked = holdMainUntil { oldTail.started }
            checks[label + "-reentrant-new-generation-finishes-before-old-tail"] = blocked
                && pump(0.4) { blueCalls == 1 } && redCalls == 1 && isBlue(replacement) && !oldTail.finished
            oldTail.release()
            checks[label + "-both-generations-deliver-exactly-once"] = pump {
                blueCalls == 1 && oldTail.finished && ThumbnailEncodingObservation.finished(label) >= 2
            } && redCalls == 1 && writes.values.filter { $0 == "blue-loader" }.count == 1
            store.imageCache.removeAllObjects()
            var diskImage: NSImage?, diskCalls = 0, unexpected = false
            store.loadImageDataAsync(forKey: label, sourceDataKey: label + "-raw", loader: {
                writes.record("unexpected-loader"); return nil
            }) { diskImage = $0; diskCalls += 1 }
            checks[label + "-old-tail-cannot-overwrite-new-disk-or-callback"] = pump { diskCalls == 1 }
                && isBlue(diskImage) && redCalls == 1 && blueCalls == 1
            unexpected = writes.values.contains("unexpected-loader")
            checks[label + "-replacement-remains-disk-warm"] = !unexpected
            store.clearAll()
        }

        let evictionTail = DemandBlockingGate(), evictionEvents = DemandEvents()
        let evicted = ThumbnailCache(countLimit: 1, namespace: "published-eviction-" + UUID().uuidString, writeEncodedData: { data, url in
            try data.write(to: url)
            if data != red && data != blue && !isBlueData(data) && !evictionEvents.values.contains("old-tail") {
                evictionEvents.record("old-tail"); evictionTail.wait()
            }
        })
        var firstCalls = 0, secondCalls = 0, firstImage: NSImage?, secondImage: NSImage?, neighbor: NSImage?
        evicted.loadImageDataAsync(forKey: "evicted-published", sourceDataKey: "evicted-raw", loader: {
            evictionEvents.record("original-loader"); return red
        }, decoder: { data in
            evictionEvents.record("original-decoder"); return NSImage(data: data)
        }) { firstImage = $0; firstCalls += 1 }
        checks["publication-eviction-starts-with-delivered-image-and-held-tail"] = pump { evictionTail.started }
            && pump(0.3) { firstCalls == 1 }
        evicted.load(forKey: "neighbor", input: .image(blueImage)) { neighbor = $0 }
        checks["publication-real-lru-evicts-first-image-during-its-tail"] = pump { neighbor != nil }
            && !evicted.imageCache.containsObject(forKey: "evicted-published")
        evicted.imageCache.removeAllObjects()
        let pngBeforeBorrow = ThumbnailEncodingObservation.count("png")
        let warmResult = evicted.hasCachedResult(forKey: "evicted-published")
        let peeked = evicted.cachedImage(forKey: "evicted-published")
        var borrowed: NSImage?, borrowing = true, synchronousBorrow = false, borrowedCalls = 0
        evicted.loadImageDataAsync(forKey: "evicted-published", sourceDataKey: "evicted-raw", loader: {
            evictionEvents.record("unexpected-borrow-loader"); return nil
        }, decoder: { data in
            evictionEvents.record("unexpected-borrow-decoder"); return NSImage(data: data)
        }) { borrowed = $0; synchronousBorrow = borrowing; borrowedCalls += 1 }
        borrowing = false
        checks["publication-memory-only-eviction-borrows-the-same-worker-image-synchronously"] = warmResult
            && firstImage != nil && peeked === firstImage && borrowed === firstImage && synchronousBorrow && borrowedCalls == 1
        checks["publication-worker-borrow-does-not-refill-lru-or-repeat-preparation"] =
            !evicted.imageCache.containsObject(forKey: "evicted-published") && ThumbnailEncodingObservation.count("png") == pngBeforeBorrow
            && evictionEvents.values.filter { $0 == "original-loader" }.count == 1
            && evictionEvents.values.filter { $0 == "original-decoder" }.count == 1
            && !evictionEvents.values.contains("unexpected-borrow-loader") && !evictionEvents.values.contains("unexpected-borrow-decoder")
        evicted.remove(forKey: "evicted-raw")
        evicted.loadImageDataAsync(forKey: "evicted-published", sourceDataKey: "evicted-raw", loader: {
            evictionEvents.record("replacement-loader"); return blue
        }) { secondImage = $0; secondCalls += 1 }
        checks["publication-explicit-invalidation-starts-new-producer-instead-of-borrowing-tail"] = pump(0.4) { secondCalls == 1 }
            && isBlue(secondImage) && evictionEvents.values.contains("replacement-loader") && !evictionTail.finished
        evictionTail.release()
        checks["publication-eviction-generations-remain-once-only"] = pump {
            evictionTail.finished && firstCalls == 1 && secondCalls == 1 && ThumbnailEncodingObservation.finished("evicted-published") >= 2
        } && evicted.cachedImage(forKey: "evicted-published") === secondImage
        var replacementDisk: Data?, replacementDiskDone = false
        evicted.loadRawDataAsync(forKey: "evicted-published", loader: { nil }) { replacementDisk = $0; replacementDiskDone = true }
        checks["publication-explicit-invalidation-old-tail-cannot-cover-blue-disk"] = pump { replacementDiskDone }
            && replacementDisk.map(isBlueData) == true
        evicted.clearAll()

        let rawTail = DemandBlockingGate()
        let rawOnly = ThumbnailCache(namespace: "ready-derived-raw-remove-" + UUID().uuidString, writeEncodedData: { data, url in
            try data.write(to: url); if data != red { rawTail.wait() }
        })
        var ready: NSImage?, afterRawRemove: NSImage?
        rawOnly.loadImageDataAsync(forKey: "ready-derived", sourceDataKey: "remove-raw-only", loader: { red }) { ready = $0 }
        checks["publication-raw-only-starts-with-ready-derived-memory"] = pump { rawTail.started } && pump(0.3) { ready != nil }
        rawOnly.remove(forKey: "remove-raw-only")
        var inside = true, rawWarm = false
        rawOnly.loadImageDataAsync(forKey: "ready-derived", sourceDataKey: "remove-raw-only", loader: { nil }) { afterRawRemove = $0; rawWarm = inside }
        inside = false
        checks["publication-raw-only-remove-does-not-retroactively-clear-ready-derived"] = rawWarm && ready != nil && afterRawRemove === ready
        rawTail.release()
        _ = pump { rawTail.finished && ThumbnailEncodingObservation.finished("ready-derived") > 0 }
        var tailDisk: Data?, tailDiskDone = false
        rawOnly.loadRawDataAsync(forKey: "ready-derived", loader: { nil }) { tailDisk = $0; tailDiskDone = true }
        checks["publication-raw-only-remove-forbids-subsequent-derived-tail-commit"] = pump { tailDiskDone } && tailDisk == nil
        rawOnly.clearAll()

        let pressureTail = DemandBlockingGate(), pressureEvents = DemandEvents()
        let pressure = ThumbnailCache(namespace: "published-generation-budget-" + UUID().uuidString, writeEncodedData: { data, url in
            try data.write(to: url)
            if !pressureEvents.values.contains("tail-held") { pressureEvents.record("tail-held"); pressureTail.wait() }
        })
        var pressureCalls = 0
        for index in 0..<20 {
            pressure.loadImageAsync(forKey: "pressure-\(index)", loader: {
                pressureEvents.record("generator-\(index)"); return .image(redImage)
            }) { _ in pressureCalls += 1 }
        }
        checks["publication-published-image-still-holds-original-generation-slot"] = pump { pressureTail.started }
            && pump(0.3) { pressureCalls == 1 } && pressureEvents.values.filter { $0.hasPrefix("generator-") }.count == 1
        pressureTail.release()
        checks["publication-pressure-drains-through-original-bounded-worker"] = pump { pressureCalls == 20 }
            && pressureEvents.values.filter { $0.hasPrefix("generator-") }.count == 20
        pressure.clearAll()

        let negative = ThumbnailCache(namespace: "publication-negative-" + UUID().uuidString, usesFailureCache: true)
        var nilCalls = 0, failureWasReady = false, reentrantNil = false, recovered: NSImage?
        negative.load(forKey: "publication-nil", input: .sourceData(Data())) { value in
            nilCalls += 1; failureWasReady = value == nil && negative.hasCachedFailure(forKey: "publication-nil")
            negative.load(forKey: "publication-nil", input: .image(blueImage)) { reentrantNil = $0 == nil }
        }
        checks["publication-nil-failure-is-cached-before-callback-and-reentrant-lookup"] = pump { nilCalls == 1 && reentrantNil }
            && failureWasReady
        negative.remove(forKey: "publication-nil")
        negative.load(forKey: "publication-nil", input: .image(blueImage)) { recovered = $0 }
        checks["publication-failed-request-retires-before-recovery-generation"] = pump { recovered != nil }
            && isBlue(recovered) && nilCalls == 1
        negative.clearAll()

        let prepared = ThumbnailCache(namespace: "publication-preparation-" + UUID().uuidString)
        let preparationGate = DemandDataGate(), preparationEvents = DemandEvents()
        var preparedCalls = 0
        let firstStream = prepared.prepare(red, forKey: "prepared", beforePublication: {
            preparationEvents.record("first-hook"); await preparationGate.wait(); return true
        })
        let firstTask = Task { for await image in firstStream { if image != nil { preparedCalls += 1 } } }
        checks["publication-prepare-still-waits-for-source-admission"] = pump { preparationGate.waiting } && preparedCalls == 0
        let secondStream = prepared.prepare(red, forKey: "prepared", beforePublication: {
            preparationEvents.record("late-hook"); return false
        })
        let secondTask = Task { for await image in secondStream { if image != nil { preparedCalls += 1 } } }
        preparationGate.release()
        checks["publication-prepare-joiners-share-one-taken-hook-and-one-result-each"] = pump { preparedCalls == 2 }
            && preparationEvents.values == ["first-hook"]
        let scoped = prepared.prepare(blue, forKey: "prepared", beforePublication: { preparationEvents.record("blue-hook"); return true })
        var scopedBlue = false
        let scopedTask = Task { for await image in scoped { scopedBlue = isBlue(image) } }
        checks["publication-prepare-signature-scope-keeps-new-source-admission"] = pump { scopedBlue }
            && preparationEvents.values == ["first-hook", "blue-hook"]
        firstTask.cancel(); secondTask.cancel(); scopedTask.cancel(); prepared.clearAll()

        let latePreparation = ThumbnailCache(namespace: "publication-late-preparation-" + UUID().uuidString)
        let decodeGate = DemandBlockingGate(), lateEvents = DemandEvents()
        for index in 0..<2 {
            latePreparation.loadImageDataAsync(forKey: "late-preparation-blocker-\(index)", loader: { red }, decoder: { data in
                lateEvents.record("decoder"); decodeGate.wait(); return NSImage(data: data)
            }) { _ in }
        }
        checks["publication-late-hook-holds-real-decode-slots"] = pump { lateEvents.values.count == 2 }
        var lateCalls = 0
        let noHook = latePreparation.prepare(red, forKey: "late-preparation")
        let noHookTask = Task { for await image in noHook { if image != nil { lateCalls += 1 } } }
        let addedHook = latePreparation.prepare(red, forKey: "late-preparation", beforePublication: {
            lateEvents.record("added-hook"); return true
        })
        let addedHookTask = Task { for await image in addedHook { if image != nil { lateCalls += 1 } } }
        decodeGate.release(); decodeGate.release()
        checks["publication-late-hook-upgrades-unpublished-preparation-before-delivery"] = pump { lateCalls == 2 }
            && lateEvents.values.filter { $0 == "added-hook" }.count == 1
        noHookTask.cancel(); addedHookTask.cancel(); latePreparation.clearAll()
        return checks
    }

    nonisolated static func isBlueData(_ data: Data) -> Bool {
        guard let bitmap = NSBitmapImageRep(data: data), let color = bitmap.colorAt(x: 4, y: 4)?.usingColorSpace(.deviceRGB) else { return false }
        return color.blueComponent > color.redComponent
    }
}
