//
//  AppKitOLDownloadsGridView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//
//  AppKit NSCollectionView 容器，管理已下载在线视频的网格。
//  列数逻辑复用 GridLayoutHelper（zoomOffset 与在线库共享）。
//

import AppKit
import Combine

// MARK: - 容器

final class AppKitOLDownloadsContainerView: NSView, ModuleFocusable {
    private enum Section { case main }

    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var entries: [OLDownloadedEntry] = []
    private var filteredEntries: [OLDownloadedEntry] = []
    private var searchQuery: String = ""
    private var orderedIDs: [Int] = []
    private var orderedIndexByID: [Int: Int] = [:]
    private var entriesByID: [Int: OLDownloadedEntry] = [:]
    private var currentPlayingNormalizedPath: String?
    private var selectedIDs: Set<Int> = []
    private var selectedAnchorID: Int?
    private var isMultiSelectMode = false
    private var lastComputedColumns: Int = 3
    private var lastAppliedSnapshotIDs: [Int] = []
    private var suppressDownloadedIDsReload = false
    private var isLayoutItemSizeUpdateScheduled = false
    private var pendingPostDeletionSelectionIndex: Int?
    private var reloadEntriesTask: Task<Void, Never>?
    private var reloadEntriesGeneration: Int = 0
    private var sortMode: WallpaperSortMode = {
        let raw = UserDefaults.standard.string(forKey: "OLDownloadsSortMode") ?? ""
        return WallpaperSortMode(rawValue: raw) ?? .none
    }()
    private var sortAscending: Bool = {
        if UserDefaults.standard.object(forKey: "OLDownloadsSortAscending") == nil { return true }
        return UserDefaults.standard.bool(forKey: "OLDownloadsSortAscending")
    }()

    private var effectiveSelectedIDs: Set<Int> {
        if isMultiSelectMode {
            return selectedIDs
        }
        if !selectedIDs.isEmpty {
            return selectedIDs
        }
        if let anchor = selectedAnchorID {
            return [anchor]
        }
        return []
    }

    private var primarySelectedID: Int? {
        selectedAnchorID ?? selectedIDs.first
    }

    private var availableInspectorSelectionIDs: Set<Int> {
        Set(orderedIDs)
    }

    var hasAnySelection: Bool {
        !effectiveSelectedIDs.isEmpty
    }

    var hasSingleSelection: Bool {
        effectiveSelectedIDs.count == 1
    }

    var isMultiSelectModeEnabled: Bool {
        isMultiSelectMode
    }

    var hasAnyItems: Bool {
        !orderedIDs.isEmpty
    }

    var selectedCount: Int {
        effectiveSelectedIDs.count
    }

    private let emptyLabel: NSTextField = {
        let l = NSTextField(labelWithString: "暂无已下载 Pixabay 视频")
        l.alignment = .center
        l.textColor = .secondaryLabelColor
        l.font = .systemFont(ofSize: 16, weight: .regular)
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var searchField: NSSearchField = {
        let f = NSSearchField()
        f.placeholderString = "搜索"
        f.sendsSearchStringImmediately = true
        f.translatesAutoresizingMaskIntoConstraints = false
        f.target = self
        f.action = #selector(handleSearchFieldChanged(_:))
        return f
    }()


    private let scrollView: NSScrollView = {
        let s = NSScrollView()
        s.drawsBackground = false
        s.hasVerticalScroller = true
        s.hasHorizontalScroller = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var collectionView: AppKitOLDownloadsCollectionView = {
        let cv = AppKitOLDownloadsCollectionView()
        cv.isSelectable = false
        cv.backgroundColors = [.clear]
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        let l = NSCollectionViewFlowLayout()
        l.minimumInteritemSpacing = 8
        l.minimumLineSpacing = 16
        l.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return l
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, Int> = {
        NSCollectionViewDiffableDataSource<Section, Int>(
            collectionView: collectionView
        ) { [weak self] cv, indexPath, id -> NSCollectionViewItem? in
            guard let self, let entry = self.entriesByID[id] else { return nil }
            // 直接 init，避免 makeItem 触发 nib 查找导致崩溃
            let item = AppKitOLDownloadsItem(nibName: nil, bundle: nil)
            item.configure(
                entry: entry,
                isSelected: self.effectiveSelectedIDs.contains(id),
                isMultiSelectMode: self.isMultiSelectMode,
                isPlaying: self.normalizedPath(entry.localURL.path) == self.currentPlayingNormalizedPath
            )
            return item
        }
    }()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        reloadEntriesTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func setup() {
        AppKitOLDownloadsItem.resetHoverTrackingActivation()
        OnlineDownloadsBridge.shared.container = self
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = dataSource
        collectionView.onBackgroundLeftClick = { [weak self] in
            self?.handleBackgroundClick()
        }
        collectionView.cardPressStateHandler = { [weak self] indexPath, isPressed in
            guard let self,
                  let cell = self.collectionView.item(at: indexPath) as? AppKitOLDownloadsItem
            else { return }
            cell.applyPressedState(isPressed)
        }
        collectionView.primaryClickHandler = { [weak self] indexPath, event in
            self?.handlePrimaryClick(indexPath: indexPath, event: event)
        }
        collectionView.contextMenuProvider = { [weak self] indexPath in
            self?.makeContextMenu(for: indexPath)
        }
        collectionView.enterHandler = { [weak self] in self?.setSelectedAsWallpaper() }
        collectionView.selectAllHandler = { [weak self] in self?.selectAll() }
        collectionView.deleteHandler = { [weak self] in self?.deleteSelected() }
        collectionView.spaceHandler = { [weak self] in self?.previewSelected() }
        collectionView.arrowHandler = { [weak self] key in self?.moveSelectionByArrowKey(key) }
        scrollView.documentView = collectionView

        addSubview(scrollView)
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // 观察 zoomOffset 和 downloadedIDs 变化
        OnlineLibraryService.shared.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleLayoutItemSizeUpdate() }
            .store(in: &cancellables)

        OnlineLibraryService.shared.$downloadedIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.suppressDownloadedIDsReload else { return }
                self.reloadEntries()
            }
            .store(in: &cancellables)

        let playbackObserver = NotificationCenter.default.addObserver(
            forName: .onlineDownloadsPlaybackPathDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let path = notification.userInfo?["path"] as? String
            self.currentPlayingNormalizedPath = path.map(self.normalizedPath)
            self.refreshVisiblePlaybackItems(forceReload: true)
        }
        observers.append(playbackObserver)

        let deleteObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsDeleteSelected, object: nil, queue: .main
        ) { [weak self] _ in self?.deleteSelected() }
        observers.append(deleteObserver)

        let reloadObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsReload, object: nil, queue: .main
        ) { [weak self] _ in self?.reloadEntries() }
        observers.append(reloadObserver)

        let selectAllObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsSelectAll, object: nil, queue: .main
        ) { [weak self] _ in self?.selectAll() }
        observers.append(selectAllObserver)

        let toggleMultiObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsToggleMultiSelect, object: nil, queue: .main
        ) { [weak self] _ in self?.toggleMultiSelect() }
        observers.append(toggleMultiObserver)

        let previewObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsPreviewSelected, object: nil, queue: .main
        ) { [weak self] _ in self?.previewSelected() }
        observers.append(previewObserver)

        let setAsWallpaperObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsSetAsWallpaper, object: nil, queue: .main
        ) { [weak self] _ in self?.setSelectedAsWallpaper() }
        observers.append(setAsWallpaperObserver)

        let sortObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsSortDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let modeRaw = notification.userInfo?["mode"] as? String,
               let mode = WallpaperSortMode(rawValue: modeRaw) {
                self.sortMode = mode
                UserDefaults.standard.set(mode.rawValue, forKey: "OLDownloadsSortMode")
            }
            if let ascending = notification.userInfo?["ascending"] as? Bool {
                self.sortAscending = ascending
                UserDefaults.standard.set(ascending, forKey: "OLDownloadsSortAscending")
            }
            self.reloadEntries()
        }
        observers.append(sortObserver)

        let searchObserver = NotificationCenter.default.addObserver(
            forName: .olDownloadsSearchQueryChanged, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let q = notification.userInfo?["query"] as? String ?? ""
            self.searchQuery = q
            self.applyFilterAndSnapshot()
        }
        observers.append(searchObserver)

        let focusObserver = NotificationCenter.default.addObserver(
            forName: .moduleDidBecomeActive, object: nil, queue: .main
        ) { [weak self] notification in
            guard let module = notification.userInfo?["module"] as? String,
                  module == ModuleIdentifier.onlineLibrary.rawValue
            else { return }
            self?.requestFocus()
        }
        observers.append(focusObserver)

        reloadEntries()
    }

    // MARK: - 重载

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        OnlineDownloadsBridge.shared.isActive = (window != nil)
    }

    func reloadIfNeeded() {
        // updateNSView 调用入口（轻量 no-op）
    }

    private func reloadEntries() {
        let dir = OnlineLibraryService.downloadDirectory
        let sortMode = self.sortMode
        let sortAscending = self.sortAscending

        reloadEntriesTask?.cancel()
        reloadEntriesGeneration += 1
        let generation = reloadEntriesGeneration
        reloadEntriesTask = Task.detached(priority: .userInitiated) {
            let loaded = await Self.loadEntries(in: dir, sortMode: sortMode, sortAscending: sortAscending)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.reloadEntriesGeneration == generation else { return }
                self.entries = loaded
                self.applyFilterAndSnapshot()
            }
        }
    }

    @objc private func handleSearchFieldChanged(_ sender: NSSearchField) {
        let q = sender.stringValue
        searchQuery = q
        applyFilterAndSnapshot()
    }

    private func applyFilterAndSnapshot() {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            filteredEntries = entries
        } else {
            filteredEntries = entries.filter {
                $0.localURL.lastPathComponent.lowercased().contains(q)
            }
        }
        applyEntries(filteredEntries)
    }

    private func applyEntries(_ newEntries: [OLDownloadedEntry]) {
        // newEntries 可以是过滤后的子集，不覆盖 entries（全量）
        entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        orderedIDs = newEntries.map { $0.id }
        orderedIndexByID = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) })
        selectedIDs = effectiveSelectedIDs.intersection(Set(orderedIDs))
        if let anchor = selectedAnchorID, !orderedIDs.contains(anchor) {
            selectedAnchorID = nil
        }
        if !isMultiSelectMode, selectedIDs.isEmpty, let first = orderedIDs.first {
            selectedIDs = [first]
            selectedAnchorID = first
        }
        syncInspectorSelectionIfNeeded()

        let isEmpty = orderedIDs.isEmpty
        emptyLabel.stringValue = searchQuery.isEmpty ? "暂无已下载 Pixabay 视频" : "无匹配结果"
        emptyLabel.isHidden = !isEmpty
        applySnapshot(ids: orderedIDs)
        DispatchQueue.main.async {
            OnlineDownloadsBridge.shared.refreshToolbar()
        }
    }

    private func applySnapshot(ids: [Int]) {
        let isReorder = !lastAppliedSnapshotIDs.isEmpty
            && ids.count == lastAppliedSnapshotIDs.count
            && Set(ids) == Set(lastAppliedSnapshotIDs)
        let visibleCount = collectionView.indexPathsForVisibleItems().count
        let animateThreshold = max(20, visibleCount + 20)
        let isInsertDelete = !lastAppliedSnapshotIDs.isEmpty
            && !isReorder
            && abs(ids.count - lastAppliedSnapshotIDs.count) <= animateThreshold
        let shouldAnimate = isInsertDelete

        var snapshot = NSDiffableDataSourceSnapshot<Section, Int>()
        snapshot.appendSections([.main])
        snapshot.appendItems(ids, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: shouldAnimate) { [weak self] in
            guard let self else { return }
            self.lastAppliedSnapshotIDs = ids
            self.resolveSelectionAfterSnapshot()
            self.reloadVisibleSelectionItems(forceReload: true)
            self.refreshVisiblePlaybackItems(forceReload: true)
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        scheduleLayoutItemSizeUpdate()
    }

    private func updateLayoutItemSize() {
        let metrics = OnlineLibraryGridLayoutSupport.metrics(
            boundsWidth: bounds.width,
            zoomOffset: OnlineLibraryService.shared.zoomOffset,
            hoverScale: AppKitOLDownloadsItem.hoverScale,
            sectionInset: flowLayout.sectionInset
        )
        lastComputedColumns = metrics.columns
        flowLayout.minimumInteritemSpacing = metrics.interitemSpacing
        flowLayout.minimumLineSpacing = metrics.lineSpacing
        let newSize = metrics.itemSize
        guard flowLayout.itemSize != newSize else { return }
        flowLayout.itemSize = newSize
        // 布局变化与悬停视觉同步生效，避免渐变层在缩放期间出现跟随滞后。
        collectionView.collectionViewLayout?.invalidateLayout()
    }

    private func scheduleLayoutItemSizeUpdate() {
        guard !isLayoutItemSizeUpdateScheduled else { return }
        isLayoutItemSizeUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLayoutItemSizeUpdateScheduled = false
            self.updateLayoutItemSize()
        }
    }

    // MARK: - 外部接入 API（供主控层后续挂接）

    func requestFocus() {
        window?.makeFirstResponder(collectionView)
    }

    func focusGrid() {
        requestFocus()
    }

    func focusSearch() {
        // 搜索聚焦由工具栏 olDownloadsSearch 承担，此处保留为空以兼容 bridge 调用
    }

    func selectAll() {
        // 未进入多选模式时自动先进入，对齐视频库/图片库行为
        if !isMultiSelectMode {
            isMultiSelectMode = true
            collectionView.allowsMultipleSelection = true
            if let anchor = selectedAnchorID {
                selectedIDs = [anchor]
            } else if let first = orderedIDs.first {
                selectedAnchorID = first
                selectedIDs = [first]
            }
            reloadVisibleSelectionItems(forceReload: true)
        }
        selectedIDs = Set(orderedIDs)
        reloadVisibleSelectionItems()
        syncInspectorSelectionIfNeeded()
        OnlineDownloadsBridge.shared.refreshToolbar()
    }

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if isMultiSelectMode {
            selectedIDs = []
            selectedAnchorID = nil
        } else {
            selectedIDs = []
        }
        collectionView.allowsMultipleSelection = isMultiSelectMode
        reloadVisibleSelectionItems(forceReload: true)
        syncInspectorSelectionIfNeeded()
    }

    func deleteSelected() {
        let targets = Array(effectiveSelectedIDs)
        guard !targets.isEmpty else { return }
        let all = entries
        let currentIndex = all.firstIndex { $0.id == (primarySelectedID ?? targets.first!) } ?? 0
        pendingPostDeletionSelectionIndex = currentIndex
        suppressDownloadedIDsReload = true
        for id in targets {
            guard let entry = entriesByID[id] else { continue }
            let local = OLLocalFile(url: entry.localURL, fileSize: 0, creationDate: Date())
            OnlineLibraryService.shared.deleteLocalFile(local)
        }
        suppressDownloadedIDsReload = false
        reloadEntries()
    }

    func showInfo() {
        let service = OnlineLibraryService.shared
        let selectedID = primarySelectedID
        let availableIDs = availableInspectorSelectionIDs

        guard !isMultiSelectMode,
              let selectedID,
              availableIDs.contains(selectedID) else {
            return
        }

        if service.selectedDownloadedItemIDForInspector == selectedID {
            service.dismissSelectedDownloadedInspector()
        } else {
            service.presentInspectorForSelectedDownloadedItem(
                selectedID,
                isMultiSelectMode: isMultiSelectMode,
                availableIDs: availableIDs
            )
        }
    }

    func revealInFinder() {
        let ids = Array(effectiveSelectedIDs)
        let urls = ids.compactMap { entriesByID[$0]?.localURL }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func previewSelected() {
        let targets: [Int]
        let startID: Int
        if isMultiSelectMode {
            let effectiveIDs = effectiveSelectedIDs
            if !effectiveIDs.isEmpty {
                targets = orderedIDs.filter { effectiveIDs.contains($0) }
                startID = primarySelectedID ?? targets.first ?? orderedIDs.first ?? 0
            } else if let anchor = selectedAnchorID {
                targets = [anchor]
                startID = anchor
            } else {
                targets = []
                startID = 0
            }
        } else {
            targets = orderedIDs
            startID = primarySelectedID ?? orderedIDs.first ?? 0
        }
        let urls = targets.compactMap { entriesByID[$0]?.localURL }
        guard !urls.isEmpty else { return }
        let startIndex = max(0, targets.firstIndex(of: startID) ?? 0)
        OLDownloadsQuickLookController.shared.open(
            ids: targets,
            urls: urls,
            index: startIndex,
            selectionSync: { [weak self] id in
                self?.syncSelectionFromQuickLook(id: id)
            }
        )
    }

    func setSelectedAsWallpaper() {
        let id = primarySelectedID
        guard let id else { return }
        setLocalAsWallpaper(id: id)
    }

    func moveSelectionByArrowKey(_ keyCode: UInt16) {
        guard !orderedIDs.isEmpty else { return }
        guard let currentID = primarySelectedID ?? orderedIDs.first,
              let idx = orderedIDs.firstIndex(of: currentID) else { return }
        let cols = max(1, lastComputedColumns)
        var newIdx = idx
        switch keyCode {
        case 123: newIdx = max(0, idx - 1)
        case 124: newIdx = min(orderedIDs.count - 1, idx + 1)
        case 126: newIdx = max(0, idx - cols)
        case 125: newIdx = min(orderedIDs.count - 1, idx + cols)
        default: return
        }
        guard newIdx != idx else { return }
        let targetID = orderedIDs[newIdx]
        selectedAnchorID = targetID
        if isMultiSelectMode {
            selectedIDs = [targetID]
        } else {
            selectedIDs = [targetID]
        }
        reloadVisibleSelectionItems()
        syncInspectorSelectionIfNeeded()
        scrollToSelectedItemIfNeeded()
        OnlineDownloadsBridge.shared.refreshToolbar()
    }

    private func handlePrimaryClick(indexPath: IndexPath, event: NSEvent) {
        guard indexPath.item < orderedIDs.count else { return }
        let id = orderedIDs[indexPath.item]
        if isMultiSelectMode {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        } else {
            selectedIDs = [id]
        }
        selectedAnchorID = id
        reloadVisibleSelectionItems()
        syncInspectorSelectionIfNeeded()
        OnlineDownloadsBridge.shared.refreshToolbar()
        // 单选态点击（含已选中卡片再次点击）直接呼出详情面板（呈现而非切换）。
        if !isMultiSelectMode, availableInspectorSelectionIDs.contains(id) {
            OnlineLibraryService.shared.presentInspectorForSelectedDownloadedItem(
                id,
                isMultiSelectMode: isMultiSelectMode,
                availableIDs: availableInspectorSelectionIDs
            )
        }
        if let item = collectionView.item(at: indexPath) as? AppKitOLDownloadsItem {
            let point = item.view.convert(event.locationInWindow, from: nil)
            if item.shouldTriggerPlayAction(at: point) {
                setLocalAsWallpaper(id: id)
            }
        }
    }

    private func setLocalAsWallpaper(id: Int) {
        if let entry = entriesByID[id] {
            currentPlayingNormalizedPath = normalizedPath(entry.localURL.path)
            refreshVisiblePlaybackItems(forceReload: true)
        }
        OnlineLibraryService.shared.setLocalFileAsWallpaper(id: id)
    }

    private func reloadVisibleSelectionItems(forceReload: Bool = false) {
        let visible = collectionView.indexPathsForVisibleItems()
        var fallbackReloadPaths = Set<IndexPath>()
        for ip in visible {
            guard ip.item < orderedIDs.count,
                  ip.item >= 0 else { continue }
            let id = orderedIDs[ip.item]
            if let cell = collectionView.item(at: ip) as? AppKitOLDownloadsItem {
                cell.applySelectionState(effectiveSelectedIDs.contains(id), multiSelectMode: isMultiSelectMode)
            } else if forceReload {
                fallbackReloadPaths.insert(ip)
            }
        }
        if !fallbackReloadPaths.isEmpty {
            collectionView.reloadItems(at: fallbackReloadPaths)
        }
    }

    private func refreshVisiblePlaybackItems(forceReload: Bool = false) {
        let visible = collectionView.indexPathsForVisibleItems()
        var fallbackReloadPaths = Set<IndexPath>()
        for ip in visible {
            guard ip.item >= 0, ip.item < orderedIDs.count else { continue }
            let id = orderedIDs[ip.item]
            guard let entry = entriesByID[id] else { continue }
            let shouldBePlaying = normalizedPath(entry.localURL.path) == currentPlayingNormalizedPath
            if let cell = collectionView.item(at: ip) as? AppKitOLDownloadsItem {
                cell.applyPlayingState(isPlaying: shouldBePlaying)
            } else if forceReload {
                fallbackReloadPaths.insert(ip)
            }
        }
        if !fallbackReloadPaths.isEmpty {
            collectionView.reloadItems(at: fallbackReloadPaths)
        }
    }

    private func makeContextMenu(for indexPath: IndexPath?) -> NSMenu? {
        if let indexPath, indexPath.item < orderedIDs.count {
            let id = orderedIDs[indexPath.item]
            selectedAnchorID = id
            if !isMultiSelectMode || !selectedIDs.contains(id) {
                selectedIDs = [id]
            }
            reloadVisibleSelectionItems()
            syncInspectorSelectionIfNeeded()
        }
        guard !effectiveSelectedIDs.isEmpty else { return nil }

        let menu = NSMenu()
        menu.autoenablesItems = false
        let singleSelectionEnabled = !isMultiSelectMode && primarySelectedID != nil
        menu.addItem(
            makeMenuItem(
                title: "设为壁纸",
                symbolName: "play.circle",
                accessibilityDescription: "设为壁纸",
                action: #selector(contextSetAsWallpaper),
                isEnabled: singleSelectionEnabled
            )
        )
        menu.addItem(
            makeMenuItem(
                title: "详细信息",
                symbolName: "info.circle",
                accessibilityDescription: "详细信息",
                action: #selector(contextShowInfo),
                isEnabled: singleSelectionEnabled
            )
        )
        menu.addItem(
            makeMenuItem(
                title: "查看文件",
                symbolName: "folder",
                accessibilityDescription: "在访达中显示",
                action: #selector(contextRevealInFinder),
                isEnabled: singleSelectionEnabled
            )
        )

        menu.addItem(.separator())

        menu.addItem(
            makeMenuItem(
                title: "删除",
                symbolName: "trash",
                accessibilityDescription: "删除",
                action: #selector(contextDeleteSelected),
                isEnabled: !selectedIDs.isEmpty || selectedAnchorID != nil
            )
        )

        return menu
    }

    @objc private func contextSetAsWallpaper() {
        setSelectedAsWallpaper()
    }

    @objc private func contextShowInfo() {
        showInfo()
    }

    @objc private func contextRevealInFinder() {
        revealInFinder()
    }

    @objc private func contextDeleteSelected() {
        deleteSelected()
    }

    private func makeMenuItem(
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

    private func syncSelectionFromQuickLook(id: Int) {
        guard orderedIndexByID[id] != nil else { return }
        selectedAnchorID = id
        selectedIDs = [id]
        reloadVisibleSelectionItems()
        syncInspectorSelectionIfNeeded()
        scrollToSelectedItemIfNeeded()
    }

    private func handleBackgroundClick() {
        guard !isMultiSelectMode else { return }
        selectedIDs = []
        selectedAnchorID = nil
        reloadVisibleSelectionItems()
        syncInspectorSelectionIfNeeded()
    }

    private func scrollToSelectedItemIfNeeded() {
        guard !isMultiSelectMode,
              let selectedID = primarySelectedID,
              let index = orderedIndexByID[selectedID] else { return }
        let indexPath = IndexPath(item: index, section: 0)
        guard let attrs = flowLayout.layoutAttributesForItem(at: indexPath) else { return }
        let itemFrame = attrs.frame
        let visibleRect = scrollView.contentView.bounds
        guard !visibleRect.contains(itemFrame) else { return }
        let targetY: CGFloat
        if itemFrame.minY < visibleRect.minY {
            targetY = max(0, itemFrame.minY - 4)
        } else {
            targetY = itemFrame.maxY - visibleRect.height + 4
        }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visibleRect.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func resolveSelectionAfterSnapshot() {
        guard let desiredIndex = pendingPostDeletionSelectionIndex else { return }
        pendingPostDeletionSelectionIndex = nil
        guard !orderedIDs.isEmpty else {
            selectedAnchorID = nil
            selectedIDs = []
            syncInspectorSelectionIfNeeded()
            return
        }
        let nextIndex = min(desiredIndex, orderedIDs.count - 1)
        let nextID = orderedIDs[nextIndex]
        selectedAnchorID = nextID
        selectedIDs = [nextID]
        syncInspectorSelectionIfNeeded()
    }

    private func syncInspectorSelectionIfNeeded() {
        OnlineLibraryService.shared.syncSelectedDownloadedInspectorIfNeeded(
            selectedID: primarySelectedID,
            isMultiSelectMode: isMultiSelectMode,
            availableIDs: availableInspectorSelectionIDs
        )
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    nonisolated private static func makeEntry(id: Int, localURL: URL) async -> OLDownloadedEntry {
        let metadata = await OnlineLibraryDownloadedAssetMetadata.load(from: localURL)
        return OLDownloadedEntry(
            id: id,
            localURL: localURL,
            fileSize: metadata.fileSize,
            duration: metadata.durationSeconds > 0 ? metadata.durationSeconds : nil,
            resolutionString: metadata.resolutionString
        )
    }

    nonisolated private static func loadEntries(
        in directory: URL,
        sortMode: WallpaperSortMode,
        sortAscending: Bool
    ) async -> [OLDownloadedEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var loaded: [OLDownloadedEntry] = []
        loaded.reserveCapacity(files.count)
        for url in files {
            guard !Task.isCancelled else { return [] }
            let name = url.lastPathComponent
            guard name.hasPrefix("online_"), name.hasSuffix(".mp4"),
                  let id = Int(name.dropFirst("online_".count).dropLast(".mp4".count))
            else { continue }
            loaded.append(await makeEntry(id: id, localURL: url))
        }

        loaded.sort { lhs, rhs in
            switch sortMode {
            case .none:
                let lDate = (try? lhs.localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rDate = (try? rhs.localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return sortAscending ? (lDate < rDate) : (lDate > rDate)
            case .name:
                let compare = lhs.localURL.lastPathComponent.localizedStandardCompare(rhs.localURL.lastPathComponent)
                return sortAscending ? (compare == .orderedAscending) : (compare == .orderedDescending)
            case .size:
                let lSize = (try? lhs.localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
                let rSize = (try? rhs.localURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
                return sortAscending ? (lSize < rSize) : (lSize > rSize)
            case .dateAdded:
                let lDate = (try? lhs.localURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                    ?? (try? lhs.localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast
                let rDate = (try? rhs.localURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                    ?? (try? rhs.localURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast
                return sortAscending ? (lDate < rDate) : (lDate > rDate)
            }
        }

        return loaded
    }
}

extension Notification.Name {
    static let olDownloadsDeleteSelected    = Notification.Name("OLDownloadsDeleteSelected")
    static let olDownloadsSelectAll         = Notification.Name("OLDownloadsSelectAll")
    static let olDownloadsToggleMultiSelect = Notification.Name("OLDownloadsToggleMultiSelect")
    static let olDownloadsPreviewSelected   = Notification.Name("OLDownloadsPreviewSelected")
    static let olDownloadsSetAsWallpaper    = Notification.Name("OLDownloadsSetAsWallpaper")
    static let olDownloadsReload            = Notification.Name("OLDownloadsReload")
    static let olDownloadsSortDidChange     = Notification.Name("OLDownloadsSortDidChange")
    static let olDownloadsSearchQueryChanged  = Notification.Name("OLDownloadsSearchQueryChanged")
}
