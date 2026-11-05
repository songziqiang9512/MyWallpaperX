import Foundation
import Combine

/// Pauses only the copied Store's directory IO. Its actual index decode,
/// publication, discovery and Library delivery continue unchanged.
nonisolated final class OnlineImageLocalScanProbe: @unchecked Sendable {
    static let shared = OnlineImageLocalScanProbe()
    private let lock = NSLock()
    private var gate: DispatchSemaphore?
    private var path: String?
    private var entered = false
    private var scans: [String: Int] = [:]
    private var indices: [String] = []

    private func key(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    func arm(at directory: URL) {
        lock.lock(); defer { lock.unlock() }
        path = key(directory); gate = DispatchSemaphore(value: 0); entered = false; scans = [:]; indices = []
    }
    func recordIndex(_ url: URL) { lock.lock(); indices.append(url.path); lock.unlock() }
    func pause(at directory: URL) {
        let pathKey = key(directory)
        lock.lock()
        scans[pathKey, default: 0] += 1
        let current = pathKey == path ? gate : nil
        if current != nil { entered = true }
        lock.unlock()
        if let current { _ = current.wait(timeout: .now() + 10) }
    }
    func release() { lock.lock(); let current = gate; gate = nil; lock.unlock(); current?.signal() }
    var hasEntered: Bool { lock.lock(); defer { lock.unlock() }; return entered }
    var readPaths: [String] { lock.lock(); defer { lock.unlock() }; return indices }
    var scannedPaths: [String: Int] { lock.lock(); defer { lock.unlock() }; return scans }
    func scans(at directory: URL) -> Int { lock.lock(); defer { lock.unlock() }; return scans[key(directory), default: 0] }
}

extension OnlineImageLibraryHarness {
    static func localIndexDeliveryAndDiscovery() async throws {
        let directory = root.appendingPathComponent("lazy-source-delivery", isDirectory: true)
        let store = OnlineImageLibraryStore(root: directory), files = FileManager.default
        @MainActor func seed(_ imageSource: OnlineImageSource) async throws -> OnlineImageLocalRecord {
            let stage = root.appendingPathComponent(UUID().uuidString + ".pending")
            try png.write(to: stage)
            let item = asset(imageSource, "indexed-before-scan-" + imageSource.rawValue)
            let result = try await store.publish(stagingURL: stage, asset: item,
                width: 3, height: 2, fileSizeBytes: Int64(png.count), fileExtension: "png")
            return result.records.first { $0.id == item.id }!
        }
        let wall = try await seed(.wallhaven), pixiv = try await seed(.pixiv)
        let wallDirectory = try store.fileURL(for: wall).deletingLastPathComponent()
        let looseURL = wallDirectory.appendingPathComponent("user-added.png")
        try png.write(to: looseURL)
        let beforeReads = source.credentialReads, beforeEvents = source.events.count
        let value = OnlineImageLibrary(root: directory), probe = OnlineImageLocalScanProbe.shared
        var terminals: [DownloadTerminalReceipt] = []
        let terminalObservation = value.downloadTerminals.sink { terminals.append($0) }
        defer { terminalObservation.cancel(); probe.release() }
        check("online-library-init-does-not-read-local-indices-or-claim-ready",
              value.snapshot.records.isEmpty && value.snapshot.sourceStatuses.isEmpty && !value.snapshot.status.hasSuccessfulScan)
        probe.arm(at: wallDirectory)
        value.prepareLocal([.wallhaven]); value.prepareLocal([.wallhaven])
        do { try await eventually("real directory scan held after index delivery") { probe.hasEntered } }
        catch {
            throw Failure(description: "\(error); armed=\(wallDirectory.path) scans=\(probe.scannedPaths) indices=\(probe.readPaths) status=\(value.snapshot.sourceStatuses)")
        }
        check("held-real-scan-still-delivers-existing-records-before-discovery",
              value.record(for: wall.id.reference) == wall && value.snapshot.records == [wall]
              && value.snapshot.sourceStatuses[.wallhaven]?.hasSuccessfulScan == false
              && value.snapshot.sourceStatuses[.pixiv] == nil && value.snapshot.unavailable.isEmpty)
        check("one-source-demand-does-not-read-the-other-index-or-start-network",
              !probe.readPaths.contains { $0.hasSuffix("/Pixiv/.pixiv.json") }
              && source.credentialReads == beforeReads && source.events.count == beforeEvents && probe.scans(at: wallDirectory) == 1)
        probe.release()
        try await eventually("released real scan discovers ordinary PNG") { value.snapshot.records.count == 2 && value.snapshot.sourceStatuses[.wallhaven]?.hasSuccessfulScan == true }
        let local = value.snapshot.records.first { $0.sourceURL.isFileURL }!
        let content = value.content(for: local.id.reference)!
        let statuses = Dictionary(uniqueKeysWithValues: OnlineImageSource.allCases.map { source -> (String, Any) in
            guard let status = value.snapshot.sourceStatuses[source] else { return (source.rawValue, NSNull()) }
            return (source.rawValue, ["phase": String(describing: status.phase), "hasSuccessfulScan": status.hasSuccessfulScan] as [String: Any])
        })
        let facts: [String: Any] = [
            "urlEqual": local.sourceURL == looseURL,
            "sourceURL": ["absolute": local.sourceURL.absoluteString, "path": local.sourceURL.path,
                "base": local.sourceURL.baseURL?.absoluteString ?? "", "hasDirectoryPath": local.sourceURL.hasDirectoryPath] as [String: Any],
            "looseURL": ["absolute": looseURL.absoluteString, "path": looseURL.path,
                "base": looseURL.baseURL?.absoluteString ?? "", "hasDirectoryPath": looseURL.hasDirectoryPath] as [String: Any],
            "capabilities": ["rawValue": content.capabilities.rawValue, "play": content.capabilities.contains(.play),
                "organize": content.capabilities.contains(.organize), "export": content.capabilities.contains(.export),
                "openSource": content.capabilities.contains(.openSource), "retryDownload": content.capabilities.contains(.retryDownload)] as [String: Any],
            "terminals": try JSONSerialization.jsonObject(with: JSONEncoder().encode(terminals)),
            "sourceStatuses": statuses, "aggregateHasSuccessfulScan": value.snapshot.status.hasSuccessfulScan]
        let receipt = try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
        FileHandle.standardError.write(Data("LOCAL DISCOVERY FACTS ".utf8) + receipt + Data([10]))
        check("discovery-uses-real-local-content-without-fabricating-download-history",
              local.sourceURL.resolvingSymlinksInPath().standardizedFileURL == looseURL.resolvingSymlinksInPath().standardizedFileURL && content.capabilities.contains([.play, .organize, .export])
              && !content.capabilities.contains(.openSource) && !content.capabilities.contains(.retryDownload)
              && terminals.isEmpty && !value.snapshot.status.hasSuccessfulScan)
        value.prepareLocal([.wallhaven]); await value.refreshLocal([.pixiv]).value
        check("explicit-second-source-load-merges-records-with-independent-readiness",
              value.record(for: pixiv.id.reference) == pixiv && value.record(for: wall.id.reference) == wall
              && value.snapshot.records.contains(local) && value.snapshot.status.hasSuccessfulScan && probe.scans(at: wallDirectory) == 1)
        let pixivIndex = directory.appendingPathComponent("Pixiv/.pixiv.json")
        let goodIndex = try Data(contentsOf: pixivIndex), beforeFailure = value.snapshot
        try Data("broken source index".utf8).write(to: pixivIndex)
        await value.refreshLocal([.pixiv]).value
        check("failed-one-source-refresh-preserves-other-source-records-and-readiness",
              value.snapshot.records == beforeFailure.records && value.snapshot.revision == beforeFailure.revision
              && value.snapshot.sourceStatuses[.wallhaven] == beforeFailure.sourceStatuses[.wallhaven]
              && value.content(for: wall.id.reference)?.capabilities.contains(.play) == true)
        try goodIndex.write(to: pixivIndex)
        await value.refreshLocal([.pixiv]).value
        check("recovered-source-refresh-keeps-the-discovered-local-identity", value.record(for: local.id.reference) == local
              && value.record(for: pixiv.id.reference) == pixiv && value.snapshot.status.hasSuccessfulScan)
        try files.removeItem(at: looseURL)
        await value.refreshLocal([.wallhaven]).value
        check("missing-discovered-content-keeps-local-identity-without-remote-retry",
              value.record(for: local.id.reference) == local && value.snapshot.unavailable.contains(local.id)
              && value.content(for: local.id.reference)?.capabilities.contains(.play) == false
              && value.content(for: local.id.reference)?.capabilities.contains(.retryDownload) == false && terminals.isEmpty)
    }
}
