//
//  WallpaperManager+ImportProcessing.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import CoreMedia

extension WallpaperManager {
    private struct ImportCounters {
        var duplicate = 0
        var linked = 0
        var missing = 0
        var unreadable = 0
        var failures: [String: String] = [:]
    }

    private enum ImportSourceValidationResult {
        case valid(URL)
        case missing
        case unreadable
    }

    private struct PreparedImportEntry {
        let sourceURL: URL
        let title: String
        let normalizedPath: String
        let cachedThumbnailPath: String?
        let cachedStaticFramePath: String?
    }

    private struct ImportPreparationResult {
        let requestedCount: Int
        let preparedImports: [PreparedImportEntry]
        let existingPathsToLink: [String]
        let counters: ImportCounters
    }

    nonisolated private struct ImportedAssetMetadataUpdate: Sendable {
        let path: String
        let size: Int64
        let duration: Int?
        let resolution: String?
    }

    func loadSampleData() {
        // 只在首次没有任何导入清单时注入内置示例。
        // 后续启动完全以持久化的 wallpapers 列表为准（包含空列表），避免删除后又恢复。
        guard !hasPersistedWallpaperIndex() else { return }

        // 内置示例从签名 Bundle 中的 Videos.zip 首次解压到 Application Support。
        for videoURL in BundledVideoLibrary.videoURLs {
            let title = videoURL.deletingPathExtension().lastPathComponent
            let newWallpaper = makeImportedWallpaper(from: videoURL, title: title)
            _ = upsertWallpaper(newWallpaper)
            if !didFinishInitialIndexLoad { initialIndexSeedWallpapers.append(newWallpaper) }
            schedulePreviewAssetGeneration(for: videoURL)
        }
    }
    func processImportedVideos(from urls: [URL], presentingIn window: NSWindow?, context: ImportContext,
                               admission: ImportedVideoPlaybackAdmission? = nil,
                               resourceLifetime: PlaybackResourceLifetime? = nil,
                               presentsSummary: Bool = true, completion: ((WallpaperSourceImportResult) -> Void)? = nil) {
        guard allowsLibraryMutation else {
            if let admission {
                guard acceptsImportedVideoPlayback(admission) else {
                    failImportedVideoPlayback(admission, reason: "视频播放请求已取消")
                    return
                }
                let matchesSource = (context == .onlinePlayback && admission.reference.provider == .pixabay)
                    || (context == .steamPlayback && admission.reference.provider == .steamWorkshop)
                if matchesSource, urls.count == 1, let url = urls.first,
                   let existing = wallpapers.first(where: { normalizedPath($0.path) == normalizedPath(url.path) }) {
                    // Reuse the existing indexed resource and the original
                    // ticket; recovery mode must not import or rewrite history.
                    withExtendedLifetime(resourceLifetime) {
                        setAsWallpaper(existing, admission: admission)
                    }
                    return
                }
                failImportedVideoPlayback(admission, reason: "需要先恢复资料库再导入播放。")
            }
            reportMigrationReadOnly(in: window)
            return
        }
        guard !urls.isEmpty else {
            if let admission { failImportedVideoPlayback(admission, reason: "没有可导入的视频，已保留原壁纸") }
            return
        }
        let indexEpoch = wallpaperIndexSaveEpoch
        let existingPathsSnapshot = Set(wallpapers.map { normalizedPath($0.path) })
        // Independent explicit organization imports complete in the original
        // serial queue. The old single-selection preparation slot still
        // supersedes its own legacy requests, never another import command.
        let generation = admission == nil && completion == nil ? beginImportPreparationRequest() : nil

        // 导入先做后台预处理，再回主线程应用结果，避免导入大批量文件时阻塞前台交互。
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let prepared = self.prepareImportEntries(
                urls,
                existingPaths: existingPathsSnapshot,
                requestGeneration: generation
            ) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.wallpaperIndexSaveEpoch == indexEpoch else { return }
                if let generation, !self.isImportPreparationRequestCurrent(generation) { return }
                self.applyPreparedImportResult(
                    prepared,
                    presentingIn: window,
                    context: context,
                    indexEpoch: indexEpoch,
                    admission: admission,
                    resourceLifetime: resourceLifetime,
                    presentsSummary: presentsSummary,
                    orderedPaths: completion != nil ? urls.map { self.normalizedPath($0.path) } : [], completion: completion
                )
            }
        }
        if generation != nil { setImportPreparationWorkItem(workItem) }
        importPreparationQueue.async(execute: workItem)
    }

    private func makeImportSummary(
        requestedCount: Int,
        importedCount: Int,
        counters: ImportCounters
    ) -> ImportSummary {
        ImportSummary(
            requestedCount: requestedCount,
            importedCount: importedCount,
            linkedCount: counters.linked,
            skippedCount: requestedCount - importedCount - counters.linked,
            thumbnailFailureCount: 0,
            failureBreakdown: importFailureBreakdown(
                duplicateCount: counters.duplicate,
                missingFileCount: counters.missing,
                unreadableFileCount: counters.unreadable
            )
        )
    }

    private func scheduleImportedAssetsProcessing(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let indexEpoch = wallpaperIndexSaveEpoch
        let normalizedURLs = urls.map { URL(fileURLWithPath: normalizedPath($0.path)) }

        importAssetPipelineQueue.async { [weak self] in
            guard let self else { return }

            // 阶段1：优先全量生成缩略图，保证列表可视体验。
            for url in normalizedURLs {
                autoreleasepool {
                    guard self.pathExists(url.path) else { return }
                    let semaphore = DispatchSemaphore(value: 0)
                    self.generateThumbnail(for: url) { [weak self] imagePath in
                        defer { semaphore.signal() }
                        guard let self, imagePath != nil else { return }
                        self.notifyThumbnailReady(forPath: url.path)
                    }
                    semaphore.wait()
                }
            }

            // 阶段2：缩略图全部完成后，再串行提取静帧（静默后台）。
            for url in normalizedURLs {
                autoreleasepool {
                    guard self.pathExists(url.path) else { return }
                    guard let staticFramePath = self.generateStaticFrame(for: url) else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.wallpaperIndexSaveEpoch == indexEpoch else { return }
                        self.updateWallpaperAssetPaths(forPath: url.path, staticFramePath: staticFramePath)
                    }
                }
            }

            // 阶段3：静帧完成后补填 fileSize, duration, resolution，供「按大小排序」直接读缓存，不再做主线程磁盘 I/O。
            Task {
                let metadataUpdates = await Self.collectImportedAssetMetadata(for: normalizedURLs)
                guard !metadataUpdates.isEmpty else { return }
                await MainActor.run {
                    guard self.wallpaperIndexSaveEpoch == indexEpoch else { return }
                    self.applyImportedAssetMetadataUpdates(metadataUpdates)
                }
            }
        }
    }

    nonisolated private static func collectImportedAssetMetadata(for urls: [URL]) async -> [ImportedAssetMetadataUpdate] {
        var updates: [ImportedAssetMetadataUpdate] = []
        updates.reserveCapacity(urls.count)

        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let asset = AVURLAsset(url: url)
            let durationSec = (try? await asset.load(.duration))?.seconds
            let duration = durationSec.map { Int($0.rounded()) }

            var resolution: String?
            if let tracks = try? await asset.loadTracks(withMediaType: .video),
               let track = tracks.first,
               let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let transformedSize = size.applying(transform)
                resolution = "\(Int(abs(transformedSize.width))) × \(Int(abs(transformedSize.height)))"
            }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                updates.append(
                    ImportedAssetMetadataUpdate(
                        path: url.path,
                        size: size,
                        duration: duration,
                        resolution: resolution
                    )
                )
            }
        }

        return updates
    }

    private func applyImportedAssetMetadataUpdates(_ updates: [ImportedAssetMetadataUpdate]) {
        guard !updates.isEmpty else { return }
        // 按需解析尚未扫描的主库前缀：小批次首项命中不必扫整库，整批最多扫描一次。
        // 同路径只登记首项，保留旧 firstIndex 的匹配语义。
        var indexByPath: [String: Int] = [:]
        indexByPath.reserveCapacity(min(wallpapers.count, updates.count))
        var nextUnindexedIndex = 0

        var updatedWallpapers = wallpapers
        var matchedPaths: [String] = []
        matchedPaths.reserveCapacity(updates.count)
        for update in updates {
            let normalized = normalizedPath(update.path)
            while indexByPath[normalized] == nil, nextUnindexedIndex < wallpapers.count {
                let index = nextUnindexedIndex
                nextUnindexedIndex += 1
                let candidate = normalizedPath(wallpapers[index].path)
                if indexByPath[candidate] == nil { indexByPath[candidate] = index }
            }
            guard let index = indexByPath[normalized] else { continue }
            updatedWallpapers[index].fileSize = update.size
            updatedWallpapers[index].duration = update.duration
            updatedWallpapers[index].resolution = update.resolution
            matchedPaths.append(update.path)
        }
        // 完整状态一次提交；重复更新最终没有变化时也不发布整库。
        if updatedWallpapers != wallpapers {
            wallpapers = updatedWallpapers
        }
        // 保留每条匹配更新的通知及顺序，包括字段未变化的匹配项。
        for path in matchedPaths {
            notifyThumbnailReady(forPath: path)
        }
    }

    private func prepareImportEntries(
        _ urls: [URL],
        existingPaths: Set<String>,
        requestGeneration: UInt64?
    ) -> ImportPreparationResult? {
        // 分块 + 取消检查点：大批次导入要可中断，不能在单轮扫描里长时间占住后台队列。
        let chunkSize = 96
        var counters = ImportCounters()
        var knownPaths = existingPaths
        var preparedImports: [PreparedImportEntry] = []
        preparedImports.reserveCapacity(urls.count)
        var existingPathsToLink: [String] = []
        existingPathsToLink.reserveCapacity(urls.count)

        var start = 0
        while start < urls.count {
            if let requestGeneration, !isImportPreparationRequestCurrent(requestGeneration) { return nil }
            let end = min(start + chunkSize, urls.count)
            autoreleasepool {
                for url in urls[start..<end] {
                    let fileName = url.lastPathComponent
                    switch validateImportSourceURL(url) {
                    case .valid(let resolvedURL):
                        let normalizedURLPath = resolvedURL.path
                        if knownPaths.contains(normalizedURLPath) {
                            existingPathsToLink.append(normalizedURLPath)
                            continue
                        }
                        knownPaths.insert(normalizedURLPath)
                        let key = cacheKey(forNormalizedPath: normalizedURLPath)
                        let thumbnailPath = thumbnailOutputURL(forKey: key).path
                        let staticFramePath = staticFrameOutputURL(forKey: key).path
                        let cachedThumbnailPath = pathExists(thumbnailPath) ? thumbnailPath : nil
                        let cachedStaticFramePath = pathExists(staticFramePath) ? staticFramePath : nil
                        preparedImports.append(
                            PreparedImportEntry(
                                sourceURL: resolvedURL,
                                title: fileName,
                                normalizedPath: normalizedURLPath,
                                cachedThumbnailPath: cachedThumbnailPath,
                                cachedStaticFramePath: cachedStaticFramePath
                            )
                        )
                    case .missing:
                        counters.missing += 1
                        counters.failures[normalizedPath(url.path)] = "文件不存在"
                    case .unreadable:
                        counters.unreadable += 1
                        counters.failures[normalizedPath(url.path)] = "文件无法读取"
                    }
                }
            }
            start = end
        }

        return ImportPreparationResult(
            requestedCount: urls.count,
            preparedImports: preparedImports,
            existingPathsToLink: existingPathsToLink,
            counters: counters
        )
    }

    private func beginImportPreparationRequest() -> UInt64 {
        importPreparationStateLock.lock()
        importPreparationGeneration &+= 1
        let generation = importPreparationGeneration
        let previousWorkItem = importPreparationWorkItem
        importPreparationWorkItem = nil
        importPreparationStateLock.unlock()
        previousWorkItem?.cancel()
        return generation
    }

    private func setImportPreparationWorkItem(_ workItem: DispatchWorkItem?) {
        importPreparationStateLock.lock()
        importPreparationWorkItem = workItem
        importPreparationStateLock.unlock()
    }

    private func isImportPreparationRequestCurrent(_ generation: UInt64) -> Bool {
        importPreparationStateLock.lock()
        let isCurrent = importPreparationGeneration == generation
        importPreparationStateLock.unlock()
        return isCurrent
    }

    private func applyPreparedImportResult(
        _ prepared: ImportPreparationResult,
        presentingIn window: NSWindow?,
        context: ImportContext,
        indexEpoch: UInt64,
        admission: ImportedVideoPlaybackAdmission?,
        resourceLifetime: PlaybackResourceLifetime?,
        presentsSummary: Bool, orderedPaths: [String], completion: ((WallpaperSourceImportResult) -> Void)?
    ) {
        guard wallpaperIndexSaveEpoch == indexEpoch, allowsLibraryMutation else { return }
        // 应用阶段只在主线程改模型，后台预处理结果不直接碰 @Published 属性。
        var counters = prepared.counters
        var playableExistingPaths = prepared.existingPathsToLink
        var indexByPath: [String: Int] = [:]
        indexByPath.reserveCapacity(wallpapers.count + prepared.preparedImports.count)
        for index in wallpapers.indices {
            indexByPath[normalizedPath(wallpapers[index].path)] = index
        }
        var newWallpapers: [VideoWallpaper] = []
        newWallpapers.reserveCapacity(prepared.preparedImports.count)
        var insertedURLs: [URL] = []
        insertedURLs.reserveCapacity(prepared.preparedImports.count)
        for path in prepared.existingPathsToLink {
            guard wallpaperIndexSaveEpoch == indexEpoch else { return }
            guard indexByPath[path] != nil else {
                counters.duplicate += 1
                continue
            }
            counters.duplicate += 1
        }

        for entry in prepared.preparedImports {
            guard wallpaperIndexSaveEpoch == indexEpoch else { return }
            if indexByPath[entry.normalizedPath] != nil {
                counters.duplicate += 1
                playableExistingPaths.append(entry.normalizedPath)
                continue
            }

            let wallpaper = makePreparedWallpaper(entry)
            newWallpapers.append(wallpaper)
            insertedURLs.append(entry.sourceURL)
            indexByPath[entry.normalizedPath] = wallpapers.count + newWallpapers.count - 1
        }

        // onlinePlayback / steamPlayback 静默导入，不弹任何提示
        if presentsSummary, context != .onlinePlayback && context != .steamPlayback {
            presentImportSummary(
                makeImportSummary(
                    requestedCount: prepared.requestedCount,
                    importedCount: newWallpapers.count,
                    counters: counters
                ),
                in: window
            )
        }

        guard wallpaperIndexSaveEpoch == indexEpoch else { return }
        if !newWallpapers.isEmpty {
            wallpapers.reserveCapacity(wallpapers.count + newWallpapers.count)
        }
        appendWallpapersInBatches(newWallpapers)
        guard wallpaperIndexSaveEpoch == indexEpoch else { return }

        let importedBacking = newWallpapers.first ?? playableExistingPaths.first.flatMap { path in
            wallpapers.first(where: { normalizedPath($0.path) == path })
        }
        // The successful import publisher supplies provenance independently of
        // playback admission. Stop cancels playback, not an accepted download.
        if let admission, prepared.requestedCount == 1, let importedBacking,
           (context == .onlinePlayback && admission.reference.provider == .pixabay)
            || (context == .steamPlayback && admission.reference.provider == .steamWorkshop) {
            libraryBackingPublished?(WallpaperContentBackingPublication(backingVideoID: importedBacking.id,
                publishedReference: admission.reference, proof: .publishedDownload))
        }
        guard wallpaperIndexSaveEpoch == indexEpoch else { return }
        // 在线库静默导入后立即播放：优先播放新导入的，已存在则从库中找
        if let admission {
            if acceptsImportedVideoPlayback(admission) {
                if let first = newWallpapers.first {
                    setAsWallpaper(first, admission: admission)
                } else if let path = playableExistingPaths.first,
                          let existing = wallpapers.first(where: { normalizedPath($0.path) == path }) {
                    setAsWallpaper(existing, admission: admission)
                } else {
                    failImportedVideoPlayback(admission, reason: "视频无法导入或已不可用，已保留原壁纸")
                }
            } else {
                // Silent import remains valid after Stop/a newer choice, but its
                // old admission never gets a fresh ticket or starts playback.
                failImportedVideoPlayback(admission, reason: "视频播放请求已取消")
            }
        }

        // 先把导入结果反馈给用户，缩略图/静帧放到后台补齐。
        scheduleImportedAssetsProcessing(insertedURLs)
        // Once this function returns, every accepted source is represented in
        // WallpaperManager.wallpapers and is included in Steam version GC's
        // persistent-path protection set.
        withExtendedLifetime(resourceLifetime) {}
        guard wallpaperIndexSaveEpoch == indexEpoch else { return }
        if let completion {
            let accepted = Set(playableExistingPaths + newWallpapers.map { normalizedPath($0.path) })
            let added = Set(newWallpapers.map { normalizedPath($0.path) })
            var reportedNew = Set<String>()
            let results = orderedPaths.map { path -> WallpaperSourceImportResult.Item in
                let url = URL(fileURLWithPath: path)
                guard accepted.contains(path), let item = wallpapers.first(where: { normalizedPath($0.path) == path }) else {
                    return .init(sourceURL: url, disposition: .failed, organizationItem: nil,
                                 failureMessage: counters.failures[path] ?? "资料库内容已变化，未完成入库")
                }
                let disposition: WallpaperSourceImportResult.Disposition = added.contains(path) && reportedNew.insert(path).inserted ? .added : .existing
                return .init(sourceURL: url, disposition: disposition,
                    organizationItem: .init(reference: .init(provider: .videoLibrary, sourceID: item.id),
                        locator: .init(path: item.path, titleHint: item.title, mediaKind: .video),
                        isPublishedLocally: true, isAvailable: true), failureMessage: nil)
            }
            completion(.init(items: results))
        }
    }


    private func schedulePreviewAssetGeneration(for url: URL) {
        scheduleStaticFrameGeneration(for: url)
        generateThumbnail(for: url) { [weak self] imagePath in
            guard let self, imagePath != nil else { return }
            self.notifyThumbnailReady(forPath: url.path)
        }
    }

    private func validateImportSourceURL(_ url: URL) -> ImportSourceValidationResult {
        let normalizedURL = URL(fileURLWithPath: normalizedPath(url.path))
        let normalizedPath = normalizedURL.path
        guard pathExists(normalizedPath) else {
            return .missing
        }
        guard isReadablePath(normalizedPath) else {
            return .unreadable
        }
        return .valid(normalizedURL)
    }

    private func makeImportedWallpaper(from url: URL, title: String) -> VideoWallpaper {
        let wallpaper = VideoWallpaper(
            title: title,
            path: url.path,
            thumbnailPath: existingThumbnailPath(for: url),
            staticFramePath: existingStaticFramePath(for: url),
            firstIndexedAt: Date()
        )
        return wallpaper
    }

    private func makePreparedWallpaper(_ entry: PreparedImportEntry) -> VideoWallpaper {
        let wallpaper = VideoWallpaper(
            title: entry.title,
            path: entry.sourceURL.path,
            thumbnailPath: entry.cachedThumbnailPath,
            staticFramePath: entry.cachedStaticFramePath,
            firstIndexedAt: Date()
        )
        return wallpaper
    }

    private func appendWallpapersInBatches(_ wallpapersToAppend: [VideoWallpaper], batchSize: Int = 80) {
        guard !wallpapersToAppend.isEmpty else { return }
        // 一次性 append 触发单次 @Published 通知，避免递归 async 在 main queue 累积大量调度帧。
        // 之前的分批递归方案在大批量导入（>80 条）时会在主队列堆积数十次调度，与渲染帧竞争。
        wallpapers.append(contentsOf: wallpapersToAppend)
    }

    /// 扫描全库并异步修补缺失的元数据（时长、分辨率等）
    func scanForMissingMetadata() {
        let missing = wallpapers.filter { $0.duration == nil || $0.resolution == nil }
        guard !missing.isEmpty else { return }
        
        let urls = missing.map { URL(fileURLWithPath: $0.path) }
        scheduleImportedAssetsProcessing(urls)
    }
}
