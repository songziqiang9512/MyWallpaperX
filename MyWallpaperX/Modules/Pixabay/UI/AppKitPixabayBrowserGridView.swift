//
//  AppKitPixabayBrowserGridView.swift
//  MyWallpaperX — Modules/Pixabay/UI
//
//  Pixabay 搜索结果 AppKit NSCollectionView 容器。
//  使用原生 NSCollectionView 展示 Pixabay 卡片。
//

import AppKit
import Combine

// MARK: - 容器

final class AppKitPixabayBrowserContainerView: NSView, ModuleFocusable, ListThumbnailTintProviding {
    let listThumbnailTintSource = ListThumbnailTintSource()
    private func publishListThumbnailTint() {
        let first = orderedIDs.first.flatMap { itemsByID[$0] }
        listThumbnailTintSource.update(id: first.map { String($0.id) }, assets: first.map { [$0.previewThumbnailURL?.absoluteString ?? ""] } ?? []) { completion in
            guard let url = first?.previewThumbnailURL else { completion(nil); return {} }
            let task = Task {
                let image = await OnlineImageThumbnailCache.shared.image(for: url, maxPixelSize: 256, priority: .prefetch)
                guard !Task.isCancelled else { return }
                completion(image)
            }
            return { task.cancel() }
        }
    }

    private enum Section { case main }
    private enum Constants {
        static let loadMoreThreshold: CGFloat = 240
    }

    private let service: PixabayService
    var onDownload:       (PixabayVideoItem) -> Void
    var onSetAsWallpaper: (PixabayVideoItem) -> Void
    var onInspect: ((PixabayVideoItem) -> Void)? {
        didSet { reloadVisibleItems() }
    }
    var onSelectionChange: ((PixabayVideoItem?) -> Void)?
    var opensDetailsOnSingleClick: () -> Bool = { false }
    var makeOrganization: ((PixabayVideoItem) -> WallpaperInspectorActions?)? {
        didSet { refreshOrganization() }
    }
    var preferredColumns = 5 {
        didSet { if preferredColumns != oldValue { scheduleLayoutItemSizeUpdate() } }
    }
    var clipWidth: CGFloat { scrollView.contentView.bounds.width }
    var onClipWidthChange: ((CGFloat) -> Void)?
    private var lastReportedClipWidth: CGFloat?

    private var cancellables = Set<AnyCancellable>()
    private var orderedIDs: [Int] = []
    private var keyboardFocusedID: Int?
    var selectedItem: PixabayVideoItem? { keyboardFocusedID.flatMap { itemsByID[$0] } }
    var selectedPrimaryAction: (() -> Void)? { selectedItem.flatMap { primaryAction(for: $0.id) } }
    private var currentColumnCount = 1
    private var itemsByID:  [Int: PixabayVideoItem] = [:]
    private var lastConsumedProgress: [Int: Double] = [:]
    private var lastPrioritizedVisibleIDs: [Int]?
    private var lastPrioritizedPixelLimit = 0
    private var isThumbnailDemandUpdateScheduled = false
    private var thumbnailWindowObservation: NSKeyValueObservation?
    private var thumbnailWindowObservers: [NSObjectProtocol] = []
    private var canLoadThumbnails: Bool {
        window?.isVisible == true && window?.isMiniaturized == false && !isHiddenOrHasHiddenAncestor
    }

    private let scrollView: WallpaperGridScrollView = {
        let s = WallpaperGridScrollView()
        s.drawsBackground = false
        s.hasVerticalScroller = true
        s.hasHorizontalScroller = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var collectionView: SteamWorkshopKeyboardCollectionView = {
        let cv = SteamWorkshopKeyboardCollectionView()
        cv.isSelectable = false
        cv.backgroundColors = [.clear]
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.keyboardDelegate = self
        cv.accessibleItemsProvider = { [weak self] in
            guard let self else { return [] }
            return self.collectionView.indexPathsForVisibleItems().sorted().compactMap { self.collectionView.item(at: $0)?.view }
        }
        cv.contextMenuProvider = { [weak self] path in
            guard let self, let path,
                  let cell = collectionView.item(at: path) as? AppKitPixabayBrowserItem else { return nil }
            return cell.buildContextMenu()
        }
        cv.primaryClickHandler = { [weak self] path, clickCount in
            guard let self, let id = dataSource.itemIdentifier(for: path) else { return false }
            guard clickCount == 1 else { return true }
            return selectItem(withID: id, opensDetails: opensDetailsOnSingleClick())
        }
        cv.onBackgroundLeftClick = { [weak self] in
            guard let self else { return }
            let previous = keyboardFocusedID
            keyboardFocusedID = nil
            updateKeyboardFocus(previous)
            onSelectionChange?(nil)
        }
        return cv
    }()

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        let l = NSCollectionViewFlowLayout()
        l.minimumInteritemSpacing = WallpaperLibraryGridMetrics.horizontalSpacing
        l.minimumLineSpacing = WallpaperLibraryGridMetrics.verticalSpacing
        l.sectionInset = NSEdgeInsets(top: WallpaperLibraryGridMetrics.topInset,
            left: WallpaperLibraryGridMetrics.edgeInset, bottom: WallpaperLibraryGridMetrics.bottomInset,
            right: WallpaperLibraryGridMetrics.edgeInset)
        return l
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, Int> = {
        NSCollectionViewDiffableDataSource<Section, Int>(
            collectionView: collectionView
        ) { [weak self] cv, indexPath, id -> NSCollectionViewItem? in
            guard let self, let item = self.itemsByID[id] else { return nil }
            guard let cell = self.collectionView.makeItem(
                withIdentifier: AppKitPixabayBrowserItem.reuseIdentifier, for: indexPath) as? AppKitPixabayBrowserItem else { return nil }
            let svc = self.service
            cell.configure(
                item: item,
                isDownloading: svc.downloadingIDs.contains(id),
                isDownloaded:  self.isItemDownloaded(id),
                downloadProgress: svc.downloadProgressByID[id],
                thumbnailDemandActive: self.canLoadThumbnails,
                organization: self.makeOrganization?(item),
                onInspect: self.onInspect.map { _ in { [weak self] in _ = self?.selectItem(withID: id, opensDetails: true) } },
                onDownload: { [weak self] in
                    guard let self, let current = self.itemsByID[id] else { return }
                    self.onDownload(current)
                },
                onSetAsWallpaper: { [weak self] in
                    guard let self, let current = self.itemsByID[id] else { return }
                    self.onSetAsWallpaper(current)
                }
            )
            cell.setKeyboardFocus(self.keyboardFocusedID == id)
            return cell
        }
    }()

    private var lastLoadedCount = 0
    private var isLayoutItemSizeUpdateScheduled = false

    // MARK: - Init

    init(
        service: PixabayService,
        onDownload: @escaping (PixabayVideoItem) -> Void,
        onSetAsWallpaper: @escaping (PixabayVideoItem) -> Void
    ) {
        self.service = service
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        super.init(frame: .zero)
        setup()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit { thumbnailWindowObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    private func setup() {
        AppKitPixabayBrowserItem.resetHoverTrackingActivation()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        collectionView.register(AppKitPixabayBrowserItem.self, forItemWithIdentifier: AppKitPixabayBrowserItem.reuseIdentifier)
        collectionView.dataSource = dataSource
        collectionView.delegate = self
        scrollView.documentView = collectionView
        scrollView.contentView.postsBoundsChangedNotifications = true

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        service.refreshDownloadedContent()
        scrollView.permitsPullCountInput = { [weak self] in
            WallpaperLibrarySheetPresentation.permitsInput(in: self?.window)
        }
        scrollView.onRefresh = { [weak self] in self?.service.refresh() }
        service.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.scrollView.applyRefreshLoading($0) }
            .store(in: &cancellables)

        // 订阅 items 变化
        service.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyItems($0) }
            .store(in: &cancellables)

        // 订阅下载状态变化 → 刷新可见卡片
        service.$downloadingIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadVisibleItems() }
            .store(in: &cancellables)

        service.$downloadedIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadVisibleItems() }
            .store(in: &cancellables)

        // 进度发布高频（节流后单任务约每 200ms 一次，多任务并发时叠加），
        // 合并为每 200ms 至多一次可见卡片刷新
        service.$downloadProgressByID
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] progress in self?.refreshDownloadProgress(progress) }
            .store(in: &cancellables)

        // 监听滚动，接近底部时触发下一页
        NotificationCenter.default.publisher(
            for: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateVisibleThumbnailPriorities()
            self?.checkLoadMore()
        }
        .store(in: &cancellables)

        // ModuleFocusable：监听模块激活通知，自动接管焦点
        NotificationCenter.default.publisher(for: .moduleDidBecomeActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let module = notification.userInfo?["module"] as? String,
                      module == ModuleIdentifier.pixabay.rawValue
                else { return }
                self?.requestFocus()
            }
            .store(in: &cancellables)
    }

    // MARK: - ModuleFocusable

    func requestFocus() {
        window?.makeFirstResponder(collectionView)
    }

    // MARK: - 数据

    private func applyItems(_ items: [PixabayVideoItem]) {
        let previousSelection = keyboardFocusedID.flatMap { itemsByID[$0] }
        var byID: [Int: PixabayVideoItem] = [:]
        byID.reserveCapacity(items.count)
        for item in items { byID[item.id] = item }
        let nextIDs = items.map(\.id)
        let changedIDs = Set(items.compactMap { item -> Int? in
            guard let previous = itemsByID[item.id], previous != item else { return nil }
            return item.id
        })
        let topologyChanged = orderedIDs != nextIDs
        guard topologyChanged || !changedIDs.isEmpty else { return }

        itemsByID = byID
        if let id = keyboardFocusedID {
            if byID[id] == nil { keyboardFocusedID = nil }
            if previousSelection != byID[id] { onSelectionChange?(byID[id]) }
        }
        lastPrioritizedVisibleIDs = nil
        guard topologyChanged else {
            publishListThumbnailTint()
            reloadVisibleItems(forIDs: changedIDs)
            updateVisibleThumbnailPriorities()
            return
        }
        orderedIDs = nextIDs
        publishListThumbnailTint()

        var snap = NSDiffableDataSourceSnapshot<Section, Int>()
        snap.appendSections([.main])
        snap.appendItems(orderedIDs, toSection: .main)
        let animated = lastLoadedCount != 0 && items.count > lastLoadedCount
        lastLoadedCount = items.count
        dataSource.apply(snap, animatingDifferences: animated) { [weak self] in
            // Animated topology changes do not reconfigure retained rows.
            // Read current DTOs/native identifiers if a later apply won first.
            if !changedIDs.isEmpty { self?.reloadVisibleItems(forIDs: changedIDs) }
        }
        updateVisibleThumbnailPriorities()
    }

    private func refreshDownloadProgress(_ progress: [Int: Double]) {
        let changedIDs = Set(lastConsumedProgress.keys).union(progress.keys).filter {
            lastConsumedProgress[$0] != progress[$0]
        }
        lastConsumedProgress = progress
        guard !changedIDs.isEmpty else { return }
        reloadVisibleItems(forIDs: changedIDs)
    }

    private func reloadVisibleItems(forIDs ids: Set<Int>? = nil) {
        let visible = collectionView.indexPathsForVisibleItems()
        guard !visible.isEmpty else { return }
        // 轻量刷新：直接重新 configure 可见 cell
        for ip in visible {
            guard let id = dataSource.itemIdentifier(for: ip), ids?.contains(id) != false,
                  let cell = collectionView.item(at: ip) as? AppKitPixabayBrowserItem,
                  let item = itemsByID[id] else { continue }
            cell.configure(
                item: item,
                isDownloading: self.service.downloadingIDs.contains(id),
                isDownloaded:  self.isItemDownloaded(id),
                downloadProgress: self.service.downloadProgressByID[id],
                thumbnailDemandActive: self.canLoadThumbnails,
                organization: self.makeOrganization?(item),
                onInspect: self.onInspect.map { _ in { [weak self] in _ = self?.selectItem(withID: id, opensDetails: true) } },
                onDownload: { [weak self] in
                    guard let self, let current = self.itemsByID[id] else { return }
                    self.onDownload(current)
                },
                onSetAsWallpaper: { [weak self] in
                    guard let self, let current = self.itemsByID[id] else { return }
                    self.onSetAsWallpaper(current)
                }
            )
            cell.setKeyboardFocus(keyboardFocusedID == id)
        }
    }

    /// Relationship publications change only the existing visible card's
    /// injected actions. Thumbnail identity and demand remain source-owned.
    func refreshOrganization() {
        for path in collectionView.indexPathsForVisibleItems() {
            guard path.item < orderedIDs.count, let item = itemsByID[orderedIDs[path.item]],
                  let cell = collectionView.item(at: path) as? AppKitPixabayBrowserItem else { continue }
            cell.updateOrganization(makeOrganization?(item), for: item.id)
        }
    }

    private func isItemDownloaded(_ id: Int) -> Bool {
        service.downloadedIDs.contains(id)
    }

    private func primaryAction(for id: Int) -> (() -> Void)? {
        guard let item = itemsByID[id] else { return nil }
        let organization = makeOrganization?(item)
        guard organization?.state.isSwitching != true else { return nil }
        if organization?.state.isPlaying == true {
            return organization?.state.canPerformPrimary == true ? organization?.onPrimary : nil
        }
        guard !service.downloadingIDs.contains(id) else { return nil }
        if isItemDownloaded(id) {
            guard organization?.state.canPerformPrimary != false else { return nil }
            return { [weak self] in self?.onSetAsWallpaper(item) }
        }
        return { [weak self] in self?.onDownload(item) }
    }

    @discardableResult
    private func performPrimaryAction(for id: Int) -> Bool {
        guard canLoadThumbnails, WallpaperLibrarySheetPresentation.permitsInput(in: window),
              let action = primaryAction(for: id) else { return false }
        action()
        return true
    }

    @discardableResult
    func performSelectedPrimaryAction() -> Bool {
        guard let item = selectedItem else { return false }
        return performPrimaryAction(for: item.id)
    }

    @discardableResult
    func inspectSelectedItem() -> Bool {
        guard canLoadThumbnails, WallpaperLibrarySheetPresentation.permitsInput(in: window),
              let item = selectedItem else { return false }
        return selectItem(withID: item.id, opensDetails: true)
    }

    @discardableResult
    private func selectItem(withID id: Int, opensDetails: Bool) -> Bool {
        guard let item = itemsByID[id] else { return false }
        let previous = keyboardFocusedID
        keyboardFocusedID = id
        if previous != id { updateKeyboardFocus(previous) }
        updateKeyboardFocus(id)
        window?.makeFirstResponder(collectionView)
        onSelectionChange?(item)
        if opensDetails { onInspect?(item) }
        return true
    }

    private func updateKeyboardFocus(_ id: Int?) {
        guard let id, let path = dataSource.indexPath(for: id),
              let cell = collectionView.item(at: path) as? AppKitPixabayBrowserItem else { return }
        cell.setKeyboardFocus(keyboardFocusedID == id)
    }

    // MARK: - 无限加载

    private func checkLoadMore() {
        guard service.hasMore, !service.isLoading else { return }
        guard let docView = scrollView.documentView else { return }
        let contentH  = docView.frame.height
        let viewportH = scrollView.contentView.bounds.height
        let offsetY   = scrollView.contentView.bounds.origin.y
        // 稍早一点触发翻页，降低到底部时的感知缝隙。
        if contentH - offsetY - viewportH < Constants.loadMoreThreshold {
            service.loadNextPage()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        thumbnailWindowObservation?.invalidate()
        thumbnailWindowObservation = nil
        thumbnailWindowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        thumbnailWindowObservers.removeAll()
        if let window {
            thumbnailWindowObservation = window.observe(\.isVisible, options: [.new]) { [weak self] observed, _ in
                MainActor.assumeIsolated {
                    guard let self, self.window === observed else { return }
                    self.updateThumbnailWindowVisibility()
                }
            }
            for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                thumbnailWindowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    MainActor.assumeIsolated {
                        guard let self, self.window === (notification.object as? NSWindow) else { return }
                        self.updateThumbnailWindowVisibility()
                    }
                })
            }
        }
        updateThumbnailWindowVisibility()
    }

    private func updateThumbnailWindowVisibility() {
        lastPrioritizedVisibleIDs = nil
        guard canLoadThumbnails else { pauseThumbnailDemand(); return }
        collectionView.visibleItems().forEach { ($0 as? AppKitPixabayBrowserItem)?.beginDisplayingThumbnail() }
        updateVisibleThumbnailPriorities()
    }

    private func pauseThumbnailDemand() {
        lastPrioritizedVisibleIDs = nil
        service.cancelThumbnailPrefetch()
        collectionView.visibleItems().forEach { ($0 as? AppKitPixabayBrowserItem)?.endDisplayingThumbnail() }
    }

    override func viewDidHide() {
        super.viewDidHide()
        pauseThumbnailDemand()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateThumbnailWindowVisibility()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateVisibleThumbnailPriorities()
    }

    private func updateVisibleThumbnailPriorities() {
        guard !isThumbnailDemandUpdateScheduled else { return }
        isThumbnailDemandUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isThumbnailDemandUpdateScheduled = false
            self.applyThumbnailDemand()
        }
    }

    private func applyThumbnailDemand() {
        guard canLoadThumbnails else { pauseThumbnailDemand(); return }
        let visibleIDs = collectionView.indexPathsForVisibleItems()
            .sorted { lhs, rhs in
                if lhs.section == rhs.section {
                    return lhs.item < rhs.item
                }
                return lhs.section < rhs.section
            }
            .compactMap { indexPath -> Int? in
                guard indexPath.item < orderedIDs.count else { return nil }
                return orderedIDs[indexPath.item]
            }
        let pixelLimit = GridThumbnailDecoder.pixelLimit(width: flowLayout.itemSize.width,
            scale: window?.backingScaleFactor ?? 2)
        guard lastPrioritizedVisibleIDs != visibleIDs || lastPrioritizedPixelLimit != pixelLimit
            || service.thumbnailPrefetchNeedsRefresh() else { return }
        lastPrioritizedVisibleIDs = visibleIDs
        lastPrioritizedPixelLimit = pixelLimit
        service.prioritizeVisibleItemIDs(visibleIDs, maxPixelSize: pixelLimit)
    }

    // MARK: - Layout

    override func layout() {
        // Install narrower metrics before AppKit lays out resized children.
        updateLayoutItemSize()
        super.layout()
        scheduleLayoutItemSizeUpdate()
    }

    private func updateLayoutItemSize() {
        let layoutWidth = min(bounds.width, scrollView.contentView.bounds.width)
        guard layoutWidth.isFinite, layoutWidth > 1 else { return }
        if window != nil { reportClipWidth(layoutWidth) }
        let metrics = WallpaperLibraryGridMetrics(clipWidth: layoutWidth, preferredColumns: preferredColumns)
        currentColumnCount = metrics.columns
        flowLayout.minimumInteritemSpacing = WallpaperLibraryGridMetrics.horizontalSpacing
        flowLayout.minimumLineSpacing = WallpaperLibraryGridMetrics.verticalSpacing
        let newSize = NSSize(width: metrics.coverSide, height: metrics.coverSide)
        guard flowLayout.itemSize != newSize else { return }
        flowLayout.itemSize = newSize
        updateVisibleThumbnailPriorities()
        // 布局变化与悬停视觉同步生效，避免渐变层在缩放期间出现跟随滞后。
        collectionView.collectionViewLayout?.invalidateLayout()
    }

    private func reportClipWidth(_ width: CGFloat) {
        guard width.isFinite, width >= 0, lastReportedClipWidth != width else { return }
        lastReportedClipWidth = width
        onClipWidthChange?(width)
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
}


extension AppKitPixabayBrowserContainerView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath) {
        if canLoadThumbnails { (item as? AppKitPixabayBrowserItem)?.beginDisplayingThumbnail() }
        else { (item as? AppKitPixabayBrowserItem)?.endDisplayingThumbnail() }
        (item as? AppKitPixabayBrowserItem)?.setKeyboardFocus(dataSource.itemIdentifier(for: indexPath) == keyboardFocusedID)
        updateVisibleThumbnailPriorities()
    }

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath) {
        (item as? AppKitPixabayBrowserItem)?.endDisplayingThumbnail()
        updateVisibleThumbnailPriorities()
    }
}

extension AppKitPixabayBrowserContainerView: SteamWorkshopKeyboardDelegate {
    func steamWorkshopCollectionView(_ collectionView: SteamWorkshopKeyboardCollectionView, handleKey event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            guard !event.isARepeat else { return true }
            return performSelectedPrimaryAction()
        }
        guard let destination = SteamWorkshopGridKeyboardNavigation.destinationIndex(keyCode: event.keyCode,
            currentIndex: keyboardFocusedID.flatMap { orderedIDs.firstIndex(of: $0) },
            itemCount: orderedIDs.count, columnCount: currentColumnCount) else { return false }
        let id = orderedIDs[destination]
        _ = selectItem(withID: id, opensDetails: false)
        if let path = dataSource.indexPath(for: id), let attributes = flowLayout.layoutAttributesForItem(at: path) {
            collectionView.scrollToVisible(attributes.frame)
        }
        return true
    }
}
