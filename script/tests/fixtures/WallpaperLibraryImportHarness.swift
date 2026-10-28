import AppKit
import Combine
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// PRODUCTION_IMAGE_MODEL
// PRODUCTION_IMPORT_VALUES

nonisolated enum WallpaperPlaybackSequence { struct Pending: Equatable, Sendable {} }
nonisolated final class ImageWorkProbe: @unchecked Sendable {
    static let shared = ImageWorkProbe()
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var created: [(id: String, path: String, addedAt: Date, width: Int?, height: Int?)] = []
    func record(_ key: String) { lock.lock(); counts[key, default: 0] += 1; lock.unlock() }
    func reset() { lock.lock(); counts.removeAll(); created.removeAll(); lock.unlock() }
    var completed: Bool { lock.lock(); defer { lock.unlock() }; return counts["finished"] == 1 }
    var finishedCount: Int { lock.lock(); defer { lock.unlock() }; return counts["finished"] ?? 0 }
    func model(id: String, path: String, addedAt: Date, width: Int?, height: Int?) {
        lock.lock(); created.append((id, path, addedAt, width, height)); lock.unlock()
    }
    var createdModels: [(id: String, path: String, addedAt: Date, width: Int?, height: Int?)] {
        lock.lock(); defer { lock.unlock() }; return created
    }
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        record("metadataStatReads")
        return try FileManager.default.attributesOfItem(atPath: path)
    }
    func imageSource(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? {
        record("metadataHeaderReads")
        return CGImageSourceCreateWithURL(url, options)
    }
    func snapshot() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: ["epochReads", "summaryBuilds", "publications", "metadataInitializations", "persistEntries", "syncEntries", "metadataStatReads", "metadataHeaderReads"].map { ($0, counts[$0] ?? 0) })
    }
}
nonisolated final class ImportRequestWorkProbe: @unchecked Sendable {
    static let shared = ImportRequestWorkProbe()
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func record(_ name: String) { lock.lock(); values[name, default: 0] += 1; lock.unlock() }
    func reset() { lock.lock(); values.removeAll(); lock.unlock() }
    func snapshot() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: ["normalize", "key", "thumbnailOutput", "staticFrameOutput", "exists"].map { ($0, values[$0] ?? 0) })
    }
}

extension WallpaperLibraryImportHarness {
    @MainActor static func imageWork(_ root: URL) async throws {
        let files = root.appendingPathComponent("image-files", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let a = files.appendingPathComponent("renamed-A.png"), b = files.appendingPathComponent("renamed-B.png")
        let missing = files.appendingPathComponent("missing.png"), alias = files.appendingPathComponent("A-alias.png")
        try png(a); try png(b)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
        var functional: [String: Any] = [:], work: [String: Any] = [:]
        let phases = ["newReceipt", "duplicatesOnly", "missingOnly", "noReceiptDuplicate", "noReceiptNew",
            "ackFailure", "syncUncertain", "workerReset", "publicationEpoch", "summaryReset", "membershipChanged"]
        for phase in phases {
            let started = Date(), directory = root.appendingPathComponent(phase, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let service = SILService(directory.appendingPathComponent("images.json"))
            let seedsExisting = ["duplicatesOnly", "noReceiptDuplicate", "ackFailure", "syncUncertain", "membershipChanged"].contains(phase)
            let original = seedsExisting ? SILWallpaper(path: a.path) : nil
            service.wallpapers = original.map { [$0] } ?? []
            service.save()
            var didRevokePublication = false
            let subscription = service.$wallpapers.dropFirst().sink { [weak service] _ in
                ImageWorkProbe.shared.record("publications")
                if phase == "publicationEpoch", !didRevokePublication {
                    didRevokePublication = true
                    service?.invalidatePendingMetadataLoad()
                }
            }
            let duplicate = phase == "duplicatesOnly" || phase == "noReceiptDuplicate"
            let inputs = duplicate ? [a, alias, a] : [phase == "missingOnly" ? missing : phase == "syncUncertain" ? b : a]
            let needsReceipt = phase != "noReceiptDuplicate" && phase != "noReceiptNew"
            let presentsSummary = phase == "summaryReset"
            presentedImportAlerts = []
            if presentsSummary { presentedImportAlertAction = { service.resetForAudit() } }
            defer { presentedImportAlertAction = nil }
            if phase == "ackFailure" { ImageImportProbe.shared.failNextWrite() }
            if phase == "syncUncertain" { ImageImportProbe.shared.failNextSynchronization() }
            let held = phase == "workerReset" ? ImageImportProbe.shared.holdNext()
                : phase == "membershipChanged" ? ImageImportProbe.shared.holdCommit() : nil
            var callbacks = 0, receipt: WallpaperSourceImportResult?
            let completion: ((WallpaperSourceImportResult) -> Void)? = needsReceipt ? { callbacks += 1; receipt = $0 } : nil
            ImageWorkProbe.shared.reset()
            service.importImages(from: inputs, presentsSummary: presentsSummary, completion: completion)
            if let held {
                precondition(held.0.wait(timeout: .now() + 5) == .success)
                if phase == "workerReset" { service.resetForAudit() }
                else { service.wallpapers = []; service.save() }
                held.1.signal()
            }
            try await wait { ImageWorkProbe.shared.completed }
            let measured = ImageWorkProbe.shared.snapshot(), finished = Date()
            let rows = service.wallpapers
            let persisted = try JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: service.persistenceURL))
            let revoked = ["workerReset", "publicationEpoch", "summaryReset"].contains(phase)
            let failed = phase == "ackFailure" || phase == "syncUncertain" || phase == "missingOnly"
            let expectedPaths = phase == "workerReset" || phase == "summaryReset" || phase == "missingOnly" ? []
                : phase == "syncUncertain" ? [a.path, b.path] : [a.path]
            let items = receipt?.items ?? []
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            var checks = [
                "mainThread": Thread.isMainThread,
                "currentMembershipAndPersistence": rows.map(\.path) == expectedPaths && rows == persisted,
                "callbackRevocation": callbacks == (needsReceipt && !revoked ? 1 : 0),
                "realUUIDAndMetadata": rows.allSatisfy { UUID(uuidString: $0.id) != nil && $0.fileSize != nil
                    && $0.pixelWidth == 1 && $0.pixelHeight == 1 && $0.addedAt >= started && $0.addedAt <= finished }
                    && Set(rows.map(\.id)).count == rows.count,
                "perInputReceiptOrder": items.map(\.sourceURL) == (needsReceipt && !revoked ? inputs : []),
                "summaryOnlyWhenRequested": presentedImportAlerts.count == (presentsSummary ? 1 : 0),
                "publishedBoundaryRevokesReceipt": phase != "publicationEpoch" || didRevokePublication,
                "sourceFilesUnchanged": FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path),
                "receiptReferencesActualRows": items.allSatisfy { item in
                    guard let value = item.organizationItem else { return item.disposition == .failed }
                    return byID[value.reference.sourceID]?.path == value.locator.path
                        && value.reference.provider == .staticImageLibrary && value.isPublishedLocally && value.isAvailable
                },
            ]
            if let original {
                checks["existingIdentityOrNewAfterRemoval"] = phase == "membershipChanged"
                    ? rows.first?.id != original.id : rows.first?.id == original.id
            }
            if failed {
                checks["failedInputsNeverGrantOrganization"] = items.count == inputs.count
                    && items.allSatisfy { $0.disposition == .failed && $0.organizationItem == nil && $0.failureMessage != nil }
            } else if !revoked && needsReceipt {
                checks["acceptedDisposition"] = items.map { String(describing: $0.disposition) }
                    == (duplicate ? ["existing", "existing", "existing"] : ["added"])
            }
            func object<Value: Encodable>(_ value: Value) throws -> Any {
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
            }
            func projected(_ records: [SILWallpaper]) throws -> [[String: Any]] {
                try records.map { row in
                    var value = try object(row) as! [String: Any]
                    value["id"] = "row:" + row.path; value["addedAt"] = "created-in-case"
                    return value
                }
            }
            let receipts = try items.map { item -> [String: Any] in
                var organization: Any = NSNull()
                if let value = item.organizationItem {
                    organization = ["sourceID": "row:" + (byID[value.reference.sourceID]?.path ?? "unmatched"),
                        "provider": value.reference.provider.rawValue, "locator": try object(value.locator),
                        "isPublishedLocally": value.isPublishedLocally, "isAvailable": value.isAvailable]
                }
                return ["sourceURL": item.sourceURL.absoluteString, "disposition": String(describing: item.disposition),
                    "organization": organization, "failureMessage": item.failureMessage as Any? ?? NSNull()]
            }
            functional[phase] = ["rows": try projected(rows), "persistedRows": try projected(persisted), "receipts": receipts,
                "checks": checks, "events": ["callbacks": callbacks, "alerts": presentedImportAlerts.map { [$0.0, $0.1] }]]
            work[phase] = measured
            withExtendedLifetime(subscription) {}
        }
        print(String(data: try JSONSerialization.data(withJSONObject: ["functional": functional, "work": work], options: [.sortedKeys]), encoding: .utf8)!)
    }

    @MainActor static func imageMetadata(_ root: URL) async throws {
        var functional: [String: Any] = [:], work: [String: Any] = [:]
        for phase in ["repeatOverlap", "availabilityChanges", "aliasAndNextRequest"] {
            let started = Date(), directory = root.appendingPathComponent("metadata-" + phase, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let parent = directory.appendingPathComponent("parent", isDirectory: true)
            let child = parent.appendingPathComponent("child", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            let a = parent.appendingPathComponent("A.png"), b = child.appendingPathComponent("B.png")
            let alias = directory.appendingPathComponent("first-alias.png")
            let other = directory.appendingPathComponent("second-alias.png")
            try png(a); try pngSized(b, width: 2, height: 3)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
            try FileManager.default.createSymbolicLink(at: other, withDestinationURL: a)
            let service = SILService(directory.appendingPathComponent("images.json"))
            service.save()
            let fresh = SILService(directory.appendingPathComponent("fresh-images.json"))
            fresh.save()
            let subscription = service.$wallpapers.dropFirst().sink { _ in ImageWorkProbe.shared.record("publications") }
            let freshSubscription = fresh.$wallpapers.dropFirst().sink { _ in ImageWorkProbe.shared.record("publications") }
            var snapshots: [[String: Any]] = [], allRequestsValid = true
            var checks: [String: Bool] = [:]
            func object<Value: Encodable>(_ value: Value) throws -> Any {
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
            }
            @MainActor func perform(_ owner: SILService, _ inputs: [URL]) async throws -> WallpaperSourceImportResult {
                var receipt: WallpaperSourceImportResult?, callbacks = 0
                let count = ImageWorkProbe.shared.finishedCount
                owner.importImages(from: inputs, presentsSummary: false) { receipt = $0; callbacks += 1 }
                try await wait { receipt != nil && ImageWorkProbe.shared.finishedCount == count + 1 }
                let value = receipt!, rows = owner.wallpapers
                let saved = try JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: owner.persistenceURL))
                let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
                allRequestsValid = allRequestsValid && callbacks == 1 && rows == saved && value.items.allSatisfy { item in
                    guard let organization = item.organizationItem else { return item.disposition == .failed }
                    return byID[organization.reference.sourceID]?.path == organization.locator.path
                        && organization.reference.provider == .staticImageLibrary && organization.isPublishedLocally
                }
                func projected(_ records: [SILWallpaper]) throws -> [[String: Any]] {
                    try records.map { row in
                        var result = try object(row) as! [String: Any]
                        result["id"] = "row:" + row.path; result["addedAt"] = "created-in-case"
                        return result
                    }
                }
                let receipts = try value.items.map { item -> [String: Any] in
                    var organization: Any = NSNull()
                    if let info = item.organizationItem {
                        organization = ["sourceID": "row:" + (byID[info.reference.sourceID]?.path ?? "unmatched"),
                            "provider": info.reference.provider.rawValue, "locator": try object(info.locator),
                            "isPublishedLocally": info.isPublishedLocally, "isAvailable": info.isAvailable]
                    }
                    return ["sourceURL": item.sourceURL.absoluteString, "disposition": String(describing: item.disposition),
                        "organization": organization, "failureMessage": item.failureMessage as Any? ?? NSNull()]
                }
                snapshots.append(["inputs": inputs.map(\.absoluteString), "rows": try projected(rows),
                    "persistedRows": try projected(saved), "receipts": receipts, "callbacks": callbacks])
                return value
            }
            ImageWorkProbe.shared.reset()
            defer { ImageImportProbe.shared.setCandidateAction(nil) }
            if phase == "repeatOverlap" {
                try FileManager.default.removeItem(at: alias)
                try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: b)
                let value = try await perform(service, [parent, child, b, b, alias])
                let sources = value.items.map { $0.sourceURL.path }
                checks["recursiveMultiplicityAndOrder"] = sources.count == 6
                    && Set(sources.prefix(2)) == Set([a.path, b.path])
                    && Array(sources.dropFirst(2)) == [b.path, b.path, b.path, alias.path]
                checks["firstWinsWithoutLosingAliasReceipt"] = service.wallpapers.count == 2
                    && value.items.filter { $0.disposition == .added }.count == 2
                    && value.items.filter { $0.disposition == .existing }.count == 4
                    && Set(value.items.filter { $0.sourceURL.path == b.path || $0.sourceURL == alias }
                        .compactMap { $0.organizationItem?.reference }).count == 1
            } else if phase == "availabilityChanges" {
                ImageImportProbe.shared.setCandidateAction { url, index in
                    if index == 1 { try! FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path) }
                    if index == 2 { try! FileManager.default.removeItem(at: url) }
                }
                let value = try await perform(service, [a, a, a])
                checks["everyOccurrenceStillChecksAvailability"] = value.items.map(\.disposition) == [.added, .existing, .failed]
                    && value.items[0].organizationItem?.isAvailable == true
                    && value.items[1].organizationItem?.isAvailable == false
                    && value.items[1].failureMessage != nil && value.items[2].failureMessage == "文件不存在"
                    && value.organizationItems.count == 1
                checks["firstMetadataAndPathRemainSourceFact"] = service.wallpapers.count == 1
                    && service.wallpapers[0].path == a.path && service.wallpapers[0].pixelWidth == 1
                    && !FileManager.default.fileExists(atPath: a.path)
            } else {
                ImageImportProbe.shared.setCandidateAction { _, index in
                    if index == 1 {
                        try! FileManager.default.removeItem(at: other)
                        try! FileManager.default.createSymbolicLink(at: other, withDestinationURL: b)
                    }
                }
                _ = try await perform(service, [alias, other])
                ImageImportProbe.shared.setCandidateAction(nil)
                let original = service.wallpapers
                checks["distinctAliasesReadTheirCurrentTargets"] = original.map(\.path) == [alias.path, other.path]
                    && original.map(\.pixelWidth) == [1, 2] && original.map(\.pixelHeight) == [1, 3]
                    && original[0].id != original[1].id
                    && original.map(\.title) == ["first-alias", "second-alias"]
                try pngSized(b, width: 3, height: 2)
                _ = try await perform(service, [other])
                checks["existingRowRemainsOriginalFirstWins"] = service.wallpapers == original
                _ = try await perform(fresh, [other])
                checks["nextRequestReadsReplacementWithoutBorrowingIdentity"] = fresh.wallpapers.count == 1
                    && fresh.wallpapers[0].pixelWidth == 3 && fresh.wallpapers[0].pixelHeight == 2
                    && fresh.wallpapers[0].path == other.path && fresh.wallpapers[0].id != original[1].id
                let models = ImageWorkProbe.shared.createdModels
                checks["eachRequestPreparedCurrentHeader"] = models.map(\.width) == [1, 2, 3, 3]
                    && models.map(\.height) == [1, 3, 2, 2]
            }
            let measured = ImageWorkProbe.shared.snapshot(), models = ImageWorkProbe.shared.createdModels, finished = Date()
            checks["actualWorkerJSONAndReceiptsRemainValid"] = allRequestsValid && Thread.isMainThread
            checks["everyCandidateHasFreshIdentityAndTime"] = models.count == (phase == "repeatOverlap" ? 6 : phase == "availabilityChanges" ? 2 : 4)
                && Set(models.map(\.id)).count == models.count
                && models.allSatisfy { UUID(uuidString: $0.id) != nil && $0.addedAt >= started && $0.addedAt <= finished }
            functional[phase] = ["requests": snapshots, "checks": checks]
            work[phase] = measured
            withExtendedLifetime((subscription, freshSubscription)) {}
        }
        print(String(data: try JSONSerialization.data(withJSONObject: ["functional": functional, "work": work], options: [.sortedKeys]), encoding: .utf8)!)
    }

    @MainActor static func drain(_ manager: WallpaperManager) async {
        await withCheckedContinuation { continuation in
            manager.importPreparationQueue.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @MainActor static func requestWork(_ root: URL) async throws {
        let sourceRoot = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let a = sourceRoot.appendingPathComponent("renamed-A.mp4"), b = sourceRoot.appendingPathComponent("renamed-B.mov")
        let missing = sourceRoot.appendingPathComponent("missing.mp4")
        try Data("owned readable A".utf8).write(to: a); try Data("owned readable B".utf8).write(to: b)
        var functional: [String: Any] = [:], work: [String: Any] = [:]
        let phases = ["nilMiss", "receiptMixed", "bothHits", "thumbnailOnly", "staticOnly",
                      "queuedAliasRetarget", "reset", "summaryEpochReentry", "summaryAliasRetarget"]
        for phase in phases {
            let caseRoot = root.appendingPathComponent(phase, isDirectory: true)
            try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: true)
            let manager = WallpaperManager(cacheRoot: caseRoot)
            try FileManager.default.createDirectory(at: manager.thumbnailCacheDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: manager.staticFrameCacheDirectory, withIntermediateDirectories: true)
            let alias = caseRoot.appendingPathComponent("source-alias.mp4")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
            let target = phase == "queuedAliasRetarget" ? b : a
            let canonical = target.resolvingSymlinksInPath().standardizedFileURL.path
            let key = manager.cacheKey(forNormalizedPath: canonical)
            let thumbnail = manager.thumbnailOutputURL(forKey: key), frame = manager.staticFrameOutputURL(forKey: key)
            let hasThumbnail = phase == "bothHits" || phase == "thumbnailOnly"
            let hasFrame = phase == "bothHits" || phase == "staticOnly"
            if hasThumbnail { try Data("owned thumbnail locator".utf8).write(to: thumbnail) }
            if hasFrame { try Data("owned frame locator".utf8).write(to: frame) }
            let inputs = phase == "receiptMixed" ? [alias, a, missing] : [alias]
            var callbacks = 0, receipt: WallpaperSourceImportResult?
            let needsReceipt = phase != "nilMiss"
            let summary = phase == "summaryEpochReentry" || phase == "summaryAliasRetarget"
            if phase == "summaryEpochReentry" { manager.summaryAction = { manager.resetForAudit() } }
            if phase == "summaryAliasRetarget" {
                manager.summaryAction = {
                    try! FileManager.default.removeItem(at: alias)
                    try! FileManager.default.createSymbolicLink(at: alias, withDestinationURL: b)
                }
            }
            let held = phase == "queuedAliasRetarget" || phase == "reset" ? manager.holdQueue() : nil
            if let held { precondition(held.0.wait(timeout: .now() + 5) == .success) }
            let started = Date()
            ImportRequestWorkProbe.shared.reset()
            let completion: ((WallpaperSourceImportResult) -> Void)? = needsReceipt ? { callbacks += 1; receipt = $0 } : nil
            manager.processImportedVideos(from: inputs, presentingIn: nil, context: needsReceipt ? .library : .pixabayPlayback,
                presentsSummary: summary, completion: completion)
            if phase == "queuedAliasRetarget" {
                try FileManager.default.removeItem(at: alias)
                try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: b)
            }
            if phase == "reset" { manager.resetForAudit() }
            held?.1.signal()
            await drain(manager)
            let finished = Date(), measured = ImportRequestWorkProbe.shared.snapshot()
            let revoked = phase == "reset" || phase == "summaryEpochReentry"
            let rows = manager.wallpapers
            var checks: [String: Bool] = [
                "mainThread": Thread.isMainThread,
                "rowCountAndCurrentSource": revoked ? rows.isEmpty : rows.count == 1 && rows[0].path == canonical,
                "callbackOwnership": callbacks == (needsReceipt && !revoked ? 1 : 0),
                "noAutoplayFromReceipt": manager.automaticPlays == 0,
                "generatedIdentityIsRealAndUnique": rows.allSatisfy { UUID(uuidString: $0.id) != nil }
                    && Set(rows.map(\.id)).count == rows.count,
                "generatedClocksAreReal": rows.allSatisfy { row in
                    row.lastUsed >= started && row.lastUsed <= finished
                        && row.firstIndexedAt.map { $0 >= started && $0 <= finished } == true
                },
                "selectedCacheNamespaces": revoked || rows.allSatisfy {
                    $0.thumbnailPath == (hasThumbnail ? thumbnail.path : nil)
                        && $0.staticFramePath == (hasFrame ? frame.path : nil)
                },
                "sourceFilesRemain": FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path),
                "derivedWorkUsesCapturedSource": manager.assetJobs.flatMap { $0 }.map(\.path) == (revoked ? [] : [canonical]),
                "summaryBoundary": manager.summaries.count == (summary ? 1 : 0),
            ]
            let rowByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            let items = receipt?.items ?? []
            checks["receiptReferencesCurrentRealRows"] = items.allSatisfy { item in
                guard let organization = item.organizationItem else { return item.disposition == .failed }
                return organization.reference.provider == .videoLibrary
                    && rowByID[organization.reference.sourceID]?.path == organization.locator.path
                    && organization.isPublishedLocally && organization.isAvailable
            }
            let expectedReceiptPaths = needsReceipt && !revoked
                ? (phase == "receiptMixed" ? [canonical, canonical, missing.path] : [canonical]) : []
            checks["orderedAllInputReceiptPaths"] = items.map(\.sourceURL.path) == expectedReceiptPaths
            checks["receiptOutcomesAndFailure"] = phase != "receiptMixed"
                || items.map { String(describing: $0.disposition) } == ["added", "existing", "failed"]
                    && items.last?.failureMessage == "文件不存在"
            func object<Value: Encodable>(_ value: Value) throws -> Any {
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
            }
            let normalizedRows = try rows.map { row -> [String: Any] in
                var value = try object(row) as! [String: Any]
                value["id"] = "row:" + row.path
                value["lastUsed"] = "generated-in-request"
                value["firstIndexedAt"] = "generated-in-request"
                return value
            }
            let normalizedItems = try items.map { item -> [String: Any] in
                var organization: Any = NSNull()
                if let value = item.organizationItem {
                    organization = ["provider": value.reference.provider.rawValue,
                        "sourceID": "row:" + (rowByID[value.reference.sourceID]?.path ?? "unmatched"),
                        "locator": try object(value.locator), "isPublishedLocally": value.isPublishedLocally,
                        "isAvailable": value.isAvailable]
                }
                return ["sourceURL": item.sourceURL.absoluteString, "disposition": String(describing: item.disposition),
                    "organization": organization, "failureMessage": item.failureMessage as Any? ?? NSNull()]
            }
            let summaries = manager.summaries.map { ["requestedCount": $0.requestedCount, "importedCount": $0.importedCount,
                "linkedCount": $0.linkedCount, "skippedCount": $0.skippedCount, "thumbnailFailureCount": $0.thumbnailFailureCount] }
            functional[phase] = ["rows": normalizedRows, "receipts": normalizedItems, "checks": checks,
                "events": ["callbacks": callbacks, "assetJobs": manager.assetJobs.map { $0.map(\.path) },
                    "summaries": summaries, "summaryFailures": manager.summaries.map(\.failureBreakdown),
                    "indexEpoch": manager.wallpaperIndexSaveEpoch]]
            work[phase] = measured
            manager.summaryAction = nil
        }
        print(String(data: try JSONSerialization.data(withJSONObject: ["functional": functional, "work": work], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
nonisolated final class ImageImportProbe: @unchecked Sendable {
    static let shared = ImageImportProbe()
    private let lock = NSLock()
    private var hold: (DispatchSemaphore, DispatchSemaphore)?
    private var commitHold: (DispatchSemaphore, DispatchSemaphore)?
    private var failSynchronization = false
    private var failWrite = false
    private var candidateAction: (@Sendable (URL, Int) -> Void)?
    private var candidateIndex = 0
    func setCandidateAction(_ action: (@Sendable (URL, Int) -> Void)?) {
        lock.lock(); candidateAction = action; candidateIndex = 0; lock.unlock()
    }
    func beforeCandidate(_ url: URL) {
        lock.lock(); let action = candidateAction, index = candidateIndex; candidateIndex += 1; lock.unlock()
        action?(url, index)
    }
    func failNextWrite() { lock.lock(); failWrite = true; lock.unlock() }
    func consumeWriteFailure() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let value = failWrite; failWrite = false; return value
    }
    func failNextSynchronization() { lock.lock(); failSynchronization = true; lock.unlock() }
    func consumeSynchronizationFailure() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let value = failSynchronization; failSynchronization = false; return value
    }
    func holdNext() -> (DispatchSemaphore, DispatchSemaphore) {
        let pair = (DispatchSemaphore(value: 0), DispatchSemaphore(value: 0))
        lock.lock(); hold = pair; lock.unlock()
        return pair
    }
    func waitIfHeld() {
        lock.lock(); let pair = hold; hold = nil; lock.unlock()
        guard let pair else { return }
        pair.0.signal(); precondition(pair.1.wait(timeout: .now() + 5) == .success)
    }
    func holdCommit() -> (DispatchSemaphore, DispatchSemaphore) {
        let pair = (DispatchSemaphore(value: 0), DispatchSemaphore(value: 0))
        lock.lock(); commitHold = pair; lock.unlock()
        return pair
    }
    func waitBeforeCommit() {
        lock.lock(); let pair = commitHold; commitHold = nil; lock.unlock()
        guard let pair else { return }
        pair.0.signal(); precondition(pair.1.wait(timeout: .now() + 5) == .success)
    }
}
@MainActor final class SILService {
    var allowsLibraryMutation = true
    var migrationRecoveryMessage: String?
    var metadataLoadGeneration: UInt64 = 0
    var currentContextTag: String?
    var wallpapers: [SILWallpaper] = []
    var selectedID: String?
    var selectedIDs = Set<String>()
    var isMultiSelectMode = false
    var sortedWallpapers: [SILWallpaper] { wallpapers }
    let persistenceURL: URL
    init(_ url: URL) { persistenceURL = url }
    func admitLibraryMutation(in window: NSWindow? = nil) -> Bool { allowsLibraryMutation }
    func syncSelectedWallpaperInspectorIfNeeded() {}
    func save() { try! persistWallpaperMetadata(wallpapers) }
    func resetForAudit() { metadataLoadGeneration &+= 1; wallpapers = []; save() }
    // PRODUCTION_IMAGE_METHODS
}
@MainActor final class WallpaperManager {
    var allowsLibraryMutation = true
    var migrationRecoveryMessage: String?
    var wallpaperIndexSaveEpoch: UInt64 = 0
    var wallpapers: [VideoWallpaper] = []
    let importPreparationQueue = DispatchQueue(label: "mwx.test.actual-import")
    let importPreparationStateLock = NSLock()
    var importPreparationGeneration: UInt64 = 0
    var importPreparationWorkItem: DispatchWorkItem?
    var libraryBackingPublished: ((WallpaperContentBackingPublication) -> Void)?
    var summaries: [ImportSummary] = []
    var assetJobs: [[URL]] = []
    var automaticPlays = 0
    var indexAcknowledgements = 0
    var indexAcknowledgementFails = false
    let thumbnailCacheDirectory: URL
    let staticFrameCacheDirectory: URL
    var summaryAction: (() -> Void)?
    init(cacheRoot: URL? = nil) {
        let root = cacheRoot ?? URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("video-cache")
        thumbnailCacheDirectory = root.appendingPathComponent("thumbnails")
        staticFrameCacheDirectory = root.appendingPathComponent("frames")
    }
    func persistWallpaperIndexNow(_ values: [VideoWallpaper]) throws {
        indexAcknowledgements += 1
        if indexAcknowledgementFails { throw CocoaError(.fileWriteNoPermission) }
    }
    // ACTUAL_VIDEO_CACHE_LEAVES
    func recordInitialIndexImportContext(_ context: ImportContext, wallpaper: VideoWallpaper) {}
    func scheduleImportedAssetsProcessing(_ urls: [URL]) { assetJobs.append(urls) }
    func acceptsImportedVideoPlayback(_ admission: ImportedVideoPlaybackAdmission) -> Bool { false }
    func setAsWallpaper(_ value: VideoWallpaper, admission: ImportedVideoPlaybackAdmission) { automaticPlays += 1 }
    func failImportedVideoPlayback(_ admission: ImportedVideoPlaybackAdmission, reason: String) {}
    func reportMigrationReadOnly(in window: NSWindow?) {}
    func presentImportSummary(_ value: ImportSummary, in window: NSWindow?) { summaries.append(value); summaryAction?() }
    func holdQueue() -> (DispatchSemaphore, DispatchSemaphore) {
        let pair = (DispatchSemaphore(value: 0), DispatchSemaphore(value: 0))
        importPreparationQueue.async { pair.0.signal(); precondition(pair.1.wait(timeout: .now() + 5) == .success) }
        return pair
    }
    func resetForAudit() { wallpaperIndexSaveEpoch &+= 1; wallpapers = [] }
    // PRODUCTION_FAILURE_SUMMARY
    // PRODUCTION_VIDEO_METHODS
}
@MainActor final class WallpaperLibraryWorkspace {
    let collections: UserCollectionsController?
    let presentation = ImportPresentation()
    var relationships: UserCollectionsSnapshot { collections!.snapshot }
    var edited: [WallpaperLibraryPage] = []
    var contentValues: [WallpaperReference: WallpaperContentItem] = [:]
    let catalog = ImportCatalog()
    init(_ collections: UserCollectionsController) { self.collections = collections }
    func didEditMembers(of page: WallpaperLibraryPage) { edited.append(page) }
    func content(for reference: WallpaperReference) throws -> WallpaperContentItem {
        guard let value = contentValues[reference] else { throw CocoaError(.fileNoSuchFile) }
        return value
    }
}
@MainActor final class ImportCatalog { var refreshes = 0; func refreshAvailability() { refreshes += 1 } }
@MainActor final class ImportPresentation { var canEditCollections = true; var page: WallpaperLibraryPage = .videos }
@MainActor var presentedImportAlerts: [(String, String)] = []
@MainActor var presentedImportAlertAction: (() -> Void)?
struct ImportAlert { let title: String; let message: String }
@MainActor func makeAppAlert(title: String, message: String) -> ImportAlert {
    ImportAlert(title: title, message: message)
}
@MainActor func presentAppAlert(_ value: ImportAlert, in window: NSWindow?) {
    presentedImportAlerts.append((value.title, value.message))
    presentedImportAlertAction?()
}
@MainActor func appModalHostWindow() -> NSWindow? { nil }

@main struct WallpaperLibraryImportHarness {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let until = Date().addingTimeInterval(5)
        while !condition(), Date() < until { try await Task.sleep(nanoseconds: 5_000_000) }
        precondition(condition(), "Actual import did not finish")
    }
    static func png(_ url: URL) throws {
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jh3sAAAAASUVORK5CYII=")!
        try bytes.write(to: url)
    }
    static func pngSized(_ url: URL, width: Int, height: Int) throws {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "request-work" {
            try await requestWork(root)
            return
        }
        if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "image-work" {
            try await imageWork(root)
            return
        }
        if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "image-metadata" {
            try await imageMetadata(root)
            return
        }
        var checks: [String: Bool] = [:]
        let files = root.appendingPathComponent("files"); try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let imageA = files.appendingPathComponent("A.png"), imageB = files.appendingPathComponent("B.png")
        let unreadableImage = files.appendingPathComponent("unreadable.png")
        let missingImage = files.appendingPathComponent("missing.png")
        try png(imageA); try png(imageB); try png(unreadableImage)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableImage.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadableImage.path) }
        let directory = files.appendingPathComponent("Directory"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let nestedA = directory.appendingPathComponent("nested-A.png"), nestedB = directory.appendingPathComponent("nested-B.png")
        try png(nestedA); try png(nestedB)
        let misleading = directory.appendingPathComponent("looks-like-image.png")
        try FileManager.default.createDirectory(at: misleading, withIntermediateDirectories: true)
        let nestedVideo = directory.appendingPathComponent("not-recursively-imported.mp4")
        try Data("source video admission fixture".utf8).write(to: nestedVideo)
        let images = SILService(root.appendingPathComponent("images.json"))
        var receipt: WallpaperSourceImportResult?
        images.importImages(from: [imageA, imageA, missingImage, unreadableImage, directory], presentsSummary: false) { receipt = $0 }
        try await wait { receipt != nil }
        let sourceResult = receipt!
        checks["ActualImageWorkerReportsPerInputAddedExistingAndMissing"] = sourceResult.items.filter { $0.sourceURL == imageA }.map(\.disposition) == [.added, .existing]
            && sourceResult.items.contains { $0.sourceURL == missingImage && $0.disposition == .failed && $0.failureMessage == "文件不存在" }
        checks["ActualImageWorkerKeepsUnreadableSourceButExcludesOrganization"] = !FileManager.default.isReadableFile(atPath: unreadableImage.path)
            && sourceResult.items.contains { $0.sourceURL == unreadableImage && $0.organizationItem?.isAvailable == false }
            && !sourceResult.organizationItems.contains { $0.locator.path == unreadableImage.path }
        checks["ImageMetadataUsesOriginalWorkerAndJSONOwner"] = images.wallpapers.first { $0.path == imageA.path }?.pixelWidth == 1
            && (try? JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: images.persistenceURL)))?.count == images.wallpapers.count
        checks["ImageNamedDirectoryNeverBecomesAvailableSource"] = sourceResult.items.contains { $0.sourceURL.standardizedFileURL.path == misleading.standardizedFileURL.path && $0.disposition == .failed }
            && !images.wallpapers.contains { $0.path == misleading.path }
        do {
            let protected = root.appendingPathComponent("write-failure", isDirectory: true)
            try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
            let saved = protected.appendingPathComponent("images.json")
            let failingImages = SILService(saved)
            failingImages.wallpapers = [SILWallpaper(path: imageA.path)]
            failingImages.save()
            let original = try Data(contentsOf: saved), originalIDs = failingImages.wallpapers.map(\.id)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: protected.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protected.path) }
            var failure: WallpaperSourceImportResult?
            failingImages.importImages(from: [imageB], presentsSummary: false) { failure = $0 }
            try await wait { failure != nil }
            let afterFailure = try Data(contentsOf: saved)
            checks["ExplicitImageReceiptRequiresActualJSONPersistenceBeforeSourcePublication"] = failure?.organizationItems.isEmpty == true
                && failure?.items.count == 1 && failure?.items.first?.disposition == .failed
                && failure?.items.first?.failureMessage?.contains("未获保存确认") == true
                && failingImages.wallpapers.map(\.id) == originalIDs && afterFailure == original
        }
        do {
            let saved = root.appendingPathComponent("sync-ack-failure.json")
            let uncertain = SILService(saved)
            ImageImportProbe.shared.failNextSynchronization()
            var failure: WallpaperSourceImportResult?
            uncertain.importImages(from: [imageB], presentsSummary: false) { failure = $0 }
            try await wait { failure != nil }
            let actual = try JSONDecoder().decode([SILWallpaper].self, from: Data(contentsOf: saved))
            checks["WriteAfterAcknowledgementFailurePublishesDiskFactButNeverSuccessfulReceipt"] = actual.count == 1
                && uncertain.wallpapers == actual && failure?.items.first?.disposition == .failed
                && failure?.organizationItems.isEmpty == true
                && failure?.items.first?.failureMessage?.contains("未获保存确认") == true
        }
        checks["DirectoryImportRemainsImagesOnlyAndPreservesNestedReceiptOrder"] = sourceResult.organizationItems.contains { $0.locator.path == nestedA.path }
            && sourceResult.organizationItems.contains { $0.locator.path == nestedB.path }
            && !images.wallpapers.contains { $0.path == nestedVideo.path }
            && sourceResult.organizationItems.compactMap { $0.locator.path }.filter { $0.hasPrefix(directory.path + "/") }
                == images.wallpapers.map(\.path).filter { $0.hasPrefix(directory.path + "/") }
        let imageHold = ImageImportProbe.shared.holdNext()
        var lateImageCallback = false
        images.importImages(from: [imageB], presentsSummary: false) { _ in lateImageCallback = true }
        precondition(imageHold.0.wait(timeout: .now() + 3) == .success)
        images.resetForAudit(); imageHold.1.signal()
        try await Task.sleep(nanoseconds: 120_000_000)
        checks["ResetRevokesActualImageWorkerBeforeCommitAndCallback"] = images.wallpapers.isEmpty && !lateImageCallback

        let videoA = files.appendingPathComponent("A.mp4"), videoB = files.appendingPathComponent("B.mp4")
        let unreadableVideo = files.appendingPathComponent("unreadable.mp4"), missingVideo = files.appendingPathComponent("missing.mp4")
        try Data("video admission A".utf8).write(to: videoA); try Data("video admission B".utf8).write(to: videoB)
        try Data("unreadable admission".utf8).write(to: unreadableVideo)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableVideo.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadableVideo.path) }
        let manager = WallpaperManager()
        var firstVideo: WallpaperSourceImportResult?, secondVideo: WallpaperSourceImportResult?, samePathVideo: WallpaperSourceImportResult?
        let videoHold = manager.holdQueue(); precondition(videoHold.0.wait(timeout: .now() + 3) == .success)
        manager.processImportedVideos(from: [videoA, videoA, missingVideo, unreadableVideo], presentingIn: nil, context: .library,
            presentsSummary: false) { firstVideo = $0 }
        manager.processImportedVideos(from: [videoB], presentingIn: nil, context: .library, presentsSummary: false) { secondVideo = $0 }
        manager.processImportedVideos(from: [videoA], presentingIn: nil, context: .library, presentsSummary: false) { samePathVideo = $0 }
        videoHold.1.signal()
        try await wait { firstVideo != nil && secondVideo != nil && samePathVideo != nil }
        checks["TwoIndependentVideoCommandsBothCompleteWithoutSuperseding"] = firstVideo?.addedCount == 1 && secondVideo?.addedCount == 1
            && manager.wallpapers.map(\.path) == [manager.normalizedPath(videoA.path), manager.normalizedPath(videoB.path)]
        checks["ConcurrentSamePathVideoCommandReusesCommittedSourceID"] = samePathVideo?.existingCount == 1
            && samePathVideo?.organizationItems.first?.reference == firstVideo?.organizationItems.first?.reference
            && manager.wallpapers.count == 2
        checks["ActualVideoWorkerPreservesPerInputOrderAndFailureReasons"] = firstVideo?.items.map(\.sourceURL.path)
                == [videoA, videoA, missingVideo, unreadableVideo].map { manager.normalizedPath($0.path) }
            && firstVideo?.items.map(\.disposition) == [.added, .existing, .failed, .failed]
            && firstVideo?.items[2].failureMessage == "文件不存在" && firstVideo?.items[3].failureMessage == "文件无法读取"
        checks["VideoReceiptUsesStableSourceIDAndNoOrganizationAutoplay"] = firstVideo?.organizationItems.first?.reference.sourceID == manager.wallpapers[0].id
            && manager.automaticPlays == 0 && manager.summaries.isEmpty
        let resetHold = manager.holdQueue(); precondition(resetHold.0.wait(timeout: .now() + 3) == .success)
        var lateVideoCallback = false
        manager.processImportedVideos(from: [videoA], presentingIn: nil, context: .library, presentsSummary: false) { _ in lateVideoCallback = true }
        manager.resetForAudit(); resetHold.1.signal()
        try await Task.sleep(nanoseconds: 120_000_000)
        checks["ResetRevokesActualVideoWorkerAndOldReceipt"] = manager.wallpapers.isEmpty && !lateVideoCallback

        let store = UserCollectionsStore(url: root.appendingPathComponent("relationships.sqlite3"))
        let controller = UserCollectionsController(store: store, snapshot: try await store.snapshot())
        let workspace = WallpaperLibraryWorkspace(controller)
        let target = try await controller.createPlaylist(name: "Captured target")
        let another = try await controller.createPlaylist(name: "Another list")
        let coordinator = WallpaperLibraryImportCoordinator(workspace: workspace, manager: manager, images: images, hostWindow: { nil })
        let unsupported = files.appendingPathComponent("not-media.txt"); try Data("not media".utf8).write(to: unsupported)
        let originalOrder = [videoB, directory, videoA, imageA, missingVideo, unsupported]
        coordinator.importFiles(originalOrder, to: .playlist(target))
        try await wait { presentedImportAlerts.contains { $0.0 == "导入结果" } }
        let sourceIDs = Dictionary(manager.wallpapers.map { ($0.path, WallpaperReference(provider: .videoLibrary, sourceID: $0.id)) }, uniquingKeysWith: { a, _ in a })
        let imageIDs = Dictionary(images.wallpapers.map { ($0.path, WallpaperReference(provider: .staticImageLibrary, sourceID: $0.id)) }, uniquingKeysWith: { a, _ in a })
        let members = controller.snapshot.members.filter { $0.playlistID == target }.sorted { $0.position < $1.position }.map(\.reference)
        let middle = images.wallpapers.filter { $0.path.hasPrefix(directory.path + "/") }.map {
            WallpaperReference(provider: .staticImageLibrary, sourceID: $0.id)
        }
        checks["MixedCoordinatorPreservesTopLevelFileAndDirectoryPositions"] = members.count == 5
            && members.first == sourceIDs[manager.normalizedPath(videoB.path)] && Array(members[1...2]) == middle
            && members[3] == sourceIDs[manager.normalizedPath(videoA.path)] && members[4] == imageIDs[imageA.path]
        checks["CapturedTargetNeverUsesAnotherCurrentList"] = !controller.snapshot.members.contains { $0.playlistID == another }
            && workspace.edited == [.playlist(target)]
        let summary = presentedImportAlerts.last!.1
        checks["CombinedFailureSummaryKeepsRealReasonsAndCounts"] = summary.contains("新增入库：5 项")
            && summary.contains("未完成：3 项") && summary.contains("missing.mp4：文件不存在")
            && summary.contains("not-media.txt：该页面不接受此文件类型") && summary.contains("looks-like-image.png")
        checks["MixedImportHasNoRetiredTagFavoriteOrPlaybackSideEffect"] = manager.wallpapers.allSatisfy { $0.tags.isEmpty && !$0.isFavorite }
            && images.wallpapers.allSatisfy { $0.tags.isEmpty } && controller.snapshot.recent.isEmpty
            && controller.snapshot.favorites.isEmpty && manager.automaticPlays == 0

        let restoredReference = sourceIDs[manager.normalizedPath(videoA.path)]!
        try await controller.perform(.setLibraryExcluded([restoredReference], true))
        let beforeRestoreAlerts = presentedImportAlerts.count
        coordinator.importFiles([videoA], to: .videos)
        try await wait { presentedImportAlerts.count > beforeRestoreAlerts }
        checks["ExplicitVerifiedExistingImportRestoresTheLibraryWithoutCopyingOrPlayback"] = !controller.snapshot.excludedLibraryReferences.contains { $0.reference == restoredReference }
            && manager.wallpapers.filter { $0.id == restoredReference.sourceID }.count == 1 && manager.automaticPlays == 0
        try await controller.perform(.setLibraryExcluded([restoredReference], true))
        let restoreHold = manager.holdQueue(); precondition(restoreHold.0.wait(timeout: .now() + 3) == .success)
        let beforeLateRestoreAlerts = presentedImportAlerts.count
        coordinator.importFiles([videoA], to: .videos)
        try await controller.perform(.setLibraryExcluded([restoredReference], true))
        let newHide = controller.snapshot.excludedLibraryReferences
        restoreHold.1.signal()
        try await wait { presentedImportAlerts.count > beforeLateRestoreAlerts }
        checks["ExplicitImportSuccessCannotClearAHideAdmittedAfterTheImportStarted"] = controller.snapshot.excludedLibraryReferences == newHide
            && FileManager.default.fileExists(atPath: videoA.path)

        let beforeFailedOnly = controller.snapshot.organizationState, beforeFailedRevision = controller.snapshot.revision
        let editsBeforeFailure = workspace.edited, failureAlertCount = presentedImportAlerts.count
        coordinator.importFiles([missingVideo, unsupported], to: .playlist(target))
        try await wait { presentedImportAlerts.count > failureAlertCount }
        checks["AllFailedImportDoesNotTouchOrganizationRevisionOrUndoMetadata"] = controller.snapshot.organizationState == beforeFailedOnly
            && controller.snapshot.revision == beforeFailedRevision && workspace.edited == editsBeforeFailure
        let failedDestination = try await controller.createPlaylist(name: "No successful source")
        let noSuccessHold = manager.holdQueue(); precondition(noSuccessHold.0.wait(timeout: .now() + 3) == .success)
        let noSuccessAlertCount = presentedImportAlerts.count
        coordinator.importFiles([missingVideo], to: .playlist(failedDestination))
        _ = try await controller.perform(.deletePlaylist(failedDestination))
        noSuccessHold.1.signal()
        try await wait { presentedImportAlerts.count > noSuccessAlertCount }
        checks["AllFailedDeletedDestinationNeverClaimsSourceImported"] = presentedImportAlerts.last?.0 != "壁纸已入库，整理未完成"
            && presentedImportAlerts.last?.1.contains("新增入库：0 项") == true
            && presentedImportAlerts.last?.1.contains("文件不存在") == true

        // A real source command may finish after its destination was deleted;
        // the source remains, and the App reports only organization failure.
        let held = manager.holdQueue(); precondition(held.0.wait(timeout: .now() + 3) == .success)
        let removed = try await controller.createPlaylist(name: "Deleted while preparing")
        let deletedAlertCount = presentedImportAlerts.count
        coordinator.importFiles([videoA], to: .playlist(removed))
        _ = try await controller.perform(.deletePlaylist(removed)); held.1.signal()
        try await wait { presentedImportAlerts.count > deletedAlertCount }
        checks["DeletedDestinationDoesNotRedirectOrHideSourceSuccess"] = manager.wallpapers.contains { $0.path == manager.normalizedPath(videoA.path) }
            && !controller.snapshot.members.contains { $0.playlistID == removed }
            && presentedImportAlerts.last?.0 == "导入整理未完成"
            && presentedImportAlerts.last?.1.contains("原始壁纸仍保留在资料库中") == true
        let alertCount = presentedImportAlerts.count
        let resetBatch = manager.holdQueue(); precondition(resetBatch.0.wait(timeout: .now() + 3) == .success)
        coordinator.importFiles([videoA], to: .favorites)
        try await controller.reset(); manager.resetForAudit(); images.resetForAudit()
        resetBatch.1.signal(); try await Task.sleep(nanoseconds: 150_000_000)
        checks["ResetRevokesMixedBatchOrganizationAndLateSuccessAlert"] = controller.snapshot.favorites.isEmpty
            && presentedImportAlerts.count == alertCount && manager.wallpapers.isEmpty && images.wallpapers.isEmpty

        // Recent readiness uses the same canonical unique-before-50 boundary
        // as the visible page, including the actual fiftieth provider.
        let canonical = WallpaperReference(provider: .videoLibrary, sourceID: "canonical")
        let alias = WallpaperReference(provider: .videoLibrary, sourceID: "alias")
        let final = WallpaperReference(provider: .staticImageLibrary, sourceID: "fiftieth")
        var recent = [WallpaperRecentUse(reference: alias, lastSuccessfulUseAt: nil, commitSequence: 100, migrationOrder: nil),
                      WallpaperRecentUse(reference: canonical, lastSuccessfulUseAt: nil, commitSequence: 99, migrationOrder: nil)]
        recent += (0..<48).map { .init(reference: .init(provider: .videoLibrary, sourceID: "v\($0)"), lastSuccessfulUseAt: nil,
                                     commitSequence: Int64(98 - $0), migrationOrder: nil) }
        recent.append(.init(reference: final, lastSuccessfulUseAt: nil, commitSequence: 1, migrationOrder: nil))
        let relationship = UserCollectionsSnapshot(revision: 0, resetEpoch: UUID(), migrationManifestID: nil, playlists: [], members: [], favorites: [],
            recent: recent, aliases: [.init(alias: alias, canonical: canonical, proof: .restoredSourceRecord)], locators: [])
        let required = try WallpaperLibraryQuery.requiredProviders(page: .recent, state: .init(), relationships: relationship)
        let visible = try WallpaperLibraryQuery.project(page: .recent, state: .init(), catalog: .init(), relationships: relationship)
        checks["RecentReadinessSharesCanonicalUniqueBeforeFiftyBoundary"] = required == [.videoLibrary, .staticImageLibrary]
            && visible.items.count == 50 && visible.items.last?.reference == final
        if checks.values.contains(false) {
            let detail: [String: Any] = [
                "videoItems": firstVideo!.items.map { ["path": $0.sourceURL.path, "status": String(describing: $0.disposition), "reason": $0.failureMessage ?? ""] },
                "secondVideoItems": secondVideo!.items.map { ["path": $0.sourceURL.path, "status": String(describing: $0.disposition)] },
                "videoSourcePaths": sourceIDs.keys.sorted(), "expectedVideos": [videoA.path, videoB.path],
                "mixedMembers": members.map(\.storageKey), "expectedVideoIDs": sourceIDs.mapValues(\.storageKey),
                "expectedImageIDs": imageIDs.mapValues(\.storageKey), "summary": summary
            ]
            FileHandle.standardError.write(try JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys]))
        }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
