//
//  AppKitOLBrowserGridView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//
//  在线库搜索结果 AppKit NSCollectionView 容器。
//  使用原生 NSCollectionView 展示在线库卡片。
//

import AppKit
import Combine

// MARK: - 容器

final class AppKitOLBrowserContainerView: NSView, ModuleFocusable, ListThumbnailTintProviding {
    let listThumbnailTintSource = ListThumbnailTintSource()
    private func publishListThumbnailTint() {
        let first = orderedIDs.first.flatMap { itemsByID[$0] }
        listThumbnailTintSource.update(id: first.map { String($0.id) }, assets: first.map { [$0.previewThumbnailURL?.absoluteString ?? ""] } ?? []) { completion in
            guard let url = first?.previewThumbnailURL else { completion(nil); return {} }
            let task = Task {
                let image = await OLThumbnailCache.shared.image(for: url, maxPixelSize: 256, priority: .prefetch)
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

    private let service: OnlineLibraryService
    var onDownload:       (OnlineLibraryVideoItem) -> Void
    var onSetAsWallpaper: (OnlineLibraryVideoItem) -> Void

    private var cancellables = Set<AnyCancellable>()
    private var orderedIDs: [Int] = []
    private var itemsByID:  [Int: OnlineLibraryVideoItem] = [:]
    private var lastConsumedProgress: [Int: Double] = [:]
    private var lastPrioritizedVisibleIDs: [Int]?
    private var lastPrioritizedPixelLimit = 0
    private var isThumbnailDemandUpdateScheduled = false
    private var thumbnailWindowObservation: NSKeyValueObservation?
    private var thumbnailWindowObservers: [NSObjectProtocol] = []
    private var canLoadThumbnails: Bool {
        window?.isVisible == true && window?.isMiniaturized == false && !isHiddenOrHasHiddenAncestor
    }

    private let scrollView: NSScrollView = {
        let s = WallpaperGridScrollView()
        s.drawsBackground = false
        s.hasVerticalScroller = true
        s.hasHorizontalScroller = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var collectionView: NSCollectionView = {
        let cv = NSCollectionView()
        cv.isSelectable = false
        cv.backgroundColors = [.clear]
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        let l = NSCollectionViewFlowLayout()
        l.minimumInteritemSpacing = 8
        l.minimumLineSpacing = 16
        l.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 48, right: 8)
        return l
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, Int> = {
        NSCollectionViewDiffableDataSource<Section, Int>(
            collectionView: collectionView
        ) { [weak self] cv, indexPath, id -> NSCollectionViewItem? in
            guard let self, let item = self.itemsByID[id] else { return nil }
            guard let cell = self.collectionView.makeItem(
                withIdentifier: AppKitOLBrowserItem.reuseIdentifier, for: indexPath) as? AppKitOLBrowserItem else { return nil }
            let svc = self.service
            cell.configure(
                item: item,
                isDownloading: svc.downloadingIDs.contains(id),
                isDownloaded:  self.isItemDownloaded(id),
                downloadProgress: svc.downloadProgressByID[id],
                thumbnailDemandActive: self.canLoadThumbnails,
                onDownload:       { [weak self] in self?.onDownload(item) },
                onSetAsWallpaper: { [weak self] in self?.onSetAsWallpaper(item) }
            )
            return cell
        }
    }()

    private var lastLoadedCount = 0
    private var isLayoutItemSizeUpdateScheduled = false

    // MARK: - Init

    init(
        service: OnlineLibraryService,
        onDownload: @escaping (OnlineLibraryVideoItem) -> Void,
        onSetAsWallpaper: @escaping (OnlineLibraryVideoItem) -> Void
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
        AppKitOLBrowserItem.resetHoverTrackingActivation()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        collectionView.register(AppKitOLBrowserItem.self, forItemWithIdentifier: AppKitOLBrowserItem.reuseIdentifier)
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

        // 订阅 zoomOffset
        service.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleLayoutItemSizeUpdate() }
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
                      module == ModuleIdentifier.onlineLibrary.rawValue
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

    private func applyItems(_ items: [OnlineLibraryVideoItem]) {
        lastPrioritizedVisibleIDs = nil
        var byID: [Int: OnlineLibraryVideoItem] = [:]
        byID.reserveCapacity(items.count)
        for item in items { byID[item.id] = item }
        itemsByID = byID
        orderedIDs = items.map { $0.id }
        publishListThumbnailTint()

        var snap = NSDiffableDataSourceSnapshot<Section, Int>()
        snap.appendSections([.main])
        snap.appendItems(orderedIDs, toSection: .main)
        let animated = lastLoadedCount != 0 && items.count > lastLoadedCount
        lastLoadedCount = items.count
        dataSource.apply(snap, animatingDifferences: animated)
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
            guard ip.item < orderedIDs.count else { continue }
            let id = orderedIDs[ip.item]
            guard ids?.contains(id) != false,
                  let cell = collectionView.item(at: ip) as? AppKitOLBrowserItem,
                  let item = itemsByID[id] else { continue }
            cell.configure(
                item: item,
                isDownloading: self.service.downloadingIDs.contains(id),
                isDownloaded:  self.isItemDownloaded(id),
                downloadProgress: self.service.downloadProgressByID[id],
                thumbnailDemandActive: self.canLoadThumbnails,
                onDownload:       { [weak self] in self?.onDownload(item) },
                onSetAsWallpaper: { [weak self] in self?.onSetAsWallpaper(item) }
            )
        }
    }

    private func isItemDownloaded(_ id: Int) -> Bool {
        if service.downloadedIDs.contains(id) { return true }
        let localURL = OnlineLibraryService.downloadDirectory.appendingPathComponent("online_\(id).mp4")
        guard FileManager.default.fileExists(atPath: localURL.path) else { return false }
        service.downloadedIDs.insert(id)
        return true
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
        collectionView.visibleItems().forEach { ($0 as? AppKitOLBrowserItem)?.beginDisplayingThumbnail() }
        updateVisibleThumbnailPriorities()
    }

    private func pauseThumbnailDemand() {
        lastPrioritizedVisibleIDs = nil
        service.cancelThumbnailPrefetch()
        collectionView.visibleItems().forEach { ($0 as? AppKitOLBrowserItem)?.endDisplayingThumbnail() }
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
        let metrics = OnlineLibraryGridLayoutSupport.metrics(
            boundsWidth: layoutWidth,
            zoomOffset: service.zoomOffset,
            sectionInset: flowLayout.sectionInset
        )
        flowLayout.minimumInteritemSpacing = metrics.interitemSpacing
        flowLayout.minimumLineSpacing = metrics.lineSpacing
        let newSize = metrics.itemSize
        guard flowLayout.itemSize != newSize else { return }
        flowLayout.itemSize = newSize
        updateVisibleThumbnailPriorities()
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
}


extension AppKitOLBrowserContainerView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath) {
        if canLoadThumbnails { (item as? AppKitOLBrowserItem)?.beginDisplayingThumbnail() }
        else { (item as? AppKitOLBrowserItem)?.endDisplayingThumbnail() }
        updateVisibleThumbnailPriorities()
    }

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath) {
        (item as? AppKitOLBrowserItem)?.endDisplayingThumbnail()
        updateVisibleThumbnailPriorities()
    }
}
