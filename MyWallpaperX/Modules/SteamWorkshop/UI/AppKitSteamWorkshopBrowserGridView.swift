//
//  AppKitSteamWorkshopBrowserGridView.swift
//  MyWallpaperX
//

import AppKit
import Combine

private final class SteamWorkshopBrowserFlowLayout: NSCollectionViewFlowLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != collectionView?.bounds.width || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }

    override func invalidationContext(forBoundsChange newBounds: NSRect) -> NSCollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        if newBounds.width != collectionView?.bounds.width,
           let flowContext = context as? NSCollectionViewFlowLayoutInvalidationContext {
            // Width changes must discard cached delegate footer widths before
            // AppKit lays out the narrowed collection, not on the next run loop.
            flowContext.invalidateFlowLayoutDelegateMetrics = true
        }
        return context
    }
}

final class AppKitSteamWorkshopBrowserContainerView: NSView, ModuleFocusable, NSCollectionViewDelegateFlowLayout, ListThumbnailTintProviding {
    let listThumbnailTintSource = ListThumbnailTintSource()
    private func publishListThumbnailTint() {
        let first = orderedIDs.first.flatMap { itemsByID[$0] }
        SteamWorkshopListThumbnailTint.publish(to: listThumbnailTintSource,
            item: first, record: first.flatMap { service.latestDownloadRecord(for: $0.id) }, refreshToken: service.previewReloadToken)
    }

    private enum Section {
        case main
        case status
    }

    private let service: SteamWorkshopService
    var onOpen: (SteamWorkshopBrowserItem) -> Void
    var onDownload: (SteamWorkshopBrowserItem) -> Void
    var onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void
    var onCancelDownload: (SteamWorkshopBrowserItem) -> Void
    var makeOrganization: ((SteamWorkshopBrowserItem) -> AppKitSteamWorkshopBrowserItem.OrganizationPresentation?)? {
        didSet { refreshLibraryActions() }
    }
    var makeOrganizationMenu: ((SteamWorkshopBrowserItem) -> NSMenu?)?
    var preferredColumns = 5 {
        didSet { if preferredColumns != oldValue { scheduleLayoutItemSizeUpdate() } }
    }
    var clipWidth: CGFloat { scrollView.contentView.bounds.width }
    var onClipWidthChange: ((CGFloat) -> Void)?
    private var lastReportedClipWidth: CGFloat?

    /// Relationships/playback are supplied by App. Source metadata and the
    /// original thumbnail demand remain unchanged by this presentation refresh.
    func refreshLibraryActions() {
        for path in collectionView.indexPathsForVisibleItems() {
            guard let cell = collectionView.item(at: path) as? AppKitSteamWorkshopBrowserItem,
                  let id = dataSource.itemIdentifier(for: path) else { continue }
            configureMetadataCell(cell, for: id)
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var itemsByID: [String: SteamWorkshopBrowserItem] = [:]
    private var orderedIDs: [String] = []
    private var keyboardFocusedID: String?
    private var currentColumnCount = 1
    private var footerState: SteamWorkshopBrowserFooterSupport.State = .hidden
    private var isApplyingSnapshot = false
    private var isItemsApplyScheduled = false
    private var moduleActivationObserver: NSObjectProtocol?
    private let previewPrefetch = SteamWorkshopPreviewPrefetchController()
    private var previewPrefetchWorkItem: DispatchWorkItem?
    private var lastPrefetchOffsetY: CGFloat?
    private var thumbnailWindowVisibilityObservation: NSKeyValueObservation?
    private var thumbnailDemandIsVisible: Bool {
        window?.isVisible == true && window?.isMiniaturized == false && !isHiddenOrHasHiddenAncestor
    }
    private var pendingLayoutItemSizeUpdate = false
    private var pendingItems: [SteamWorkshopBrowserItem]?

    private let scrollView: WallpaperGridScrollView = {
        let scrollView = WallpaperGridScrollView()
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
            return self.itemMenu(for: item)
        }
        collectionView.primaryClickHandler = { [weak self] path in
            guard let self, let id = self.dataSource.itemIdentifier(for: path) else { return false }
            return self.openItem(withID: id)
        }
        return collectionView
    }()

    private func itemMenu(for item: SteamWorkshopBrowserItem) -> NSMenu {
        let menu = SteamWorkshopItemMenu.make(item: item, service: service, navigationVersion: service.navigationVersion)
        if let organization = makeOrganizationMenu?(item), !organization.items.isEmpty {
            menu.addItem(.separator())
            for entry in organization.items {
                organization.removeItem(entry)
                menu.addItem(entry)
            }
        }
        return menu
    }

    private lazy var flowLayout: NSCollectionViewFlowLayout = {
        let layout = SteamWorkshopBrowserFlowLayout()
        layout.minimumInteritemSpacing = WallpaperLibraryGridMetrics.horizontalSpacing
        layout.minimumLineSpacing = WallpaperLibraryGridMetrics.verticalSpacing
        layout.sectionInset = SteamWorkshopGridLayoutSupport.sectionInset
        return layout
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
            guard let cell = self.collectionView.makeItem(
                withIdentifier: AppKitSteamWorkshopBrowserItem.reuseIdentifier, for: indexPath) as? AppKitSteamWorkshopBrowserItem else { return nil }
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
        previewPrefetchWorkItem?.cancel()
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
        if window == nil { reportClipWidth(0) }
        thumbnailWindowVisibilityObservation = nil
        if let window {
            thumbnailWindowVisibilityObservation = window.observe(\.isVisible, options: [.new]) { [weak self] window, _ in
                MainActor.assumeIsolated {
                    guard let self, self.window === window else { return }
                    self.syncVisiblePreviewAnimationStates(isVisible: self.thumbnailDemandIsVisible)
                    self.prioritizeVisibleItemsForHydration()
                }
            }
        }
        if window != nil { needsLayout = true }
        syncVisiblePreviewAnimationStates(isVisible: thumbnailDemandIsVisible)
        prioritizeVisibleItemsForHydration()
    }

    override func viewDidHide() {
        super.viewDidHide(); cancelPreviewPrefetch(); syncVisiblePreviewAnimationStates(isVisible: false)
    }
    override func viewDidUnhide() {
        super.viewDidUnhide(); syncVisiblePreviewAnimationStates(isVisible: thumbnailDemandIsVisible); prioritizeVisibleItemsForHydration()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        collectionView.collectionViewLayout = flowLayout
        collectionView.register(AppKitSteamWorkshopBrowserItem.self, forItemWithIdentifier: AppKitSteamWorkshopBrowserItem.reuseIdentifier)
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

        // Xcode 27 (Swift 6.4) introduces this SDK symbol. Runtime availability
        // alone cannot make it compile with the Xcode 26 release toolchain.
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            installPullToRefreshIfSupported()
        }
        #endif

        service.$displayedBrowserItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyItems($0) }
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
                self?.publishListThumbnailTint()
                self?.prioritizeVisibleItemsForHydration()
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
                self?.previewPrefetch.cancelAll()
                self?.forceReloadVisiblePreviews()
                self?.publishListThumbnailTint()
                self?.prioritizeVisibleItemsForHydration()
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
            .sink { [weak self] _ in self?.restorePendingScrollOffsetIfReady() }
            .store(in: &cancellables)

        // 下拉刷新的收口：feed 刷新结束（含失败/登录指引等同步结束路径）
        // 就撤销刷新指示，不区分刷新发起方式。
        service.$isRefreshingBrowserFeed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRefreshing in
                guard let self, !isRefreshing else { return }
                #if compiler(>=6.4)
                if #available(macOS 27.0, *) {
                    (self.pullToRefreshController as? NSRefreshController)?.endRefreshing()
                }
                #endif
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

        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self, let window = notification.object as? NSWindow, self.window === window else { return }
                    self.syncVisiblePreviewAnimationStates(isVisible: self.thumbnailDemandIsVisible)
                    self.prioritizeVisibleItemsForHydration()
                }.store(in: &cancellables)
        }
        applyItems(service.displayedBrowserItems)
    }

    #if compiler(>=6.4)
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
    #endif

    private func applyItems(_ items: [SteamWorkshopBrowserItem]) {
        pendingItems = items
        guard !isItemsApplyScheduled else { return }
        isItemsApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isItemsApplyScheduled = false
            self.applyPendingItemsIfReady()
        }
    }

    private func applyPendingItemsIfReady() {
        guard !isItemsApplyScheduled, !isApplyingSnapshot,
              updateLayoutItemSize(),
              let items = pendingItems else { return }
        pendingItems = nil
        commitItems(items)
    }

    private func commitItems(_ items: [SteamWorkshopBrowserItem]) {
        let previousItemsByID = itemsByID
        let previousOrderedIDs = orderedIDs
        let previousFocusIndex = keyboardFocusedID.flatMap { previousOrderedIDs.firstIndex(of: $0) }
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        orderedIDs = items.map(\.id)
        publishListThumbnailTint()
        if let previousFocusIndex, let focusedID = keyboardFocusedID, !orderedIDs.contains(focusedID) {
            keyboardFocusedID = orderedIDs.isEmpty ? nil : orderedIDs[min(previousFocusIndex, orderedIDs.count - 1)]
        }
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
        let footerWasVisible = dataSource.snapshot().itemIdentifiers.contains(SteamWorkshopBrowserFooterSupport.itemID)
        let structureUnchanged = previousOrderedIDs == orderedIDs && footerWasVisible == (footerState != .hidden)
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
            restorePendingScrollOffsetIfReady()
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
        let animate = SteamWorkshopGridLayoutSupport.shouldAnimateChange(
            from: previousOrderedIDs, to: orderedIDs, visibleCount: collectionView.indexPathsForVisibleItems().count,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        dataSource.apply(snapshot, animatingDifferences: animate) { [weak self] in
            guard let self else { return }
            self.isApplyingSnapshot = false
            self.updateLayoutItemSize()
            self.reloadVisibleItems()
            self.refreshFooterState(forceReload: true)
            self.updateBrowserScrollMetrics()
            self.prioritizeVisibleItemsForHydration()
            self.checkLoadMore()
            self.ensureKeyboardFocus()
            self.applyPendingItemsIfReady()
            self.restorePendingScrollOffsetIfReady()
        }
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
        guard !isApplyingSnapshot else { return }
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
            item.setPreviewVisible(isVisible && thumbnailDemandIsVisible)
        }
    }

    private func configureCell(_ cell: AppKitSteamWorkshopBrowserItem, for id: String) {
        guard let item = itemsByID[id] else { return }
        let organization = makeOrganization?(item)
        cell.configure(
            displayContext: .browser,
            isPlaying: organization?.isPlaying ?? false,
            item: item,
            downloadRecord: service.latestDownloadRecord(for: id),
            downloadProgressStore: service.downloadProgressStore,
            isDownloading: service.isDownloading(itemID: id),
            isDownloaded: service.isDownloaded(itemID: id),
            isKeyboardFocused: keyboardFocusedID == id,
            organization: organization,
            makeMenu: { [weak self] in
                guard let self, let current = self.itemsByID[id] else { return nil }
                return self.itemMenu(for: current)
            },
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
        let organization = makeOrganization?(item)
        cell.configureMetadataOnly(
            displayContext: .browser,
            isPlaying: organization?.isPlaying ?? false,
            item: item,
            downloadRecord: service.latestDownloadRecord(for: id),
            downloadProgressStore: service.downloadProgressStore,
            isDownloading: service.isDownloading(itemID: id),
            isDownloaded: service.isDownloaded(itemID: id),
            isKeyboardFocused: keyboardFocusedID == id,
            organization: organization,
            makeMenu: { [weak self] in
                guard let self, let current = self.itemsByID[id] else { return nil }
                return self.itemMenu(for: current)
            },
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
        guard window != nil, !isApplyingSnapshot, !isItemsApplyScheduled, pendingItems == nil,
              service.pendingBrowserScrollRestoreOffset == nil,
              service.hasMoreBrowserItems, !service.isLoadingMoreBrowserItems else { return }
        // Author search covers loaded pages only; even a single match must not
        // shrink the grid into repeatedly preloading the rest of the catalog.
        guard service.allowsAutomaticBrowserContinuation else { return }
        // Filtering may hide an entire raw page. Keep a manual continuation
        // rather than automatically draining an unbounded personal collection.
        guard !orderedIDs.isEmpty else { return }
        guard let documentView = scrollView.documentView else { return }
        let contentHeight = documentView.frame.height
        let viewport = scrollView.gridViewportRect
        guard contentHeight > 0, !viewport.isEmpty else { return }
        let preloadDistance = max(720, scrollView.contentView.bounds.height * 2.5)
        if contentHeight - viewport.maxY < preloadDistance {
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
        let visibleRect = scrollView.gridViewportRect
        guard !visibleRect.contains(itemFrame) else { return }
        let targetY = itemFrame.minY < visibleRect.minY
            ? max(0, itemFrame.minY - 4)
            : itemFrame.maxY - visibleRect.height + 4
        let top = scrollView.gridDocumentTopY
        let bottom = max(top, collectionView.bounds.height - scrollView.contentView.bounds.height + scrollView.contentInsets.bottom)
        let nativeY = min(bottom, max(top, targetY - scrollView.contentInsets.top))
        scrollView.contentView.setBoundsOrigin(NSPoint(x: scrollView.contentView.bounds.origin.x, y: nativeY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateKeyboardFocusItem(withID id: String?, focused: Bool) {
        guard let id else { return }
        if let item = cellForItemID(id) {
            item.setKeyboardFocus(focused)
            return
        }
        // Offscreen cells receive current focus when displayed. Reloading an
        // absent cell here needlessly starts another native layout transaction.
    }

    private func indexPathForItemID(_ id: String) -> IndexPath? {
        guard let index = orderedIDs.firstIndex(of: id) else { return nil }
        return IndexPath(item: index, section: 0)
    }

    private func cellForItemID(_ id: String) -> AppKitSteamWorkshopBrowserItem? {
        guard let indexPath = indexPathForItemID(id) else { return nil }
        return collectionView.item(at: indexPath) as? AppKitSteamWorkshopBrowserItem
    }

    private func cancelPreviewPrefetch() {
        previewPrefetchWorkItem?.cancel()
        previewPrefetchWorkItem = nil
        lastPrefetchOffsetY = nil
        previewPrefetch.cancelAll()
    }

    private func prioritizeVisibleItemsForHydration() {
        guard thumbnailDemandIsVisible else {
            cancelPreviewPrefetch(); return
        }
        guard previewPrefetchWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.previewPrefetchWorkItem = nil
            self.prefetchCurrentViewport()
        }
        previewPrefetchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func prefetchCurrentViewport() {
        guard thumbnailDemandIsVisible else {
            cancelPreviewPrefetch(); return
        }
        let offset = scrollView.contentView.bounds.minY
        let direction = lastPrefetchOffsetY.map { offset == $0 ? 0 : (offset > $0 ? 1 : -1) } ?? 0
        lastPrefetchOffsetY = offset
        let visible = collectionView.indexPathsForVisibleItems().filter { $0.section == 0 }.map(\.item)
        let indices = GridThumbnailPrefetchDemand.indices(visibleIndices: visible, itemCount: orderedIDs.count,
            neighborLimit: min(24, currentColumnCount * 2), direction: direction)
        let candidates = (indices + visible).compactMap { index -> SteamWorkshopPreviewPrefetchController.Candidate? in
            guard index >= 0, index < orderedIDs.count else { return nil }
            let id = orderedIDs[index]
            guard let item = itemsByID[id] else { return nil }
            return .init(id: id, item: item, record: service.latestDownloadRecord(for: id), startsIfMissing: !visible.contains(index))
        }
        let pixels = min(800, GridThumbnailDecoder.pixelLimit(width: flowLayout.itemSize.width,
            scale: window?.backingScaleFactor ?? 2))
        previewPrefetch.replace(with: candidates, maxPixelSize: pixels)
    }

    @discardableResult
    private func updateLayoutItemSize() -> Bool {
        guard !isApplyingSnapshot else { return false }
        guard let layoutWidth = resolvedLayoutWidth() else { reportClipWidth(0); return false }
        let viewportWidthChanged = lastReportedClipWidth != layoutWidth
        reportClipWidth(layoutWidth)
        let metrics = WallpaperLibraryGridMetrics(clipWidth: layoutWidth, preferredColumns: preferredColumns)
        currentColumnCount = metrics.columns
        let newSize = NSSize(width: metrics.coverSide, height: metrics.coverSide)
        guard viewportWidthChanged || flowLayout.itemSize != newSize
                || flowLayout.minimumInteritemSpacing != WallpaperLibraryGridMetrics.horizontalSpacing
                || flowLayout.minimumLineSpacing != WallpaperLibraryGridMetrics.verticalSpacing else { return true }
        flowLayout.minimumInteritemSpacing = WallpaperLibraryGridMetrics.horizontalSpacing
        flowLayout.minimumLineSpacing = WallpaperLibraryGridMetrics.verticalSpacing
        flowLayout.itemSize = newSize
        flowLayout.invalidateLayout()
        prioritizeVisibleItemsForHydration()
        return true
    }

    private func reportClipWidth(_ width: CGFloat) {
        guard width.isFinite, width >= 0, lastReportedClipWidth != width else { return }
        lastReportedClipWidth = width
        onClipWidthChange?(width)
    }

    private func scheduleLayoutItemSizeUpdate() {
        guard pendingLayoutItemSizeUpdate == false else { return }
        pendingLayoutItemSizeUpdate = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingLayoutItemSizeUpdate = false
            self.updateLayoutItemSize()
            self.applyPendingItemsIfReady()
            self.restorePendingScrollOffsetIfReady()
        }
    }

    private func resolvedLayoutWidth() -> CGFloat? {
        let width = scrollView.contentView.bounds.width
        guard window != nil, width.isFinite, width > 1 else { return nil }
        return width
    }

    private func restorePendingScrollOffsetIfReady() {
        guard let offsetY = service.pendingBrowserScrollRestoreOffset else { return }
        restoreScrollOffset(offsetY)
    }

    private func restoreScrollOffset(_ offsetY: CGFloat) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.restoreScrollOffset(offsetY)
            }
            return
        }
        // Independent publishers can deliver an old offset before the current
        // feed reaches this view. Keep the source token for its actual layout.
        guard window != nil, !isItemsApplyScheduled, !isApplyingSnapshot, !pendingLayoutItemSizeUpdate, pendingItems == nil,
              let documentView = scrollView.documentView else { return }
        let viewport = scrollView.gridViewportRect
        guard viewport.width > 1, viewport.height > 0,
              orderedIDs == service.displayedBrowserItems.map(\.id),
              footerState == SteamWorkshopBrowserFooterSupport.resolvedState(
                failureMessage: service.browserLoadMoreFailureMessage,
                isLoadingMore: service.isLoadingMoreBrowserItems,
                hasMore: service.hasMoreBrowserItems, itemIDs: orderedIDs) else { return }
        collectionView.layoutSubtreeIfNeeded()
        // Source snapshots persist the uncovered document viewport, not the
        // native clip origin (whose true top is negative below a toolbar).
        let top = scrollView.gridDocumentTopY
        let maxOffsetY = max(top, documentView.bounds.height - scrollView.contentView.bounds.height + scrollView.contentInsets.bottom)
        let clampedOffsetY = min(max(top, offsetY - scrollView.contentInsets.top), maxOffsetY)
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
        guard window != nil, let documentView = scrollView.documentView else { return }
        let viewport = scrollView.gridViewportRect
        guard !viewport.isEmpty else { return }
        service.updateBrowserScrollMetrics(
            offsetY: max(0, viewport.minY),
            contentHeight: documentView.frame.height,
            viewportHeight: viewport.height
        )
    }

    private func refreshFooterState(forceReload: Bool = false) {
        guard !isApplyingSnapshot else {
            applyItems(service.displayedBrowserItems)
            return
        }
        let previousState = footerState
        let newState = SteamWorkshopBrowserFooterSupport.resolvedState(
            failureMessage: service.browserLoadMoreFailureMessage,
            isLoadingMore: service.isLoadingMoreBrowserItems,
            hasMore: service.hasMoreBrowserItems,
            itemIDs: orderedIDs
        )
        let stateChanged = newState != footerState
        footerState = newState
        if previousState != .hidden, newState != .hidden,
           SteamWorkshopBrowserFooterSupport.size(for: previousState, boundsWidth: collectionView.bounds.width,
                sectionInset: flowLayout.sectionInset).height != SteamWorkshopBrowserFooterSupport.size(
                    for: newState, boundsWidth: collectionView.bounds.width, sectionInset: flowLayout.sectionInset).height {
            flowLayout.invalidateLayout()
        }
        scheduleLayoutItemSizeUpdate()
        guard stateChanged || forceReload else { return }
        let visibilityChanged = previousState == .hidden || newState == .hidden
        if stateChanged && visibilityChanged {
            applyItems(service.displayedBrowserItems)
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

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        // A live resize can narrow the viewport during an animated snapshot.
        // Keep its old card metrics inside the new bounds until the transaction
        // completes and updateLayoutItemSize installs the final square size.
        let availableWidth = min(collectionView.bounds.width, scrollView.contentView.bounds.width)
            - flowLayout.sectionInset.left - flowLayout.sectionInset.right
        let width = max(1, min(flowLayout.itemSize.width, availableWidth))
        let cardSize = NSSize(width: width, height: width)
        guard let id = dataSource.itemIdentifier(for: indexPath) else {
            return cardSize
        }
        if id == SteamWorkshopBrowserFooterSupport.itemID {
            return SteamWorkshopBrowserFooterSupport.size(
                for: footerState,
                boundsWidth: min(collectionView.bounds.width, scrollView.contentView.bounds.width),
                sectionInset: flowLayout.sectionInset
            )
        }
        return cardSize
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
        item.setKeyboardFocus(keyboardFocusedID == id)
        item.setPreviewVisible(thumbnailDemandIsVisible)
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
            SteamWorkshopItemMenu.make(item: item, service: service, navigationVersion: service.navigationVersion).popUp(positioning: nil, at: NSPoint(x: frame.midX, y: frame.midY), in: collectionView)
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
