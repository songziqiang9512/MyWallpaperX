import Foundation

/// Only the copied Store's two commit boundaries call this test probe. The
/// production move, encode, cancellation check and atomic-write bodies remain.
nonisolated final class OnlineImageCommitProbe: @unchecked Sendable {
    enum Phase { case beforeCheck, afterWrite }
    static let shared = OnlineImageCommitProbe()
    private let lock = NSLock()
    private var phase: Phase?
    private let entered = DispatchSemaphore(value: 0)
    private let resume = DispatchSemaphore(value: 0)

    func arm(_ phase: Phase) { lock.lock(); self.phase = phase; lock.unlock() }
    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
    func release() { resume.signal() }
    func pause(at current: Phase) {
        lock.lock()
        let pauses = phase == current
        if pauses { phase = nil }
        lock.unlock()
        if pauses { entered.signal(); _ = resume.wait(timeout: .now() + 10) }
    }
}

@main struct OnlineImageLibraryStoreHarness {
    static func main() async throws {
        let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = work.appendingPathComponent("library", isDirectory: true)
        let files = FileManager.default
        let store = OnlineImageLibraryStore(root: root)
        var checks: [String: Bool] = [:]
        let first = try await store.load()
        checks["absent-manifest-is-local-ready-empty-without-creating-a-directory"] = first.status.hasSuccessfulScan
            && first.records.isEmpty && !files.fileExists(atPath: root.path)

        func asset(_ source: OnlineImageSource, _ id: String, _ page: Int = 0) -> OnlineImageAsset {
            OnlineImageAsset(id: .init(source: source, artworkID: id, pageIndex: page), title: "Saved original",
                sourceURL: URL(string: "https://example.org/artwork/" + id)!,
                originalURL: URL(string: "https://cdn.example.org/image?signature=fixture-expiring-secret")!,
                author: "Author", tags: ["tag"])
        }
        func staging(_ text: String) throws -> URL {
            let url = work.appendingPathComponent(UUID().uuidString + ".pending")
            try Data(text.utf8).write(to: url)
            return url
        }
        func publish(_ value: OnlineImageAsset, bytes: String) async throws -> OnlineImageLocalSnapshot {
            try await store.publish(stagingURL: staging(bytes), asset: value, width: 80, height: 60,
                fileSizeBytes: Int64(bytes.utf8.count), fileExtension: "PNG")
        }
        var a = asset(.wallhaven, "Ab001"); a.rating = .adult
        let original = try await publish(a, bytes: "old-validated-image")
        let oldRecord = original.records[0]
        let oldURL = try store.fileURL(for: oldRecord)
        let manifestURL = root.appendingPathComponent("manifest.json")
        let firstBytes = try Data(contentsOf: manifestURL)
        let replaced = try await publish(a, bytes: "new-validated-image")
        let replacement = replaced.records[0]
        let replacementURL = try store.fileURL(for: replacement)
        let replacementBytes = try Data(contentsOf: manifestURL)
        let replacementObject = try JSONSerialization.jsonObject(with: replacementBytes) as! [String: Any]
        checks["official-download-rating-survives-original-commit-and-replacement"] = oldRecord.rating == .adult && replacement.rating == .adult
        do {
            let legacyRoot = work.appendingPathComponent("legacy-library", isDirectory: true)
            try files.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
            var legacyManifest = replacementObject
            legacyManifest["records"] = (legacyManifest["records"] as! [[String: Any]]).map { entry in
                var value = entry; value.removeValue(forKey: "rating"); return value
            }
            let legacyBytes = try JSONSerialization.data(withJSONObject: legacyManifest)
            let legacyURL = legacyRoot.appendingPathComponent("manifest.json")
            try legacyBytes.write(to: legacyURL)
            let legacy = try await OnlineImageLibraryStore(root: legacyRoot).load()
            let unchangedLegacy = try Data(contentsOf: legacyURL)
            checks["old-unrated-manifest-remains-readable-without-rewrite-or-rating-guess"] = legacy.records.count == 1
                && legacy.records[0].rating == nil && unchangedLegacy == legacyBytes
        }
        let oldImageBytes = try Data(contentsOf: oldURL), newImageBytes = try Data(contentsOf: replacementURL)
        checks["replacement-uses-independent-revision-and-retains-active-old-bytes"] = replacement.revision != oldRecord.revision
            && replacement.relativePath != oldRecord.relativePath
            && oldImageBytes == Data("old-validated-image".utf8)
            && newImageBytes == Data("new-validated-image".utf8)
            && replacementObject["retiredPaths"] as? [String] == [oldRecord.relativePath]
        checks["replacement-preserves-first-success-time-and-never-persists-expiring-original-url"] = replacement.firstDownloadedAt == oldRecord.firstDownloadedAt
            && !String(decoding: replacementBytes, as: UTF8.self).contains("fixture-expiring-secret")
            && firstBytes != replacementBytes
        let p0 = asset(.pixiv, "001234", 0), p2 = asset(.pixiv, "001234", 2)
        _ = try await publish(p0, bytes: "page-zero")
        let pages = try await publish(p2, bytes: "page-two")
        checks["opaque-provider-and-page-assets-do-not-collapse"] = Set(pages.records.map(\.assetID)) == [a.id, p0.id, p2.id]
        let unrelated = root.appendingPathComponent("unrelated-user-file.png")
        try Data("unrelated".utf8).write(to: unrelated)
        let reopened = try await OnlineImageLibraryStore(root: root).load()
        checks["restart-reads-manifest-only-without-login-or-directory-import"] = reopened.status.hasSuccessfulScan
            && reopened.records == pages.records && reopened.unavailable.isEmpty && files.fileExists(atPath: unrelated.path)
            && files.fileExists(atPath: oldURL.path)

        let missingRecord = pages.records.first { $0.assetID == p0.id }!
        let missingURL = try store.fileURL(for: missingRecord)
        try files.removeItem(at: missingURL)
        let missing = try await store.load()
        checks["missing-file-retains-identity-and-local-readiness-as-unavailable"] = missing.records == pages.records
            && missing.unavailable == [p0.id] && missing.status.hasSuccessfulScan
        try files.createDirectory(at: missingURL, withIntermediateDirectories: false)
        let directory = try await store.load()
        checks["directory-at-record-path-never-becomes-an-available-image"] = directory.unavailable == [p0.id]
        try files.removeItem(at: missingURL)
        try files.createSymbolicLink(at: missingURL, withDestinationURL: replacementURL)
        let linked = try await store.load()
        checks["in-root-symlink-is-not-an-ordinary-image-leaf"] = linked.unavailable == [p0.id]
        try files.removeItem(at: missingURL)
        try files.createSymbolicLink(at: missingURL, withDestinationURL: root.appendingPathComponent("absent/image.png"))
        do {
            let dangling = try await store.load()
            checks["in-root-dangling-symlink-does-not-inherit-ancestor-availability"] = dangling.unavailable == [p0.id]
        } catch OnlineImageLibraryStore.StoreError.invalidPath {
            checks["in-root-dangling-symlink-does-not-inherit-ancestor-availability"] = true
        }
        try files.removeItem(at: missingURL)
        try Data("restored-page-zero".utf8).write(to: missingURL)
        let restored = try await store.load()
        checks["next-load-recaptures-the-now-regular-leaf"] = restored.records == pages.records && restored.unavailable.isEmpty
        try files.removeItem(at: missingURL)

        func record(at path: String) -> OnlineImageLocalRecord {
            .init(assetID: oldRecord.assetID, title: oldRecord.title, sourceURL: oldRecord.sourceURL,
                author: oldRecord.author, authorID: oldRecord.authorID, tags: oldRecord.tags,
                relativePath: path, pixelWidth: oldRecord.pixelWidth, pixelHeight: oldRecord.pixelHeight,
                fileSizeBytes: oldRecord.fileSizeBytes, firstDownloadedAt: oldRecord.firstDownloadedAt, revision: oldRecord.revision)
        }
        let outside = work.appendingPathComponent("outside", isDirectory: true)
        try files.createDirectory(at: outside, withIntermediateDirectories: true)
        for (name, path) in [("dotdot", "../outside/image.png"), ("absolute", "/outside/image.png"),
                             ("empty-component", "wallhaven//image.png")] {
            do { _ = try store.fileURL(for: record(at: path)); checks["relative-path-refuses-" + name] = false }
            catch OnlineImageLibraryStore.StoreError.invalidPath { checks["relative-path-refuses-" + name] = true }
        }
        let blockedRoot = work.appendingPathComponent("missing-under-file", isDirectory: true)
        try files.createDirectory(at: blockedRoot, withIntermediateDirectories: false)
        try Data("ordinary-parent".utf8).write(to: blockedRoot.appendingPathComponent("parent"))
        var blockedObject = replacementObject
        var blockedRecords = blockedObject["records"] as! [[String: Any]]
        blockedRecords[0]["relativePath"] = "parent/missing.png"
        blockedObject["records"] = blockedRecords
        try JSONSerialization.data(withJSONObject: blockedObject).write(to: blockedRoot.appendingPathComponent("manifest.json"))
        let blocked = try await OnlineImageLibraryStore(root: blockedRoot).load()
        checks["missing-leaf-never-inherits-an-existing-regular-ancestor-type"] = blocked.unavailable == [a.id]

        let beforeWriteFailure = try Data(contentsOf: manifestURL)
        let sourceDirectory = root.appendingPathComponent("Wallhaven", isDirectory: true)
        let filesBeforeWriteFailure = try files.contentsOfDirectory(atPath: sourceDirectory.path).sorted()
        let heldManifest = work.appendingPathComponent("manifest-held-for-write-fault.json")
        try files.moveItem(at: manifestURL, to: heldManifest)
        try files.createDirectory(at: manifestURL, withIntermediateDirectories: false)
        var refusedManifestWrite = false
        do { _ = try await publish(a, bytes: "uncommitted-write-fault") }
        catch { refusedManifestWrite = true }
        try files.removeItem(at: manifestURL)
        try files.moveItem(at: heldManifest, to: manifestURL)
        let afterWriteFailure = try await store.load()
        checks["atomic-manifest-write-failure-rolls-back-new-file-and-retains-prior-publication"] = try refusedManifestWrite
            && Data(contentsOf: manifestURL) == beforeWriteFailure && afterWriteFailure.records == pages.records
            && files.contentsOfDirectory(atPath: sourceDirectory.path).sorted() == filesBeforeWriteFailure
            && files.fileExists(atPath: oldURL.path) && files.fileExists(atPath: replacementURL.path)

        let beforeCancellation = try Data(contentsOf: manifestURL)
        let sourceFilesBeforeCancellation = try files.contentsOfDirectory(atPath: root.appendingPathComponent("Wallhaven").path).sorted()
        OnlineImageCommitProbe.shared.arm(.beforeCheck)
        let cancelledStage = try staging("cancel-before-commit")
        let cancelTask = Task.detached {
            try await store.publish(stagingURL: cancelledStage, asset: a, width: 80, height: 60,
                fileSizeBytes: 20, fileExtension: "png")
        }
        guard OnlineImageCommitProbe.shared.waitUntilEntered() else { fatalError("precommit probe did not run") }
        cancelTask.cancel(); OnlineImageCommitProbe.shared.release()
        do { _ = try await cancelTask.value; checks["cancellation-before-manifest-commit-publishes-nothing"] = false }
        catch is CancellationError {
            checks["cancellation-before-manifest-commit-publishes-nothing"] = try Data(contentsOf: manifestURL) == beforeCancellation
                && files.fileExists(atPath: oldURL.path) && files.fileExists(atPath: replacementURL.path)
                && files.contentsOfDirectory(atPath: root.appendingPathComponent("Wallhaven").path).sorted() == sourceFilesBeforeCancellation
        }
        let afterCancel = try await store.load()
        let activeBeforeCommittedCancel = afterCancel.records.first { $0.assetID == a.id }!
        OnlineImageCommitProbe.shared.arm(.afterWrite)
        let committedStage = try staging("cancel-after-commit")
        let committedTask = Task.detached {
            try await store.publish(stagingURL: committedStage, asset: a, width: 80, height: 60,
                fileSizeBytes: 19, fileExtension: "png")
        }
        guard OnlineImageCommitProbe.shared.waitUntilEntered() else { fatalError("postcommit probe did not run") }
        committedTask.cancel(); OnlineImageCommitProbe.shared.release()
        let committed = try await committedTask.value
        let committedRecord = committed.records.first { $0.assetID == a.id }!
        let restartedCommit = try await OnlineImageLibraryStore(root: root).load()
        checks["cancellation-after-manifest-commit-returns-success-with-published-file"] = try committedRecord.revision != activeBeforeCommittedCancel.revision
            && files.fileExists(atPath: store.fileURL(for: committedRecord).path)
            && restartedCommit.records == committed.records
        do {
            _ = try await store.removeRecord(id: a.id, expectedRevision: activeBeforeCommittedCancel.revision)
            checks["old-delete-receipt-cannot-remove-new-revision"] = false
        } catch OnlineImageLibraryStore.StoreError.changedRecord { checks["old-delete-receipt-cannot-remove-new-revision"] = true }
        let committedURL = try store.fileURL(for: committedRecord)
        try files.removeItem(at: committedURL)
        let removed = try await store.removeRecord(id: a.id, expectedRevision: committedRecord.revision)
        checks["record-removal-keeps-other-pages-and-never-unlinks-retired-or-unrelated-files"] = Set(removed.records.map(\.assetID)) == [p0.id, p2.id]
            && files.fileExists(atPath: oldURL.path) && files.fileExists(atPath: replacementURL.path)
            && files.fileExists(atPath: unrelated.path)

        for (name, bytes) in [("bad-json", Data("{".utf8)), ("unknown-version", Data("{\"schemaVersion\":2}".utf8))] {
            let invalidRoot = work.appendingPathComponent(name, isDirectory: true)
            try files.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
            let invalidManifest = invalidRoot.appendingPathComponent("manifest.json")
            try bytes.write(to: invalidManifest)
            let invalidStore = OnlineImageLibraryStore(root: invalidRoot)
            var refusedLoad = false, refusedWrite = false
            do { _ = try await invalidStore.load() } catch { refusedLoad = true }
            let stage = try staging("must-remain-owned-by-service")
            do {
                _ = try await invalidStore.publish(stagingURL: stage, asset: a, width: 1, height: 1, fileSizeBytes: 27, fileExtension: "png")
            } catch { refusedWrite = true }
            checks[name + "-refuses-load-and-publication-without-rewriting-input-or-consuming-staging"] = try refusedLoad && refusedWrite
                && Data(contentsOf: invalidManifest) == bytes && files.fileExists(atPath: stage.path)
        }
        for (name, path, target) in [("dotdot", "../outside/image.png", outside),
                                     ("symlink", "link/image.png", outside),
                                     ("dangling-symlink", "link/image.png", outside.appendingPathComponent("absent"))] {
            var escapeObject = replacementObject
            var escapeRecords = escapeObject["records"] as! [[String: Any]]
            escapeRecords[0]["relativePath"] = path
            escapeObject["records"] = escapeRecords
            let escapeBytes = try JSONSerialization.data(withJSONObject: escapeObject)
            let escapeRoot = work.appendingPathComponent("manifest-escape-" + name, isDirectory: true)
            try files.createDirectory(at: escapeRoot, withIntermediateDirectories: true)
            try files.createSymbolicLink(at: escapeRoot.appendingPathComponent("link"), withDestinationURL: target)
            let escapeManifest = escapeRoot.appendingPathComponent("manifest.json")
            try escapeBytes.write(to: escapeManifest)
            do {
                _ = try await OnlineImageLibraryStore(root: escapeRoot).load()
                checks["manifest-" + name + "-escape-is-rejected-without-overwrite"] = false
            } catch OnlineImageLibraryStore.StoreError.invalidPath {
                checks["manifest-" + name + "-escape-is-rejected-without-overwrite"] = try Data(contentsOf: escapeManifest) == escapeBytes
            }
        }
        let sharedRoot = work.appendingPathComponent("module-paths", isDirectory: true)
        let legacyRoot = sharedRoot.appendingPathComponent("在线图片", isDirectory: true)
        // Preserve the bytes of the old Date fields, as a real schema-one
        // manifest did. JSONSerialization's number formatter can round them.
        let oldPathJSON = String(decoding: try JSONEncoder().encode(replacement.relativePath), as: UTF8.self)
        let legacyPathJSON = String(decoding: try JSONEncoder().encode("wallhaven/legacy.png"), as: UTF8.self)
        let legacyManifest = String(decoding: replacementBytes, as: UTF8.self).replacingOccurrences(of: oldPathJSON, with: legacyPathJSON)
        try files.createDirectory(at: legacyRoot.appendingPathComponent("wallhaven"), withIntermediateDirectories: true)
        let legacyImage = legacyRoot.appendingPathComponent("wallhaven/legacy.png")
        try Data("legacy-original".utf8).write(to: legacyImage)
        try Data(legacyManifest.utf8).write(to: legacyRoot.appendingPathComponent("manifest.json"))
        let upgraded = OnlineImageLibraryStore(root: sharedRoot, legacyRoot: legacyRoot, manifestName: "online-images.json")
        let legacyLoaded = try await upgraded.load()
        let legacyRecord = legacyLoaded.records[0]
        let legacyURL = try upgraded.fileURL(for: legacyRecord)
        checks["legacy-manifest-load-preserves-id-revision-time-and-file-without-copy-or-new-manifest"] =
            legacyRecord.assetID == replacement.assetID && legacyRecord.revision == replacement.revision
            && legacyRecord.firstDownloadedAt == replacement.firstDownloadedAt && legacyURL.standardizedFileURL.path == legacyImage.standardizedFileURL.path
            && !files.fileExists(atPath: sharedRoot.appendingPathComponent("online-images.json").path)
        if checks["legacy-manifest-load-preserves-id-revision-time-and-file-without-copy-or-new-manifest"] != true {
            let mismatch = "legacy preservation id=\(legacyRecord.assetID == replacement.assetID) revision=\(legacyRecord.revision == replacement.revision) dateDelta=\(legacyRecord.firstDownloadedAt.timeIntervalSince(replacement.firstDownloadedAt)) path=\(legacyURL.path) expected=\(legacyImage.path)\n"
            FileHandle.standardError.write(Data(mismatch.utf8))
        }
        let mixed = try await upgraded.publish(stagingURL: staging("brand-new-pixiv"), asset: p0,
            width: 80, height: 60, fileSizeBytes: 15, fileExtension: "png")
        checks["new-publication-uses-brand-directory-and-unique-shared-manifest-with-old-reference-intact"] =
            mixed.records.contains { $0.relativePath.hasPrefix("Pixiv/") }
            && mixed.records.contains { $0.assetID == legacyRecord.assetID && $0.relativePath == legacyRecord.relativePath }
            && files.fileExists(atPath: legacyImage.path)
            && files.fileExists(atPath: sharedRoot.appendingPathComponent("online-images.json").path)
            && !files.fileExists(atPath: sharedRoot.appendingPathComponent("manifest.json").path)
        try Data("old manifest now obsolete".utf8).write(to: legacyRoot.appendingPathComponent("manifest.json"))
        let mixedRestart = try await OnlineImageLibraryStore(root: sharedRoot, legacyRoot: legacyRoot, manifestName: "online-images.json").load()
        checks["new-manifest-is-the-only-authority-after-first-real-commit"] = mixedRestart.records == mixed.records
        let removedLegacy = try await upgraded.removeRecord(id: legacyRecord.assetID, expectedRevision: legacyRecord.revision)
        checks["removing-legacy-record-preserves-new-brand-records"] = removedLegacy.records.count == mixed.records.count - 1
            && removedLegacy.records.contains { $0.assetID == p0.id }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
