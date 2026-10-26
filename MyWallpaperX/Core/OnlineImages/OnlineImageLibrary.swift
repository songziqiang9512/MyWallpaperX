import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The two image sources share one publication owner. Browser rows are never a second local index.
@MainActor final class OnlineImageLibrary: ObservableObject {
    static let shared = OnlineImageLibrary()
    @Published private(set) var snapshot = OnlineImageLocalSnapshot()
    @Published private(set) var progress: [OnlineImageAssetID: Double] = [:]
    @Published var errorMessage: String?
    @Published private(set) var wallhavenCredentialRevision: UInt64 = 0
    let root: URL
    let wallhaven = WallhavenClient()
    private(set) var pixiv: PixivClient?
    @Published private(set) var pixivSession: PixivSession?
    private let store: OnlineImageLibraryStore
    private let credentials = WallhavenCredentialStore()
    private var credentialPreparation: Task<Void, Never>?
    private var sessionSubscription: AnyCancellable?
    private var activeScope = "pixiv-anonymous"
    private var pixivTransport: WallpaperNetworkSession?
    private var pixivTransportUpdate: Task<Void, Never>?
    private var pixivPreparation: Task<Void, Never>?
    private var isPixivPrepared = false
    private var pixivLogoutEpoch: UInt64 = 0
    private var recordsByID: [OnlineImageAssetID: OnlineImageLocalRecord] = [:]
    private var transfers: [OnlineImageAssetID: (id: UUID, task: Task<Void, Never>, scope: String?)] = [:]
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

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyWallpaperX/在线图片", isDirectory: true)
        store = OnlineImageLibraryStore(root: self.root)
        refreshLocal()
    }

    func refreshLocal() {
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
            credentialPreparation = Task { [credentials, wallhaven] in
                do { await wallhaven.setAPIKey(try await credentials.read()) }
                catch { errorMessage = error.localizedDescription }
            }
        }
        await credentialPreparation?.value
        return wallhaven
    }

    func setWallhavenKey(_ value: String?) async throws {
        _ = await prepareWallhaven()
        try await credentials.write(value)
        await wallhaven.setAPIKey(value)
        wallhavenCredentialRevision &+= 1
        for (id, transfer) in transfers where id.source == .wallhaven { transfer.1.cancel() }
        details = details.filter { !$0.key.hasPrefix("wallhaven:") }
        for (key, request) in detailTasks where key.hasPrefix("wallhaven:") { request.task.cancel() }
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
                await OLThumbnailCache.shared.invalidate(scopeID: previous)
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

    func thumbnailRequest(url: URL, source: OnlineImageSource) -> OLThumbnailRequest {
        source == .pixiv ? .init(url: url, scopeID: pixivScope, session: pixivSession?.urlSession,
            referer: URL(string: "https://www.pixiv.net/")) : .init(url: url)
    }

    func cancel(_ id: OnlineImageAssetID) { transfers[id]?.1.cancel() }

    func download(_ asset: OnlineImageAsset, apply: Bool = false) {
        startDownload(id: asset.id, apply: apply) { asset }
    }

    func downloadArtwork(_ artwork: OnlineImageArtwork, pageIndex: Int = 0, apply: Bool = false) {
        let id = OnlineImageAssetID(source: artwork.source, artworkID: artwork.artworkID, pageIndex: pageIndex)
        startDownload(id: id, apply: apply) { [self] in
            let resolved = try await detail(artwork)
            let assets = try await assets(for: resolved)
            guard let asset = assets.first(where: { $0.id == id }) else { throw OnlineImageError.unsupported }
            return asset
        }
    }

    private func startDownload(id: OnlineImageAssetID, apply: Bool,
                               resolve: @escaping @MainActor () async throws -> OnlineImageAsset) {
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
            defer {
                if transfers[id]?.0 == token { transfers.removeValue(forKey: id); progress.removeValue(forKey: id) }
            }
            guard await waitForDownloadSlot(token) else { return }
            defer { releaseDownloadSlot(token) }
            let staging = root.appendingPathComponent(".image-\(token.uuidString).pending")
            do {
                try Task.checkCancellation()
                if initialScope == nil { _ = await preparePixiv(); try Task.checkCancellation() }
                let scope = initialScope ?? requestScope(id.source)
                if transfers[id]?.id == token { transfers[id]?.scope = scope }
                let asset = try await resolve()
                try Task.checkCancellation()
                guard asset.id == id, scope == requestScope(id.source) else { throw CancellationError() }
                let configuration = asset.id.source == .pixiv ? pixivSession?.urlSession.configuration : .ephemeral
                var request = URLRequest(url: asset.originalURL)
                if asset.id.source == .pixiv { request.setValue("https://www.pixiv.net/", forHTTPHeaderField: "Referer") }
                guard request.url?.scheme == "https", let host = request.url?.host else { throw OnlineImageError.invalidResponse }
                try await Task.detached(priority: .utility) { [root] in
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                }.value
                defer { Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: staging) } }
                let transfer = WallpaperFileTransfer(expectedBytes: asset.expectedBytes ?? 0, stagingURL: staging,
                    configuration: configuration, allowedHosts: [host], progressHandler: { [weak self] fraction in
                        guard self?.transfers[asset.id]?.0 == token else { return }
                        self?.progress[asset.id] = fraction
                    })
                _ = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        transfer.start(request: request) { continuation.resume(with: $0) }
                    }
                } onCancel: { transfer.cancel() }
                let info = try await Task.detached(priority: .utility) { try Self.imageInfo(staging) }.value
                try Task.checkCancellation()
                guard scope == requestScope(id.source) else { throw CancellationError() }
                let value = try await store.publish(stagingURL: staging, asset: asset, width: info.width,
                    height: info.height, fileSizeBytes: info.bytes, fileExtension: info.extensionName)
                accept(value)
                if !Task.isCancelled, scope == requestScope(id.source),
                   applyIntent?() == true { requestLibraryPlayback?(asset.id.reference) }
            } catch is CancellationError { }
            catch let error as URLError where error.code == .cancelled { }
            catch { errorMessage = error.localizedDescription }
        }
        transfers[id] = (token, task, initialScope)
    }

    func requestScope(_ source: OnlineImageSource) -> String {
        source == .pixiv ? pixivScope : "wallhaven-\(wallhavenCredentialRevision)"
    }

    func retry(_ reference: WallpaperReference) {
        guard let record = record(for: reference) else { return }
        let shell = OnlineImageArtwork(source: record.id.source, artworkID: record.id.artworkID,
            title: record.title, sourceURL: record.sourceURL)
        downloadArtwork(shell, pageIndex: record.id.pageIndex)
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
