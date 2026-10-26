import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

// External leaves only. Service, Store, Projection, models, ImageIO and the
// monotonic playback gate are compiled from unchanged, frozen product sources.
actor WallhavenCredentialStore {
    private var value: String?
    func read() throws -> String? { value }
    func write(_ value: String?) throws { self.value = value }
}

actor WallhavenClient {
    func setAPIKey(_ value: String?) {}
    func detail(id: String) async throws -> OnlineImageArtwork {
        try await SourceProbe.shared.detail(source: .wallhaven, id: id)
    }
    func assets(for value: OnlineImageArtwork) async throws -> [OnlineImageAsset] {
        try await SourceProbe.shared.assets(for: value)
    }
}

actor PixivClient {
    private var session: WallpaperNetworkSession
    init(session: WallpaperNetworkSession? = nil) {
        self.session = session ?? WallpaperNetworkSession(URLSession(configuration: .ephemeral))
    }
    func replaceSession(_ session: WallpaperNetworkSession) { self.session = session }
    func usesSession(_ session: WallpaperNetworkSession) -> Bool { self.session === session }
    func detail(id: String) async throws -> OnlineImageArtwork {
        try await SourceProbe.shared.detail(source: .pixiv, id: id)
    }
    func assets(for value: OnlineImageArtwork) async throws -> [OnlineImageAsset] {
        try await SourceProbe.shared.assets(for: value)
    }
}

@MainActor final class PixivSession: ObservableObject {
    struct State { let scopeID: String }
    static var nextPreparation: PixivPreparationProbe?
    @Published private(set) var state = State(scopeID: "pixiv-anonymous")
    private(set) var urlSession = WallpaperNetworkSession(URLSession(configuration: .ephemeral))
    private let preparation: PixivPreparationProbe?
    private var epoch = 0
    var scopeID: String { state.scopeID }

    init() {
        preparation = Self.nextPreparation
        Self.nextPreparation = nil
    }

    func refresh(afterExplicitAccountAction: Bool = false) async {
        if afterExplicitAccountAction { revokeScope() }
        let expected = epoch
        await preparation?.waitForCookieSnapshot()
        guard expected == epoch else { return }
        if preparation?.hasPersistedCookie == true { revokeScope() }
    }

    func revokeScope() {
        epoch += 1
        let previous = urlSession
        urlSession = WallpaperNetworkSession(URLSession(configuration: .ephemeral))
        state = State(scopeID: UUID().uuidString)
        previous.retire()
    }

    func logout() async {
        epoch += 1
        preparation?.logoutCalls += 1
        let previous = urlSession
        urlSession = WallpaperNetworkSession(URLSession(configuration: .ephemeral))
        state = State(scopeID: "pixiv-anonymous")
        previous.retire()
    }
}

/// Simulates the asynchronous persisted-cookie snapshot leaf. Real isolated
/// WebKit cookie copying is covered by PixivClientHarness, without an account.
@MainActor final class PixivPreparationProbe {
    let hasPersistedCookie: Bool
    private(set) var refreshCalls = 0
    var logoutCalls = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    var isWaiting: Bool { !waiters.isEmpty }

    init(hasPersistedCookie: Bool = true) { self.hasPersistedCookie = hasPersistedCookie }
    func waitForCookieSnapshot() async {
        refreshCalls += 1
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let values = waiters; waiters = []
        values.forEach { $0.resume() }
    }
}

nonisolated struct OLThumbnailRequest {
    let url: URL
    var scopeID = "public"
    var session: WallpaperNetworkSession? = nil
    var referer: URL? = nil
}

actor OLThumbnailCache {
    static let shared = OLThumbnailCache()
    private(set) var invalidations: [String] = []
    func invalidate(scopeID: String) { invalidations.append(scopeID) }
}

nonisolated enum WallpaperSourceFileDeletion {
    struct Prepared: Sendable { let url: URL }
    struct Outcome: Sendable { let sourceFileDeleted: Bool; let failureMessage: String? }
    static func prepare(_ url: URL) throws -> Prepared {
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        DeletionProbe.shared.pausePreparation()
        return .init(url: url)
    }
    static func unlinkPrepared(_ value: Prepared) -> Outcome {
        DeletionProbe.shared.recordUnlink()
        do { try FileManager.default.removeItem(at: value.url); return .init(sourceFileDeleted: true, failureMessage: nil) }
        catch { return .init(sourceFileDeleted: false, failureMessage: error.localizedDescription) }
    }
    static func synchronizeDirectory(after value: Prepared) -> Outcome { .init(sourceFileDeleted: true, failureMessage: nil) }
}

/// Stops only the fixture's file-identity preparation leaf. The actual service
/// must recheck its record and caller permission after this worker returns.
nonisolated final class DeletionProbe: @unchecked Sendable {
    static let shared = DeletionProbe()
    private let lock = NSLock()
    private var gate: DispatchSemaphore?
    private var entered = false
    private var unlinks = 0

    func arm() { lock.lock(); gate = DispatchSemaphore(value: 0); entered = false; lock.unlock() }
    func pausePreparation() {
        lock.lock(); let current = gate; if current != nil { entered = true }; lock.unlock()
        if let current { _ = current.wait(timeout: .now() + 5) }
    }
    func release() { lock.lock(); let current = gate; gate = nil; lock.unlock(); current?.signal() }
    var hasEntered: Bool { lock.lock(); defer { lock.unlock() }; return entered }
    var unlinkCount: Int { lock.lock(); defer { lock.unlock() }; return unlinks }
    func recordUnlink() { lock.lock(); unlinks += 1; lock.unlock() }
}

struct ImportedVideoPlaybackAdmission { static let notificationUserInfoKey = "fixture-admission" }
struct PlaybackResourceLifetime {}

/// Cancellation can deliberately lose a race to a completed response. This
/// models transport completion already queued when a consumer revokes scope.
@MainActor final class SourceProbe {
    static let shared = SourceProbe()
    struct Pending {
        let key: String
        let ordinal: Int
        let continuation: CheckedContinuation<OnlineImageArtwork, Error>
    }
    private var pending: [UUID: Pending] = [:]
    private(set) var events: [String] = []
    private(set) var starts: [String: Int] = [:]
    private(set) var cancellations: [String: Int] = [:]
    var ignoreCancellation = Set<String>()
    var resolvedAssets: [OnlineImageAsset] = []
    var heldAssetKeys = Set<String>()
    private(set) var pendingAssets: [String: CheckedContinuation<[OnlineImageAsset], Error>] = [:]

    func detail(source: OnlineImageSource, id: String) async throws -> OnlineImageArtwork {
        let key = source.rawValue + ":" + id, token = UUID()
        starts[key, default: 0] += 1
        events.append("detail:" + key)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { pending[token] = .init(key: key, ordinal: starts[key]!, continuation: $0) }
        } onCancel: { Task { @MainActor in self.cancel(token, key: key) } }
    }

    private func cancel(_ token: UUID, key: String) {
        cancellations[key, default: 0] += 1
        guard !ignoreCancellation.contains(key), let value = pending.removeValue(forKey: token) else { return }
        value.continuation.resume(throwing: CancellationError())
    }

    func resolve(_ key: String, title: String = "resolved", latest: Bool = false) {
        let candidates = pending.filter { $0.value.key == key }.sorted { $0.value.ordinal < $1.value.ordinal }
        guard let (token, value) = latest ? candidates.last : candidates.first else { return }
        pending.removeValue(forKey: token)
        let pieces = key.split(separator: ":", maxSplits: 1).map(String.init)
        value.continuation.resume(returning: artwork(OnlineImageSource(rawValue: pieces[0])!, pieces[1], title: title))
    }

    func assets(for value: OnlineImageArtwork) async throws -> [OnlineImageAsset] {
        events.append("assets:" + value.id + ":" + value.kind.rawValue)
        guard value.kind == .image, value.originalURL != nil else { throw OnlineImageError.unsupported }
        if heldAssetKeys.contains(value.id) {
            return try await withCheckedThrowingContinuation { pendingAssets[value.id] = $0 }
        }
        return resolvedAssets
    }

    func resolveAssets(_ key: String, values: [OnlineImageAsset]) {
        heldAssetKeys.remove(key)
        pendingAssets.removeValue(forKey: key)?.resume(returning: values)
    }
}

/// No URLSession delegate or socket is used. Completion is delivered from a
/// background queue, and actual generated bytes enter the service's ImageIO.
nonisolated final class TransferProbe: @unchecked Sendable {
    static let shared = TransferProbe()
    struct Entry {
        let key: String
        let staging: URL
        let completion: (Result<URL, Error>) -> Void
    }
    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]
    private var preCancelled = Set<UUID>()
    private var startCounts: [String: Int] = [:]
    private var cancelCounts: [String: Int] = [:]
    private var ignoreCancellation = Set<String>()
    private var maximum = 0

    func begin(_ token: UUID, request: URLRequest, staging: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let key = request.url!.lastPathComponent
        lock.lock()
        startCounts[key, default: 0] += 1
        let cancelled = preCancelled.remove(token) != nil
        if !cancelled { entries[token] = .init(key: key, staging: staging, completion: completion) }
        maximum = max(maximum, entries.count)
        lock.unlock()
        if cancelled { completion(.failure(URLError(.cancelled))) }
    }

    func cancel(_ token: UUID) {
        lock.lock()
        guard let value = entries[token] else { preCancelled.insert(token); lock.unlock(); return }
        cancelCounts[value.key, default: 0] += 1
        if ignoreCancellation.contains(value.key) { lock.unlock(); return }
        entries.removeValue(forKey: token)
        lock.unlock()
        DispatchQueue.global().async { value.completion(.failure(URLError(.cancelled))) }
    }

    @discardableResult func finish(_ key: String, bytes: Data) -> Bool {
        lock.lock()
        guard let (token, value) = entries.first(where: { $0.value.key == key }) else { lock.unlock(); return false }
        entries.removeValue(forKey: token)
        lock.unlock()
        DispatchQueue.global().async {
            do { try bytes.write(to: value.staging); value.completion(.success(value.staging)) }
            catch { value.completion(.failure(error)) }
        }
        return true
    }

    func ignoreCancel(for key: String) { lock.lock(); ignoreCancellation.insert(key); lock.unlock() }
    func starts(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return startCounts[key, default: 0] }
    func cancels(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return cancelCounts[key, default: 0] }
    var activeCount: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    var maxActive: Int { lock.lock(); defer { lock.unlock() }; return maximum }
    func resetMaximum() { lock.lock(); maximum = entries.count; lock.unlock() }
}

nonisolated final class WallpaperFileTransfer: @unchecked Sendable {
    private let token = UUID()
    private let staging: URL
    init(expectedBytes: Int64, stagingURL: URL, configuration: URLSessionConfiguration? = nil,
         allowedHosts: Set<String>? = nil, progressHandler: @escaping @MainActor (Double) -> Void) {
        staging = stagingURL
    }
    func start(request: URLRequest, completion: @escaping (Result<URL, Error>) -> Void) {
        TransferProbe.shared.begin(token, request: request, staging: staging, completion: completion)
    }
    func cancel() { TransferProbe.shared.cancel(token) }
}

@MainActor private func artwork(_ source: OnlineImageSource, _ id: String, title: String = "fixture") -> OnlineImageArtwork {
    .init(source: source, artworkID: id, title: title, sourceURL: URL(string: "https://example.invalid/work/" + id)!,
          originalURL: URL(string: "https://example.invalid/original/" + id)!, kind: .image)
}

@MainActor private func asset(_ source: OnlineImageSource, _ id: String, page: Int = 0) -> OnlineImageAsset {
    .init(id: .init(source: source, artworkID: id, pageIndex: page), title: "fixture-" + id,
          sourceURL: URL(string: "https://example.invalid/work/" + id)!,
          originalURL: URL(string: "https://example.invalid/original/" + id)!)
}

@main @MainActor struct OnlineImageLibraryHarness {
    struct Failure: Error { let description: String }
    static var checks: [String: Bool] = [:]
    static let transfer = TransferProbe.shared
    static let source = SourceProbe.shared
    static var root: URL!
    static var png = Data()

    static func check(_ name: String, _ value: Bool) { checks[name] = value }

    static func eventually(_ label: String, _ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<1000 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw Failure(description: "Timed out: " + label)
    }

    static func settle() async throws { for _ in 0..<8 { await Task.yield() }; try await Task.sleep(for: .milliseconds(20)) }

    static func library(_ name: String) async throws -> OnlineImageLibrary {
        let value = OnlineImageLibrary(root: root.appendingPathComponent(name, isDirectory: true))
        try await eventually("initial scan " + name) { value.snapshot.status.hasSuccessfulScan }
        return value
    }

    static func drained(_ value: OnlineImageLibrary, _ label: String) async throws {
        try await eventually("download drained " + label) { value.progress.isEmpty }
    }

    static func resultWasCancelled(_ task: Task<OnlineImageArtwork, Error>) async -> Bool {
        do { _ = try await task.value; return false } catch is CancellationError { return true } catch { return false }
    }

    static func makePNG() throws -> Data {
        guard let context = CGContext(data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure(description: "CGContext")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        let data = NSMutableData()
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure(description: "PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure(description: "PNG encoding") }
        return data as Data
    }

    static func detailConsumers() async throws {
        let value = try await library("detail-consumers"), item = artwork(.wallhaven, "detail-shared")
        let first = Task { try await value.detail(item) }
        try await eventually("first shared detail") { source.starts[item.id] == 1 }
        let second = Task { try await value.detail(item) }
        try await settle()
        first.cancel()
        try await settle()
        check("one-detail-consumer-cancellation-keeps-shared-inner-request", source.cancellations[item.id, default: 0] == 0)
        source.resolve(item.id)
        let secondValue = try await second.value
        check("remaining-detail-consumer-receives-result", secondValue.artworkID == item.artworkID)
        check("cancelled-detail-consumer-does-not-receive-result", await resultWasCancelled(first))
        _ = try await value.detail(item)
        check("successful-detail-is-shared-and-cached", source.starts[item.id] == 1)

        let lastItem = artwork(.wallhaven, "detail-last"), last = Task { try await value.detail(lastItem) }
        try await eventually("last detail started") { source.starts[lastItem.id] == 1 }
        last.cancel()
        try await eventually("inner detail cancelled") { source.cancellations[lastItem.id, default: 0] == 1 }
        check("last-detail-consumer-cancels-inner-request", await resultWasCancelled(last))
        let replacement = Task { try await value.detail(lastItem) }
        try await eventually("replacement detail") { source.starts[lastItem.id] == 2 }
        source.resolve(lastItem.id, title: "new-request")
        check("cancelled-detail-is-not-reused", try await replacement.value.title == "new-request")
    }

    static func concurrentDownloads() async throws {
        let value = try await library("concurrency")
        transfer.resetMaximum()
        let a = asset(.wallhaven, "queue-a"), b = asset(.wallhaven, "queue-b")
        let cancelled = asset(.wallhaven, "queue-cancel"), next = asset(.wallhaven, "queue-next")
        value.download(a); value.download(b)
        try await eventually("two download slots") { transfer.activeCount == 2 }
        value.download(cancelled); value.download(next)
        try await settle()
        check("third-and-fourth-downloads-wait-for-two-slots", transfer.starts("queue-cancel") == 0 && transfer.starts("queue-next") == 0)
        value.cancel(cancelled.id)
        try await eventually("queued cancellation") { value.progress[cancelled.id] == nil }
        transfer.finish("queue-a", bytes: png)
        try await eventually("next queued download starts") { transfer.starts("queue-next") == 1 }
        transfer.finish("queue-b", bytes: png); transfer.finish("queue-next", bytes: png)
        try await drained(value, "concurrency")
        check("download-concurrency-never-exceeds-two", transfer.maxActive == 2)
        check("cancelled-queued-download-never-starts-or-publishes", transfer.starts("queue-cancel") == 0 && value.record(for: cancelled.id.reference) == nil)
        check("uncancelled-queued-downloads-publish", value.snapshot.records.count == 3)
    }

    static func playbackIntentAndCommit() async throws {
        for revokedByStop in [false, true] {
            let suffix = revokedByStop ? "stop" : "new-intent"
            let value = try await library("intent-" + suffix), item = asset(.wallhaven, "intent-" + suffix)
            let gate = ImportedVideoAutoplayGate()
            var playback: [WallpaperReference] = []
            value.captureApplyIntent = { let token = gate.claim(); return { gate.isCurrent(token) } }
            value.requestLibraryPlayback = { playback.append($0) }
            value.download(item, apply: true)
            try await eventually("intent download " + suffix) { transfer.starts(item.id.artworkID) == 1 }
            if revokedByStop { gate.invalidate() } else { _ = gate.claim() }
            transfer.finish(item.id.artworkID, bytes: png)
            try await drained(value, suffix)
            check("download-after-" + suffix + "-retains-publication", value.record(for: item.id.reference) != nil)
            check("download-after-" + suffix + "-cannot-take-desktop", playback.isEmpty)
        }

        let value = try await library("commit-cancel"), item = asset(.wallhaven, "commit-cancel")
        let gate = ImportedVideoAutoplayGate()
        var playback: [WallpaperReference] = []
        value.captureApplyIntent = { let token = gate.claim(); return { gate.isCurrent(token) } }
        value.requestLibraryPlayback = { playback.append($0) }
        let observation = value.$snapshot.sink { snapshot in
            if snapshot.records.contains(where: { $0.id == item.id }) { value.cancel(item.id) }
        }
        value.download(item, apply: true)
        try await eventually("postcommit cancel transfer") { transfer.starts("commit-cancel") == 1 }
        transfer.finish("commit-cancel", bytes: png)
        try await drained(value, "postcommit cancel")
        let record = value.record(for: item.id.reference)
        let committed = record.flatMap { value.localURL(for: $0) }
        check("cancel-at-publication-keeps-committed-file-and-receipt", committed.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        check("cancel-at-publication-suppresses-automatic-apply", playback.isEmpty)
        observation.cancel()
        let content = value.content(for: item.id.reference)
        check("real-imageio-publication-projects-local-capabilities", record?.pixelWidth == 3 && record?.pixelHeight == 2 && content?.capabilities.contains([.play, .organize, .export]) == true)
        value.download(item, apply: true)
        check("explicit-apply-of-existing-local-file-is-immediate", playback == [item.id.reference] && transfer.starts("commit-cancel") == 1)
        let positive = asset(.wallhaven, "current-intent")
        value.download(positive, apply: true)
        try await eventually("current intent transfer") { transfer.starts("current-intent") == 1 }
        transfer.finish("current-intent", bytes: png)
        try await drained(value, "current intent")
        check("current-uncancelled-intent-applies-after-real-publication", playback == [item.id.reference, positive.id.reference] && value.record(for: positive.id.reference) != nil)
    }

    static func duplicateAndInvalidBytes() async throws {
        let value = try await library("duplicate-invalid"), item = asset(.wallhaven, "duplicate")
        value.download(item); value.download(item, apply: true)
        try await eventually("deduplicated transfer") { transfer.starts("duplicate") == 1 }
        try await settle()
        check("same-asset-downloads-use-one-transfer", transfer.starts("duplicate") == 1 && value.progress.count == 1)
        transfer.finish("duplicate", bytes: png)
        try await drained(value, "duplicate")
        guard let old = value.record(for: item.id.reference), let file = value.localURL(for: old) else { throw Failure(description: "missing old receipt") }
        let goodManifest = try Data(contentsOf: value.root.appendingPathComponent("manifest.json"))
        let bad = asset(.wallhaven, "bad-image")
        value.download(bad)
        try await eventually("bad-image transfer") { transfer.starts("bad-image") == 1 }
        transfer.finish("bad-image", bytes: Data("<html>not an image</html>".utf8))
        try await drained(value, "bad image")
        check("bad-image-does-not-create-local-receipt", value.record(for: bad.id.reference) == nil && value.errorMessage != nil)
        check("bad-image-leaves-existing-manifest-and-bytes-unchanged", try Data(contentsOf: value.root.appendingPathComponent("manifest.json")) == goodManifest && Data(contentsOf: file) == png)

        try FileManager.default.removeItem(at: file)
        value.refreshLocal()
        try await eventually("missing local scan") { value.snapshot.unavailable.contains(item.id) }
        value.download(item)
        try await eventually("replacement transfer") { transfer.starts("duplicate") == 2 }
        transfer.finish("duplicate", bytes: Data([0, 1, 2, 3]))
        try await drained(value, "invalid replacement")
        check("invalid-replacement-preserves-old-record-and-revision", value.record(for: item.id.reference) == old && value.snapshot.unavailable.contains(item.id))
        check("unavailable-local-projection-offers-retry-without-play", value.content(for: item.id.reference)?.capabilities.contains(.retryDownload) == true && value.content(for: item.id.reference)?.capabilities.contains(.play) == false)
    }

    static func artworkIntentBeforeDetail() async throws {
        let value = try await library("artwork-intent-detail")
        let shell = artwork(.wallhaven, "artwork-delayed-detail")
        let item = asset(.wallhaven, shell.artworkID)
        let gate = ImportedVideoAutoplayGate()
        var playback: [WallpaperReference] = []
        var captures = 0
        value.captureApplyIntent = {
            captures += 1
            let token = gate.claim()
            return { gate.isCurrent(token) }
        }
        value.requestLibraryPlayback = { playback.append($0) }
        source.resolvedAssets = [item]
        value.downloadArtwork(shell, apply: true)
        let capturedAtClick = captures == 1
        try await eventually("artwork detail remains pending") { source.starts[shell.id] == 1 }
        let waitsForDetail = transfer.starts(item.id.artworkID) == 0
        _ = gate.claim() // The user chooses B while A's detail is still pending.
        source.resolve(shell.id)
        try await eventually("artwork download after delayed detail") { transfer.starts(item.id.artworkID) == 1 }
        transfer.finish(item.id.artworkID, bytes: png)
        try await drained(value, "artwork delayed detail")
        check("download-artwork-delayed-detail-cannot-reclaim-desktop-after-new-intent",
              capturedAtClick && waitsForDetail && captures == 1 && playback.isEmpty && value.record(for: item.id.reference) != nil)
    }

    static func retryAndScanFailure() async throws {
        let value = try await library("retry-scan"), item = asset(.pixiv, "retry-pages", page: 1)
        _ = await value.preparePixiv()
        value.download(item)
        try await eventually("retry initial transfer") { transfer.starts("retry-pages") == 1 }
        transfer.finish("retry-pages", bytes: png)
        try await drained(value, "retry initial")
        let old = value.record(for: item.id.reference)!
        try FileManager.default.removeItem(at: value.localURL(for: old)!)
        value.refreshLocal()
        try await eventually("retry unavailable scan") { value.snapshot.unavailable.contains(item.id) }
        source.resolvedAssets = [asset(.pixiv, "retry-pages"), item]
        let eventStart = source.events.count
        value.retry(item.id.reference)
        try await eventually("retry requests detail") { source.starts["pixiv:retry-pages"] == 1 }
        check("missing-local-retry-waits-for-detail-before-assets", !source.events.dropFirst(eventStart).contains(where: { $0.hasPrefix("assets:") }) && transfer.starts("retry-pages") == 1)
        source.resolve("pixiv:retry-pages")
        try await eventually("retry starts exact page transfer") { transfer.starts("retry-pages") == 2 }
        check("missing-local-retry-resolves-detail-before-assets", Array(source.events.dropFirst(eventStart)).prefix(2) == ["detail:pixiv:retry-pages", "assets:pixiv:retry-pages:image"])
        transfer.finish("retry-pages", bytes: png)
        try await drained(value, "retry restored")
        check("missing-local-retry-restores-exact-page-identity", value.record(for: item.id.reference)?.id == item.id && value.record(for: item.id.reference)?.revision != old.revision && !value.snapshot.unavailable.contains(item.id) && value.snapshot.records.count == 1)

        let manifestURL = value.root.appendingPathComponent("manifest.json"), goodManifest = try Data(contentsOf: manifestURL)
        let revision = value.snapshot.revision, records = value.snapshot.records
        try Data("broken manifest".utf8).write(to: manifestURL)
        value.refreshLocal()
        try await eventually("failed scan status") { if case .failed = value.snapshot.status.phase { return true }; return false }
        check("failed-scan-does-not-invent-store-revision", value.snapshot.revision == revision && value.snapshot.records == records && value.snapshot.status.hasSuccessfulScan)
        try goodManifest.write(to: manifestURL)
        let next = asset(.wallhaven, "after-failed-scan")
        value.download(next)
        try await eventually("download after failed scan") { transfer.starts("after-failed-scan") == 1 }
        transfer.finish("after-failed-scan", bytes: png)
        try await drained(value, "after failed scan")
        check("next-real-publication-is-accepted-after-failed-scan", value.record(for: next.id.reference) != nil && value.snapshot.revision > revision)
    }

    static func visibilityRevocation(_ imageSource: OnlineImageSource) async throws {
        let name = imageSource.rawValue, value = try await library("revocation-" + name)
        if imageSource == .pixiv { _ = await value.preparePixiv() }
        let cachedItem = artwork(imageSource, "cached-detail-" + name)
        let initialCache = Task { try await value.detail(cachedItem) }
        try await eventually("initial cached detail " + name) { source.starts[cachedItem.id] == 1 }
        source.resolve(cachedItem.id, title: "cached-old-scope")
        _ = try await initialCache.value
        _ = try await value.detail(cachedItem)
        check(name + "-same-scope-detail-cache-is-used", source.starts[cachedItem.id] == 1)
        let detailItem = artwork(imageSource, "revoked-detail-" + name)
        let item = asset(imageSource, "revoked-download-" + name)
        source.ignoreCancellation.insert(detailItem.id)
        transfer.ignoreCancel(for: item.id.artworkID)
        let oldDetail = Task { try await value.detail(detailItem) }
        try await eventually("old scoped detail " + name) { source.starts[detailItem.id] == 1 }
        value.download(item)
        try await eventually("old scoped transfer " + name) { transfer.starts(item.id.artworkID) == 1 }
        if imageSource == .pixiv { value.pixivSession!.revokeScope() }
        else { try await value.setWallhavenKey("fixture-new-key") }
        try await settle()
        check(name + "-visibility-change-cancels-old-inner-detail", source.cancellations[detailItem.id, default: 0] == 1)
        check(name + "-visibility-change-cancels-uncommitted-download", transfer.cancels(item.id.artworkID) == 1)
        source.resolve(detailItem.id, title: "old-scope")
        check(name + "-late-old-detail-is-rejected", await resultWasCancelled(oldDetail))
        transfer.finish(item.id.artworkID, bytes: png)
        try await drained(value, "revoked transfer " + name)
        check(name + "-late-old-download-is-not-published", value.record(for: item.id.reference) == nil)

        let currentCache = Task { try await value.detail(cachedItem) }
        try await eventually("cached detail refetched after scope change " + name) { source.starts[cachedItem.id] == 2 }
        source.resolve(cachedItem.id, title: "cache-current-scope")
        check(name + "-visibility-change-invalidates-completed-detail-cache", try await currentCache.value.title == "cache-current-scope")

        let current = Task { try await value.detail(detailItem) }
        try await eventually("new scoped detail " + name) { source.starts[detailItem.id] == 2 }
        source.resolve(detailItem.id, title: "current-scope")
        let fresh = try await current.value
        _ = try await value.detail(detailItem)
        check(name + "-old-detail-cache-cannot-satisfy-new-scope", fresh.title == "current-scope" && source.starts[detailItem.id] == 2)
        value.download(item)
        try await eventually("new scoped transfer " + name) { transfer.starts(item.id.artworkID) == 2 }
        transfer.finish(item.id.artworkID, bytes: png)
        try await drained(value, "new scoped transfer " + name)
        check(name + "-new-scope-can-download-same-asset", value.record(for: item.id.reference) != nil)
    }

    static func concurrentPixivPreparation() async throws {
        let value = try await library("pixiv-first-preparation")
        let cookieSnapshot = PixivPreparationProbe()
        PixivSession.nextPreparation = cookieSnapshot
        let firstItem = artwork(.pixiv, "first-cookie-detail")
        let secondItem = artwork(.pixiv, "second-cookie-download")
        let secondAsset = asset(.pixiv, secondItem.artworkID)
        source.resolvedAssets = [secondAsset]
        let firstDetail = Task { try await value.detail(firstItem) }
        try await eventually("first persisted-cookie snapshot waits") { cookieSnapshot.isWaiting }
        value.downloadArtwork(secondItem)
        let secondPreparation = Task { await value.preparePixiv() }
        try await settle()
        check("concurrent-first-pixiv-consumers-wait-for-cookie-preparation",
              source.starts[firstItem.id, default: 0] == 0 && source.starts[secondItem.id, default: 0] == 0
              && transfer.starts(secondAsset.id.artworkID) == 0)
        cookieSnapshot.release()
        let client = await secondPreparation.value
        let reusedClient = await value.preparePixiv()
        check("first-pixiv-preparation-is-shared-with-one-cookie-refresh", client === reusedClient && cookieSnapshot.refreshCalls == 1)
        let preparedHandle = value.pixivSession!.urlSession
        let clientSharesHandle = await client.usesSession(preparedHandle)
        let thumbnail = value.thumbnailRequest(url: URL(string: "https://i.pximg.net/fixture.jpg")!, source: .pixiv)
        check("prepared-pixiv-client-and-thumbnail-share-the-session-owned-network-handle",
              clientSharesHandle && thumbnail.session === preparedHandle)
        try await eventually("both consumers use prepared scope") { source.starts[firstItem.id] == 1 && source.starts[secondItem.id] == 1 }
        source.resolve(firstItem.id); source.resolve(secondItem.id)
        let detail = try await firstDetail.value
        check("first-persisted-cookie-detail-survives-initial-scope-change", detail.artworkID == firstItem.artworkID && value.pixivScope != "pixiv-anonymous")
        try await eventually("bootstrap download starts after scope binding") { transfer.starts(secondAsset.id.artworkID) == 1 }
        transfer.finish(secondAsset.id.artworkID, bytes: png)
        try await drained(value, "concurrent persisted-cookie preparation")
        check("concurrent-bootstrap-download-publishes-under-prepared-scope", value.record(for: secondAsset.id.reference) != nil)
    }

    static func logoutDuringPixivPreparation() async throws {
        let value = try await library("pixiv-bootstrap-logout")
        let cookieSnapshot = PixivPreparationProbe()
        PixivSession.nextPreparation = cookieSnapshot
        let detailItem = artwork(.pixiv, "logout-bootstrap-detail")
        let firstItem = artwork(.pixiv, "logout-bootstrap-download-a")
        let secondItem = artwork(.pixiv, "logout-bootstrap-download-b")
        var detailWasCancelled: Bool?
        let pendingDetail = Task {
            do { _ = try await value.detail(detailItem); detailWasCancelled = false }
            catch is CancellationError { detailWasCancelled = true }
            catch { detailWasCancelled = false }
        }
        try await eventually("logout holds initial cookie preparation") { cookieSnapshot.isWaiting }
        value.downloadArtwork(firstItem); value.downloadArtwork(secondItem)
        try await settle()
        await value.logoutPixiv()
        cookieSnapshot.release()
        try await eventually("detail settles after bootstrap logout") {
            detailWasCancelled != nil || source.starts[detailItem.id, default: 0] != 0
        }
        // Drain an incorrectly resumed request before reporting the failed
        // assertion, so a real regression never leaks a fixture continuation.
        if source.starts[detailItem.id, default: 0] != 0 { source.resolve(detailItem.id) }
        await pendingDetail.value
        try await drained(value, "logout bootstrap downloads")
        check("explicit-logout-revokes-bootstrap-downloads-before-any-source-request",
              source.starts[firstItem.id, default: 0] == 0 && source.starts[secondItem.id, default: 0] == 0
              && transfer.starts(firstItem.artworkID) == 0 && transfer.starts(secondItem.artworkID) == 0
              && value.snapshot.records.isEmpty)
        check("explicit-logout-revokes-detail-consumer-waiting-for-first-preparation",
              detailWasCancelled == true && source.starts[detailItem.id, default: 0] == 0)
        check("late-cookie-preparation-cannot-undo-explicit-logout", cookieSnapshot.logoutCalls == 1 && value.pixivScope == "pixiv-anonymous")
    }

    static func save(_ item: OnlineImageAsset, in value: OnlineImageLibrary) async throws -> OnlineImageLocalRecord {
        let expectedStarts = transfer.starts(item.id.artworkID) + 1
        value.download(item)
        try await eventually("save " + item.id.artworkID) { transfer.starts(item.id.artworkID) == expectedStarts }
        transfer.finish(item.id.artworkID, bytes: png)
        try await drained(value, item.id.artworkID)
        guard let record = value.record(for: item.id.reference) else { throw Failure(description: "missing saved record") }
        return record
    }

    static func logoutAssetsAndAnonymousRequests() async throws {
        let preparing = try await library("pixiv-assets-bootstrap-logout")
        let cookieSnapshot = PixivPreparationProbe()
        PixivSession.nextPreparation = cookieSnapshot
        let firstItem = artwork(.pixiv, "logout-assets-preparation")
        let eventStart = source.events.count
        var preparationWasCancelled = false
        let pendingAssets = Task {
            do { _ = try await preparing.assets(for: firstItem) }
            catch is CancellationError { preparationWasCancelled = true }
            catch { }
        }
        try await eventually("assets waits for first cookie preparation") { cookieSnapshot.isWaiting }
        await preparing.logoutPixiv()
        cookieSnapshot.release()
        await pendingAssets.value
        check("explicit-logout-revokes-assets-waiting-for-first-preparation",
              preparationWasCancelled && !source.events.dropFirst(eventStart).contains("assets:" + firstItem.id + ":image"))

        let value = try await library("pixiv-anonymous-logout-results")
        _ = await value.preparePixiv()
        let item = artwork(.pixiv, "logout-assets-result"), oldAsset = asset(.pixiv, "logout-assets-result")
        source.heldAssetKeys.insert(item.id)
        let oldAssets = Task { try await value.assets(for: item) }
        try await eventually("old anonymous assets pending") { source.pendingAssets[item.id] != nil }
        let anonymousScope = value.pixivScope
        await value.logoutPixiv()
        source.resolveAssets(item.id, values: [oldAsset])
        var lateAssetsWereCancelled = false
        do { _ = try await oldAssets.value } catch is CancellationError { lateAssetsWereCancelled = true }
        check("explicit-logout-rejects-late-assets-even-when-anonymous-scope-id-is-unchanged",
              lateAssetsWereCancelled && value.pixivScope == anonymousScope)
        source.resolvedAssets = [oldAsset]
        let currentAssets = try await value.assets(for: item)
        check("new-anonymous-assets-request-is-allowed-after-logout", currentAssets == [oldAsset])

        let detailItem = artwork(.pixiv, "logout-anonymous-detail")
        source.ignoreCancellation.insert(detailItem.id)
        let oldDetail = Task { try await value.detail(detailItem) }
        try await eventually("old anonymous detail pending") { source.starts[detailItem.id] == 1 }
        await value.logoutPixiv()
        let newDetail = Task { try await value.detail(detailItem) }
        try await settle()
        let startedNewRequest = source.starts[detailItem.id] == 2
        if startedNewRequest {
            source.resolve(detailItem.id, title: "current-anonymous", latest: true)
        } else {
            source.resolve(detailItem.id, title: "late-prior-anonymous")
        }
        let fresh = try? await newDetail.value
        if startedNewRequest { source.resolve(detailItem.id, title: "late-prior-anonymous") }
        check("explicit-logout-rejects-old-anonymous-detail-result", await resultWasCancelled(oldDetail))
        check("new-anonymous-detail-cannot-reuse-prior-logout-request",
              startedNewRequest && fresh?.title == "current-anonymous")

        let otherItem = artwork(.wallhaven, "wallhaven-during-pixiv-logout")
        let otherDetail = Task { try await value.detail(otherItem) }
        try await eventually("Wallhaven detail before Pixiv logout") { source.starts[otherItem.id] == 1 }
        await value.logoutPixiv()
        source.resolve(otherItem.id)
        check("pixiv-logout-does-not-reject-unrelated-wallhaven-detail", try await otherDetail.value.artworkID == otherItem.artworkID)
    }

    static func deletionWasRejected(_ task: Task<Void, Error>) async -> Bool {
        do { try await task.value; return false }
        catch OnlineImageError.message { return true }
        catch { return false }
    }

    static func deletionAdmission() async throws {
        let value = try await library("deletion-admission"), probe = DeletionProbe.shared
        let resetItem = asset(.wallhaven, "delete-reset")
        let resetRecord = try await save(resetItem, in: value)
        let resetURL = value.localURL(for: resetRecord)!
        var epoch = 1
        let admittedEpoch = epoch, beforeResetUnlinks = probe.unlinkCount
        probe.arm()
        let resetDeletion = Task {
            try await value.delete(resetItem.id.reference, expectedRevision: resetRecord.revision,
                                   permitsDeletion: { epoch == admittedEpoch })
        }
        try await eventually("deletion preparation before reset") { probe.hasEntered }
        epoch += 1
        probe.release()
        let resetRejected = await deletionWasRejected(resetDeletion)
        check("reset-during-file-preparation-revokes-final-unlink",
              resetRejected && probe.unlinkCount == beforeResetUnlinks
              && value.record(for: resetItem.id.reference) == resetRecord && FileManager.default.fileExists(atPath: resetURL.path))

        let revisionItem = asset(.pixiv, "delete-revision", page: 1)
        _ = await value.preparePixiv()
        let old = try await save(revisionItem, in: value)
        let oldURL = value.localURL(for: old)!, beforeRevisionUnlinks = probe.unlinkCount
        probe.arm()
        let revisionDeletion = Task { try await value.delete(revisionItem.id.reference, expectedRevision: old.revision) }
        try await eventually("deletion preparation before replacement") { probe.hasEntered }
        try FileManager.default.removeItem(at: oldURL)
        value.refreshLocal()
        try await eventually("replacement marks old image missing") { value.snapshot.unavailable.contains(revisionItem.id) }
        let replacement = try await save(revisionItem, in: value)
        let replacementURL = value.localURL(for: replacement)!
        probe.release()
        let revisionRejected = await deletionWasRejected(revisionDeletion)
        check("replacement-during-file-preparation-revokes-old-delete",
              revisionRejected && probe.unlinkCount == beforeRevisionUnlinks && replacement.revision != old.revision
              && value.record(for: revisionItem.id.reference) == replacement && FileManager.default.fileExists(atPath: replacementURL.path))
        let staleDeletion = Task { try await value.delete(revisionItem.id.reference, expectedRevision: old.revision) }
        check("delete-confirmed-old-revision-cannot-delete-new-publication",
              await deletionWasRejected(staleDeletion) && probe.unlinkCount == beforeRevisionUnlinks
              && value.record(for: revisionItem.id.reference) == replacement)
        try await value.delete(revisionItem.id.reference, expectedRevision: replacement.revision)
        check("current-permitted-delete-removes-only-its-file-and-manifest-record",
              value.record(for: revisionItem.id.reference) == nil && !FileManager.default.fileExists(atPath: replacementURL.path)
              && value.record(for: resetItem.id.reference) == resetRecord && FileManager.default.fileExists(atPath: resetURL.path))
    }

    static func main() async {
        do {
            root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            png = try makePNG()
            try await detailConsumers()
            try await concurrentDownloads()
            try await playbackIntentAndCommit()
            try await artworkIntentBeforeDetail()
            try await duplicateAndInvalidBytes()
            try await retryAndScanFailure()
            try await visibilityRevocation(.pixiv)
            try await visibilityRevocation(.wallhaven)
            try await concurrentPixivPreparation()
            try await logoutDuringPixivPreparation()
            try await logoutAssetsAndAnonymousRequests()
            try await deletionAdmission()
            check("all-controlled-transfers-drained", transfer.activeCount == 0)
            print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
            if checks.values.contains(false) { exit(1) }
        } catch {
            print(String(data: (try? JSONEncoder().encode(checks)) ?? Data(), encoding: .utf8) ?? "{}")
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
