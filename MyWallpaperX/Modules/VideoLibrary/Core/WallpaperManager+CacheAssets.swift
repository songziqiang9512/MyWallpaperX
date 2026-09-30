//
//  WallpaperManager+CacheAssets.swift
//  MyWallpaperX
//

import Foundation

extension WallpaperManager {
    func clearAllCaches() {
        // 清缓存必须同时清理内存态、磁盘态和索引里的派生路径，单清一层会留下孤儿引用。
        // 缩略图解码缓存（ThumbnailCache 各 namespace）由设置「清除缓存」统一入口的
        // 显式清单逐实例清空（VideoLibraryThumbnailStore/SILThumbnailStore.clearDiskCache
        // + OLThumbnailCache.clearAll），这里负责视频库自身的失败记录与派生路径索引失效。
        clearPreviewCacheArtifacts()
        thumbnailGenerationFailureLock.lock()
        thumbnailGenerationFailures.removeAll()
        thumbnailGenerationFailureLock.unlock()

        for index in wallpapers.indices {
            wallpapers[index].thumbnailPath = nil
            wallpapers[index].staticFramePath = nil
        }

        if var currentWallpaper {
            currentWallpaper.thumbnailPath = nil
            currentWallpaper.staticFramePath = nil
            self.currentWallpaper = currentWallpaper
        }

        if !recentlyUsedWallpapers.isEmpty {
            recentlyUsedWallpapers = recentlyUsedWallpapers.map { wallpaper in
                var cleared = wallpaper
                cleared.thumbnailPath = nil
                cleared.staticFramePath = nil
                return cleared
            }
        }

        saveWallpapers()
        saveRecentWallpapers()
        persistCurrentWallpaperSnapshot()
    }

    func updateWallpaperAssetPaths(forPath path: String, thumbnailPath: String? = nil, staticFramePath: String? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateWallpaperAssetPaths(forPath: path, thumbnailPath: thumbnailPath, staticFramePath: staticFramePath)
            }
            return
        }

        let normalized = normalizedPath(path)

        // 资产回写要同步主库、当前播放项和最近使用快照，避免三处状态出现不同步。
        if let index = wallpapers.firstIndex(where: { normalizedPath($0.path) == normalized }) {
            _ = applyAssetPaths(
                to: &wallpapers[index],
                thumbnailPath: thumbnailPath,
                staticFramePath: staticFramePath
            )
        }

        if var current = currentWallpaper, normalizedPath(current.path) == normalized {
            let didChangeCurrent = applyAssetPaths(
                to: &current,
                thumbnailPath: thumbnailPath,
                staticFramePath: staticFramePath
            )
            if didChangeCurrent {
                currentWallpaper = current
            }
        }

        if !recentlyUsedWallpapers.isEmpty {
            var didUpdateRecent = false
            recentlyUsedWallpapers = recentlyUsedWallpapers.map { wallpaper in
                guard normalizedPath(wallpaper.path) == normalized else { return wallpaper }
                var updated = wallpaper
                let didChange = applyAssetPaths(
                    to: &updated,
                    thumbnailPath: thumbnailPath,
                    staticFramePath: staticFramePath
                )
                didUpdateRecent = didUpdateRecent || didChange
                return updated
            }
            if didUpdateRecent {
                saveRecentWallpapers()
            }
        }
    }

    func ensurePreviewAssetsForWallpaper(_ wallpaper: VideoWallpaper) {
        // 资产补齐是按需触发的：能直接命中缓存就不重复生成，没命中才后台补。
        let sourceURL = URL(fileURLWithPath: wallpaper.path)
        let normalized = normalizedPath(sourceURL.path)
        guard pathExists(normalized) else {
            let title = wallpaper.displayTitle
            reportMissingIndexedFile(path: normalized, displayTitle: title)
            return
        }

        if resolvedThumbnailPath(for: wallpaper) != nil {
            scheduleStaticFrameGeneration(for: sourceURL)
            return
        }

        guard shouldRetryThumbnailGeneration(for: normalized) || isThumbnailGenerationInFlight(for: normalized) else {
            notifyThumbnailReady(forPath: sourceURL.path)
            scheduleStaticFrameGeneration(for: sourceURL)
            return
        }

        generateThumbnail(for: sourceURL) { [weak self] _ in
            guard let self else { return }
            self.notifyThumbnailReady(forPath: sourceURL.path)
        }
        scheduleStaticFrameGeneration(for: sourceURL)
    }

    private func applyAssetPaths(
        to wallpaper: inout VideoWallpaper,
        thumbnailPath: String?,
        staticFramePath: String?
    ) -> Bool {
        var didChange = false
        if let thumbnailPath, wallpaper.thumbnailPath != thumbnailPath {
            wallpaper.thumbnailPath = thumbnailPath
            didChange = true
        }
        if let staticFramePath, wallpaper.staticFramePath != staticFramePath {
            wallpaper.staticFramePath = staticFramePath
            didChange = true
        }
        return didChange
    }
}
