import Combine
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The two image sources share one publication owner. Browser rows are never a second local index.
@MainActor final class OnlineImageLibrary: ObservableObject {
    static let shared = OnlineImageLibrary()
    @Published private(set) var snapshot = OnlineImageLocalSnapshot()
    @Published private(set) var progress: [OnlineImageAssetID: Double] = [:]
    let downloadTasksDidChange = PassthroughSubject<Void, Never>()
    let downloadTerminals = PassthroughSubject<DownloadTerminalReceipt, Never>()
    @Published var errorMessage: String?
    @Published private(set) var wallhavenCredentialRevision: UInt64 = 0
    @Published private(set) var wallhavenAccount: WallhavenAccountInfo = .unread
    private var wallhavenAccountTask: Task<Void, Never>?
    let root: URL
    private let legacyRoot: URL?
    var downloadRoots: [URL] { [root.appendingPathComponent("Wallhaven"), root.appendingPathComponent("Pixiv")] + [legacyRoot].compactMap { $0 } }
    let wallhaven = WallhavenClient()
    private(set) var pixiv: PixivClient?
    @Published private(set) var pixivSession: PixivSession?
    private let store: OnlineImageLibraryStore
    private let originalCacheRoot: URL
    private var originalCacheClearTask: Task<Void, Never>?
    private let credentials = WallhavenCredentialStore()
    private var credentialPreparation: Task<Bool, Never>?
    private var wallhavenCacheScope = "wallhaven-public"
    private var sessionSubscription: AnyCancellable?
    private var activeScope = "pixiv-anonymous"
    private var pixivTransport: WallpaperNetworkSession?
    private var pixivTransportUpdate: Task<Void, Never>?
    private var pixivPreparation: Task<Void, Never>?
    private var isPixivPrepared = false
    private var pixivLogoutEpoch: UInt64 = 0
    private var recordsByID: [OnlineImageAssetID: OnlineImageLocalRecord] = [:]
    private struct Transfer {
        let id: UUID
        let task: Task<Void, Never>
        var scope: String?
        var title: String
        var phase: DownloadTaskPhase
        var previewURL: URL?
        var cachedOriginalDirectory: URL?
        let createdAt: Date
    }
    struct DownloadActivity {
        let assetID: OnlineImageAssetID
        let attemptID: UUID
        let title: String
        let phase: DownloadTaskPhase
        let previewURL: URL?
        let createdAt: Date
    }
    private var transfers: [OnlineImageAssetID: Transfer] = [:]
    var activeDownloadCount: Int { transfers.count }
    var downloadActivities: [DownloadActivity] {
        let waitingOrder = Dictionary(uniqueKeysWithValues: waitingDownloads.enumerated().map { ($0.element.0, $0.offset) })
        return transfers.map { id, transfer in
            DownloadActivity(assetID: id, attemptID: transfer.id, title: transfer.title,
                             phase: transfer.phase, previewURL: transfer.previewURL, createdAt: transfer.createdAt)
        }.sorted {
            if ($0.phase == .queued) != ($1.phase == .queued) { return $0.phase != .queued }
            if $0.phase == .queued {
                let left = waitingOrder[$0.attemptID] ?? Int.max, right = waitingOrder[$1.attemptID] ?? Int.max
                if left != right { return left < right }
            }
            return $0.createdAt < $1.createdAt
        }
    }
    func downloadActivity(for id: OnlineImageAssetID) -> DownloadActivity? {
        guard let transfer = transfers[id] else { return nil }
        return DownloadActivity(assetID: id, attemptID: transfer.id, title: transfer.title,
            phase: transfer.phase, previewURL: transfer.previewURL, createdAt: transfer.createdAt)
    }
    private var details: [String: (Date, OnlineImageArtwork)] = [:]
    private struct DetailRequest {
        let id: UUID
        let task: Task<OnlineImageArtwork, Error>
        var consumers: Set<UUID>
    }
    private var detailTasks: [String: DetailRequest] = [:]
    private var activeDownloads = Set<UUID>()
    private var waitingDownloads: [(UUID, CheckedContinuation<Bool, Never>)] = []
    var requestLibraryPlayback: ((WallpaperReference) -> Void)?
    var captureApplyIntent: (() -> (() -> Bool))?
    var isFileInUse: ((String) -> Bool)?

    init(root: URL? = nil, originalCacheRoot: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
        legacyRoot = root == nil ? self.root.appendingPathComponent("在线图片", isDirectory: true) : nil
        store = OnlineImageLibraryStore(root: self.root, legacyRoot: legacyRoot,
            manifestName: root == nil ? "online-images.json" : "manifest.json")
        self.originalCacheRoot = originalCacheRoot ?? root?.appendingPathComponent(".quick-look-cache", isDirectory: true)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MyWallpaperX/OriginalPreviews", isDirectory: true)
        refreshLocal()
    }

    @discardableResult
    func refreshLocal() -> Task<Void, Never> {
        Task { [weak self, store] in
            do { let value = try await store.load(); self?.accept(value) }
            catch {
                guard let self else { return }
                snapshot.status = .init(phase: .failed(message: error.localizedDescription),
                    hasSuccessfulScan: snapshot.status.hasSuccessfulScan)
            }
        }
    }

    func prepareWallhaven() async -> WallhavenClient {
        if credentialPreparation == nil {
            credentialPreparation = Task { [weak self, credentials, wallhaven] in
                do {
                    let key = try await credentials.read()
                    let scope = Self.keyCacheScope(key)
                    self?.wallhavenCacheScope = scope
                    self?.wallhavenAccount = scope == "wallhaven-public" ? .unconfigured : .saved
                    await wallhaven.setAPIKey(key)
                    return true
                } catch { self?.errorMessage = error.localizedDescription; return false }
            }
        }
        _ = await credentialPreparation?.value
        return wallhaven
    }

    func setWallhavenKey(_ value: String?) async throws {
        _ = await prepareWallhaven()
        try await credentials.write(value)
        await wallhaven.setAPIKey(value)
        let scope = Self.keyCacheScope(value)
        if scope == wallhavenCacheScope {
            if scope == "wallhaven-public" { wallhavenAccount = .unconfigured }
            else { refreshWallhavenAccount() }
            return
        }
        wallhavenCacheScope = scope
        wallhavenAccountTask?.cancel(); wallhavenAccountTask = nil
        wallhavenCredentialRevision &+= 1
        wallhavenAccount = wallhavenCacheScope == "wallhaven-public" ? .unconfigured : .saved
        for (id, transfer) in transfers where id.source == .wallhaven { transfer.task.cancel() }
        details = details.filter { !$0.key.hasPrefix("wallhaven:") }
        for (key, request) in detailTasks where key.hasPrefix("wallhaven:") { request.task.cancel() }
        if wallhavenAccount.hasStoredKey == true { refreshWallhavenAccount() }
    }

    /// Only a deliberate save/refresh reads account metadata. The ordinary
    /// preparation path above restores the saved key without any account I/O.
    func refreshWallhavenAccount() {
        guard wallhavenAccountTask == nil else { return }
        let revision = wallhavenCredentialRevision
        wallhavenAccountTask = Task { [weak self] in
            guard let self else { return }
            defer { if revision == wallhavenCredentialRevision { wallhavenAccountTask = nil } }
            var client = await prepareWallhaven()
            // A failed read stays cached for ordinary browsing. Only this
            // deliberate account action retries it once; a successful save
            // already established the key and needs no read-back.
            if wallhavenAccount == .unread, await credentialPreparation?.value == false {
                credentialPreparation = nil
                client = await prepareWallhaven()
            }
            guard !Task.isCancelled, revision == wallhavenCredentialRevision,
                  wallhavenAccount.hasStoredKey == true else { return }
            wallhavenAccount = .loading
            do {
                let collections = try await client.collections()
                guard !Task.isCancelled, revision == wallhavenCredentialRevision else { return }
                wallhavenAccount = .ready(collections)
            } catch {
                guard !Task.isCancelled, revision == wallhavenCredentialRevision else { return }
                wallhavenAccount = .unavailable(error.localizedDescription)
            }
        }
    }

    func preparePixiv() async -> PixivClient {
        if let pixiv, let pixivSession {
            await pixivPreparation?.value
            await synchronizePixivTransport(pixiv, session: pixivSession)
            return pixiv
        }
        let session = PixivSession()
        pixivSession = session
        let client = PixivClient(session: session.urlSession)
        pixivTransport = session.urlSession
        pixiv = client
        activeScope = session.scopeID
        sessionSubscription = session.$state.dropFirst().receive(on: DispatchQueue.main).sink { [weak self, weak session] _ in
            guard let self, let session, session.scopeID != activeScope else { return }
            let previous = activeScope
            activeScope = session.scopeID
            for (id, transfer) in transfers where id.source == .pixiv && transfer.scope != nil && transfer.scope != activeScope { transfer.task.cancel() }
            details = details.filter { !$0.key.hasPrefix("pixiv:") || !$0.key.hasSuffix(":" + previous) }
            for (key, value) in detailTasks where key.hasPrefix("pixiv:") && key.hasSuffix(":" + previous) { value.task.cancel() }
            Task {
                await self.synchronizePixivTransport(client, session: session)
                await OnlineImageThumbnailCache.shared.invalidate(scopeID: previous)
            }
        }
        let preparation = Task {
            await session.refresh()
            await synchronizePixivTransport(client, session: session)
            activeScope = session.scopeID
            isPixivPrepared = true
        }
        pixivPreparation = preparation
        await preparation.value
        return client
    }

    private func synchronizePixivTransport(_ client: PixivClient, session: PixivSession) async {
        if pixivTransport !== session.urlSession {
            let transport = session.urlSession
            pixivTransport = transport
            let previous = pixivTransportUpdate
            pixivTransportUpdate = Task {
                await previous?.value
                await client.replaceSession(transport)
            }
        }
        await pixivTransportUpdate?.value
    }

    var pixivScope: String { pixivSession?.scopeID ?? "pixiv-anonymous" }

    func logoutPixiv() async {
        pixivLogoutEpoch &+= 1
        for (id, transfer) in transfers where id.source == .pixiv { transfer.task.cancel() }
        for key in Array(detailTasks.keys) where key.hasPrefix("pixiv:") {
            detailTasks.removeValue(forKey: key)?.task.cancel()
        }
        details = details.filter { !$0.key.hasPrefix("pixiv:") }
        guard let pixivSession else { return }
        await pixivSession.logout()
        if let pixiv { await synchronizePixivTransport(pixiv, session: pixivSession) }
    }

    func record(for reference: WallpaperReference) -> OnlineImageLocalRecord? {
        guard let id = OnlineImageAssetID(reference: reference) else { return nil }
        return recordsByID[id]
    }

    func localURL(for record: OnlineImageLocalRecord) -> URL? { try? store.fileURL(for: record) }

    func content(for reference: WallpaperReference) -> WallpaperContentItem? {
        guard let record = record(for: reference), let url = localURL(for: record) else { return nil }
        return OnlineImageContentProjection.local(record, url: url, available: !snapshot.unavailable.contains(record.id))
    }

    func detail(_ artwork: OnlineImageArtwork) async throws -> OnlineImageArtwork {
        try Task.checkCancellation()
        let logoutEpoch = pixivLogoutEpoch
        if artwork.source == .pixiv {
            _ = await preparePixiv()
            try Task.checkCancellation()
            guard logoutEpoch == pixivLogoutEpoch else { throw CancellationError() }
        }
        let scope = artwork.source == .pixiv ? pixivScope : "wallhaven-\(wallhavenCredentialRevision)"
        let key = artwork.id + ":" + scope
        if let cached = details[key], Date().timeIntervalSince(cached.0) < 1800 { return cached.1 }
        let consumer = UUID()
        let request: DetailRequest
        if var existing = detailTasks[key] {
            existing.consumers.insert(consumer); detailTasks[key] = existing; request = existing
        } else {
            let task = Task {
                if artwork.source == .wallhaven {
                    let client = await prepareWallhaven()
                    return try await client.detail(id: artwork.artworkID)
                }
                let client = await preparePixiv()
                return try await client.detail(id: artwork.artworkID)
            }
            request = .init(id: UUID(), task: task, consumers: [consumer])
            detailTasks[key] = request
        }
        return try await withTaskCancellationHandler {
            defer { releaseDetailConsumer(consumer, key: key, requestID: request.id) }
            let value = try await request.task.value
            try Task.checkCancellation()
            let currentScope = artwork.source == .pixiv ? pixivScope : "wallhaven-\(wallhavenCredentialRevision)"
            guard scope == currentScope, artwork.source != .pixiv || logoutEpoch == pixivLogoutEpoch else { throw CancellationError() }
            if details[key] == nil, details.count >= 96, let oldest = details.min(by: { $0.value.0 < $1.value.0 })?.key {
                details.removeValue(forKey: oldest)
            }
            details[key] = (Date(), value)
            return value
        } onCancel: { Task { @MainActor [weak self] in self?.releaseDetailConsumer(consumer, key: key, requestID: request.id) } }
    }

    private func releaseDetailConsumer(_ consumer: UUID, key: String, requestID: UUID) {
        guard var request = detailTasks[key], request.id == requestID else { return }
        request.consumers.remove(consumer)
        if request.consumers.isEmpty { detailTasks.removeValue(forKey: key); request.task.cancel() }
        else { detailTasks[key] = request }
    }

    func assets(for artwork: OnlineImageArtwork) async throws -> [OnlineImageAsset] {
        if artwork.source == .wallhaven { let client = await prepareWallhaven(); return try await client.assets(for: artwork) }
        let logoutEpoch = pixivLogoutEpoch
        let client = await preparePixiv()
        try Task.checkCancellation()
        guard logoutEpoch == pixivLogoutEpoch else { throw CancellationError() }
        let scope = pixivScope
        let assets = try await client.assets(for: artwork)
        try Task.checkCancellation()
        guard logoutEpoch == pixivLogoutEpoch, scope == pixivScope else { throw CancellationError() }
        return assets
    }

    func thumbnailRequest(url: URL, source: OnlineImageSource) -> OnlineImageThumbnailRequest {
        source == .pixiv ? .init(url: url, scopeID: pixivScope, session: pixivSession?.urlSession,
            referer: URL(string: "https://www.pixiv.net/")) : .init(url: url)
    }

    func cancel(_ id: OnlineImageAssetID) { transfers[id]?.task.cancel() }

    func cancel(_ id: OnlineImageAssetID, attemptID: UUID) {
        guard transfers[id]?.id == attemptID else { return }
        transfers[id]?.task.cancel()
    }

    func download(_ asset: OnlineImageAsset, apply: Bool = false) {
        startDownload(id: asset.id, title: asset.title, previewURL: asset.previewURL, apply: apply) { [self] in
            let cached = await cachedOriginal(asset.id)
            return (asset, cached?.url)
        }
    }

    func downloadArtwork(_ artwork: OnlineImageArtwork, pageIndex: Int = 0, apply: Bool = false) {
        let id = OnlineImageAssetID(source: artwork.source, artworkID: artwork.artworkID, pageIndex: pageIndex)
        startDownload(id: id, title: artwork.title, previewURL: artwork.thumbnailURL ?? artwork.previewURL, apply: apply) { [self] in
            if artwork.source == .wallhaven { _ = await prepareWallhaven() }
            if let cached = await cachedOriginal(id) {
                var asset = cached.asset
                if artwork.rating != .unknown { asset.rating = artwork.rating }
                return (asset, cached.url)
            }
            let resolved = try await detail(artwork)
            let assets = try await assets(for: resolved)
            guard let asset = assets.first(where: { $0.id == id }) else { throw OnlineImageError.unsupported }
            return (asset, nil)
        }
    }

    private func startDownload(id: OnlineImageAssetID, title: String, previewURL: URL?, apply: Bool,
                               resolve: @escaping @MainActor () async throws -> (OnlineImageAsset, URL?)) {
        guard transfers[id] == nil else { return }
        if !snapshot.unavailable.contains(id), let record = record(for: id.reference) {
            if apply { requestLibraryPlayback?(record.id.reference) }
            return
        }
        let token = UUID()
        let initialScope = id.source == .pixiv && !isPixivPrepared ? nil : requestScope(id.source)
        let applyIntent = apply ? captureApplyIntent?() : nil
        progress[id] = 0
        let task = Task { [weak self] in
            guard let self else { return }
            var outcome: DownloadTerminalOutcome = .cancelled
            var failure: String?
            var terminalTitle = title
            defer {
                if transfers[id]?.id == token { transfers.removeValue(forKey: id); progress.removeValue(forKey: id) }
                downloadTerminals.send(.init(id: .init(reference: id.reference, attemptID: token.uuidString),
                    title: terminalTitle, outcome: outcome, recordedAt: Date(), failureMessage: failure))
                downloadTasksDidChange.send()
            }
            guard await waitForDownloadSlot(token) else { return }
            defer { releaseDownloadSlot(token) }
            transfers[id]?.phase = .preparing
            downloadTasksDidChange.send()
            let staging = root.appendingPathComponent(".image-\(token.uuidString).pending")
            do {
                try Task.checkCancellation()
                if initialScope == nil { _ = await preparePixiv(); try Task.checkCancellation() }
                let scope = initialScope ?? requestScope(id.source)
                if transfers[id]?.id == token { transfers[id]?.scope = scope }
                let (asset, cachedURL) = try await resolve()
                try Task.checkCancellation()
                guard asset.id == id, scope == requestScope(id.source) else { throw CancellationError() }
                transfers[id]?.cachedOriginalDirectory = cachedURL?.deletingLastPathComponent()
                terminalTitle = asset.title
                transfers[id]?.title = asset.title
                if let previewURL = asset.previewURL { transfers[id]?.previewURL = previewURL }
                transfers[id]?.phase = .transferring
                downloadTasksDidChange.send()
                try await Task.detached(priority: .utility) { [root] in
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                }.value
                defer { Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: staging) } }
                if let cachedURL {
                    try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: cachedURL, to: staging) }.value
                    progress[id] = 1
                } else {
                    try await fetchOriginal(asset, to: staging, progress: { [weak self] fraction in
                        guard self?.transfers[asset.id]?.id == token else { return }
                        self?.progress[asset.id] = fraction
                    })
                }
                transfers[id]?.phase = .saving
                downloadTasksDidChange.send()
                let info: (width: Int, height: Int, bytes: Int64, extensionName: String)
                do { info = try await Task.detached(priority: .utility) { try Self.imageInfo(staging) }.value }
                catch {
                    if let cachedURL {
                        await Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: cachedURL.deletingLastPathComponent()) }.value
                    }
                    throw error
                }
                try Task.checkCancellation()
                guard scope == requestScope(id.source) else { throw CancellationError() }
                let value = try await store.publish(stagingURL: staging, asset: asset, width: info.width,
                    height: info.height, fileSizeBytes: info.bytes, fileExtension: info.extensionName)
                outcome = .completed
                accept(value)
                if !Task.isCancelled, scope == requestScope(id.source),
                   applyIntent?() == true { requestLibraryPlayback?(asset.id.reference) }
            } catch is CancellationError { }
            catch let error as URLError where error.code == .cancelled { }
            catch { outcome = .failed; failure = error.localizedDescription; errorMessage = error.localizedDescription }
        }
        transfers[id] = Transfer(id: token, task: task, scope: initialScope, title: title,
                                 phase: .queued, previewURL: previewURL, createdAt: Date())
        downloadTasksDidChange.send()
    }

    func requestScope(_ source: OnlineImageSource) -> String {
        source == .pixiv ? pixivScope : "wallhaven-\(wallhavenCredentialRevision)"
    }

    /// A cache leaf, never a local publication or saved CDN credential. Keeping
    /// only publishable metadata lets a subsequent download work offline after restart.
    nonisolated private struct OriginalPreviewMetadata: Codable, Sendable {
        let id: OnlineImageAssetID
        let title: String
        let sourceURL: URL
        let author: String?
        let authorID: String?
        let tags: [String]
        let width: Int?
        let height: Int?
        let fileName: String
        let rating: WallpaperContentRating?
        func asset(at url: URL) -> OnlineImageAsset {
            .init(id: id, title: title, sourceURL: sourceURL, originalURL: url,
                  author: author, authorID: authorID, tags: tags, width: width, height: height, rating: rating ?? .unknown)
        }
    }

    func cachedOriginalPreviewURL(for id: OnlineImageAssetID) async -> URL? { await cachedOriginal(id)?.url }

    /// Keep download copies alive while removing only optional preview caches.
    /// The caller revokes the current Quick Look request before installing this
    /// barrier; later previews wait without losing their own command.
    @discardableResult
    func clearOriginalPreviewCache(after cancelledPreview: Task<Void, Never>? = nil) -> Task<Void, Never> {
        if let originalCacheClearTask { return originalCacheClearTask }
        let protected = Set(transfers.keys.map { originalCacheDirectory($0).path })
            .union(transfers.values.compactMap { $0.cachedOriginalDirectory?.path })
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MyWallpaperX-OriginalPreviews", isDirectory: true)
        let clearing = Task { [originalCacheRoot] in
            await cancelledPreview?.value
            await Task.detached(priority: .utility) {
                let files = FileManager.default
                for root in [originalCacheRoot, temporaryRoot] {
                    let contents = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                    for url in contents where !protected.contains(url.path) { try? files.removeItem(at: url) }
                }
            }.value
            self.originalCacheClearTask = nil
        }
        originalCacheClearTask = clearing
        return clearing
    }

    func originalPreviewURL(_ asset: OnlineImageAsset) async throws -> URL {
        if let cached = await cachedOriginal(asset.id) { return cached.url }
        try Task.checkCancellation()
        let directory = originalCacheDirectory(asset.id)
        let ext = asset.originalURL.pathExtension
        let fileName = "original." + (ext.isEmpty ? "img" : ext)
        let destination = directory.appendingPathComponent(fileName)
        // Acquisition must remain usable when the optional disk cache cannot be written.
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MyWallpaperX-OriginalPreviews", isDirectory: true)
        // Acquisition is a live transaction, separate from the reclaimable
        // fallback cache. A clear must not unlink a later request's open file.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("MyWallpaperX-Original-\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? "img" : ext)
        var acquired = false
        defer { if !acquired { Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: staging) } } }
        try await transferOriginal(asset, to: staging)
        try Task.checkCancellation()
        let metadata = OriginalPreviewMetadata(id: asset.id, title: asset.title, sourceURL: asset.sourceURL,
            author: asset.author, authorID: asset.authorID, tags: asset.tags, width: asset.width, height: asset.height,
            fileName: fileName, rating: asset.rating)
        await originalCacheClearTask?.value
        try Task.checkCancellation()
        let ready = await Task.detached(priority: .utility) { [originalCacheRoot] () -> URL in
            let files = FileManager.default
            do {
                try files.createDirectory(at: directory, withIntermediateDirectories: true)
                let metadataURL = directory.appendingPathComponent("metadata.json")
                try? files.removeItem(at: metadataURL)
                if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
                try files.moveItem(at: staging, to: destination)
                try? files.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
                try? JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
                Self.removeExpiredOriginals(in: originalCacheRoot)
                return destination
            } catch {
                do {
                    try files.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
                    let fallback = temporaryRoot.appendingPathComponent(staging.lastPathComponent)
                    try files.moveItem(at: staging, to: fallback)
                    Self.removeExpiredOriginals(in: temporaryRoot)
                    return fallback
                } catch { return staging }
            }
        }.value
        acquired = ready != destination
        return ready
    }

    func fetchOriginal(_ asset: OnlineImageAsset, to staging: URL, progress: ((Double) -> Void)? = nil) async throws {
        if let cached = await cachedOriginal(asset.id) {
            try Task.checkCancellation()
            transfers[asset.id]?.cachedOriginalDirectory = cached.url.deletingLastPathComponent()
            try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: cached.url, to: staging) }.value
            try Task.checkCancellation()
            progress?(1)
            return
        }
        try await transferOriginal(asset, to: staging, progress: progress)
    }

    private nonisolated static func removeExpiredOriginals(in directory: URL) {
        let files = FileManager.default
        let contents = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in contents {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               Date().timeIntervalSince(date) >= 86_400 { try? files.removeItem(at: url) }
        }
    }

    private static func keyCacheScope(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return "wallhaven-public" }
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func originalCacheDirectory(_ id: OnlineImageAssetID) -> URL {
        let scope = id.source == .pixiv ? pixivSession?.originalCacheScope ?? "pixiv-anonymous" : wallhavenCacheScope
        let key = id.reference.storageKey + ":" + scope
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return originalCacheRoot.appendingPathComponent(digest, isDirectory: true)
    }

    private func cachedOriginal(_ id: OnlineImageAssetID) async -> (url: URL, asset: OnlineImageAsset)? {
        guard !Task.isCancelled else { return nil }
        await originalCacheClearTask?.value
        guard !Task.isCancelled else { return nil }
        let directory = originalCacheDirectory(id)
        return await Task.detached(priority: .utility) { () -> (url: URL, asset: OnlineImageAsset)? in
            let files = FileManager.default
            guard let bytes = try? Data(contentsOf: directory.appendingPathComponent("metadata.json")),
                  let metadata = try? JSONDecoder().decode(OriginalPreviewMetadata.self, from: bytes), metadata.id == id,
                  metadata.fileName == (metadata.fileName as NSString).lastPathComponent else { return nil }
            let original = directory.appendingPathComponent(metadata.fileName)
            guard let attributes = try? original.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  attributes.isRegularFile == true, let date = attributes.contentModificationDate else { return nil }
            guard Date().timeIntervalSince(date) < 86_400 else {
                try? files.removeItem(at: directory)
                return nil
            }
            return (original, metadata.asset(at: original))
        }.value
    }

    private func transferOriginal(_ asset: OnlineImageAsset, to staging: URL, progress: ((Double) -> Void)? = nil) async throws {
        let configuration = asset.id.source == .pixiv ? pixivSession?.urlSession.configuration : .ephemeral
        var request = URLRequest(url: asset.originalURL)
        if asset.id.source == .pixiv { request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "Referer") }
        guard request.url?.scheme == "https", let host = request.url?.host else { throw OnlineImageError.invalidResponse }
        let transfer = WallpaperFileTransfer(expectedBytes: asset.expectedBytes ?? 0, stagingURL: staging,
            configuration: configuration, allowedHosts: [host], progressHandler: { progress?($0) })
        _ = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.start(request: request) { continuation.resume(with: $0) }
            }
        } onCancel: { transfer.cancel() }
    }

    func retry(_ reference: WallpaperReference) {
        guard let record = record(for: reference) else { return }
        let shell = OnlineImageArtwork(source: record.id.source, artworkID: record.id.artworkID,
            title: record.title, sourceURL: record.sourceURL)
        downloadArtwork(shell, pageIndex: record.id.pageIndex)
    }

    /// A failed first download has no manifest record. Resolve its exact source
    /// and page again instead of borrowing current browser rows or a saved CDN.
    func retryDownload(_ reference: WallpaperReference, title: String) {
        guard let id = OnlineImageAssetID(reference: reference) else { return }
        let base = id.source == .wallhaven ? URL(string: "https://wallhaven.cc/w/")!
            : URL(string: "https://www.pixiv.net/artworks/")!
        let pageURL = base.appendingPathComponent(id.artworkID)
        let artwork = OnlineImageArtwork(source: id.source, artworkID: id.artworkID, title: title, sourceURL: pageURL)
        downloadArtwork(artwork, pageIndex: id.pageIndex)
    }

    func delete(_ reference: WallpaperReference, expectedRevision: UUID? = nil,
                permitsDeletion: @escaping () -> Bool = { true }) async throws {
        guard permitsDeletion(), let record = record(for: reference),
              expectedRevision == nil || expectedRevision == record.revision,
              let url = localURL(for: record), transfers[record.id] == nil else {
            throw OnlineImageError.message("该图片正在下载或记录已变化，请稍后重试。")
        }
        if !snapshot.unavailable.contains(record.id) {
            let prepared = try await Task.detached(priority: .utility) { try WallpaperSourceFileDeletion.prepare(url) }.value
            guard permitsDeletion(), self.record(for: reference)?.revision == record.revision, isFileInUse?(url.path) != true else {
                throw OnlineImageError.message("该图片正在作为壁纸使用，请先切换后再删除。")
            }
            let result = WallpaperSourceFileDeletion.unlinkPrepared(prepared)
            guard result.sourceFileDeleted else { throw OnlineImageError.message(result.failureMessage ?? "删除失败") }
            let sync = await Task.detached(priority: .utility) { WallpaperSourceFileDeletion.synchronizeDirectory(after: prepared) }.value
            if let message = sync.failureMessage { errorMessage = message }
        }
        do { accept(try await store.removeRecord(id: record.id, expectedRevision: record.revision)) }
        catch { refreshLocal(); throw error }
    }

    private func accept(_ value: OnlineImageLocalSnapshot) {
        guard value.revision >= snapshot.revision else { return }
        recordsByID = Dictionary(value.records.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        snapshot = value
    }

    private func waitForDownloadSlot(_ token: UUID) async -> Bool {
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            if activeDownloads.count < 2 { activeDownloads.insert(token); return true }
            return await withCheckedContinuation { waitingDownloads.append((token, $0)) }
        } onCancel: { Task { @MainActor [weak self] in
            guard let self, let index = waitingDownloads.firstIndex(where: { $0.0 == token }) else { return }
            waitingDownloads.remove(at: index).1.resume(returning: false)
        } }
    }

    private func releaseDownloadSlot(_ token: UUID) {
        activeDownloads.remove(token)
        if !waitingDownloads.isEmpty {
            let next = waitingDownloads.removeFirst(); activeDownloads.insert(next.0); next.1.resume(returning: true)
        }
    }

    private nonisolated static func imageInfo(_ url: URL) throws -> (width: Int, height: Int, bytes: Int64, extensionName: String) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1, let type = CGImageSourceGetType(source),
              let utType = UTType(type as String), utType.conforms(to: .image), let ext = utType.preferredFilenameExtension,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, width > 0,
              let height = props[kCGImagePropertyPixelHeight] as? Int, height > 0,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else {
            throw OnlineImageError.message("下载内容不是可读取的静态原图，未加入资料库。")
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return (width, height, Int64(size), ext)
    }
}
