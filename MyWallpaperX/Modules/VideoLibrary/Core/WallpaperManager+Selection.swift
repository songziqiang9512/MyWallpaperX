//
//  WallpaperManager+Selection.swift
//  MyWallpaperX
//

import Foundation

extension WallpaperManager {
    var favoriteWallpapers: [VideoWallpaper] { wallpapers.filter { $0.isFavorite } }

    func selectedLibraryWallpaperIndices(for selection: WallpaperSelectionContext) -> [Int] {
        // 这里必须把 selection 快照映射回主库索引，否则最近使用、标签页和库页会出现状态漂移。
        let selectedIDs = effectiveSelectedWallpaperIDs
        guard !selectedIDs.isEmpty else { return [] }
        if selectedIDs.count == 1,
           let selectedID = selectedIDs.first,
           let directIndex = wallpapers.firstIndex(where: { $0.id == selectedID }) {
            return [directIndex]
        }

        var unresolvedIDs = selectedIDs
        var selectedPaths = Set<String>()
        selectedPaths.reserveCapacity(selectedIDs.count)
        for wallpaper in selection.sourceWallpapers(from: self) {
            guard unresolvedIDs.contains(wallpaper.id) else { continue }
            selectedPaths.insert(normalizedPath(wallpaper.path))
            unresolvedIDs.remove(wallpaper.id)
            if unresolvedIDs.isEmpty {
                break
            }
        }

        guard !selectedPaths.isEmpty else { return [] }

        return wallpapers.indices.filter { index in
            selectedPaths.contains(normalizedPath(wallpapers[index].path))
        }
    }

    func areAllSelectedWallpapersFavorite(for selection: WallpaperSelectionContext) -> Bool {
        let indices = selectedLibraryWallpaperIndices(for: selection)
        guard !indices.isEmpty else { return false }
        return indices.allSatisfy { wallpapers[$0].isFavorite }
    }

    func isWallpaperFavoriteForDisplay(_ wallpaper: VideoWallpaper) -> Bool {
        guard let libraryIndex = findWallpaperIndex(forPath: wallpaper.path) else {
            return wallpaper.isFavorite
        }
        return wallpapers[libraryIndex].isFavorite
    }

    var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func filterWallpapers(_ wallpapers: [VideoWallpaper], usingNormalizedQuery query: String) -> [VideoWallpaper] {
        guard !query.isEmpty else { return wallpapers }
        return wallpapers.filter {
            $0.title.lowercased().contains(query) ||
            $0.tags.contains { $0.lowercased().contains(query) }
        }
    }

    func sortedWallpapers(_ wallpapers: [VideoWallpaper], selectionKey: String? = nil) -> [VideoWallpaper] {
        // 排序只做只读派生，不改主库顺序，便于随时切换和还原。
        // selectionKey 非空时读取该列表的独立排序状态；为空时退回全局 settings（兼容旧调用）。
        let state: SortState
        if let key = selectionKey, let perState = perSelectionSortStates[key] {
            state = perState
        } else {
            state = SortState(mode: settings.sortMode, ascending: settings.sortAscending)
        }
        let ascending = state.ascending
        switch state.mode {
        case .none:
            return wallpapers
        case .name:
            let sorted = wallpapers.sorted {
                $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending
            }
            return ascending ? sorted : sorted.reversed()
        case .size:
            // 优先读缓存的 fileSize，避免每次排序都做同步磁盘 I/O（#5 修复）。
            // fileSize 为 nil 时视为 Int64.max（排到末尾），后台补齐后触发列表刷新。
            let sorted = wallpapers.sorted {
                ($0.fileSize ?? Int64.max) < ($1.fileSize ?? Int64.max)
            }
            return ascending ? sorted : sorted.reversed()
        case .dateAdded:
            let sorted = wallpapers.sorted { $0.lastUsed < $1.lastUsed }
            return ascending ? sorted : sorted.reversed()
        }
    }

    /// 读取指定列表的排序状态，无记录时返回默认值。
    func sortState(for key: String) -> SortState {
        perSelectionSortStates[key] ?? SortState()
    }

    /// 更新指定列表的排序状态并持久化。
    func setSortState(_ state: SortState, for key: String) {
        perSelectionSortStates[key] = state
        savePerSelectionSortStates()
    }

    func loadPerSelectionSortStates() {
        guard let data = UserDefaults.standard.data(forKey: perSelectionSortStatesKey),
              let decoded = try? JSONDecoder().decode([String: SortState].self, from: data) else {
            return
        }
        perSelectionSortStates = decoded
    }

    func savePerSelectionSortStates() {
        guard let data = try? JSONEncoder().encode(perSelectionSortStates) else { return }
        UserDefaults.standard.set(data, forKey: perSelectionSortStatesKey)
    }

    var effectiveSelectedWallpaperIDs: Set<String> {
        // 多选和单选共用一个“有效选择集合”，上层只看这个结果，不直接读两个选择槽。
        if isMultiSelectMode {
            return selectedWallpaperIds
        }
        guard let selectedWallpaperId else { return [] }
        return [selectedWallpaperId]
    }

    var hasAnyWallpaperSelection: Bool {
        !effectiveSelectedWallpaperIDs.isEmpty
    }

    var hasSingleWallpaperSelection: Bool {
        !isMultiSelectMode && selectedWallpaperId != nil
    }

    func clearSingleSelectionIfNeeded() {
        guard hasSingleWallpaperSelection else { return }
        selectedWallpaperId = nil
    }

    func setSingleSelection(_ wallpaperID: String?) {
        guard !isMultiSelectMode else { return }
        selectedWallpaperId = wallpaperID
    }

    func replaceMultiSelection(with wallpaperIDs: Set<String>) {
        guard isMultiSelectMode else { return }
        selectedWallpaperIds = wallpaperIDs
        if selectedWallpaperId != nil {
            selectedWallpaperId = nil
        }
    }

    var currentImportContext: ImportContext {
        if let tag = selectedTag, !tag.isEmpty {
            return .tag(tag)
        }

        switch selectedCategory {
        case .favorites:
            return .favorites
        default:
            return .library
        }
    }

    var selectedWallpaperForQuickLook: VideoWallpaper? {
        if isMultiSelectMode {
            guard let selectedID = selectedWallpaperIds.sorted().first else { return nil }
            return wallpapers.first { $0.id == selectedID }
        }

        guard let selectedWallpaperId else { return nil }
        return wallpapers.first { $0.id == selectedWallpaperId }
    }

    var selectedWallpaperForInspector: VideoWallpaper? {
        guard let inspectedWallpaperID else { return nil }
        return wallpapers.first { $0.id == inspectedWallpaperID }
    }

    var isInspectorPresentedForSelectedWallpaper: Bool {
        guard !isMultiSelectMode,
              let selectedWallpaperId else { return false }
        return inspectedWallpaperID == selectedWallpaperId
    }

    func presentInspectorForSelectedWallpaper() {
        guard !isMultiSelectMode,
              let selectedWallpaperId,
              wallpapers.contains(where: { $0.id == selectedWallpaperId }) else {
            return
        }
        inspectedWallpaperID = selectedWallpaperId
    }

    func toggleInspectorForSelectedWallpaper() {
        if isInspectorPresentedForSelectedWallpaper {
            dismissSelectedWallpaperInspector()
        } else {
            presentInspectorForSelectedWallpaper()
        }
    }

    func dismissSelectedWallpaperInspector() {
        inspectedWallpaperID = nil
    }

    func syncSelectedWallpaperInspectorIfNeeded() {
        guard inspectedWallpaperID != nil else { return }
        guard !isMultiSelectMode,
              let selectedWallpaperId,
              wallpapers.contains(where: { $0.id == selectedWallpaperId }) else {
            inspectedWallpaperID = nil
            return
        }
        inspectedWallpaperID = selectedWallpaperId
    }

    var isMuted: Bool {
        // 兼容旧调用点，但公共静音权威是 PlaybackMuteState；不再从音量反推。
        PlaybackMuteState.shared.isMuted
    }

    func selectCategory(_ category: Category) {
        // 切换主分类时清空旧选择，避免侧边栏、工具栏和网格保留跨分类 selection。
        let didChange = selectedCategory != category || selectedTag != nil
        selectedCategory = category
        selectedTag = nil
        if didChange {
            clearSelectionState()
        }
    }

    func selectTag(_ tag: String) {
        // 标签页切换同样走统一清理路径，保证 selection 只和当前视图绑定。
        let didChange = selectedCategory != .tags || selectedTag != tag
        selectedCategory = .tags
        selectedTag = tag
        if didChange {
            clearSelectionState()
        }
    }

    func clearSelectionState() {
        isMultiSelectMode = false
        selectedWallpaperIds.removeAll()
        selectedWallpaperId = nil
    }

    func exitMultiSelectMode() {
        clearSelectionState()
    }

    func markCardInteraction() {
        pendingCardInteractionResetWorkItem?.cancel()
        pendingCardInteraction = true
        let resetWorkItem = DispatchWorkItem { [weak self] in
            self?.pendingCardInteraction = false
        }
        pendingCardInteractionResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: resetWorkItem)
    }

    func consumePendingCardInteraction() -> Bool {
        let pending = pendingCardInteraction
        pendingCardInteraction = false
        pendingCardInteractionResetWorkItem?.cancel()
        pendingCardInteractionResetWorkItem = nil
        return pending
    }

    func toggleMultiSelectMode() {
        // 进入/退出多选时只保留一个选择槽，避免单选态和多选态互相覆盖。
        if isMultiSelectMode {
            selectedWallpaperIds.removeAll()
        } else {
            selectedWallpaperId = nil
        }
        isMultiSelectMode.toggle()
    }

    func toggleWallpaperSelection(_ wallpaper: VideoWallpaper) {
        if isMultiSelectMode {
            if selectedWallpaperIds.contains(wallpaper.id) {
                selectedWallpaperIds.remove(wallpaper.id)
            } else {
                selectedWallpaperIds.insert(wallpaper.id)
            }
        } else {
            selectedWallpaperId = wallpaper.id
        }
    }

    @discardableResult
    func moveSingleSelectionByArrowKey(_ keyCode: UInt16, ignoreSearchFieldState: Bool = false) -> Bool {
        guard !isMultiSelectMode else { return false }
        if !ignoreSearchFieldState {
            guard !isSearchFieldActive else { return false }
        }

        let supportedKeyCodes: Set<UInt16> = [123, 124, 125, 126]
        guard supportedKeyCodes.contains(keyCode) else { return false }

        let source = currentSelectionContext.sourceWallpapers(from: self)
        let selectionKey = currentSelectionContext.scrollPersistenceKey
        let query = normalizedSearchQuery
        // 必须用排序后的列表，保证 index 与网格实际渲染顺序一致。
        let sorted = sortedWallpapers(source, selectionKey: selectionKey)
        let wallpapers = filterWallpapers(sorted, usingNormalizedQuery: query)
        guard !wallpapers.isEmpty else { return false }

        // 方向键导航必须基于当前过滤后的可见集合，而不是完整库集合。
        let currentIndex = wallpapers.firstIndex { $0.id == selectedWallpaperId } ?? 0
        let columnCount = max(1, visibleGridColumnCount)
        let nextIndex: Int

        switch keyCode {
        case 123: // ←
            nextIndex = max(0, currentIndex - 1)
        case 124: // →
            nextIndex = min(wallpapers.count - 1, currentIndex + 1)
        case 126: // ↑
            nextIndex = max(0, currentIndex - columnCount)
        case 125: // ↓
            nextIndex = min(wallpapers.count - 1, currentIndex + columnCount)
        default:
            return false
        }

        setSingleSelection(wallpapers[nextIndex].id)
        return true
    }

    func setWallpaperSelection(_ wallpaperID: String, selected: Bool) {
        guard isMultiSelectMode else { return }
        if selected {
            selectedWallpaperIds.insert(wallpaperID)
        } else {
            selectedWallpaperIds.remove(wallpaperID)
        }
    }

    @discardableResult
    func reorderTag(_ tag: String, to targetIndex: Int) -> Bool {
        guard let sourceIndex = tags.firstIndex(of: tag) else { return false }
        var updated = tags
        let clampedTarget = max(0, min(targetIndex, updated.count))
        var destination = clampedTarget
        if sourceIndex < destination {
            destination -= 1
        }
        guard sourceIndex != destination,
              destination >= 0,
              destination <= updated.count else {
            return true
        }
        let moved = updated.remove(at: sourceIndex)
        updated.insert(moved, at: destination)
        // 标签顺序是用户态数据，移动后必须立即写盘，避免重启后回退。
        tags = updated
        saveTags()
        return true
    }

    @discardableResult
    func createTagIfNeeded(_ rawName: String) -> String? {
        let tagName = rawName.trimmingCharacters(in: .whitespaces)
        guard !tagName.isEmpty, !tags.contains(tagName) else { return nil }
        tags.append(tagName)
        saveTags()
        return tagName
    }

    @discardableResult
    func renameTag(_ oldTag: String, to rawNewName: String) -> String? {
        let newName = rawNewName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != oldTag else { return nil }
        guard let index = tags.firstIndex(of: oldTag) else { return nil }

        tags[index] = newName
        mutateWallpapers(containingTag: oldTag) { wallpaper in
            wallpaper.tags.removeAll { $0 == oldTag }
            wallpaper.tags.append(newName)
        }
        saveTags()
        return newName
    }

    @discardableResult
    func removeTagFromLibrary(_ tag: String) -> Bool {
        guard tags.contains(tag) else { return false }
        tags.removeAll { $0 == tag }
        mutateWallpapers(containingTag: tag) { wallpaper in
            wallpaper.tags.removeAll { $0 == tag }
        }
        saveTags()
        return true
    }

    private func mutateWallpapers(containingTag tag: String, _ update: (inout VideoWallpaper) -> Void) {
        // 标签修改需要同步回写主库所有命中的壁纸快照，避免标签页和库页显示不一致。
        for wallpaperIndex in wallpapers.indices where wallpapers[wallpaperIndex].tags.contains(tag) {
            update(&wallpapers[wallpaperIndex])
        }
    }
}
