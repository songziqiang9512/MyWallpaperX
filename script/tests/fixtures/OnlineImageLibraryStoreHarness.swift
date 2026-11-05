import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Only the copied Store's two commit boundaries call this test probe. The
/// production move, encode, cancellation check and atomic-write bodies remain.
nonisolated final class OnlineImageStoreProbe: @unchecked Sendable {
    enum Phase { case beforeCheck, afterWrite }
    static let shared = OnlineImageStoreProbe()
    private let lock = NSLock()
    private var phase: Phase?
    private let entered = DispatchSemaphore(value: 0)
    private let resume = DispatchSemaphore(value: 0)
    private var reads: [URL] = []

    func recordRead(_ url: URL) { lock.lock(); reads.append(url); lock.unlock() }
    func resetReads() { lock.lock(); reads = []; lock.unlock() }
    var readPaths: [String] { lock.lock(); defer { lock.unlock() }; return reads.map(\.path) }
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

nonisolated private struct SourceImageIndex: Encodable {
    let schemaVersion = 1
    var records: [OnlineImageLocalRecord]
    var retiredPaths: [String] = []
}

@main struct OnlineImageLibraryStoreHarness {
    static func imageBytes() throws -> Data {
        let context = CGContext(data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return bytes as Data
    }

    static func main() async throws {
        let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = work.appendingPathComponent("library", isDirectory: true)
        let files = FileManager.default
        let store = OnlineImageLibraryStore(root: root)
        var checks: [String: Bool] = [:]
        let first = try await store.load()
        checks["absent-index-load-is-unconfirmed-empty-without-creating-a-directory"] = !first.status.hasSuccessfulScan
            && first.records.isEmpty && !files.fileExists(atPath: root.path)
            && Set(first.sourceStatuses.keys) == Set(OnlineImageSource.allCases)
        _ = try await store.scan(.wallhaven)
        let empty = try await store.scan(.pixiv)
        checks["absent-source-directories-scan-ready-empty-without-materializing-them"] = empty.status.hasSuccessfulScan
            && empty.records.isEmpty && !files.fileExists(atPath: root.path)

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
        let manifestURL = root.appendingPathComponent("Wallhaven/.wallhaven.json")
        let firstBytes = try Data(contentsOf: manifestURL)
        let replaced = try await publish(a, bytes: "new-validated-image")
        let replacement = replaced.records[0]
        let replacementURL = try store.fileURL(for: replacement)
        let replacementBytes = try Data(contentsOf: manifestURL)
        let replacementObject = try JSONSerialization.jsonObject(with: replacementBytes) as! [String: Any]
        checks["official-download-rating-survives-original-commit-and-replacement"] = oldRecord.rating == .adult && replacement.rating == .adult
        do {
            let unratedRoot = work.appendingPathComponent("unrated-source", isDirectory: true)
            let unratedIndex = unratedRoot.appendingPathComponent("Wallhaven/.wallhaven.json")
            try files.createDirectory(at: unratedIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
            var value = replacementObject
            value["records"] = (value["records"] as! [[String: Any]]).map { entry in
                var record = entry; record.removeValue(forKey: "rating"); return record
            }
            let bytes = try JSONSerialization.data(withJSONObject: value)
            try bytes.write(to: unratedIndex)
            let loaded = try await OnlineImageLibraryStore(root: unratedRoot).load([.wallhaven])
            checks["current-source-without-rating-remains-unknown-without-rewrite"] = try loaded.records.count == 1
                && loaded.records[0].rating == nil && Data(contentsOf: unratedIndex) == bytes
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
        checks["restart-load-reads-index-before-directory-confirmation"] = !reopened.status.hasSuccessfulScan
            && reopened.records == pages.records && reopened.unavailable.isEmpty && files.fileExists(atPath: unrelated.path)
            && files.fileExists(atPath: oldURL.path)

        let missingRecord = pages.records.first { $0.assetID == p0.id }!
        let missingURL = try store.fileURL(for: missingRecord)
        try files.removeItem(at: missingURL)
        _ = try await store.load([.pixiv])
        let missing = try await store.scan(.pixiv)
        checks["missing-file-retains-identity-and-local-readiness-as-unavailable"] = missing.records == pages.records
            && missing.unavailable == [p0.id] && missing.status.hasSuccessfulScan
        try files.createDirectory(at: missingURL, withIntermediateDirectories: false)
        let directory = try await store.scan(.pixiv)
        checks["directory-at-record-path-never-becomes-an-available-image"] = directory.unavailable == [p0.id]
        try files.removeItem(at: missingURL)
        try files.createSymbolicLink(at: missingURL, withDestinationURL: replacementURL)
        let linked = try await store.scan(.pixiv)
        checks["in-root-symlink-is-not-an-ordinary-image-leaf"] = linked.unavailable == [p0.id]
        try files.removeItem(at: missingURL)
        try files.createSymbolicLink(at: missingURL, withDestinationURL: root.appendingPathComponent("absent/image.png"))
        do {
            let dangling = try await store.scan(.pixiv)
            checks["in-root-dangling-symlink-does-not-inherit-ancestor-availability"] = dangling.unavailable == [p0.id]
        } catch OnlineImageLibraryStore.StoreError.invalidPath {
            checks["in-root-dangling-symlink-does-not-inherit-ancestor-availability"] = true
        }
        try files.removeItem(at: missingURL)
        try Data("restored-page-zero".utf8).write(to: missingURL)
        let restored = try await store.scan(.pixiv)
        checks["next-scan-recaptures-the-now-regular-leaf"] = restored.records == pages.records && restored.unavailable.isEmpty
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
        try files.createDirectory(at: blockedRoot.appendingPathComponent("Wallhaven"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: blockedObject).write(to: blockedRoot.appendingPathComponent("Wallhaven/.wallhaven.json"))
        let blockedStore = OnlineImageLibraryStore(root: blockedRoot)
        _ = try await blockedStore.load()
        let blocked = try await blockedStore.scan(.wallhaven)
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
        OnlineImageStoreProbe.shared.arm(.beforeCheck)
        let cancelledStage = try staging("cancel-before-commit")
        let cancelTask = Task.detached {
            try await store.publish(stagingURL: cancelledStage, asset: a, width: 80, height: 60,
                fileSizeBytes: 20, fileExtension: "png")
        }
        guard OnlineImageStoreProbe.shared.waitUntilEntered() else { fatalError("precommit probe did not run") }
        cancelTask.cancel(); OnlineImageStoreProbe.shared.release()
        do { _ = try await cancelTask.value; checks["cancellation-before-manifest-commit-publishes-nothing"] = false }
        catch is CancellationError {
            checks["cancellation-before-manifest-commit-publishes-nothing"] = try Data(contentsOf: manifestURL) == beforeCancellation
                && files.fileExists(atPath: oldURL.path) && files.fileExists(atPath: replacementURL.path)
                && files.contentsOfDirectory(atPath: root.appendingPathComponent("Wallhaven").path).sorted() == sourceFilesBeforeCancellation
        }
        let afterCancel = try await store.load()
        let activeBeforeCommittedCancel = afterCancel.records.first { $0.assetID == a.id }!
        OnlineImageStoreProbe.shared.arm(.afterWrite)
        let committedStage = try staging("cancel-after-commit")
        let committedTask = Task.detached {
            try await store.publish(stagingURL: committedStage, asset: a, width: 80, height: 60,
                fileSizeBytes: 19, fileExtension: "png")
        }
        guard OnlineImageStoreProbe.shared.waitUntilEntered() else { fatalError("postcommit probe did not run") }
        committedTask.cancel(); OnlineImageStoreProbe.shared.release()
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
            let invalidManifest = invalidRoot.appendingPathComponent("Wallhaven/.wallhaven.json")
            try files.createDirectory(at: invalidManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
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
            try files.createDirectory(at: escapeRoot.appendingPathComponent("Wallhaven"), withIntermediateDirectories: true)
            try files.createSymbolicLink(at: escapeRoot.appendingPathComponent("link"), withDestinationURL: target)
            let escapeManifest = escapeRoot.appendingPathComponent("Wallhaven/.wallhaven.json")
            try escapeBytes.write(to: escapeManifest)
            do {
                let escapedStore = OnlineImageLibraryStore(root: escapeRoot)
                _ = try await escapedStore.load()
                _ = try await escapedStore.scan(.wallhaven)
                checks["manifest-" + name + "-escape-is-rejected-without-overwrite"] = false
            } catch OnlineImageLibraryStore.StoreError.invalidPath {
                checks["manifest-" + name + "-escape-is-rejected-without-overwrite"] = try Data(contentsOf: escapeManifest) == escapeBytes
            }
        }
        let sharedRoot = work.appendingPathComponent("module-paths", isDirectory: true)
        let current = OnlineImageLibraryStore(root: sharedRoot)
        let brandRecord = try await current.publish(stagingURL: staging("brand-new-pixiv"), asset: p0,
            width: 80, height: 60, fileSizeBytes: 15, fileExtension: "png").records[0]
        checks["new-publication-writes-only-its-hidden-source-index"] = brandRecord.relativePath.hasPrefix("Pixiv/")
            && files.fileExists(atPath: sharedRoot.appendingPathComponent("Pixiv/.pixiv.json").path)
            && !files.fileExists(atPath: sharedRoot.appendingPathComponent("Wallhaven/.wallhaven.json").path)
            && !files.fileExists(atPath: sharedRoot.appendingPathComponent("online-images.json").path)
            && !files.fileExists(atPath: sharedRoot.appendingPathComponent("manifest.json").path)
        let restarted = try await OnlineImageLibraryStore(root: sharedRoot).load([.pixiv])
        checks["source-index-restart-preserves-exact-record-identity-date-and-revision"] = restarted.records == [brandRecord]

        let discoveryRoot = work.appendingPathComponent("real-discovery", isDirectory: true)
        let discovery = OnlineImageLibraryStore(root: discoveryRoot), image = try imageBytes()
        func imageStage() throws -> URL {
            let url = work.appendingPathComponent(UUID().uuidString + ".pending")
            try image.write(to: url)
            return url
        }
        let oldImage = try await discovery.publish(stagingURL: imageStage(), asset: a,
            width: 3, height: 2, fileSizeBytes: Int64(image.count), fileExtension: "png").records[0]
        let imageReplacement = try await discovery.publish(stagingURL: imageStage(), asset: a,
            width: 3, height: 2, fileSizeBytes: Int64(image.count), fileExtension: "png").records[0]
        _ = try await discovery.publish(stagingURL: imageStage(), asset: p0,
            width: 3, height: 2, fileSizeBytes: Int64(image.count), fileExtension: "png")
        let wallDirectory = discoveryRoot.appendingPathComponent("Wallhaven")
        let looseURL = wallDirectory.appendingPathComponent("an ordinary image.png")
        try image.write(to: looseURL)
        for name in [".hidden.png", "image.pending", "image.staging", "image.part", "image.tmp"] {
            try image.write(to: wallDirectory.appendingPathComponent(name))
        }
        try Data("<html>not a static image</html>".utf8).write(to: wallDirectory.appendingPathComponent("invalid.png"))
        let cold = OnlineImageLibraryStore(root: discoveryRoot)
        OnlineImageStoreProbe.shared.resetReads()
        let indexed = try await cold.load([.wallhaven])
        checks["requested-source-load-is-lazy-and-delivers-only-existing-index-records"] = indexed.records == [imageReplacement]
            && indexed.sourceStatuses[.pixiv] == nil && indexed.sourceStatuses[.wallhaven]?.hasSuccessfulScan == false
            && !OnlineImageStoreProbe.shared.readPaths.contains { $0.hasSuffix("/.pixiv.json") }
        let discovered = try await cold.scan(.wallhaven)
        let loose = discovered.records.first { $0.sourceURL.isFileURL }!
        let looseContent = OnlineImageContentProjection.local(loose, url: looseURL, available: true)
        checks["real-image-discovery-assigns-local-only-identity-and-no-remote-permissions"] = discovered.records.count == 2
            && loose.id.source == .wallhaven && loose.id.artworkID.hasPrefix("local:") && loose.sourceURL == looseURL
            && loose.pixelWidth == 3 && loose.pixelHeight == 2 && loose.fileSizeBytes == Int64(image.count)
            && looseContent.capabilities.contains([.play, .organize, .export])
            && !looseContent.capabilities.contains(.openSource) && !looseContent.capabilities.contains(.retryDownload)
        let retiredImageURL = try discovery.fileURL(for: oldImage)
        checks["discovery-never-revives-retired-hidden-pending-or-invalid-files"] = !discovered.records.contains { $0.relativePath == oldImage.relativePath }
            && discovered.records.filter { $0.sourceURL.isFileURL }.map(\.sourceURL) == [looseURL]
            && files.fileExists(atPath: retiredImageURL.path)
        let stable = try await OnlineImageLibraryStore(root: discoveryRoot).load([.wallhaven])
        checks["discovered-local-identity-revision-and-time-survive-real-index-reload"] = stable.records == discovered.records
        try files.removeItem(at: looseURL)
        let unavailableLoose = try await cold.scan(.wallhaven)
        let missingLoose = OnlineImageContentProjection.local(loose, url: looseURL, available: false)
        checks["missing-discovered-image-retains-local-identity-without-fake-redownload"] = unavailableLoose.unavailable.contains(loose.id)
            && unavailableLoose.records.contains(loose) && !missingLoose.capabilities.contains(.play)
            && !missingLoose.capabilities.contains(.retryDownload) && !missingLoose.capabilities.contains(.openSource)
        let pixivIndex = discoveryRoot.appendingPathComponent("Pixiv/.pixiv.json")
        let goodPixiv = try Data(contentsOf: pixivIndex)
        try Data("broken source index".utf8).write(to: pixivIndex)
        var rejectedPartition = false
        do { _ = try await cold.load([.pixiv]) } catch { rejectedPartition = true }
        let sourceFailure = await cold.failed(.pixiv, message: "fixture corrupt partition")
        checks["one-corrupt-source-preserves-the-other-admitted-records-and-revision"] = rejectedPartition
            && sourceFailure.records == unavailableLoose.records && sourceFailure.revision == unavailableLoose.revision
            && sourceFailure.sourceStatuses[.wallhaven]?.hasSuccessfulScan == true
        try goodPixiv.write(to: pixivIndex)

        let obsoleteRoot = work.appendingPathComponent("obsolete-indices", isDirectory: true)
        let oldDirectory = obsoleteRoot.appendingPathComponent("在线图片", isDirectory: true)
        try files.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        let oldBytes = Data("obsolete index is neither read nor deleted".utf8)
        let oldFiles = [obsoleteRoot.appendingPathComponent("online-images.json"),
            obsoleteRoot.appendingPathComponent("manifest.json"), oldDirectory.appendingPathComponent("manifest.json")]
        for file in oldFiles { try oldBytes.write(to: file) }
        let obsoleteStore = OnlineImageLibraryStore(root: obsoleteRoot)
        let emptyCurrent = try await obsoleteStore.load()
        checks["obsolete-root-indices-are-ignored-without-migration-or-deletion"] = try emptyCurrent.records.isEmpty
            && oldFiles.allSatisfy { try Data(contentsOf: $0) == oldBytes }
            && !files.fileExists(atPath: obsoleteRoot.appendingPathComponent("Wallhaven/.wallhaven.json").path)
            && !files.fileExists(atPath: obsoleteRoot.appendingPathComponent("Pixiv/.pixiv.json").path)

        let wrongSourceRoot = work.appendingPathComponent("wrong-source-partition", isDirectory: true)
        try files.createDirectory(at: wrongSourceRoot.appendingPathComponent("Pixiv"), withIntermediateDirectories: true)
        let wrongSourceIndex = wrongSourceRoot.appendingPathComponent("Pixiv/.pixiv.json")
        let wrongSourceBytes = try JSONEncoder().encode(SourceImageIndex(records: [imageReplacement]))
        try wrongSourceBytes.write(to: wrongSourceIndex)
        let wrongSourceStore = OnlineImageLibraryStore(root: wrongSourceRoot)
        var rejectedWrongSource = false
        do { _ = try await wrongSourceStore.load([.pixiv]) } catch { rejectedWrongSource = true }
        let otherSource = try await wrongSourceStore.load([.wallhaven])
        checks["wrong-source-index-is-rejected-without-affecting-other-source"] = try rejectedWrongSource
            && otherSource.records.isEmpty && Data(contentsOf: wrongSourceIndex) == wrongSourceBytes

        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
