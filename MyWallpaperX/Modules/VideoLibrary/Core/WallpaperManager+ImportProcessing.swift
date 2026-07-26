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
            let newWallpaper = makeImportedWallpaper(from: videoURL, title: title, context: .library)
            _ = upsertWallpaper(newWallpaper)
            schedulePreviewAssetGeneration(for: videoURL)
        }
    }
    func processImportedVideos(from urls: [URL], presentingIn window: NSWindow?, context: ImportContext,
                               autoplayToken: ImportedVideoAutoplayGate.Token? = nil) {
        guard !urls.isEmpty else { return }
        let existingPathsSnapshot = Set(wallpapers.map { normalizedPath($0.path) })
        let generation = autoplayToken == nil ? beginImportPreparationRequest() : nil

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
                if let generation, !self.isImportPreparationRequestCurrent(generation) { return }
                self.applyPreparedImportResult(prepared, presentingIn: window, context: context, autoplayToken: autoplayToken)
            }
        }
        if autoplayToken == nil { setImportPreparationWorkItem(workItem) }
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
                        self?.updateWallpaperAssetPaths(forPath: url.path, staticFramePath: staticFramePath)
                    }
                }
            }

            // 阶段3：静帧完成后补填 fileSize, duration, resolution，供「按大小排序」直接读缓存，不再做主线程磁盘 I/O。
            Task {
                let metadataUpdates = await Self.collectImportedAssetMetadata(for: normalizedURLs)
                guard !metadataUpdates.isEmpty else { return }
                await MainActor.run {
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
        for update in updates {
            let normalized = normalizedPath(update.path)
            if let index = wallpapers.firstIndex(where: { normalizedPath($0.path) == normalized }) {
                wallpapers[index].fileSize = update.size
                wallpapers[index].duration = update.duration
                wallpapers[index].resolution = update.resolution
                // 复用现有可见卡片刷新通道，确保导入后元数据能及时显示。
                notifyThumbnailReady(forPath: update.path)
            }
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
                        let cachedThumbnailPath = existingThumbnailPath(for: resolvedURL)
                        let cachedStaticFramePath = existingStaticFramePath(for: resolvedURL)
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
                    case .unreadable:
                        counters.unreadable += 1
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
        context: ImportContext, autoplayToken: ImportedVideoAutoplayGate.Token?
    ) {
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
            guard let index = indexByPath[path] else {
                counters.duplicate += 1
                continue
            }
            if applyContextMetadataIfNeeded(context, to: &wallpapers[index]) {
                counters.linked += 1
            } else {
                counters.duplicate += 1
            }
        }

        for entry in prepared.preparedImports {
            if let index = indexByPath[entry.normalizedPath] {
                if applyContextMetadataIfNeeded(context, to: &wallpapers[index]) {
                    counters.linked += 1
                } else {
                    counters.duplicate += 1
                }
                playableExistingPaths.append(entry.normalizedPath)
                continue
            }

            let wallpaper = makePreparedWallpaper(entry, context: context)
            newWallpapers.append(wallpaper)
            insertedURLs.append(entry.sourceURL)
            indexByPath[entry.normalizedPath] = wallpapers.count + newWallpapers.count - 1
        }

        // onlinePlayback / steamPlayback 静默导入，不弹任何提示
        if context != .onlinePlayback && context != .steamPlayback {
            presentImportSummary(
                makeImportSummary(
                    requestedCount: prepared.requestedCount,
                    importedCount: newWallpapers.count,
                    counters: counters
                ),
                in: window
            )
        }

        if !newWallpapers.isEmpty {
            wallpapers.reserveCapacity(wallpapers.count + newWallpapers.count)
        }
        appendWallpapersInBatches(newWallpapers)

        // 在线库静默导入后立即播放：优先播放新导入的，已存在则从库中找
        if let autoplayToken, ImportedVideoAutoplayGate.shared.isCurrent(autoplayToken) {
            if let first = newWallpapers.first {
                setAsWallpaper(first, userInitiated: true)
            } else if let path = playableExistingPaths.first,
                      let existing = wallpapers.first(where: { normalizedPath($0.path) == path }) {
                setAsWallpaper(existing, userInitiated: true)
            }
        }

        // 先把导入结果反馈给用户，缩略图/静帧放到后台补齐。
        scheduleImportedAssetsProcessing(insertedURLs)
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

    private func makeImportedWallpaper(from url: URL, title: String, context: ImportContext) -> VideoWallpaper {
        var wallpaper = VideoWallpaper(
            title: title,
            path: url.path,
            thumbnailPath: existingThumbnailPath(for: url),
            staticFramePath: existingStaticFramePath(for: url)
        )
        _ = applyContextMetadataIfNeeded(context, to: &wallpaper)
        return wallpaper
    }

    private func makePreparedWallpaper(_ entry: PreparedImportEntry, context: ImportContext) -> VideoWallpaper {
        var wallpaper = VideoWallpaper(
            title: entry.title,
            path: entry.sourceURL.path,
            thumbnailPath: entry.cachedThumbnailPath,
            staticFramePath: entry.cachedStaticFramePath
        )
        _ = applyContextMetadataIfNeeded(context, to: &wallpaper)
        return wallpaper
    }

    private func appendWallpapersInBatches(_ wallpapersToAppend: [VideoWallpaper], batchSize: Int = 80) {
        guard !wallpapersToAppend.isEmpty else { return }
        // 一次性 append 触发单次 @Published 通知，避免递归 async 在 main queue 累积大量调度帧。
        // 之前的分批递归方案在大批量导入（>80 条）时会在主队列堆积数十次调度，与渲染帧竞争。
        wallpapers.append(contentsOf: wallpapersToAppend)
    }

    @discardableResult
    private func applyContextMetadataIfNeeded(_ context: ImportContext, to wallpaper: inout VideoWallpaper) -> Bool {
        // 导入到某个分类时，只补上下文需要的标签，不覆盖用户已有收藏 / 标签的主状态。
        switch context {
        case .library:
            return false
        case .onlinePlayback:
            return false  // 静默入库，不附加任何标签
        case .steamPlayback:
            return false  // 静默入库，不附加任何标签
        case .favorites:
            guard !wallpaper.isFavorite else { return false }
            wallpaper.isFavorite = true
            return true
        case .tag(let tag):
            guard !wallpaper.tags.contains(tag) else { return false }
            wallpaper.tags.append(tag)
            return true
        }
    }

    /// 扫描全库并异步修补缺失的元数据（时长、分辨率等）
    func scanForMissingMetadata() {
        let missing = wallpapers.filter { $0.duration == nil || $0.resolution == nil }
        guard !missing.isEmpty else { return }
        
        let urls = missing.map { URL(fileURLWithPath: $0.path) }
        scheduleImportedAssetsProcessing(urls)
    }
}
