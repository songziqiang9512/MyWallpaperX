//
//  AppKitLibraryGridView.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class AppKitLibraryGridContainerView: NSView, ModuleFocusable {
    private enum Section {
        case main
    }

    let wallpaperManager: WallpaperManager
    let thumbnailProvider: AppKitThumbnailProvider
    let animatesReorder: Bool
    /// 删除/导入时对可见区域内（≤35条变化）做原生 diffable 动画，独立于 animatesReorder。
    let animatesInsertDelete: Bool
    private var cancellables = Set<AnyCancellable>()
    private var viewportPrefetchWorkItem: DispatchWorkItem?
    var wallpapersByID: [String: VideoWallpaper] = [:]
    private var normalizedPathToIDs: [String: Set<String>] = [:]
    var orderedIDs: [String] = []
    private var orderedIndexByID: [String: Int] = [:]
    var sourceWallpapers: [VideoWallpaper] = []
    var isApplyingSelectionSnapshot = false
    private var lastAppliedSnapshotIDs: [String] = []
    private var pendingSnapshotIDs: [String] = []
    private var isSnapshotApplyScheduled = false
    private var boxSelectionState: BoxSelectionState?
    private var isMultiSelectModeVisualUpdateScheduled = false
    private var pendingThumbnailReloadPaths = Set<String>()
    private var isThumbnailReloadScheduled = false
    private var isSelectionSyncScheduled = false
    private var isSelectionVisualUpdateScheduled = false
    private var isVisibleItemStateRefreshScheduled = false
    private var missingPathProbeTimer: DispatchSourceTimer?
    private var visibleMissingWallpaperIDs = Set<String>()
    private var lastAppliedQuery: String = ""
    private var pendingVisibleColumnCount: Int?
    private var isLayoutItemSizeUpdateScheduled = false
    private var lastPrefetchRange: ClosedRange<Int>?
    private var lastObservedPlayingNormalizedPath: String?
    private var lastObservedSelectedIDs = Set<String>()
    private var scrollToTopObserver: NSObjectProtocol?
    private var moduleFocusObserver: NSObjectProtocol?
    private var isScrollToTopAnimating = false
    private var restingScrollOrigin: NSPoint?

    private let emptyStateLabel: NSTextField = {
        let label = NSTextField(labelWithString: "暂无视频\n请导入视频文件")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 18, weight: .regular)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    lazy var collectionView: AppKitWallpaperCollectionView = {
        let collectionView = AppKitWallpaperCollectionView()
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.onBackgroundLeftClick = { [weak self] in
            self?.handleBackgroundClick()
        }
        collectionView.contextMenuProvider = { [weak self] indexPath in
            self?.makeContextMenu(for: indexPath)
        }
        collectionView.cardInteractionHandler = { [weak self] in
            self?.wallpaperManager.markCardInteraction()
        }
        collectionView.playRequestHandler = { [weak self] indexPath in
            self?.handlePlayRequest(at: indexPath)
        }
        collectionView.primaryClickHandler = { [weak self] indexPath in
            self?.handlePrimaryClick(at: indexPath) ?? false
        }
        collectionView.cardPressStateHandler = { [weak self] indexPath, isPressed in
            self?.updateCardPressState(at: indexPath, isPressed: isPressed)
        }
        collectionView.boxSelectionBeginHandler = { [weak self] indexPath in
            self?.beginBoxSelection(at: indexPath) ?? false
        }
        collectionView.boxSelectionUpdateHandler = { [weak self] rect in
            self?.updateBoxSelection(in: rect)
        }
        collectionView.boxSelectionEndHandler = { [weak self] in
            self?.endBoxSelection()
        }
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 16
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return layout
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, String> = {
        let dataSource = NSCollectionViewDiffableDataSource<Section, String>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, wallpaperID in
            guard let self,
                  let wallpaper = self.wallpapersByID[wallpaperID] else {
                return nil
            }
            let item = AppKitWallpaperItem(nibName: nil, bundle: nil)
            self.configure(item: item, for: wallpaper)
            return item
        }
        return dataSource
    }()

    init(wallpaperManager: WallpaperManager, animatesReorder: Bool = false, animatesInsertDelete: Bool = false) {
        self.wallpaperManager = wallpaperManager
        self.animatesReorder = animatesReorder
        self.animatesInsertDelete = animatesInsertDelete
        self.thumbnailProvider = AppKitThumbnailProvider(wallpaperManager: wallpaperManager)
        super.init(frame: .zero)
        AppKitWallpaperItem.resetHoverTrackingActivation()
        setupViewHierarchy()
        setupObservers()
        observeScrollToTopRequests()
        startMissingPathProbeTimer()
        observeModuleFocusRequests()
    }

    deinit {
        if let scrollToTopObserver {
            NotificationCenter.default.removeObserver(scrollToTopObserver)
        }
        if let moduleFocusObserver {
            NotificationCenter.default.removeObserver(moduleFocusObserver)
        }
        viewportPrefetchWorkItem?.cancel()
        missingPathProbeTimer?.cancel()
        missingPathProbeTimer = nil
        cancellables.removeAll()
    }

    // MARK: - ModuleFocusable

    func requestFocus() {
        window?.makeFirstResponder(collectionView)
    }

    private func observeModuleFocusRequests() {
        moduleFocusObserver = NotificationCenter.default.addObserver(
            forName: .moduleDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let module = notification.userInfo?["module"] as? String,
                  module == ModuleIdentifier.videoLibrary.rawValue else { return }
            self.requestFocus()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        scheduleRestingScrollOriginCapture()
    }

    override func layout() {
        super.layout()
        scheduleLayoutItemSizeUpdate()
    }

    private func observeScrollToTopRequests() {
        scrollToTopObserver = NotificationCenter.default.addObserver(
            forName: .appKitRequestScrollToTopForCurrentSelection,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.scrollToTop(animated: true)
        }
    }

    func update(wallpapers: [VideoWallpaper]) {
        // 更新入口区分 fast path 与全量重建，避免每次轻微数据变化都重刷整个网格。
        let query = wallpaperManager.normalizedSearchQuery
        let canUseFastPath =
            query.isEmpty &&
            lastAppliedQuery.isEmpty &&
            sourceWallpapers.count == wallpapers.count &&
            zip(sourceWallpapers, wallpapers).allSatisfy { $0.id == $1.id }

        sourceWallpapers = wallpapers
        if canUseFastPath {
            let previousByID = wallpapersByID
            var byID: [String: VideoWallpaper] = [:]
            byID.reserveCapacity(wallpapers.count)
            var changedRenderableIDs = Set<String>()
            var hasPathMutation = false
            for wallpaper in wallpapers {
                if let previous = previousByID[wallpaper.id] {
                    if previous.isFavorite != wallpaper.isFavorite {
                        changedRenderableIDs.insert(wallpaper.id)
                    }
                    if previous.fileSize != wallpaper.fileSize
                        || previous.duration != wallpaper.duration
                        || previous.resolution != wallpaper.resolution {
                        changedRenderableIDs.insert(wallpaper.id)
                    }
                    if previous.path != wallpaper.path {
                        hasPathMutation = true
                        changedRenderableIDs.insert(wallpaper.id)
                    }
                }
                byID[wallpaper.id] = wallpaper
            }
            wallpapersByID = byID
            if hasPathMutation {
                rebuildPathIndex(wallpapers)
            }
            if !changedRenderableIDs.isEmpty {
                reloadVisibleItems(forIDs: changedRenderableIDs)
            }
            scheduleVisibleItemStateRefresh()
            scheduleSyncSelectionFromManager()
            emptyStateLabel.isHidden = !orderedIDs.isEmpty
            return
        }

        applyFilterAndSnapshot(usingNormalizedQuery: query)
        scheduleSyncSelectionFromManager()
        emptyStateLabel.isHidden = !orderedIDs.isEmpty
    }

    private func setupViewHierarchy() {
        // 网格仅负责“列表 + 空状态”，不在这里堆额外装饰容器，减少层级和命中误差。
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        scrollView.documentView = collectionView
        scrollView.contentView.postsBoundsChangedNotifications = true

        addSubview(scrollView)
        addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func setupObservers() {
        // 所有后台变化都通过 publisher 进入同一批调度点，避免卡片逐个独立刷新。
        wallpaperManager.thumbnailReadyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changedPath in
                self?.enqueueThumbnailReload(forNormalizedPath: changedPath)
            }
            .store(in: &cancellables)

        wallpaperManager.$selectedWallpaperId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSyncSelectionFromManager()
                self?.scheduleSelectionVisualUpdate()
            }
            .store(in: &cancellables)

        wallpaperManager.$selectedWallpaperIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSyncSelectionFromManager()
                self?.scheduleSelectionVisualUpdate()
            }
            .store(in: &cancellables)

        wallpaperManager.$isMultiSelectMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSyncSelectionFromManager()
                self?.scheduleMultiSelectModeVisualRefresh()
            }
            .store(in: &cancellables)

        wallpaperManager.$currentWallpaper
            .receive(on: DispatchQueue.main)
            .sink { [weak self] wallpaper in
                self?.handleCurrentWallpaperChange(wallpaper)
            }
            .store(in: &cancellables)

        // 用户调整缩放时重新计算卡片尺寸。
        wallpaperManager.$gridZoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLayoutItemSize()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.scheduleViewportPrefetch()
        }
        .store(in: &cancellables)
    }

    private func configure(item: AppKitWallpaperItem, for wallpaper: VideoWallpaper) {
        let isSelected = wallpaperManager.selectedWallpaperId == wallpaper.id
            || wallpaperManager.selectedWallpaperIds.contains(wallpaper.id)
        let isPlaying = wallpaperManager.currentWallpaper?.path == wallpaper.path
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

    private func rebuildPathIndex(_ wallpapers: [VideoWallpaper]) {
        // 同一路径可能对应多个 ID（导入/重建时），这里保留路径到 ID 集合的反向索引。
        var mapping: [String: Set<String>] = [:]
        for wallpaper in wallpapers {
            let normalized = wallpaperManager.normalizedPath(wallpaper.path)
            mapping[normalized, default: []].insert(wallpaper.id)
        }
        normalizedPathToIDs = mapping
    }

    private func applySnapshot(ids: [String]) {
        // snapshot 只在主线程批量提交，避免频繁 apply 造成滚动时抖动。
        pendingSnapshotIDs = ids
        guard !isSnapshotApplyScheduled else { return }
        isSnapshotApplyScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSnapshotApplyScheduled = false
            let idsToApply = self.pendingSnapshotIDs
            self.pendingSnapshotIDs = []
            guard idsToApply != self.lastAppliedSnapshotIDs else { return }

            // 重排动画：纯重排（数量不变）且开启 animatesReorder 时生效。
            // 增删动画：开启 animatesInsertDelete、有历史快照、且变化量在「视口内可见数 + 20」以内时生效，
            // 超出视口的大批量变化跳过动画避免卡顿。
            let isReorder = !self.lastAppliedSnapshotIDs.isEmpty
                && idsToApply.count == self.lastAppliedSnapshotIDs.count
                && Set(idsToApply) == Set(self.lastAppliedSnapshotIDs)
            let visibleCount = self.collectionView.indexPathsForVisibleItems().count
            let animateThreshold = max(20, visibleCount + 20)
            let isInsertDelete = !self.lastAppliedSnapshotIDs.isEmpty
                && !isReorder
                && abs(idsToApply.count - self.lastAppliedSnapshotIDs.count) <= animateThreshold
            let shouldAnimate = (self.animatesReorder && isReorder)
                || (self.animatesInsertDelete && isInsertDelete)

            var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
            snapshot.appendSections([.main])
            snapshot.appendItems(idsToApply, toSection: .main)
            self.dataSource.apply(snapshot, animatingDifferences: shouldAnimate) { [weak self] in
                guard let self else { return }
                self.lastAppliedSnapshotIDs = idsToApply
                self.scheduleVisibleItemStateRefresh()
                self.scheduleRestingScrollOriginCapture()
            }
        }
    }

    private func applyFilterAndSnapshot(usingNormalizedQuery query: String) {
        // 过滤后的结果必须去重后再进 snapshot，否则同一个文件可能出现重复卡片。
        let filtered = wallpaperManager.filterWallpapers(sourceWallpapers, usingNormalizedQuery: query)
        var seenIDs = Set<String>()
        var uniqueWallpapers: [VideoWallpaper] = []
        uniqueWallpapers.reserveCapacity(filtered.count)
        for wallpaper in filtered where seenIDs.insert(wallpaper.id).inserted {
            uniqueWallpapers.append(wallpaper)
        }

        var byID: [String: VideoWallpaper] = [:]
        byID.reserveCapacity(uniqueWallpapers.count)
        for wallpaper in uniqueWallpapers {
            byID[wallpaper.id] = wallpaper
        }

        wallpapersByID = byID
        orderedIDs = uniqueWallpapers.map(\.id)
        orderedIndexByID = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) })
        rebuildPathIndex(uniqueWallpapers)
        applySnapshot(ids: orderedIDs)
        lastAppliedQuery = query
        lastPrefetchRange = nil
        emptyStateLabel.isHidden = !orderedIDs.isEmpty
        scheduleViewportPrefetch()
    }

    private func updateLayoutItemSize() {
        let availableWidth = max(0, bounds.width - flowLayout.sectionInset.left - flowLayout.sectionInset.right)
        let columnCount = calculateColumnCount(width: availableWidth)
        let baseSpacing: CGFloat = 8
        // 动态间距：卡片宽 × (scale-1)，刚好容纳放大量不遮盖相邻卡片
        let estimatedCardWidth = max(100, (availableWidth - baseSpacing * CGFloat(max(0, columnCount - 1))) / CGFloat(columnCount))
        let hoverScale: CGFloat = AppKitWallpaperItem.hoverScale
        let minSpacing = estimatedCardWidth * (hoverScale - 1.0)
        let effectiveSpacing = max(baseSpacing, minSpacing)
        flowLayout.minimumInteritemSpacing = effectiveSpacing
        flowLayout.minimumLineSpacing = effectiveSpacing
        let totalSpacing = CGFloat(max(0, columnCount - 1)) * effectiveSpacing
        let cardWidth = max(100, (availableWidth - totalSpacing) / CGFloat(columnCount))
        let cardHeight = max(56, cardWidth / (16.0 / 9.0))
        let newSize = NSSize(width: floor(cardWidth), height: floor(cardHeight + 2))

        if flowLayout.itemSize != newSize {
            flowLayout.itemSize = newSize
            // 布局变化与悬停视觉同步生效，避免渐变层在缩放期间出现跟随滞后。
            self.collectionView.collectionViewLayout?.invalidateLayout()
        }
        scheduleVisibleGridColumnCountUpdateIfNeeded(columnCount)
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

    private func scrollToTop(animated: Bool) {
        guard !isScrollToTopAnimating else { return }
        guard scrollView.documentView != nil else { return }

        let targetOrigin = restingScrollOrigin ?? NSPoint(x: 0, y: 0)
        guard scrollView.contentView.bounds.origin != targetOrigin else { return }

        viewportPrefetchWorkItem?.cancel()
        isScrollToTopAnimating = true
        NotificationCenter.default.post(name: .appKitLibraryGridScrollToTopAnimationWillStart, object: nil)
        NSAnimationContext.runAnimationGroup { context in
            let distance = abs(scrollView.contentView.bounds.origin.y - targetOrigin.y)
            context.duration = animated ? min(0.36, max(0.20, distance / 5200.0)) : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.85, 0.20, 1.0)
            scrollView.contentView.animator().setBoundsOrigin(targetOrigin)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.isScrollToTopAnimating = false
            NotificationCenter.default.post(name: .appKitLibraryGridScrollToTopAnimationDidEnd, object: nil)
        }
    }

    private func scheduleRestingScrollOriginCapture() {
        guard restingScrollOrigin == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.restingScrollOrigin == nil else { return }
            // 不调用 layoutSubtreeIfNeeded —— main.async 回调时布局已完成，
            // 强制触发会在父视图 layout() 执行期间造成布局递归警告。
            self.captureRestingScrollOriginIfNeeded()
        }
    }

    private func captureRestingScrollOriginIfNeeded() {
        guard restingScrollOrigin == nil else { return }
        guard window != nil, scrollView.documentView != nil else { return }
        guard collectionView.numberOfItems(inSection: 0) > 0 else { return }
        restingScrollOrigin = scrollView.contentView.bounds.origin
    }

    private func calculateColumnCount(width: CGFloat) -> Int {
        GridLayoutHelper.columnCount(
            for: width,
            zoomOffset: wallpaperManager.gridZoomOffset
        )
    }

    private func enqueueThumbnailReload(forNormalizedPath path: String) {
        // 缩略图生成完成只刷新仍在可见区域的卡片，避免全量 reload 干扰滚动。
        pendingThumbnailReloadPaths.insert(path)
        guard !isThumbnailReloadScheduled else { return }
        isThumbnailReloadScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isThumbnailReloadScheduled = false

            let paths = self.pendingThumbnailReloadPaths
            self.pendingThumbnailReloadPaths.removeAll()
            guard !paths.isEmpty else { return }
            let visibleIndexPaths = Set(self.collectionView.indexPathsForVisibleItems())
            guard !visibleIndexPaths.isEmpty else { return }

            var indexPaths = Set<IndexPath>()
            for normalizedPath in paths {
                guard let ids = self.normalizedPathToIDs[normalizedPath], !ids.isEmpty else { continue }
                for id in ids {
                    guard let index = self.orderedIndexByID[id] else { continue }
                    let candidate = IndexPath(item: index, section: 0)
                    if visibleIndexPaths.contains(candidate) {
                        indexPaths.insert(candidate)
                    }
                }
            }

            guard !indexPaths.isEmpty else { return }
            self.collectionView.reloadItems(at: indexPaths)
        }
    }

    func reloadVisibleItems() {
        // 这是最后的粗刷新兜底入口，正常路径应优先走更小粒度的 ID / path 刷新。
        let visible = collectionView.indexPathsForVisibleItems()
        guard !visible.isEmpty else { return }
        collectionView.reloadItems(at: Set(visible))
    }

    private func reloadVisibleItems(forIDs ids: Set<String>) {
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

    private func reloadVisibleItems(forNormalizedPaths paths: Set<String>) {
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

    private func scheduleMultiSelectModeVisualRefresh() {
        guard !isMultiSelectModeVisualUpdateScheduled else { return }
        isMultiSelectModeVisualUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMultiSelectModeVisualUpdateScheduled = false
            self.refreshVisibleItemsForMultiSelectMode()
        }
    }

    private func refreshVisibleItemsForMultiSelectMode() {
        let visibleIndexPaths = Set(collectionView.indexPathsForVisibleItems())
        guard !visibleIndexPaths.isEmpty else { return }

        var selectedIDs = wallpaperManager.selectedWallpaperIds
        if let single = wallpaperManager.selectedWallpaperId {
            selectedIDs.insert(single)
        }
        let isMultiSelect = wallpaperManager.isMultiSelectMode
        var fallbackReloadIndexPaths = Set<IndexPath>()

        for indexPath in visibleIndexPaths {
            guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { continue }
            let id = orderedIDs[indexPath.item]
            if let item = collectionView.item(at: indexPath) as? AppKitWallpaperItem {
                item.applySelectionState(
                    isSelected: selectedIDs.contains(id),
                    multiSelectMode: isMultiSelect
                )
            } else {
                fallbackReloadIndexPaths.insert(indexPath)
            }
        }

        if !fallbackReloadIndexPaths.isEmpty {
            collectionView.reloadItems(at: fallbackReloadIndexPaths)
        }
    }

    private func scheduleSelectionVisualUpdate() {
        // 选择态视觉更新被合并到下一主线程回合，避免同一批 selection 改动触发多次刷新。
        guard !isSelectionVisualUpdateScheduled else { return }
        isSelectionVisualUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSelectionVisualUpdateScheduled = false
            self.updateSelectionVisualsIfNeeded()
        }
    }

    private func scheduleVisibleItemStateRefresh() {
        // snapshot 完成后统一修正可见卡片的收藏 / 选中 / 播放状态，避免旧 cell 残留。
        guard !isVisibleItemStateRefreshScheduled else { return }
        isVisibleItemStateRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isVisibleItemStateRefreshScheduled = false
            self.refreshVisibleItemsForCurrentState()
        }
    }

    private func refreshVisibleItemsForCurrentState() {
        let visibleIndexPaths = Set(collectionView.indexPathsForVisibleItems())
        guard !visibleIndexPaths.isEmpty else { return }

        var selectedIDs = wallpaperManager.selectedWallpaperIds
        if let single = wallpaperManager.selectedWallpaperId {
            selectedIDs.insert(single)
        }
        let currentPlayingNormalizedPath = wallpaperManager.currentWallpaper.map { wallpaperManager.normalizedPath($0.path) }
        let isMultiSelect = wallpaperManager.isMultiSelectMode
        var fallbackReloadIndexPaths = Set<IndexPath>()

        for indexPath in visibleIndexPaths {
            guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { continue }
            let id = orderedIDs[indexPath.item]
            guard let wallpaper = wallpapersByID[id] else { continue }

            if let item = collectionView.item(at: indexPath) as? AppKitWallpaperItem {
                item.applyFavoriteState(
                    isFavorite: wallpaper.isFavorite
                )
                item.applySelectionState(
                    isSelected: selectedIDs.contains(id),
                    multiSelectMode: isMultiSelect
                )
                let shouldBePlaying: Bool
                if let currentPlayingNormalizedPath {
                    shouldBePlaying = wallpaperManager.normalizedPath(wallpaper.path) == currentPlayingNormalizedPath
                } else {
                    shouldBePlaying = false
                }
                item.applyPlayingState(isPlaying: shouldBePlaying)
            } else {
                fallbackReloadIndexPaths.insert(indexPath)
            }
        }

        if !fallbackReloadIndexPaths.isEmpty {
            collectionView.reloadItems(at: fallbackReloadIndexPaths)
        }
    }

    private func updateSelectionVisualsIfNeeded() {
        var currentSelectedIDs = wallpaperManager.selectedWallpaperIds
        if let single = wallpaperManager.selectedWallpaperId {
            currentSelectedIDs.insert(single)
        }
        let changedIDs = currentSelectedIDs.symmetricDifference(lastObservedSelectedIDs)
        lastObservedSelectedIDs = currentSelectedIDs
        updateVisibleSelectionItems(forIDs: changedIDs, selectedIDs: currentSelectedIDs)
        // 方向键导航后，确保新选中项滚动进视口。
        scrollToSelectedItemIfNeeded()
    }

    private func scrollToSelectedItemIfNeeded() {
        // 只在单选时跟踪滚动，多选模式下方向键不驱动导航，无需自动滚动。
        guard !wallpaperManager.isMultiSelectMode,
              let selectedID = wallpaperManager.selectedWallpaperId,
              let index = orderedIndexByID[selectedID] else { return }
        let indexPath = IndexPath(item: index, section: 0)
        // 通过 layout 计算 item frame，比 indexPathsForVisibleItems 更可靠。
        guard let attrs = flowLayout.layoutAttributesForItem(at: indexPath) else { return }
        let itemFrame = attrs.frame
        let visibleRect = scrollView.contentView.bounds
        // 已完全在视口内，无需滚动。
        guard !visibleRect.contains(itemFrame) else { return }
        // 判断方向：item 在视口上方则向上滚，在下方则向下滚。
        let targetY: CGFloat
        if itemFrame.minY < visibleRect.minY {
            // 向上：让 item 顶部与视口顶部对齐（留 4pt 间距）。
            targetY = max(0, itemFrame.minY - 4)
        } else {
            // 向下：让 item 底部与视口底部对齐（留 4pt 间距）。
            targetY = itemFrame.maxY - visibleRect.height + 4
        }
        let targetOrigin = NSPoint(x: visibleRect.origin.x, y: targetY)
        scrollView.contentView.setBoundsOrigin(targetOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateVisibleSelectionItems(forIDs changedIDs: Set<String>, selectedIDs: Set<String>) {
        // 这里只刷可见卡片；看不见的项交给下次滚动时自然重建。
        let visibleIndexPaths = Set(collectionView.indexPathsForVisibleItems())
        guard !visibleIndexPaths.isEmpty else { return }

        let expensiveDiffThreshold = max(240, visibleIndexPaths.count * 4)
        if changedIDs.count > expensiveDiffThreshold {
            var fallbackReloadIndexPaths = Set<IndexPath>()
            for indexPath in visibleIndexPaths {
                guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { continue }
                let id = orderedIDs[indexPath.item]
                if let item = collectionView.item(at: indexPath) as? AppKitWallpaperItem {
                    item.applySelectionState(
                        isSelected: selectedIDs.contains(id),
                        multiSelectMode: wallpaperManager.isMultiSelectMode
                    )
                } else {
                    fallbackReloadIndexPaths.insert(indexPath)
                }
            }
            if !fallbackReloadIndexPaths.isEmpty {
                collectionView.reloadItems(at: fallbackReloadIndexPaths)
            }
            return
        }

        guard !changedIDs.isEmpty else { return }
        var fallbackReloadIndexPaths = Set<IndexPath>()
        for id in changedIDs {
            guard let index = orderedIndexByID[id] else { continue }
            let indexPath = IndexPath(item: index, section: 0)
            guard visibleIndexPaths.contains(indexPath) else { continue }

            if let item = collectionView.item(at: indexPath) as? AppKitWallpaperItem {
                item.applySelectionState(
                    isSelected: selectedIDs.contains(id),
                    multiSelectMode: wallpaperManager.isMultiSelectMode
                )
            } else {
                fallbackReloadIndexPaths.insert(indexPath)
            }
        }

        if !fallbackReloadIndexPaths.isEmpty {
            collectionView.reloadItems(at: fallbackReloadIndexPaths)
        }
    }

    private func handleCurrentWallpaperChange(_ wallpaper: VideoWallpaper?) {
        // 播放态变化只刷旧项和新项，不整屏重刷。
        let newNormalizedPath = wallpaper.map { wallpaperManager.normalizedPath($0.path) }
        let oldNormalizedPath = lastObservedPlayingNormalizedPath
        guard newNormalizedPath != oldNormalizedPath else { return }
        lastObservedPlayingNormalizedPath = newNormalizedPath

        var changedPaths = Set<String>()
        if let oldNormalizedPath {
            changedPaths.insert(oldNormalizedPath)
        }
        if let newNormalizedPath {
            changedPaths.insert(newNormalizedPath)
        }
        if changedPaths.isEmpty {
            return
        }
        updateVisiblePlayingItems(forNormalizedPaths: changedPaths, playingNormalizedPath: newNormalizedPath)
    }

    private func updateVisiblePlayingItems(forNormalizedPaths paths: Set<String>, playingNormalizedPath: String?) {
        guard !paths.isEmpty else { return }
        let visibleIndexPaths = Set(collectionView.indexPathsForVisibleItems())
        guard !visibleIndexPaths.isEmpty else { return }

        var fallbackReloadIndexPaths = Set<IndexPath>()
        for normalizedPath in paths {
            guard let ids = normalizedPathToIDs[normalizedPath], !ids.isEmpty else { continue }
            for id in ids {
                guard let index = orderedIndexByID[id] else { continue }
                let indexPath = IndexPath(item: index, section: 0)
                guard visibleIndexPaths.contains(indexPath) else { continue }

                let shouldBePlaying: Bool
                if let wallpaper = wallpapersByID[id], let playingNormalizedPath {
                    shouldBePlaying = wallpaperManager.normalizedPath(wallpaper.path) == playingNormalizedPath
                } else {
                    shouldBePlaying = false
                }

                if let item = collectionView.item(at: indexPath) as? AppKitWallpaperItem {
                    item.applyPlayingState(isPlaying: shouldBePlaying)
                } else {
                    fallbackReloadIndexPaths.insert(indexPath)
                }
            }
        }

        if !fallbackReloadIndexPaths.isEmpty {
            collectionView.reloadItems(at: fallbackReloadIndexPaths)
        }
    }

    private func syncSelectionFromManager() {
        // collectionView 的 selection 必须跟 manager 的选择态同步，不能反过来让 item 自己决定。
        collectionView.allowsMultipleSelection = wallpaperManager.isMultiSelectMode
        collectionView.isBoxSelectionEnabled = wallpaperManager.isMultiSelectMode
        if wallpaperManager.isMultiSelectMode {
            if !collectionView.selectionIndexPaths.isEmpty {
                isApplyingSelectionSnapshot = true
                collectionView.selectionIndexPaths = []
                isApplyingSelectionSnapshot = false
            }
            return
        }
        var selectedIDs = wallpaperManager.selectedWallpaperIds
        if let single = wallpaperManager.selectedWallpaperId {
            selectedIDs.insert(single)
        }
        applyCollectionSelection(for: selectedIDs)
    }

    private func scheduleSyncSelectionFromManager() {
        guard !isSelectionSyncScheduled else { return }
        isSelectionSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSelectionSyncScheduled = false
            self.syncSelectionFromManager()
        }
    }

    private func applyCollectionSelection(for selectedIDs: Set<String>) {
        // selection 只在差异变化时写回，避免重复设置 selectionIndexPaths 触发事件回环。
        var indexPaths = Set<IndexPath>()
        for id in selectedIDs {
            guard let index = orderedIndexByID[id] else { continue }
            indexPaths.insert(IndexPath(item: index, section: 0))
        }
        if collectionView.selectionIndexPaths == indexPaths,
           collectionView.allowsMultipleSelection == wallpaperManager.isMultiSelectMode,
           collectionView.isBoxSelectionEnabled == wallpaperManager.isMultiSelectMode {
            return
        }
        isApplyingSelectionSnapshot = true
        collectionView.selectionIndexPaths = indexPaths
        isApplyingSelectionSnapshot = false
    }

    private func scheduleViewportPrefetch() {
        // 滚动事件只合并为一次预取调度，避免高频 bounds 变化直接压到主线程。
        guard !isScrollToTopAnimating else { return }
        viewportPrefetchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.prefetchAroundVisibleRange()
        }
        viewportPrefetchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
    }

    private func prefetchAroundVisibleRange() {
        // 预取范围围绕当前可见区展开，保持与 Photos 类似的“前后几屏预热”体验。
        guard !isScrollToTopAnimating else { return }
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
        guard !visibleIndexPaths.isEmpty, !orderedIDs.isEmpty else { return }
        let visibleIndices = visibleIndexPaths.map(\.item)
        guard let minVisible = visibleIndices.min(), let maxVisible = visibleIndices.max() else { return }

        let visibleCount = max(1, maxVisible - minVisible + 1)
        // 预热窗口控制在可见区前后约 2 屏，降低滚动中的预取竞争。
        let preloadCount = min(48, max(12, visibleCount * 2))
        let start = max(0, minVisible - preloadCount)
        let end = min(orderedIDs.count - 1, maxVisible + preloadCount)
        guard start <= end else { return }
        let prefetchRange = start...end
        if lastPrefetchRange == prefetchRange {
            return
        }
        lastPrefetchRange = prefetchRange

        for index in prefetchRange {
            let id = orderedIDs[index]
            guard let wallpaper = wallpapersByID[id] else { continue }
            thumbnailProvider.prefetchThumbnail(for: wallpaper)
        }
    }

    private func scheduleVisibleGridColumnCountUpdateIfNeeded(_ columnCount: Int) {
        if wallpaperManager.visibleGridColumnCount == columnCount {
            pendingVisibleColumnCount = nil
            return
        }
        if pendingVisibleColumnCount == columnCount {
            return
        }
        pendingVisibleColumnCount = columnCount
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.pendingVisibleColumnCount == columnCount else { return }
            self.pendingVisibleColumnCount = nil
            if self.wallpaperManager.visibleGridColumnCount != columnCount {
                self.wallpaperManager.visibleGridColumnCount = columnCount
            }
        }
    }

    private func startMissingPathProbeTimer() {
        // 缺失文件探针只检查可见项，目的是尽早给出路径缺失提示，但不做全库扫描。
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            self?.probeVisibleMissingWallpapers()
        }
        missingPathProbeTimer = timer
        timer.resume()
    }

    private func probeVisibleMissingWallpapers() {
        // 这里不修复数据，只负责发现“可见项缺失/恢复”并触发局部刷新。
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
        guard !visibleIndexPaths.isEmpty else {
            visibleMissingWallpaperIDs.removeAll()
            return
        }

        var currentMissingIDs = Set<String>()
        var recoveredIDs = Set<String>()

        for indexPath in visibleIndexPaths {
            guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { continue }
            let id = orderedIDs[indexPath.item]
            guard let wallpaper = wallpapersByID[id] else { continue }
            let fileExists = wallpaperManager.normalizedSourcePathExists(wallpaper.path)
            if !fileExists {
                currentMissingIDs.insert(id)
                continue
            }

            if visibleMissingWallpaperIDs.contains(id) {
                recoveredIDs.insert(id)
            }

            if wallpaperManager.resolvedThumbnailPath(for: wallpaper) == nil {
                wallpaperManager.ensurePreviewAssetsForWallpaper(wallpaper)
            }
        }

        visibleMissingWallpaperIDs = currentMissingIDs
        reloadVisibleItems(forIDs: recoveredIDs)
    }

    private func handleBackgroundClick() {
        guard !wallpaperManager.isMultiSelectMode else { return }
        wallpaperManager.clearSingleSelectionIfNeeded()
        collectionView.selectionIndexPaths = []
    }

    private func handlePrimaryClick(at indexPath: IndexPath) -> Bool {
        guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { return true }

        if !wallpaperManager.isMultiSelectMode {
            // 单选态下点击已选中的卡片：呼出详情面板并吞掉事件，
            // 不让系统把 selection 反向切换掉。
            if wallpaperManager.selectedWallpaperId == orderedIDs[indexPath.item] {
                wallpaperManager.presentInspectorForSelectedWallpaper()
                return true
            }
            return false
        }

        // 多选态下点击空白卡片区域的行为是切换选中，不是播放。
        let id = orderedIDs[indexPath.item]
        var selectedIDs = wallpaperManager.selectedWallpaperIds
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        wallpaperManager.replaceMultiSelection(with: selectedIDs)
        return true
    }

    private func beginBoxSelection(at indexPath: IndexPath?) -> Bool {
        guard wallpaperManager.isMultiSelectMode else { return false }
        let initialIDs = wallpaperManager.selectedWallpaperIds
        let mode: BoxSelectionState.Mode
        if let indexPath,
           indexPath.item >= 0,
           indexPath.item < orderedIDs.count {
            let wallpaperID = orderedIDs[indexPath.item]
            mode = initialIDs.contains(wallpaperID) ? .deselect : .select
        } else {
            mode = .select
        }
        boxSelectionState = BoxSelectionState(mode: mode, initialIDs: initialIDs)
        return true
    }

    private func updateBoxSelection(in rect: NSRect) {
        guard let state = boxSelectionState else { return }
        let touchedIDs = wallpaperIDs(intersecting: rect)
        let selectedIDs = state.resolve(touching: touchedIDs)
        guard selectedIDs != wallpaperManager.selectedWallpaperIds else { return }
        wallpaperManager.replaceMultiSelection(with: selectedIDs)
    }

    private func endBoxSelection() {
        boxSelectionState = nil
    }

    private func updateCardPressState(at indexPath: IndexPath, isPressed: Bool) {
        // 卡片按压只改变 item 的局部视觉态，不反向改 selection。
        guard indexPath.item >= 0, indexPath.item < orderedIDs.count else { return }
        guard let item = collectionView.item(at: indexPath) as? AppKitWallpaperItem else { return }
        item.applyPressedState(isPressed)
    }

    private func wallpaperIDs(intersecting rect: NSRect) -> Set<String> {
        guard !orderedIDs.isEmpty else { return [] }
        let normalizedRect = rect.standardized
        let queryRect: NSRect
        if normalizedRect.width < 1 && normalizedRect.height < 1 {
            queryRect = NSRect(x: normalizedRect.origin.x, y: normalizedRect.origin.y, width: 1, height: 1)
        } else {
            queryRect = normalizedRect
        }

        var ids = Set<String>()
        if let attributes = collectionView.collectionViewLayout?.layoutAttributesForElements(in: queryRect) {
            for attribute in attributes where attribute.representedElementCategory == .item {
                guard let indexPath = attribute.indexPath else { continue }
                let itemIndex = indexPath.item
                guard itemIndex >= 0, itemIndex < orderedIDs.count else { continue }
                ids.insert(orderedIDs[itemIndex])
            }
        }

        if ids.isEmpty {
            let centerPoint = NSPoint(x: queryRect.midX, y: queryRect.midY)
            if let indexPath = collectionView.indexPathForItem(at: centerPoint),
               indexPath.item >= 0,
               indexPath.item < orderedIDs.count {
                ids.insert(orderedIDs[indexPath.item])
            }
        }
        return ids
    }

}
