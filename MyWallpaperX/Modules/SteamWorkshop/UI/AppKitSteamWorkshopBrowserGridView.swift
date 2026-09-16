//
//  AppKitSteamWorkshopBrowserGridView.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class AppKitSteamWorkshopBrowserContainerView: NSView, ModuleFocusable, NSCollectionViewDelegateFlowLayout {
    private enum Section {
        case main
        case status
    }

    private let service: SteamWorkshopService
    var onOpen: (SteamWorkshopBrowserItem) -> Void
    var onDownload: (SteamWorkshopBrowserItem) -> Void
    var onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void
    var onCancelDownload: (SteamWorkshopBrowserItem) -> Void

    private var cancellables = Set<AnyCancellable>()
    private var itemsByID: [String: SteamWorkshopBrowserItem] = [:]
    private var orderedIDs: [String] = []
    private var keyboardFocusedID: String?
    private var currentColumnCount = 1
    private var footerState: SteamWorkshopBrowserFooterSupport.State = .hidden
    private var isApplyingSnapshot = false
    private var pendingFooterSnapshotRefresh = false
    private var moduleActivationObserver: NSObjectProtocol?
    private var lastPrioritizedVisibleIDs: [String] = []
    private var pendingLayoutInvalidation = false
    private var pendingLayoutItemSizeUpdate = false
    private var lastNonZeroLayoutWidth: CGFloat = 0
    private var hasResolvedInitialItemSize = false
    private var pendingItemsUntilInitialLayout: [SteamWorkshopBrowserItem]?

    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    /// 刷新 Owner 已从工具栏按钮迁到原生下拉刷新（NSRefreshController，
    /// macOS 27+）；旧 `.steamRefresh` 工具栏项已退役。仅在 macOS 27+ 时
    /// 持有实例（存储属性不能标 @available，故用 AnyObject 存取）。
    private var pullToRefreshController: AnyObject?

    private lazy var collectionView: SteamWorkshopKeyboardCollectionView = {
        let collectionView = SteamWorkshopKeyboardCollectionView()
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.keyboardDelegate = self
        collectionView.accessibleItemsProvider = { [weak self] in
            guard let self else { return [] }
            return self.collectionView.indexPathsForVisibleItems().sorted().compactMap {
                self.collectionView.item(at: $0)?.view
            }
        }
        collectionView.contextMenuProvider = { [weak self] path in
            guard let self, let path, let id = self.dataSource.itemIdentifier(for: path),
                  let item = self.itemsByID[id] else { return nil }
            let previous = self.keyboardFocusedID
            self.keyboardFocusedID = id
            self.updateKeyboardFocusItem(withID: previous, focused: false)
            self.updateKeyboardFocusItem(withID: id, focused: true)
            return SteamWorkshopItemMenu.make(item: item, service: self.service)
        }
        collectionView.primaryClickHandler = { [weak self] path in
            guard let self, let id = self.dataSource.itemIdentifier(for: path) else { return false }
            return self.openItem(withID: id)
        }
        collectionView.cardPressStateHandler = { [weak self] indexPath, pressed in
            guard let self,
                  let item = self.collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { return }
            item.applyPressedState(pressed)
        }
        return collectionView
    }()

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        SteamWorkshopGridLayoutSupport.makeFlowLayout()
    }()

    private lazy var dataSource: NSCollectionViewDiffableDataSource<Section, String> = {
        let dataSource = NSCollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { [weak self] _, indexPath, id in
            guard let self else { return nil }
            if id == SteamWorkshopBrowserFooterSupport.itemID {
                let item = AppKitSteamWorkshopBrowserFooterItem()
                self.configureFooter(item)
                return item
            }
            guard let item = self.itemsByID[id] else { return nil }
            let cell = AppKitSteamWorkshopBrowserItem(nibName: nil, bundle: nil)
            self.configureCell(cell, for: id)
            return cell
        }
        return dataSource
    }()

    init(
        service: SteamWorkshopService,
        onOpen: @escaping (SteamWorkshopBrowserItem) -> Void,
        onDownload: @escaping (SteamWorkshopBrowserItem) -> Void,
        onSetAsWallpaper: @escaping (SteamWorkshopDownloadRecord) -> Void,
        onCancelDownload: @escaping (SteamWorkshopBrowserItem) -> Void
    ) {
        self.service = service
        self.onOpen = onOpen
        self.onDownload = onDownload
        self.onSetAsWallpaper = onSetAsWallpaper
        self.onCancelDownload = onCancelDownload
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let moduleActivationObserver {
            NotificationCenter.default.removeObserver(moduleActivationObserver)
        }
    }

    func requestFocus() {
        ensureKeyboardFocus()
        window?.makeFirstResponder(collectionView)
    }

    override func layout() {
        super.layout()
        scheduleLayoutItemSizeUpdate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            needsLayout = true
        }
        syncVisiblePreviewAnimationStates(isVisible: window != nil)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = dataSource
        collectionView.delegate = self
        scrollView.documentView = collectionView
        scrollView.contentView.postsBoundsChangedNotifications = true

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        if #available(macOS 27.0, *) {
            installPullToRefreshIfSupported()
        }

        service.$displayedBrowserItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyItems($0) }
            .store(in: &cancellables)

        service.$zoomOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleLayoutItemSizeUpdate() }
            .store(in: &cancellables)

        service.$activeDownloadItemIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadVisibleItems()
            }
            .store(in: &cancellables)

        service.$downloads
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadVisibleItems()
            }
            .store(in: &cancellables)

        service.$launchPendingRecordID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadVisibleItems()
            }
            .store(in: &cancellables)

        service.$previewReloadToken
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.forceReloadVisiblePreviews()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            service.$isLoadingMoreBrowserItems,
            service.$hasMoreBrowserItems,
            service.$browserLoadMoreFailureMessage
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            self?.refreshFooterState()
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.updateBrowserScrollMetrics()
            self.prioritizeVisibleItemsForHydration()
            self.checkLoadMore()
        }
        .store(in: &cancellables)

        service.$pendingBrowserScrollRestoreOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] offsetY in
                guard let self, let offsetY else { return }
                self.restoreScrollOffset(offsetY)
            }
            .store(in: &cancellables)

        // 下拉刷新的收口：feed 刷新结束（含失败/登录指引等同步结束路径）
        // 就撤销刷新指示，不区分刷新发起方式。
        service.$isRefreshingBrowserFeed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRefreshing in
                guard let self, !isRefreshing else { return }
                if #available(macOS 27.0, *) {
                    (self.pullToRefreshController as? NSRefreshController)?.endRefreshing()
                }
            }
            .store(in: &cancellables)

        moduleActivationObserver = NotificationCenter.default.addObserver(
            forName: .moduleDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let module = notification.userInfo?["module"] as? String,
                  module == ModuleIdentifier.steamWorkshop.rawValue else { return }
            self?.requestFocus()
        }

        applyItems(service.displayedBrowserItems)
    }

    @available(macOS 27.0, *)
    private func installPullToRefreshIfSupported() {
        let controller = NSRefreshController()
        controller.target = self
        controller.action = #selector(handlePullToRefresh)
        scrollView.refreshController = controller
        pullToRefreshController = controller
    }

    @available(macOS 27.0, *)
    @objc private func handlePullToRefresh() {
        // 个人来源未登录时 refresh() 走既有登录指引路径并同步复位指示器。
        service.refresh()
    }

    private func applyItems(_ items: [SteamWorkshopBrowserItem]) {
        guard hasResolvedInitialItemSize || updateLayoutItemSize(invalidateImmediately: true) else {
            pendingItemsUntilInitialLayout = items
            return
        }
        pendingItemsUntilInitialLayout = nil
        let previousItemsByID = itemsByID
        let previousOrderedIDs = orderedIDs
        let previousFooterState = footerState
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        orderedIDs = items.map(\.id)
        footerState = SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: service.browserLoadMoreFailureMessage,
            isLoadingMore: service.isLoadingMoreBrowserItems,
            hasMore: service.hasMoreBrowserItems,
            itemIDs: orderedIDs
        )
        let changedIDs = orderedIDs.filter { id in
            guard let previous = previousItemsByID[id], let current = itemsByID[id] else { return false }
            return previous != current
        }
        let structureUnchanged = previousOrderedIDs == orderedIDs && previousFooterState == footerState
        if structureUnchanged {
            if !changedIDs.isEmpty {
                reloadVisibleMetadata(for: Set(changedIDs))
            } else if footerState != .hidden {
                configureVisibleFooterIfNeeded()
            }
            updateBrowserScrollMetrics()
            prioritizeVisibleItemsForHydration()
            checkLoadMore()
            ensureKeyboardFocus()
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(orderedIDs, toSection: .main)
        if footerState != .hidden {
            snapshot.appendSections([.status])
            snapshot.appendItems([SteamWorkshopBrowserFooterSupport.itemID], toSection: .status)
        }
        isApplyingSnapshot = true
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.isApplyingSnapshot = false
            if !changedIDs.isEmpty {
                self.reloadVisibleItems()
            }
            self.refreshFooterState(forceReload: true)
            self.updateBrowserScrollMetrics()
            self.prioritizeVisibleItemsForHydration()
            self.checkLoadMore()
            self.ensureKeyboardFocus()
        }
    }

    private func applyPendingItemsIfInitialLayoutIsReady() {
        guard hasResolvedInitialItemSize,
              let pendingItems = pendingItemsUntilInitialLayout else {
            return
        }
        pendingItemsUntilInitialLayout = nil
        applyItems(pendingItems)
    }

    private func reloadVisibleMetadata(for changedIDs: Set<String>) {
        guard !changedIDs.isEmpty else { return }
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: indexPath), changedIDs.contains(id) else { continue }
            guard let cell = collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { continue }
            guard itemsByID[id] != nil else { continue }
            configureMetadataCell(cell, for: id)
        }
    }

    private func reloadVisibleItems() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: indexPath) else { continue }
            if id == SteamWorkshopBrowserFooterSupport.itemID {
                guard let footerItem = collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserFooterItem else { continue }
                configureFooter(footerItem)
                continue
            }
            guard let cell = collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { continue }
            guard itemsByID[id] != nil else { continue }
            configureCell(cell, for: id)
        }
    }

    private func forceReloadVisiblePreviews() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: indexPath), id != SteamWorkshopBrowserFooterSupport.itemID else { continue }
            guard let cell = collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem else { continue }
            guard itemsByID[id] != nil else { continue }
            cell.forceReloadPreview()
        }
    }

    private func syncVisiblePreviewAnimationStates(isVisible: Bool) {
        for visibleItem in collectionView.visibleItems() {
            guard let item = visibleItem as? AppKitSteamWorkshopBrowserItem else { continue }
            item.setPreviewVisible(isVisible)
        }
    }

    private func configureCell(_ cell: AppKitSteamWorkshopBrowserItem, for id: String) {
        guard let item = itemsByID[id] else { return }
        cell.configure(
            displayContext: .browser,
            item: item,
            downloadRecord: service.latestDownloadRecord(for: id),
            downloadProgressStore: service.downloadProgressStore,
            isDownloading: service.isDownloading(itemID: id),
            isDownloaded: service.isDownloaded(itemID: id),
            isKeyboardFocused: keyboardFocusedID == id,
            onOpen: { [weak self] in _ = self?.openItem(withID: id) },
            onDownload: { [weak self] in self?.onDownload(item) },
            onSetAsWallpaper: { [weak self] in
                guard let self, let record = self.service.downloadRecord(for: id) else { return }
                self.onSetAsWallpaper(record)
            },
            onCancelDownload: { [weak self] in self?.onCancelDownload(item) }
        )
    }

    private func configureMetadataCell(_ cell: AppKitSteamWorkshopBrowserItem, for id: String) {
        guard let item = itemsByID[id] else { return }
        cell.configureMetadataOnly(
            displayContext: .browser,
            item: item,
            downloadRecord: service.latestDownloadRecord(for: id),
            downloadProgressStore: service.downloadProgressStore,
            isDownloading: service.isDownloading(itemID: id),
            isDownloaded: service.isDownloaded(itemID: id),
            isKeyboardFocused: keyboardFocusedID == id,
            onOpen: { [weak self] in _ = self?.openItem(withID: id) },
            onDownload: { [weak self] in self?.onDownload(item) },
            onSetAsWallpaper: { [weak self] in
                guard let self, let record = self.service.downloadRecord(for: id) else { return }
                self.onSetAsWallpaper(record)
            },
            onCancelDownload: { [weak self] in self?.onCancelDownload(item) }
        )
    }

    @discardableResult
    private func openItem(withID id: String) -> Bool {
        guard let item = itemsByID[id] else { return false }
        let previous = keyboardFocusedID
        keyboardFocusedID = id
        updateKeyboardFocusItem(withID: previous, focused: false)
        updateKeyboardFocusItem(withID: id, focused: true)
        window?.makeFirstResponder(collectionView)
        onOpen(item)
        return true
    }

    private func checkLoadMore() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.checkLoadMore()
            }
            return
        }
        guard service.hasMoreBrowserItems, !service.isLoadingMoreBrowserItems else { return }
        // Filtering may hide an entire raw page. Keep a manual continuation
        // rather than automatically draining an unbounded personal collection.
        guard !orderedIDs.isEmpty else { return }
        guard let documentView = scrollView.documentView else { return }
        let contentHeight = documentView.frame.height
        let viewportHeight = scrollView.contentView.bounds.height
        let offsetY = scrollView.contentView.bounds.origin.y
        guard contentHeight > 0, viewportHeight > 0 else { return }
        let preloadDistance = max(720, viewportHeight * 2.5)
        if contentHeight - offsetY - viewportHeight < preloadDistance {
            service.loadMoreBrowserItemsIfNeeded()
        }
    }

    private func handleEscapeKey() -> Bool {
        guard service.selectedBrowserItem != nil else { return false }
        InspectorHostActions.postClose()
        return true
    }

    private func ensureKeyboardFocus() {
        guard !orderedIDs.isEmpty else {
            let previousID = keyboardFocusedID
            keyboardFocusedID = nil
            updateKeyboardFocusItem(withID: previousID, focused: false)
            return
        }
        if let focusedID = keyboardFocusedID, orderedIDs.contains(focusedID) {
            updateKeyboardFocusItem(withID: focusedID, focused: true)
            return
        }
        focusItem(at: 0)
    }

    private func focusItem(at index: Int) {
        guard index >= 0, index < orderedIDs.count else { return }
        let nextID = orderedIDs[index]
        let previousID = keyboardFocusedID
        keyboardFocusedID = nextID
        updateKeyboardFocusItem(withID: previousID, focused: false)
        updateKeyboardFocusItem(withID: nextID, focused: true)
        scrollToItem(nextID)
    }

    private func handleArrowKey(_ keyCode: UInt16) -> Bool {
        let currentIndex = keyboardFocusedID.flatMap { orderedIDs.firstIndex(of: $0) }
        guard let destination = SteamWorkshopGridKeyboardNavigation.destinationIndex(
            keyCode: keyCode,
            currentIndex: currentIndex,
            itemCount: orderedIDs.count,
            columnCount: currentColumnCount
        ) else { return false }
        focusItem(at: destination)
        return true
    }

    private func handlePrimaryActionKey() -> Bool {
        guard let id = keyboardFocusedID,
              let item = itemsByID[id] else { return false }
        onOpen(item)
        return true
    }

    private func scrollToItem(_ id: String) {
        guard let indexPath = indexPathForItemID(id),
              let attributes = flowLayout.layoutAttributesForItem(at: indexPath) else { return }
        let itemFrame = attributes.frame
        let visibleRect = scrollView.contentView.bounds
        guard !visibleRect.contains(itemFrame) else { return }
        let targetY = itemFrame.minY < visibleRect.minY
            ? max(0, itemFrame.minY - 4)
            : itemFrame.maxY - visibleRect.height + 4
        scrollView.contentView.setBoundsOrigin(NSPoint(x: visibleRect.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateKeyboardFocusItem(withID id: String?, focused: Bool) {
        guard let id else { return }
        if let item = cellForItemID(id) {
            item.setKeyboardFocus(focused)
            return
        }
        guard let indexPath = indexPathForItemID(id) else { return }
        collectionView.reloadItems(at: Set([indexPath]))
    }

    private func indexPathForItemID(_ id: String) -> IndexPath? {
        guard let index = orderedIDs.firstIndex(of: id) else { return nil }
        return IndexPath(item: index, section: 0)
    }

    private func cellForItemID(_ id: String) -> AppKitSteamWorkshopBrowserItem? {
        guard let indexPath = indexPathForItemID(id) else { return nil }
        return collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem
    }

    private func prioritizeVisibleItemsForHydration() {
        let visibleIDs = collectionView.indexPathsForVisibleItems()
            .sorted()
            .compactMap { indexPath -> String? in
                guard let id = dataSource.itemIdentifier(for: indexPath), id != SteamWorkshopBrowserFooterSupport.itemID else { return nil }
                return id
            }
        guard !visibleIDs.isEmpty else { return }
        let prioritized = Array(visibleIDs.prefix(16))
        guard prioritized != lastPrioritizedVisibleIDs else { return }
        lastPrioritizedVisibleIDs = prioritized
        service.prioritizeVisibleBrowserItemIDs(prioritized)
    }

    @discardableResult
    private func updateLayoutItemSize(invalidateImmediately: Bool = false) -> Bool {
        guard let layoutWidth = resolvedLayoutWidth() else { return false }
        let metrics = SteamWorkshopGridLayoutSupport.metrics(
            boundsWidth: layoutWidth,
            zoomOffset: service.zoomOffset,
            hoverScale: AppKitSteamWorkshopBrowserItem.hoverScale,
            sectionInset: flowLayout.sectionInset
        )
        currentColumnCount = metrics.columns
        flowLayout.minimumInteritemSpacing = metrics.interitemSpacing
        flowLayout.minimumLineSpacing = metrics.lineSpacing
        let newSize = metrics.itemSize
        hasResolvedInitialItemSize = true

        guard flowLayout.itemSize != newSize else { return true }
        flowLayout.itemSize = newSize
        scheduleLayoutInvalidation()
        return true
    }

    private func scheduleLayoutItemSizeUpdate() {
        guard pendingLayoutItemSizeUpdate == false else { return }
        pendingLayoutItemSizeUpdate = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingLayoutItemSizeUpdate = false
            self.updateLayoutItemSize()
            self.applyPendingItemsIfInitialLayoutIsReady()
        }
    }

    private func resolvedLayoutWidth() -> CGFloat? {
        let candidates = [
            bounds.width,
            scrollView.bounds.width,
            scrollView.contentView.bounds.width,
            superview?.bounds.width ?? 0
        ]
        if let width = candidates.first(where: { $0.isFinite && $0 > 1 }) {
            lastNonZeroLayoutWidth = width
            return width
        }
        if lastNonZeroLayoutWidth > 1 {
            return lastNonZeroLayoutWidth
        }
        return nil
    }

    private func scheduleLayoutInvalidation() {
        guard pendingLayoutInvalidation == false else { return }
        pendingLayoutInvalidation = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingLayoutInvalidation = false
            self.collectionView.collectionViewLayout?.invalidateLayout()
        }
    }

    private func restoreScrollOffset(_ offsetY: CGFloat) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.restoreScrollOffset(offsetY)
            }
            return
        }
        guard let documentView = scrollView.documentView else {
            service.consumePendingBrowserScrollRestoreOffset()
            return
        }
        let maxOffsetY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        let clampedOffsetY = min(max(0, offsetY), maxOffsetY)
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: clampedOffsetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateBrowserScrollMetrics()
        service.consumePendingBrowserScrollRestoreOffset()
    }

    private func updateBrowserScrollMetrics() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateBrowserScrollMetrics()
            }
            return
        }
        guard let documentView = scrollView.documentView else { return }
        service.updateBrowserScrollMetrics(
            offsetY: scrollView.contentView.bounds.origin.y,
            contentHeight: documentView.frame.height,
            viewportHeight: scrollView.contentView.bounds.height
        )
    }

    private func refreshFooterState(forceReload: Bool = false) {
        let previousState = footerState
        let newState = SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: service.browserLoadMoreFailureMessage,
            isLoadingMore: service.isLoadingMoreBrowserItems,
            hasMore: service.hasMoreBrowserItems,
            itemIDs: orderedIDs
        )
        let stateChanged = newState != footerState
        footerState = newState
        scheduleLayoutItemSizeUpdate()
        guard stateChanged || forceReload else { return }
        let visibilityChanged = previousState == .hidden || newState == .hidden
        if stateChanged && visibilityChanged {
            scheduleFooterSnapshotRefresh()
            return
        }
        configureVisibleFooterIfNeeded()
    }

    private func configureVisibleFooterIfNeeded() {
        collectionView.visibleItems().compactMap { $0 as? AppKitSteamWorkshopBrowserFooterItem }.forEach {
            configureFooter($0)
        }
    }

    private func configureFooter(_ item: AppKitSteamWorkshopBrowserFooterItem) {
        SteamWorkshopBrowserFooterSupport.configure(item, state: footerState) { [weak self] in
            self?.service.retryLoadingMoreBrowserItems()
        }
    }

    private func scheduleFooterSnapshotRefresh() {
        pendingFooterSnapshotRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.pendingFooterSnapshotRefresh else { return }
            guard !self.isApplyingSnapshot else {
                return
            }
            self.pendingFooterSnapshotRefresh = false
            self.applyItems(self.service.displayedBrowserItems)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        guard let id = dataSource.itemIdentifier(for: indexPath) else {
            return flowLayout.itemSize
        }
        if id == SteamWorkshopBrowserFooterSupport.itemID {
            return SteamWorkshopBrowserFooterSupport.size(
                for: footerState,
                boundsWidth: bounds.width,
                sectionInset: flowLayout.sectionInset
            )
        }
        return flowLayout.itemSize
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        if id == SteamWorkshopBrowserFooterSupport.itemID {
            if let footerItem = item as? AppKitSteamWorkshopBrowserFooterItem {
                configureFooter(footerItem)
            }
            return
        }

        guard let item = item as? AppKitSteamWorkshopBrowserItem else { return }
        item.setPreviewVisible(true)
        prioritizeVisibleItemsForHydration()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didEndDisplaying item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let item = item as? AppKitSteamWorkshopBrowserItem else { return }
        item.setPreviewVisible(false)
    }
}

extension AppKitSteamWorkshopBrowserContainerView: SteamWorkshopKeyboardDelegate {
    func steamWorkshopCollectionView(_ collectionView: SteamWorkshopKeyboardCollectionView, handleKey event: NSEvent) -> Bool {
        if event.keyCode == 96 && event.modifierFlags.contains(.shift),
           let id = keyboardFocusedID, let item = itemsByID[id],
           let path = indexPathForItemID(id), let frame = flowLayout.layoutAttributesForItem(at: path)?.frame {
            SteamWorkshopItemMenu.make(item: item, service: service).popUp(positioning: nil, at: NSPoint(x: frame.midX, y: frame.midY), in: collectionView)
            return true
        }
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return false }
        switch event.keyCode {
        case 123, 124, 125, 126:
            return handleArrowKey(event.keyCode)
        case 36, 76:
            guard !event.isARepeat else { return true }
            return handlePrimaryActionKey()
        case 53:
            return handleEscapeKey()
        default:
            return false
        }
    }
}
