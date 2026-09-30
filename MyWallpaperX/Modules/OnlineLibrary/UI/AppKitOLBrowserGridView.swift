//
//  AppKitOLBrowserGridView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//
//  在线库搜索结果 AppKit NSCollectionView 容器。
//  替换原 SwiftUI LazyVGrid，彻底解决 hover 放大被裁剪的 bug。
//

import AppKit
import Combine

// MARK: - Collection View

final class AppKitOLCollectionView: NSCollectionView {
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?
    private var pressedCardIndexPath: IndexPath?
    private var pressedCardTimestamp: TimeInterval = 0
    private var pendingPressReleaseWorkItem: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        pendingPressReleaseWorkItem?.cancel()
        pendingPressReleaseWorkItem = nil

        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point) {
            pressedCardIndexPath = indexPath
            pressedCardTimestamp = ProcessInfo.processInfo.systemUptime
            cardPressStateHandler?(indexPath, true)
        }

        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.type == .leftMouseUp, let pressedCardIndexPath else { return }
        pendingPressReleaseWorkItem = OnlineLibraryCollectionInteractionSupport.schedulePressRelease(
            pressedAt: pressedCardTimestamp
        ) { [weak self] in
            guard let self else { return }
            self.cardPressStateHandler?(pressedCardIndexPath, false)
            self.pressedCardIndexPath = nil
        }
    }
}

// MARK: - 容器

final class AppKitOLBrowserContainerView: NSView, ModuleFocusable {
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

    private let scrollView: NSScrollView = {
        let s = NSScrollView()
        s.drawsBackground = false
        s.hasVerticalScroller = true
        s.hasHorizontalScroller = false
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var collectionView: AppKitOLCollectionView = {
        let cv = AppKitOLCollectionView()
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
            // 直接 init，避免 makeItem 触发 nib 查找导致崩溃
            let cell = AppKitOLBrowserItem(nibName: nil, bundle: nil)
            let svc = self.service
            cell.configure(
                item: item,
                isDownloading: svc.downloadingIDs.contains(id),
                isDownloaded:  self.isItemDownloaded(id),
                downloadProgress: svc.downloadProgressByID[id],
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

    private func setup() {
        AppKitOLBrowserItem.resetHoverTrackingActivation()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = dataSource
        collectionView.cardPressStateHandler = { [weak self] indexPath, isPressed in
            guard let self,
                  let cell = self.collectionView.item(at: indexPath) as? AppKitOLBrowserItem
            else { return }
            cell.applyPressedState(isPressed)
        }
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
            .sink { [weak self] _ in self?.reloadVisibleItems() }
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
        var byID: [Int: OnlineLibraryVideoItem] = [:]
        byID.reserveCapacity(items.count)
        for item in items { byID[item.id] = item }
        itemsByID = byID
        orderedIDs = items.map { $0.id }

        var snap = NSDiffableDataSourceSnapshot<Section, Int>()
        snap.appendSections([.main])
        snap.appendItems(orderedIDs, toSection: .main)
        let animated = lastLoadedCount != 0 && items.count > lastLoadedCount
        lastLoadedCount = items.count
        dataSource.apply(snap, animatingDifferences: animated)
        updateVisibleThumbnailPriorities()
    }

    private func reloadVisibleItems() {
        let visible = collectionView.indexPathsForVisibleItems()
        guard !visible.isEmpty else { return }
        // 轻量刷新：直接重新 configure 可见 cell
        for ip in visible {
            guard ip.item < orderedIDs.count,
                  let cell = collectionView.item(at: ip) as? AppKitOLBrowserItem
            else { continue }
            let id = orderedIDs[ip.item]
            guard let item = itemsByID[id] else { continue }
            cell.configure(
                item: item,
                isDownloading: self.service.downloadingIDs.contains(id),
                isDownloaded:  self.isItemDownloaded(id),
                downloadProgress: self.service.downloadProgressByID[id],
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

    private func updateVisibleThumbnailPriorities() {
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
        service.prioritizeVisibleItemIDs(visibleIDs)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        scheduleLayoutItemSizeUpdate()
    }

    private func updateLayoutItemSize() {
        let metrics = OnlineLibraryGridLayoutSupport.metrics(
            boundsWidth: bounds.width,
            zoomOffset: service.zoomOffset,
            hoverScale: 1.05,
            sectionInset: flowLayout.sectionInset
        )
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
}
