//
//  AppKitLibraryGridView+Cells.swift
//  MyWallpaperX
//

import AppKit

extension AppKitLibraryGridContainerView {
    func registerWallpaperItemCell() {
        // cellProvider 依赖 makeItem 重用队列，必须先注册 item 类。
        collectionView.register(
            AppKitWallpaperItem.self,
            forItemWithIdentifier: AppKitWallpaperItem.reuseIdentifier
        )
    }

    func makeCellItem(collectionView: NSCollectionView, at indexPath: IndexPath, wallpaperID: String) -> NSCollectionViewItem? {
        guard let wallpaper = wallpapersByID[wallpaperID] else {
            return nil
        }
        // 走标准重用队列，滚动/局部 reload 时复用 item，configure 负责全量覆盖状态。
        guard let item = collectionView.makeItem(
            withIdentifier: AppKitWallpaperItem.reuseIdentifier,
            for: indexPath
        ) as? AppKitWallpaperItem else {
            return nil
        }
        configure(item: item, for: wallpaper)
        return item
    }

    private func configure(item: AppKitWallpaperItem, for wallpaper: VideoWallpaper) {
        let isSelected = wallpaperManager.selectedWallpaperId == wallpaper.id
            || wallpaperManager.selectedWallpaperIds.contains(wallpaper.id)
        let isPlaying = wallpaperManager.effectiveCurrentWallpaper?.path == wallpaper.path
        let isFavorite = wallpaper.isFavorite
        let multiSelect = wallpaperManager.isMultiSelectMode

        item.configure(
            wallpaper: wallpaper,
            isSelected: isSelected,
            isPlaying: isPlaying,
            isFavorite: isFavorite,
            multiSelectMode: multiSelect,
            wallpaperManager: wallpaperManager,
            thumbnailProvider: thumbnailProvider
        )
    }

    func reloadVisibleItems() {
        // 这是最后的粗刷新兜底入口，正常路径应优先走更小粒度的 ID / path 刷新。
        let visible = collectionView.indexPathsForVisibleItems()
        guard !visible.isEmpty else { return }
        collectionView.reloadItems(at: Set(visible))
    }

    func reloadVisibleItems(forIDs ids: Set<String>) {
        // 按 ID 刷新是最稳的路径，适合收藏、标签或播放态变化。
        guard !ids.isEmpty else { return }
        let visibleIndexPaths = Set(collectionView.indexPathsForVisibleItems())
        guard !visibleIndexPaths.isEmpty else { return }

        var indexPaths = Set<IndexPath>()
        for id in ids {
            guard let index = orderedIndexByID[id] else { continue }
            let candidate = IndexPath(item: index, section: 0)
            if visibleIndexPaths.contains(candidate) {
                indexPaths.insert(candidate)
            }
        }

        guard !indexPaths.isEmpty else { return }
        collectionView.reloadItems(at: indexPaths)
    }

    func reloadVisibleItems(forNormalizedPaths paths: Set<String>) {
        // 路径级刷新用于缩略图与缓存变化，适合后台生成完成后的补刷。
        guard !paths.isEmpty else { return }
        let visibleIndexPaths = Set(collectionView.indexPathsForVisibleItems())
        guard !visibleIndexPaths.isEmpty else { return }

        var indexPaths = Set<IndexPath>()
        for normalizedPath in paths {
            guard let ids = normalizedPathToIDs[normalizedPath], !ids.isEmpty else { continue }
            for id in ids {
                guard let index = orderedIndexByID[id] else { continue }
                let candidate = IndexPath(item: index, section: 0)
                if visibleIndexPaths.contains(candidate) {
                    indexPaths.insert(candidate)
                }
            }
        }

        guard !indexPaths.isEmpty else { return }
        collectionView.reloadItems(at: indexPaths)
    }
}
