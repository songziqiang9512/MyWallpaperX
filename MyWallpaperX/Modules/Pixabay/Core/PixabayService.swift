//
//  PixabayService.swift
//  MyWallpaperX — Modules/Pixabay/Core
//
//  在线图库数据层：Pixabay API 搜索、分页、分类定义、状态发布。
//  依赖：Foundation、Combine 与共享播放准入值；不直接依赖播放 Manager/renderer。
//  切换其他图库服务只需替换 buildURL / fetchPage / 数据映射部分。
//

import Foundation
import Combine
import Darwin

// MARK: - API 响应解码（私有）

private struct PixabayResponse: Decodable {
    let totalHits: Int
    let hits:      [PixabayHit]
}

private struct PixabayHit: Decodable {
    let id: Int; let pageURL: String; let tags: String
    let duration: Int; let user: String
    let videos: PixabayHitVideos
    enum CodingKeys: String, CodingKey {
        case id, pageURL, tags, duration, user, videos
    }
}

private struct PixabayHitVideos: Decodable {
    let large: PixabayHitFile?; let medium: PixabayHitFile?
    let small: PixabayHitFile?; let tiny:   PixabayHitFile?
}

private struct PixabayHitFile: Decodable {
    let url: String; let width: Int; let height: Int
    let size: Int;   let thumbnail: String
}

private extension PixabayHit {
    func toItem() -> PixabayVideoItem {
        func map(_ f: PixabayHitFile?) -> PixabayVideoFile? {
            f.map { PixabayVideoFile(url: $0.url, width: $0.width,
                                          height: $0.height, size: $0.size,
                                          thumbnail: $0.thumbnail) }
        }
        return PixabayVideoItem(
            id: id, pageURL: pageURL, tags: tags, duration: duration, user: user,
            videos: PixabayVideoFiles(
                large: map(videos.large), medium: map(videos.medium),
                small: map(videos.small), tiny:   map(videos.tiny)
            )
        )
    }
}

// MARK: - 服务

@MainActor
final class PixabayService: ObservableObject {
    static let shared = PixabayService()
    /// App owns product intent admission; downloading alone never calls this.
    var requestLibraryPlayback: ((WallpaperReference) -> Void)?
    var prepareExplicitLibraryRestoration: ((WallpaperReference) -> (() -> Void)?)?
    var prepareVideoPlaybackIntent: ((WallpaperReference, WallpaperPlaybackSequence.Pending?) -> ImportedVideoPlaybackAdmission?)?
    private enum Constants {
        static let visibleThumbnailPrefetchLimit = 18
    }

    // MARK: 搜索状态
    @Published var items:        [PixabayVideoItem] = []
    @Published var isLoading:    Bool   = false
    @Published var errorMessage: String? = nil
    @Published var hasMore:      Bool   = false
    @Published var totalHits:    Int    = 0

    @Published private(set) var currentParams = PixabaySearchParams()
    private var currentPage: Int = 1
    private(set) var hasLoadedOnce: Bool = false

    /// 清空 API Key 并重置所有状态，切回登录界面
    func clearAPIKeyAndReset() {
        searchTask?.cancel()
        apiKey        = ""
        items         = []
        errorMessage  = nil
        isLoading     = false
        hasMore       = false
        hasLoadedOnce = false
        toolbarQuery  = ""
        cancelThumbnailPrefetch()
        itemIndexByID.removeAll()
        objectWillChange.send()
    }

    // MARK: 工具栏驱动状态（工具栏写入，BrowserView 读取）
    @Published var toolbarCategory: PixabayCategory = .all
    @Published var toolbarQuery:    String = ""

    // MARK: API Key
    // Keep the installed preference key when renaming the Pixabay module.
    private static let apiKeyDefaultsKey = "OnlineLibraryAPIKey"
    var apiKey: String {
        get { UserDefaults.standard.string(forKey: Self.apiKeyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.apiKeyDefaultsKey); objectWillChange.send() }
    }
    var hasValidAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    func setAPIKeyAndSearch(_ value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key != apiKey.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        apiKey = key
        toolbarQuery = currentParams.query
        search(params: currentParams)
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()
    private var searchTask: Task<Void, Never>?
    private struct ThumbnailPrefetch {
        let id: UUID
        let url: URL
        let pixelSize: Int
        let task: Task<Void, Never>
        var completed = false
        var failed = false
        var generation: Int?
    }
    private var thumbnailPrefetches: [Int: ThumbnailPrefetch] = [:]
    private var itemIndexByID: [Int: Int] = [:]
    private var previousVisibleStart: Int?
    private var downloadedContentTask: Task<Void, Never>?
    private var downloadedContentGeneration: UInt64 = 0
    private var initialDownloadedScanCompleted = false
    @Published private(set) var downloadedContent = PixabayDownloadedContentSnapshot(revision: 0, entries: [], status: .initial)

    private init() { refreshDownloadedContent() }

    deinit { downloadedContentTask?.cancel() }

    /// The only directory/AV metadata owner. Presentation and transfer ticks
    /// consume the published value and never request another scan implicitly.
    @discardableResult
    func refreshDownloadedContent() -> Task<Void, Never> {
        downloadedContentTask?.cancel()
        downloadedContentGeneration &+= 1
        let generation = downloadedContentGeneration
        publishDownloadedContent(downloadedContent.entries, status: .init(phase: .loading,
            hasSuccessfulScan: downloadedContent.status.hasSuccessfulScan))
        let directory = Self.downloadDirectory, legacy = Self.legacyDownloadDirectory
        let previous = downloadedContent.entries
        let worker = Task.detached(priority: .utility) {
            try await PixabayDownloadedContent.scan(in: directory, reusing: previous, legacyDirectory: legacy)
        }
        let task = Task { [weak self] in
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, let self, self.downloadedContentGeneration == generation else { return }
                self.initialDownloadedScanCompleted = true
                self.publishDownloadedContent(result.entries, completedScan: true,
                    status: .init(phase: .ready(warnings: result.warnings), hasSuccessfulScan: true))
            } catch is CancellationError {
                // A cancelled/replaced scan owns no publication or error.
            } catch {
                guard !Task.isCancelled, let self, self.downloadedContentGeneration == generation else { return }
                self.initialDownloadedScanCompleted = true
                // Failure ends the initial lookup wait, but does not turn an
                // unknown source into a successful empty library or revoke a
                // previous successful source's playback readiness.
                self.publishDownloadedContent(self.downloadedContent.entries, status: .init(
                    phase: .failed(message: "无法读取已下载 Pixabay 内容：" + error.localizedDescription),
                    hasSuccessfulScan: self.downloadedContent.status.hasSuccessfulScan))
            }
        }
        downloadedContentTask = task
        return task
    }

    private func publishDownloadedContent(_ entries: [PixabayDownloadedEntry], completedScan: Bool = false,
                                         status: WallpaperSourceScanStatus? = nil) {
        let contentChanged = downloadedContent.entries != entries || (completedScan && downloadedContent.revision == 0)
        let next = PixabayDownloadedContentSnapshot(
            revision: contentChanged ? downloadedContent.revision &+ 1 : downloadedContent.revision,
            entries: entries, status: status ?? downloadedContent.status)
        if downloadedContent != next { downloadedContent = next }
        let availableIDs = Set(entries.filter(\.isAvailable).map(\.id))
        if downloadedIDs != availableIDs { downloadedIDs = availableIDs }
    }

    /// User-action fallback during the first async scan (and after external
    /// changes). This is deliberately not called by rendering or progress.
    private func existingDownloadedURL(id: Int) -> URL? {
        let known = downloadedContent.entries.first { $0.id == id }?.localURL
        let canonical = Self.downloadDirectory.appendingPathComponent("online_\(id).mp4")
        for url in [known, canonical, Self.legacyDownloadDirectory.appendingPathComponent("online_\(id).mp4")].compactMap({ $0 }) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue, FileManager.default.isReadableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// Only explicit playback uses this synchronous user-action validation.
    /// Query/cell/progress callers consume the published worker snapshot.
    func libraryContentItemForExplicitPlayback(id: Int) -> WallpaperContentItem? {
        guard let url = existingDownloadedURL(id: id) else { return nil }
        let published = downloadedContent.entries.first {
            $0.id == id && $0.localURL.standardizedFileURL == url.standardizedFileURL
        }
        let facts = WallpaperContentLocalFacts(isPublishedLocally: true, isAvailable: true,
            canPlay: true, canDelete: true, localURL: url, resourceRevision: published?.thumbnailSourceKey)
        return PixabayLibraryContentProjection.project(download: published, sourceID: id, facts: facts)
    }

    // MARK: - 公开接口

    func search(params: PixabaySearchParams) {
        searchTask?.cancel()
        currentParams = params
        currentPage   = 1
        items         = []
        errorMessage  = nil
        hasMore       = false
        hasLoadedOnce = true
        cancelThumbnailPrefetch()
        itemIndexByID.removeAll()
        fetchPage(page: 1, appending: false)
    }

    func loadNextPage() {
        guard hasMore, !isLoading else { return }
        fetchPage(page: currentPage + 1, appending: true)
    }

    func prioritizeVisibleItemIDs(_ ids: [Int], maxPixelSize: Int = 512) {
        let visibleIndexes = ids.compactMap { itemIndexByID[$0] }.sorted()
        guard let first = visibleIndexes.first else { cancelThumbnailPrefetch(); return }
        let direction = previousVisibleStart.map { first == $0 ? 0 : (first > $0 ? 1 : -1) } ?? 0
        previousVisibleStart = first
        let indices = GridThumbnailPrefetchDemand.indices(visibleIndices: visibleIndexes,
            itemCount: items.count, neighborLimit: Constants.visibleThumbnailPrefetchLimit, direction: direction)
        prefetchThumbnailImages(for: indices.map { items[$0] }, visibleIDs: Set(ids), maxPixelSize: maxPixelSize)
    }

    func thumbnailPrefetchNeedsRefresh() -> Bool {
        thumbnailPrefetches.values.contains {
            $0.completed && !$0.failed && OnlineImageThumbnailCache.shared.readyImage(for: $0.url, maxPixelSize: $0.pixelSize) == nil
        }
    }

    func cancelThumbnailPrefetch() {
        thumbnailPrefetches.values.forEach { $0.task.cancel() }
        thumbnailPrefetches.removeAll()
        previousVisibleStart = nil
    }

    // MARK: - 下载状态
    @Published var downloadingIDs: Set<Int> = []
    @Published var downloadProgressByID: [Int: Double] = [:]
    let downloadTasksDidChange = PassthroughSubject<Void, Never>()
    let downloadTerminals = PassthroughSubject<DownloadTerminalReceipt, Never>()
    struct DownloadActivity {
        let itemID: Int
        let attemptID: UUID
        let title: String
        let phase: DownloadTaskPhase
        let previewURL: URL?
        let createdAt: Date
    }
    private struct DownloadSlot {
        let attemptID: UUID
        let task: Task<Void, Never>
        var title: String
        var phase: DownloadTaskPhase
        var previewURL: URL?
        let createdAt: Date
    }
    private var downloadSlots: [Int: DownloadSlot] = [:]
    var activeDownloadCount: Int { downloadSlots.count }
    var downloadActivities: [DownloadActivity] {
        downloadSlots.map { id, slot in
            DownloadActivity(itemID: id, attemptID: slot.attemptID, title: slot.title,
                             phase: slot.phase, previewURL: slot.previewURL, createdAt: slot.createdAt)
        }.sorted { $0.createdAt < $1.createdAt }
    }
    func downloadActivity(for id: Int) -> DownloadActivity? {
        guard let slot = downloadSlots[id] else { return nil }
        return DownloadActivity(itemID: id, attemptID: slot.attemptID, title: slot.title,
            phase: slot.phase, previewURL: slot.previewURL, createdAt: slot.createdAt)
    }
    @Published private(set) var downloadedIDs: Set<Int> = []
    @Published var downloadError:  String?  = nil
    /// OL-04：仅下载完成后的成功提示（文件存储路径），UI 层消费后置 nil
    @Published var downloadSuccessMessage: String? = nil
    /// OL-04：最近下载完成的 item ID，供 Toast「设为壁纸」按钮使用
    @Published var lastDownloadedItemID: Int? = nil
    @Published private(set) var inspectedDownloadedItemID: Int? = nil

    var selectedDownloadedItemIDForInspector: Int? {
        inspectedDownloadedItemID
    }

    func presentInspectorForSelectedDownloadedItem(
        _ selectedID: Int?,
        isMultiSelectMode: Bool,
        availableIDs: Set<Int>
    ) {
        guard !isMultiSelectMode,
              let selectedID,
              availableIDs.contains(selectedID) else {
            return
        }
        inspectedDownloadedItemID = selectedID
    }

    func dismissSelectedDownloadedInspector() {
        inspectedDownloadedItemID = nil
    }

    func syncSelectedDownloadedInspectorIfNeeded(
        selectedID: Int?,
        isMultiSelectMode: Bool,
        availableIDs: Set<Int>
    ) {
        guard inspectedDownloadedItemID != nil else { return }
        guard !isMultiSelectMode,
              let selectedID,
              availableIDs.contains(selectedID) else {
            inspectedDownloadedItemID = nil
            return
        }
        inspectedDownloadedItemID = selectedID
    }

    /// 仅下载到本地，不触发播放
    func download(item: PixabayVideoItem) {
        startDownload(item: item)
    }

    /// 设为壁纸：文件已在本地时立即播放（OL-05 直接用户意图）；未下载时
    /// 仅下载——用户裁决（2026-09-26）：下载完成后不自动切换播放，
    /// 下载只是下载，用户稍后再点一次即播放。通知名
    /// pixabayVideoReadyToPlay 定义在 Shell/ContentViewSupport.swift。
    func downloadAndSet(item: PixabayVideoItem, libraryPending: WallpaperPlaybackSequence.Pending? = nil) {
        if downloadedIDs.contains(item.id) || existingDownloadedURL(id: item.id) != nil {
            postReadyToPlay(id: item.id, libraryPending: libraryPending)
            return
        }
        startDownload(item: item)
    }

    /// OL-05：已下载文件直接设为壁纸（从本地路径发通知，无需重新下载）
    @discardableResult
    private func postReadyToPlay(id: Int, libraryPending: WallpaperPlaybackSequence.Pending? = nil) -> Bool {
        guard let libraryPending else {
            requestLibraryPlayback?(WallpaperReference(provider: .pixabay, sourceID: String(id)))
            return false
        }
        guard let local = existingDownloadedURL(id: id) else {
            var entries = downloadedContent.entries
            if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].isAvailable = false }
            publishDownloadedContent(entries)
            refreshDownloadedContent()
            return false
        }
        guard let admission = prepareVideoPlaybackIntent?(
            WallpaperReference(provider: .pixabay, sourceID: String(id)), libraryPending) else {
            downloadError = "视频播放入口尚未就绪。"
            return false
        }
        ImportedVideoPlaybackRequest(localURL: local, admission: admission)
            .post(name: .pixabayVideoReadyToPlay)
        return true
    }

    private func startDownload(item: PixabayVideoItem) {
        startDownload(id: item.id, item: item)
    }

    func retryDownload(id: Int) { startDownload(id: id, item: nil) }

    func cancelDownload(id: Int, attemptID: UUID) {
        guard let slot = downloadSlots[id], slot.attemptID == attemptID else { return }
        slot.task.cancel()
    }

    private func startDownload(id: Int, item: PixabayVideoItem?) {
        guard downloadSlots[id] == nil else { return }
        let restoration = prepareExplicitLibraryRestoration?(.init(provider: .pixabay, sourceID: String(id)))
        if existingDownloadedURL(id: id) != nil {
            restoration?()
            refreshDownloadedContent()
            return
        }
        let attempt = UUID()
        let title = item?.displayTitle ?? "Pixabay #\(id)"
        let task = Task { [self] in
            var terminal: DownloadTerminalOutcome?
            var failure: String?
            var terminalTitle = title
            defer {
                downloadSlots.removeValue(forKey: id)
                downloadingIDs.remove(id)
                downloadProgressByID[id] = nil
                if let terminal {
                    downloadTerminals.send(.init(id: .init(reference: .init(provider: .pixabay, sourceID: String(id)),
                        attemptID: attempt.uuidString), title: terminalTitle, outcome: terminal,
                        recordedAt: Date(), failureMessage: failure))
                }
                downloadTasksDidChange.send()
            }
            do {
                // Legacy filenames such as online_0007.mp4 are resolved only by
                // the source scan. A click during that first scan must not create
                // a second same-ID file merely because the canonical path is absent.
                while !initialDownloadedScanCompleted, let pending = downloadedContentTask {
                    try Task.checkCancellation()
                    let generation = downloadedContentGeneration
                    await pending.value
                    if generation == downloadedContentGeneration { break }
                }
                try Task.checkCancellation()
                if existingDownloadedURL(id: id) != nil { restoration?(); return }
                let resolved: PixabayVideoItem
                if let item { resolved = item }
                else { resolved = try await resolveDownloadItem(id: id) }
                guard let source = resolved.bestVideoDownload else { throw downloadFailure("该视频当前没有可下载的文件。") }
                terminalTitle = resolved.displayTitle
                downloadSlots[id]?.title = terminalTitle
                downloadSlots[id]?.previewURL = resolved.previewThumbnailURL
                downloadSlots[id]?.phase = .transferring
                downloadTasksDidChange.send()
                _ = try await fetchAndMove(
                    from: source.url,
                    expectedBytes: source.expectedBytes,
                    name: "online_\(id).mp4",
                    itemID: id, attemptID: attempt
                )
                // rename is the publication point. A later cancel cannot
                // turn these committed bytes into a cancelled history row.
                terminal = .completed
                restoration?()
                refreshDownloadedContent()
                lastDownloadedItemID = id
                downloadSuccessMessage = "已保存到 \"影片/MyWallpaperX/Pixabay\""
            } catch is CancellationError {
                terminal = .cancelled
            } catch let error as URLError where error.code == .cancelled {
                terminal = .cancelled
            } catch {
                terminal = .failed
                failure = error.localizedDescription
                downloadError = error.localizedDescription
            }
        }
        downloadSlots[id] = DownloadSlot(attemptID: attempt, task: task, title: title,
                                        phase: .preparing, previewURL: item?.previewThumbnailURL, createdAt: Date())
        downloadingIDs.insert(id)
        downloadProgressByID[id] = 0
        downloadTasksDidChange.send()
    }

    /// A history retry resolves its fixed ID with the original API/session;
    /// it never edits the browser query, current page or visible item array.
    private func resolveDownloadItem(id: Int) async throws -> PixabayVideoItem {
        guard hasValidAPIKey else { throw downloadFailure("请先填写 Pixabay API Key。") }
        var components = URLComponents(string: "https://pixabay.com/api/videos/")!
        components.queryItems = [.init(name: "key", value: apiKey), .init(name: "id", value: String(id))]
        let (data, response) = try await session.data(from: components.url!)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw downloadFailure("无效响应。") }
        guard http.statusCode == 200 else {
            throw downloadFailure(http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 400
                ? "API Key 无效，请重新填写。" : "服务器错误 (\(http.statusCode))")
        }
        let responseValue = try JSONDecoder().decode(PixabayResponse.self, from: data)
        guard let item = responseValue.hits.first(where: { $0.id == id }) else { throw downloadFailure("该视频当前不可访问。") }
        return item.toItem()
    }

    private func downloadFailure(_ message: String) -> NSError {
        NSError(domain: "PixabayDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func fetchAndMove(from url: URL, expectedBytes: Int64?, name: String, itemID: Int, attemptID: UUID) async throws -> URL {
        if let expectedBytes, expectedBytes > 0 {
            downloadProgressByID[itemID] = max(downloadProgressByID[itemID] ?? 0, 0.01)
        }
        let dest = Self.downloadDirectory.appendingPathComponent(name)
        let directory = dest.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let staging = directory.appendingPathComponent(".online-\(UUID().uuidString).pending")
        defer { try? FileManager.default.removeItem(at: staging) }
        let tmp = try await downloadFile(from: url, itemID: itemID, attemptID: attemptID,
                                         expectedBytes: expectedBytes, stagingURL: staging)
        try Task.checkCancellation()
        downloadSlots[itemID]?.phase = .saving
        downloadTasksDidChange.send()
        guard rename(tmp.path, dest.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return dest
    }

    private func downloadFile(from url: URL, itemID: Int, attemptID: UUID, expectedBytes: Int64?, stagingURL: URL) async throws -> URL {
        let delegate = WallpaperFileTransfer(
            expectedBytes: expectedBytes ?? 0,
            stagingURL: stagingURL,
            progressHandler: { [weak self] progress in
                guard let self, self.downloadSlots[itemID]?.attemptID == attemptID,
                      self.downloadProgressByID[itemID] != progress else { return }
                self.downloadProgressByID[itemID] = progress
            }
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(from: url) { result in
                    continuation.resume(with: result)
                }
            }
        } onCancel: { delegate.cancel() }
    }

    func refresh() { search(params: currentParams) }

    // MARK: - 下载文件管理

    /// New downloads use the brand directory; old files stay in their original location.
    static var downloadDirectory: URL {
        FileManager.default
            .urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyWallpaperX", isDirectory: true)
            .appendingPathComponent("Pixabay", isDirectory: true)
    }

    static var legacyDownloadDirectory: URL {
        downloadDirectory.deletingLastPathComponent().appendingPathComponent("在线图库", isDirectory: true)
    }
    static var downloadRoots: [URL] { [downloadDirectory, legacyDownloadDirectory] }

    /// Revoke the old scan before deletion; only successful removals leave
    /// the local publication. Missing files count as already removed.
    @discardableResult
    func deleteLocalFiles(at urls: [URL], isInUse: ((URL) -> Bool)? = nil) -> [PixabayLocalDeletionResult] {
        downloadedContentTask?.cancel()
        downloadedContentGeneration &+= 1
        var results: [PixabayLocalDeletionResult] = []
        for url in urls {
            let failure: String?
            var deleted = false
            do {
                let directory = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
                guard url.isFileURL, PixabayDownloadedContent.itemID(for: url) != nil,
                      Self.downloadRoots.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL.path == directory.path }),
                      isInUse?(url) != true else {
                    throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "源文件不属于当前下载目录，或正在播放/准备；请先停止后重试"])
                }
                do {
                    let prepared = try WallpaperSourceFileDeletion.prepare(url)
                    let outcome = WallpaperSourceFileDeletion.remove(prepared)
                    deleted = outcome.sourceFileDeleted
                    failure = outcome.failureMessage
                } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(POSIXErrorCode.ENOENT.rawValue) {
                    // A readable, present owner directory distinguishes an
                    // already removed child from an offline/missing volume.
                    let values = try FileManager.default.attributesOfItem(atPath: directory.path)
                    guard values[.type] as? FileAttributeType == .typeDirectory,
                          FileManager.default.isReadableFile(atPath: directory.path) else { throw error }
                    failure = nil
                }
            } catch { failure = error.localizedDescription }
            results.append(.init(localURL: url, id: PixabayDownloadedContent.itemID(for: url), failureMessage: failure,
                sourceFileDeleted: deleted))
        }
        let removed = Set(results.filter(\.succeeded).map { Data($0.localURL.standardizedFileURL.path.utf8) })
        publishDownloadedContent(downloadedContent.entries.filter {
            !removed.contains(Data($0.localURL.standardizedFileURL.path.utf8))
        })
        refreshDownloadedContent()
        return results
    }

    /// 从本地已下载文件直接设为壁纸（下载管理面板调用）
    @discardableResult
    func setLocalFileAsWallpaper(id: Int, libraryPending: WallpaperPlaybackSequence.Pending? = nil) -> Bool {
        postReadyToPlay(id: id, libraryPending: libraryPending)
    }

    /// OL-12：便利搜索方法，用当前状态填充缺省值，消除调用方重复构建 PixabaySearchParams
    func searchWithCurrentContext(
        query:    String?                  = nil,
        category: PixabayCategory?   = nil,
        order:    PixabayOrder?      = nil
    ) {
        var params = currentParams
        params.query = query ?? toolbarQuery
        params.category = category ?? toolbarCategory
        params.order = order ?? currentParams.order
        params.page = 1
        search(params: params)
    }

    // MARK: - 私有

    private func fetchPage(page: Int, appending: Bool) {
        guard hasValidAPIKey else { isLoading = false; errorMessage = "请先填写 Pixabay API Key"; return }
        let params = currentParams
        guard let url = buildURL(params: params, page: page) else { isLoading = false; errorMessage = "URL 构建失败"; return }

        isLoading    = true
        errorMessage = nil

        searchTask = Task { [weak self] in
            guard let self else { return }
            // Search/reset cancels the prior task before admitting its next
            // request. A cancelled completion must not clear that request's
            // loading state, including URLSession's URLError.cancelled path.
            defer { if !Task.isCancelled { self.isLoading = false } }
            do {
                let (data, response) = try await self.session.data(from: url)
                if Task.isCancelled { return }
                guard let http = response as? HTTPURLResponse else {
                    self.errorMessage = "无效响应"; return
                }
                switch http.statusCode {
                case 200:
                    let decoded  = try JSONDecoder().decode(PixabayResponse.self, from: data)
                    let newItems = decoded.hits.map { $0.toItem() }
                    var nextItems: [PixabayVideoItem] = []
                    var nextIndex: [Int: Int] = [:]
                    // Page overlap and repeated hits share one stable row:
                    // preserve first position, accept the latest metadata.
                    for value in (appending ? self.items : []) + newItems {
                        if let index = nextIndex[value.id] { nextItems[index] = value }
                        else { nextIndex[value.id] = nextItems.count; nextItems.append(value) }
                    }
                    self.currentPage = page
                    self.totalHits   = decoded.totalHits
                    self.hasMore     = (page * params.perPage) < decoded.totalHits
                    // @Published emits in willSet. During that callback both
                    // stored values must still describe the old array; install
                    // its precomputed index immediately after the array setter,
                    // with no suspension before deferred UI delivery.
                    self.items = nextItems
                    self.itemIndexByID = nextIndex
                case 400:       self.errorMessage = "API Key 无效或不完整，请重新填写"
                case 401, 403:  self.errorMessage = "API Key 无效，请重新填写"
                case 429:       self.errorMessage = "请求过于频繁，请稍后再试"
                default:        self.errorMessage = "服务器错误 (\(http.statusCode))"
                }
            } catch is CancellationError {
                // 正常取消
            } catch {
                if !Task.isCancelled { self.errorMessage = "网络错误：\(error.localizedDescription)" }
            }
        }
    }

    private func buildURL(params: PixabaySearchParams, page: Int) -> URL? {
        var c = URLComponents(string: "https://pixabay.com/api/videos/")
        var q: [URLQueryItem] = [
            .init(name: "key",        value: apiKey),
            .init(name: "per_page",   value: "\(params.perPage)"),
            .init(name: "page",       value: "\(page)"),
            .init(name: "order",      value: params.order.rawValue),
            .init(name: "safesearch", value: String(params.safeSearch))
        ]
        if !params.query.trimmingCharacters(in: .whitespaces).isEmpty {
            q.append(.init(name: "q", value: params.query))
        }
        if params.category != .all {
            q.append(.init(name: "category", value: params.category.rawValue))
        }
        if params.videoType != .all { q.append(.init(name: "video_type", value: params.videoType.rawValue)) }
        if params.minWidth > 0 { q.append(.init(name: "min_width", value: String(params.minWidth))) }
        if params.minHeight > 0 { q.append(.init(name: "min_height", value: String(params.minHeight))) }
        if params.editorsChoice { q.append(.init(name: "editors_choice", value: "true")) }
        c?.queryItems = q
        return c?.url
    }

    private func prefetchThumbnailImages(for items: [PixabayVideoItem], visibleIDs: Set<Int>, maxPixelSize: Int) {
        let candidates = items.compactMap { item -> (Int, URL)? in
            item.previewThumbnailURL.map { (item.id, $0) }
        }
        // Keep a near->visible lease until it leaves both sets, so its newly
        // visible card has time to join the existing producer.
        let nextIDs = Set(candidates.map(\.0)).union(visibleIDs)
        for (id, request) in thumbnailPrefetches where !nextIDs.contains(id) {
            request.task.cancel()
            thumbnailPrefetches.removeValue(forKey: id)
        }
        for (id, url) in candidates {
            let previous = thumbnailPrefetches[id]
            if let current = previous, current.url == url, current.pixelSize == maxPixelSize {
                if !current.completed || OnlineImageThumbnailCache.shared.readyImage(for: url, maxPixelSize: maxPixelSize) != nil { continue }
            }
            previous?.task.cancel()
            let requestID = UUID()
            let task = Task { [weak self] in
                let generation = await OnlineImageThumbnailCache.shared.publicationGeneration()
                // A terminal bad source is retained until source/tier or clear
                // changes; a successfully decoded image can be preheated again
                // after memory eviction without another network fetch.
                let sameSource = previous?.url == url && previous?.pixelSize == maxPixelSize
                let suppressFailure = sameSource && previous?.failed == true && previous?.generation == generation
                let failed: Bool
                if suppressFailure { failed = true }
                else { failed = await OnlineImageThumbnailCache.shared.image(for: url, maxPixelSize: maxPixelSize, priority: .prefetch) == nil }
                guard !Task.isCancelled, let self, self.thumbnailPrefetches[id]?.id == requestID else { return }
                self.thumbnailPrefetches[id]?.completed = true
                self.thumbnailPrefetches[id]?.failed = failed
                self.thumbnailPrefetches[id]?.generation = generation
            }
            thumbnailPrefetches[id] = ThumbnailPrefetch(id: requestID, url: url, pixelSize: maxPixelSize, task: task)
        }
    }
}
