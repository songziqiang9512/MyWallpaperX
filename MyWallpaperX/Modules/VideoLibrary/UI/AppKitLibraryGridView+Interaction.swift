//
//  AppKitLibraryGridView+Interaction.swift
//  MyWallpaperX
//

import AppKit

extension AppKitLibraryGridContainerView {
    func selectForContextMenuIfNeeded(_ indexPath: IndexPath?) {
        // 右键菜单只修正当前命中项的 selection，不改多选模式的其它选择结果。
        guard let indexPath,
              indexPath.item >= 0,
              indexPath.item < orderedIDs.count else {
            return
        }

        let id = orderedIDs[indexPath.item]
        if wallpaperManager.isMultiSelectMode {
            if !wallpaperManager.selectedWallpaperIds.contains(id) {
                wallpaperManager.replaceMultiSelection(with: [id])
            }
        } else {
            wallpaperManager.setSingleSelection(id)
            collectionView.selectionIndexPaths = [indexPath]
        }
    }

    func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        selectForContextMenuIfNeeded(indexPath)
        guard wallpaperManager.hasAnyWallpaperSelection else { return nil }
        let selection = wallpaperManager.currentSelectionContext
        guard !selection.isSettings else { return nil }

        let menu = NSMenu(title: "WallpaperMenu")
        menu.autoenablesItems = false

        menu.addItem(
            makeContextMenuItem(
                title: "设为壁纸",
                symbolName: "play.circle",
                accessibilityDescription: "设为壁纸",
                action: #selector(handleContextSetAsWallpaper(_:)),
                isEnabled: wallpaperManager.hasSingleWallpaperSelection
            )
        )

        // 收藏状态互斥：已全部收藏则显示"取消收藏"，否则显示"收藏壁纸"。
        let allFavorited = wallpaperManager.areAllSelectedWallpapersFavorite(for: selection)
        let favoriteTitle = allFavorited ? "取消收藏" : "收藏壁纸"
        let favoriteSymbol = allFavorited ? "heart.slash" : "heart"
        menu.addItem(
            makeContextMenuItem(
                title: favoriteTitle,
                symbolName: favoriteSymbol,
                accessibilityDescription: favoriteTitle,
                action: #selector(handleContextToggleFavorite(_:)),
                isEnabled: true
            )
        )

        menu.addItem(
            makeContextMenuItem(
                title: "添加标签",
                symbolName: "tag",
                accessibilityDescription: "添加标签",
                action: #selector(handleContextAddTag(_:)),
                isEnabled: !wallpaperManager.tags.isEmpty
            )
        )

        menu.addItem(
            makeContextMenuItem(
                title: "详细信息",
                symbolName: "info.circle",
                accessibilityDescription: "详细信息",
                action: #selector(handleContextShowInfo(_:)),
                isEnabled: wallpaperManager.hasSingleWallpaperSelection
            )
        )

        menu.addItem(
            makeContextMenuItem(
                title: "查看文件",
                symbolName: "folder",
                accessibilityDescription: "查看文件",
                action: #selector(handleContextRevealInFinder(_:)),
                isEnabled: wallpaperManager.hasSingleWallpaperSelection
            )
        )

        menu.addItem(.separator())

        menu.addItem(
            makeContextMenuItem(
                title: "删除",
                symbolName: "trash",
                accessibilityDescription: "删除",
                action: #selector(handleContextDelete(_:)),
                isEnabled: selection.deletionScope != nil
            )
        )
        return menu
    }

    private func makeContextMenuItem(
        title: String,
        symbolName: String,
        accessibilityDescription: String,
        action: Selector,
        isEnabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        item.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
        return item
    }

    @objc func handleContextSetAsWallpaper(_ sender: Any?) {
        guard let id = wallpaperManager.selectedWallpaperId,
              let wallpaper = wallpapersByID[id] ?? sourceWallpapers.first(where: { $0.id == id }) else {
            return
        }
        handlePlayRequest(wallpaper)
    }

    @objc func handleContextToggleFavorite(_ sender: Any?) {
        UIActionHelper.toggleFavoriteSelection(
            manager: wallpaperManager,
            selection: wallpaperManager.currentSelectionContext
        )
    }

    @objc func handleContextAddTag(_ sender: Any?) {
        UIActionHelper.presentTagPicker(
            manager: wallpaperManager,
            window: window
        ) { [weak self] in
            self?.reloadVisibleItems()
        }
    }

    @objc func handleContextShowInfo(_ sender: Any?) {
        wallpaperManager.presentInspectorForSelectedWallpaper()
    }

    @objc func handleContextRevealInFinder(_ sender: Any?) {
        guard let id = wallpaperManager.selectedWallpaperId,
              let wallpaper = wallpapersByID[id] ?? sourceWallpapers.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wallpaper.path)])
    }

    @objc func handleContextDelete(_ sender: Any?) {
        UIActionHelper.performDelete(
            manager: wallpaperManager,
            selection: wallpaperManager.currentSelectionContext,
            window: window
        )
    }

    func handlePlayRequest(_ wallpaper: VideoWallpaper) {
        // 播放请求先记一个 card interaction，再交给 manager 统一走切换入口。
        wallpaperManager.markCardInteraction()
        wallpaperManager.requestSetAsWallpaper(wallpaper)
    }

    func handlePlayRequest(at indexPath: IndexPath) {
        guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { return }
        guard let wallpaper = wallpapersByID[orderedIDs[indexPath.item]] else { return }
        handlePlayRequest(wallpaper)
    }
}

extension AppKitLibraryGridContainerView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, shouldDeselectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        // 单选态下禁止把当前选中的卡片通过再次点击取消掉，selection 只能由背景点击或外部状态清空。
        guard !wallpaperManager.isMultiSelectMode else { return indexPaths }
        return []
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard indexPath.item >= 0,
              indexPath.item < orderedIDs.count,
              let wallpaper = wallpapersByID[orderedIDs[indexPath.item]],
              let cardItem = item as? AppKitWallpaperItem else {
            return
        }
        cardItem.applyFavoriteState(isFavorite: wallpaper.isFavorite)
        cardItem.applySelectionState(
            isSelected: wallpaperManager.selectedWallpaperId == wallpaper.id
                || wallpaperManager.selectedWallpaperIds.contains(wallpaper.id),
            multiSelectMode: wallpaperManager.isMultiSelectMode
        )
        cardItem.applyPlayingState(
            isPlaying: wallpaperManager.currentWallpaper?.path == wallpaper.path
        )
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        // 选择态只在这里回写到 manager，避免 item 自己和 manager 各写一份状态。
        guard !isApplyingSelectionSnapshot else { return }
        guard wallpaperManager.isMultiSelectMode else {
            guard let indexPath = indexPaths.first,
                  indexPath.item < orderedIDs.count else { return }
            let selectedID = orderedIDs[indexPath.item]
            wallpaperManager.setSingleSelection(selectedID)
            // 点击卡片直接呼出详情面板（与信息按钮同效）。
            wallpaperManager.presentInspectorForSelectedWallpaper()
            return
        }

        if collectionView.selectionIndexPaths.isEmpty {
            wallpaperManager.replaceMultiSelection(with: [])
            return
        }
        let ids = Set(collectionView.selectionIndexPaths.compactMap { path in
            path.item < orderedIDs.count ? orderedIDs[path.item] : nil
        })
        wallpaperManager.replaceMultiSelection(with: ids)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        // 多选取消同样只回写最终结果，不按每个 item 的中间态做重复刷新。
        guard !isApplyingSelectionSnapshot else { return }
        guard wallpaperManager.isMultiSelectMode else { return }
        guard (collectionView as? AppKitWallpaperCollectionView)?.lastPrimaryClickIndexPath == nil else { return }
        let ids = Set(collectionView.selectionIndexPaths.compactMap { path in
            path.item < orderedIDs.count ? orderedIDs[path.item] : nil
        })
        wallpaperManager.replaceMultiSelection(with: ids)
    }
}

extension AppKitLibraryGridContainerView: NSCollectionViewPrefetching {
    func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        // 预取只预热可见区附近的缩略图，不做额外主线程回写。
        for indexPath in indexPaths {
            guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { continue }
            let id = orderedIDs[indexPath.item]
            guard let wallpaper = wallpapersByID[id] else { continue }
            thumbnailProvider.prefetchThumbnail(for: wallpaper)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { continue }
            thumbnailProvider.cancelPrefetch(id: orderedIDs[indexPath.item])
        }
    }
}
