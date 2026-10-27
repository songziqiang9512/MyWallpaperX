import AppKit

/// The local pages share selection, keyboard, layout and drag semantics. Cells
/// and thumbnail requests remain with their original provider; this controller
/// receives a value projection and never reads files or edits relationships.
@MainActor final class WallpaperLibraryGridController: NSViewController,
    NSCollectionViewDataSource, NSCollectionViewDelegate, NSGestureRecognizerDelegate {
    struct CellState {
        let isSelected: Bool
        let isSelecting: Bool
        let isFocused: Bool
    }
    typealias CellFactory = (NSCollectionView, IndexPath, WallpaperContentItem, CellState) -> NSCollectionViewItem
    typealias Header = (view: NSView, heightForWidth: (CGFloat) -> CGFloat)
    private let makeCell: CellFactory
    var updateCell: ((NSCollectionViewItem, WallpaperContentItem, CellState) -> Void)?
    var needsCellReplacement: ((NSCollectionViewItem, WallpaperContentItem) -> Bool)?
    var setCellVisible: ((NSCollectionViewItem, Bool) -> Void)?
    /// Value-only viewport demand. Source owners retain pixels, scheduling and
    /// file freshness; this grid owns geometry and the mounted visibility lease.
    var onViewport: (([WallpaperContentItem], [WallpaperContentItem]) -> Void)?
    /// Returns the presentation's accepted session receipt. Its asynchronous
    /// view echo can then be distinguished from a reset or a later page visit.
    var onSelection: ((Set<WallpaperReference>, WallpaperReference?) -> UUID?)?
    var onInspect: ((WallpaperContentItem) -> Void)?
    var onPrimaryAction: ((WallpaperContentItem) -> Void)?
    var onQuickLook: ((WallpaperContentItem) -> Void)?
    var onDelete: (([WallpaperContentItem]) -> Void)?
    var onEscape: (() -> Void)?
    var onScrollAnchor: ((WallpaperLibraryPage, WallpaperReference?, Double, Bool) -> Void)?
    var onClipWidthChange: ((CGFloat) -> Void)?
    var onImportFiles: (([URL]) -> Bool)?
    var menuProvider: (([WallpaperContentItem]) -> NSMenu?)?
    static let referencesType = NSPasteboard.PasteboardType("com.songziqiang.MyWallpaperX.wallpaper-references")
    private static let playlistSessionType = NSPasteboard.PasteboardType("com.songziqiang.MyWallpaperX.wallpaper-drag-session")

    let collection = WallpaperLibraryCollectionView()
    let scrollView = WallpaperGridScrollView()
    private let layout = NSCollectionViewFlowLayout()
    private var headerContent: Header?
    private var headerHeight: CGFloat = 0
    private static let headerID = NSUserInterfaceItemIdentifier("WallpaperLibraryPageHeader")
    private(set) var items: [WallpaperContentItem] = []
    private(set) var selection = WallpaperLibrarySelectionState()
    private var preferredColumns = 5
    private var lastClipWidth: CGFloat = 0
    private var acceptsScrollReceipts = true
    private var pendingScroll: (reference: WallpaperReference?, offset: Double?, atTop: Bool?)?
    private var permitsDragging = false
    private var applying = false
    private var boxSelection: BoxSelectionState?
    private var gestureSessionID: UUID?
    private var mouseDownSelectionReceipt: (reference: WallpaperReference, page: WallpaperLibraryPage, sessionID: UUID)?
    private var selectionOrigin: NSPoint?
    private var scrollObserver: NSObjectProtocol?
    private var viewportWork: DispatchWorkItem?
    private var lastViewportOffsetY: CGFloat?
    private weak var viewportWindow: NSWindow?
    private var viewportWindowVisibility: NSKeyValueObservation?
    private var viewportWindowObservers: [NSObjectProtocol] = []
    private var isPageDisplayed = true
    private var hasViewportDemand = false
    private var page: WallpaperLibraryPage?
    private lazy var coverClick = NSClickGestureRecognizer(target: self, action: #selector(clickCover(_:)))
    private lazy var selectionPan = NSPanGestureRecognizer(target: self, action: #selector(panSelection(_:)))

    init(makeCell: @escaping CellFactory) {
        self.makeCell = makeCell
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = WallpaperLibraryGridRootView()
        root.onVisibilityChanged = { [weak self] in self?.synchronizeViewportVisibility() }
        view = root
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.allowsEmptySelection = true
        collection.dataSource = self
        collection.delegate = self
        collection.register(WallpaperLibraryGridHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: Self.headerID)
        collection.registerForDraggedTypes([.fileURL])
        collection.setDraggingSourceOperationMask(.copy, forLocal: true)
        collection.setDraggingSourceOperationMask([], forLocal: false)
        coverClick.numberOfClicksRequired = 1
        coverClick.delaysPrimaryMouseButtonEvents = false
        coverClick.delegate = self
        selectionPan.delegate = self
        selectionPan.delaysPrimaryMouseButtonEvents = false
        collection.addGestureRecognizer(coverClick)
        collection.addGestureRecognizer(selectionPan)
        collection.onBoxSelection = { [weak self] path, rect, finished in self?.boxSelect(path, rect: rect, finished: finished) }
        collection.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        collection.onSelectAll = { [weak self] in self?.selectAllInSelectionMode() }
        collection.onMouseDownSelection = { [weak self] path in
            guard let self, !self.applying else { return false }
            self.mouseDownSelectionReceipt = nil
            guard !self.selection.isSelecting, let value = self.item(at: path), let page = self.page else { return true }
            if self.selection.references == [value.reference], self.selection.focusedReference == value.reference { return true }
            guard self.select([value.reference], focus: value.reference) else { return false }
            self.mouseDownSelectionReceipt = (value.reference, page, self.selection.sessionID)
            return true
        }
        collection.contextMenuProvider = { [weak self] path in self?.menu(at: path) }
        scrollView.documentView = collection
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.applying else { return }
                    if !self.scrollView.isGridScrolling { self.reportScrollAnchor() }
                    self.scheduleViewport()
                }
            }
        scrollView.onScrollSettled = { [weak self] in self?.reportScrollAnchor() }
    }

    deinit {
        viewportWork?.cancel()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        viewportWindowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewWillLayout() {
        // Native resizing can reflow the old item size before didLayout. Keep
        // the last real viewport in the existing pending position first.
        if !applying, pendingScroll == nil, acceptsScrollReceipts, page != nil, hasRestorableViewport {
            let anchor = visibleAnchor(), atTop = scrollView.isGridAtTop
            if anchor != nil || atTop {
                pendingScroll = (anchor?.reference, anchor.map { Double($0.offset) }, atTop)
            }
        }
        super.viewWillLayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !applying else { return }
        applying = true
        // Complete the scroll view's native tiling as well as the document's
        // flow layout before consuming a saved position.
        scrollView.layoutSubtreeIfNeeded()
        updateLayout()
        collection.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        applyPendingScroll()
        applying = false
        scheduleViewport()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        reportScrollAnchor()
        isPageDisplayed = false
        cancelViewport()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        isPageDisplayed = true
        synchronizeViewportVisibility()
    }

    func update(page: WallpaperLibraryPage, items: [WallpaperContentItem], selection: WallpaperLibrarySelectionState,
                preferredColumns: Int, permitsDragging: Bool, scrollAnchor: WallpaperReference?,
                scrollOffset: Double? = nil, scrollAtTop: Bool? = nil, resetScroll: Bool = false,
                header: Header? = nil) {
        loadViewIfNeeded()
        let entering = self.page != page || resetScroll || !acceptsScrollReceipts
        if entering {
            if !resetScroll { reportScrollAnchor() }
            cancelViewport()
            pendingScroll = (scrollAnchor, scrollOffset, scrollAtTop)
        }
        let oldAnchor = visibleAnchor()
        let wasAtTop = scrollView.isGridAtTop
        let orderChanged = self.items.map(\.reference) != items.map(\.reference)
        var replacedCells = Set(zip(self.items, items).enumerated().compactMap { index, pair in
            pair.0.reference == pair.1.reference && pair.0.providerReference.provider != pair.1.providerReference.provider
                ? IndexPath(item: index, section: 0) : nil
        })
        if let needsCellReplacement, !orderChanged, !entering {
            for path in collection.indexPathsForVisibleItems() where items.indices.contains(path.item) {
                if let cell = collection.item(at: path), needsCellReplacement(cell, items[path.item]) {
                    replacedCells.insert(path)
                }
            }
        }
        let zoomChanged = self.preferredColumns != preferredColumns
        let headerChanged = headerContent?.view !== header?.view
        if gestureSessionID != nil, entering || orderChanged || zoomChanged || gestureSessionID != selection.sessionID
            || self.selection.isSelecting != selection.isSelecting {
            boxSelection = nil
            gestureSessionID = nil
            mouseDownSelectionReceipt = nil
            selectionOrigin = nil
            collection.cancelSelectionTracking = true
            coverClick.isEnabled = false
            selectionPan.isEnabled = false
            coverClick.isEnabled = true
            selectionPan.isEnabled = true
        }
        applying = true
        defer { applying = false }
        if orderChanged || entering || headerChanged {
            collection.visibleItems().forEach { invalidateAccessibilityActivation($0); setCellVisible?($0, false) }
        } else if !replacedCells.isEmpty {
            replacedCells.compactMap { collection.item(at: $0) }.forEach(invalidateAccessibilityActivation)
        }
        self.items = items
        headerContent = header
        acceptsScrollReceipts = true
        self.page = page
        self.selection = selection
        self.preferredColumns = preferredColumns
        self.permitsDragging = permitsDragging
        // AppKit can request cells synchronously while changing selection or
        // tiling the scroll view. Replace its old count/layout topology before
        // any such call can observe the newly installed value projection.
        if orderChanged || entering || headerChanged {
            collection.reloadData()
        } else if !replacedCells.isEmpty {
            collection.reloadItems(at: replacedCells)
        }
        collection.allowsMultipleSelection = selection.isSelecting
        scrollView.layoutSubtreeIfNeeded()
        let geometryChanged = updateLayout(measureHeader: true)
        collection.selectionIndexPaths = Set(items.indices.compactMap {
            selection.references.contains(items[$0].reference) ? IndexPath(item: $0, section: 0) : nil
        })
        refreshVisibleCells()
        collection.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        if orderChanged || entering || zoomChanged || headerChanged || geometryChanged {
            if pendingScroll != nil {
                applyPendingScroll()
            } else if let oldAnchor {
                _ = restoreScroll(reference: oldAnchor.reference, offset: Double(oldAnchor.offset), atTop: wasAtTop)
            }
        }
        scheduleViewport()
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let host = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: Self.headerID, for: indexPath)
        (host as? WallpaperLibraryGridHeader)?.setContent(headerContent?.view)
        return host
    }

    @discardableResult private func updateLayout(measureHeader: Bool = false) -> Bool {
        let width = scrollView.contentView.bounds.width
        guard width.isFinite, width > 0 else { return false }
        let widthChanged = lastClipWidth != width
        if headerContent == nil { headerHeight = 0 }
        else if measureHeader || widthChanged { headerHeight = max(0, headerContent!.heightForWidth(width)) }
        let metrics = WallpaperLibraryGridMetrics(clipWidth: width, preferredColumns: preferredColumns)
        let size = NSSize(width: metrics.coverSide, height: metrics.coverSide)
        let headerSize = NSSize(width: width, height: headerHeight)
        var changed = layout.headerReferenceSize != headerSize
        if changed { layout.headerReferenceSize = headerSize; layout.invalidateLayout() }
        if layout.itemSize != size || layout.sectionInset.left != metrics.horizontalInset {
            changed = true
            layout.itemSize = size
            layout.sectionInset = NSEdgeInsets(top: WallpaperLibraryGridMetrics.topInset, left: metrics.horizontalInset,
                bottom: WallpaperLibraryGridMetrics.bottomInset, right: metrics.horizontalInset)
            layout.minimumInteritemSpacing = WallpaperLibraryGridMetrics.horizontalSpacing
            layout.minimumLineSpacing = WallpaperLibraryGridMetrics.verticalSpacing
            layout.invalidateLayout()
        }
        if widthChanged {
            lastClipWidth = width
            onClipWidthChange?(width)
        }
        return changed
    }

    private var hasRestorableViewport: Bool {
        let viewport = scrollView.gridViewportRect
        guard !viewport.isEmpty else { return false }
        guard let window = view.window else { return true }
        return !collection.convert(viewport, to: nil).intersection(window.contentLayoutRect).isEmpty
    }

    private func restoreScroll(reference: WallpaperReference?, offset: Double?, atTop: Bool?) -> Bool {
        let width = scrollView.contentView.bounds.width
        guard width.isFinite, width > 0, hasRestorableViewport else { return false }
        let index = reference.flatMap { reference in items.firstIndex { $0.reference == reference } }
        // An empty initial source snapshot must not consume a saved position.
        if reference != nil, index == nil, items.isEmpty { return false }
        let legacyTop = atTop == nil && offset == nil && (index ?? 0) == 0
        var y = scrollView.gridDocumentTopY
        if atTop != true, !legacyTop, let index {
            layout.prepare()
            guard let attributes = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return false }
            y = attributes.frame.minY - CGFloat(offset ?? 0) - scrollView.contentInsets.top
        }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(scrollView.gridDocumentTopY, y)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return true
    }

    private func applyPendingScroll() {
        guard let pendingScroll else { return }
        let previousApplying = applying
        applying = true
        defer { applying = previousApplying }
        if restoreScroll(reference: pendingScroll.reference, offset: pendingScroll.offset, atTop: pendingScroll.atTop) {
            self.pendingScroll = nil
        }
    }

    private func reportScrollAnchor() {
        guard acceptsScrollReceipts, !applying, isPageDisplayed, let page, !items.isEmpty, pendingScroll == nil,
              gestureSessionID == nil, boxSelection == nil else { return }
        let anchor = visibleAnchor()
        onScrollAnchor?(page, anchor?.reference, Double(anchor?.offset ?? 0), scrollView.isGridAtTop)
    }

    /// The existing reset owner revoked the old projection. A native scroll
    /// settlement after detachment must not recreate its saved view position.
    func invalidateScrollReceipt() { acceptsScrollReceipts = false }

    private func state(for item: WallpaperContentItem) -> CellState {
        CellState(isSelected: selection.references.contains(item.reference), isSelecting: selection.isSelecting,
            isFocused: selection.focusedReference == item.reference)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let value = items[indexPath.item]
        let cell = makeCell(collectionView, indexPath, value, state(for: value))
        bindAccessibilityActivation(cell, content: value)
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        let frame = layout.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
        if let value = self.item(at: indexPath) { bindAccessibilityActivation(item, content: value) }
        setCellVisible?(item, viewportIsVisible && frame.intersects(collection.gridVisibleRect))
        scheduleViewport()
    }
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        invalidateAccessibilityActivation(item)
        setCellVisible?(item, false)
    }

    private func item(at index: IndexPath?) -> WallpaperContentItem? {
        guard let index, items.indices.contains(index.item) else { return nil }
        return items[index.item]
    }

    private func refreshVisibleCells() {
        for path in collection.indexPathsForVisibleItems() {
            guard let value = item(at: path), let cell = collection.item(at: path) else { continue }
            updateCell?(cell, value, state(for: value))
            bindAccessibilityActivation(cell, content: value)
        }
    }

    private func invalidateAccessibilityActivation(_ cell: NSCollectionViewItem) {
        guard let root = cell.view as? WallpaperCardInteractionView else { return }
        root.onAccessibilityActivate = { false }
    }

    private func bindAccessibilityActivation(_ cell: NSCollectionViewItem, content: WallpaperContentItem) {
        guard let root = cell.view as? WallpaperCardInteractionView, let page, !page.isRemoteBrowse || page == .wallhaven || page == .pixiv else { return }
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.group)
        root.setAccessibilityLabel(content.title)
        let reference = content.reference, sessionID = selection.sessionID
        root.onAccessibilityActivate = { [weak self, weak root, weak cell] in
            guard let self, let root, let cell, cell.view === root,
                  !self.applying, self.viewportIsVisible, self.page == page, self.selection.sessionID == sessionID,
                  let path = self.collection.indexPath(for: cell), self.collection.item(at: path) === cell,
                  let current = self.item(at: path), current.reference == reference,
                  self.layout.layoutAttributesForItem(at: path)?.frame.intersects(self.collection.gridVisibleRect) == true else { return false }
            return self.activateCover(current)
        }
    }

    private var viewportIsVisible: Bool {
        isViewLoaded && isPageDisplayed && view.window?.isVisible == true
            && view.window?.isMiniaturized == false && !view.isHiddenOrHasHiddenAncestor
    }

    private func synchronizeViewportVisibility() {
        guard isViewLoaded else { return }
        if viewportWindow !== view.window {
            viewportWindowVisibility?.invalidate()
            viewportWindowVisibility = nil
            viewportWindowObservers.forEach(NotificationCenter.default.removeObserver)
            viewportWindowObservers.removeAll()
            viewportWindow = view.window
            if let window = view.window {
                viewportWindowVisibility = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.synchronizeViewportVisibility() }
                }
                for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                    viewportWindowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.synchronizeViewportVisibility() }
                    })
                }
            }
        }
        if viewportIsVisible { scheduleViewport() } else { cancelViewport() }
    }

    private func scheduleViewport() {
        guard viewportIsVisible else { cancelViewport(); return }
        // Leading coalescing retains one deadline while continued scrolling
        // supplies newer geometry. It never defers a whole gesture to its end.
        guard viewportWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.viewportWork = nil
            self.publishViewport()
        }
        viewportWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    private func cancelViewport() {
        viewportWork?.cancel()
        viewportWork = nil
        lastViewportOffsetY = nil
        collection.visibleItems().forEach { invalidateAccessibilityActivation($0); setCellVisible?($0, false) }
        if hasViewportDemand {
            hasViewportDemand = false
            onViewport?([], [])
        }
    }

    private func publishViewport() {
        guard viewportIsVisible else { cancelViewport(); return }
        let viewport = collection.gridVisibleRect
        let indices = layout.layoutAttributesForElements(in: viewport).compactMap { attribute -> Int? in
            guard attribute.representedElementCategory == .item, attribute.frame.intersects(viewport),
                  let path = attribute.indexPath, items.indices.contains(path.item) else { return nil }
            return path.item
        }.sorted()
        let visiblePaths = Set(indices.map { IndexPath(item: $0, section: 0) })
        for cell in collection.visibleItems() {
            let path = collection.indexPath(for: cell)
            let visible = path.map(visiblePaths.contains) == true
            if visible, let content = item(at: path) { bindAccessibilityActivation(cell, content: content) }
            else { invalidateAccessibilityActivation(cell) }
            setCellVisible?(cell, visible)
        }
        let offset = viewport.minY
        let direction = lastViewportOffsetY.map { offset == $0 ? 0 : offset > $0 ? 1 : -1 } ?? 0
        lastViewportOffsetY = offset
        let metrics = WallpaperLibraryGridMetrics(clipWidth: scrollView.contentView.bounds.width, preferredColumns: preferredColumns)
        let nearby = GridThumbnailPrefetchDemand.indices(visibleIndices: indices, itemCount: items.count,
            neighborLimit: min(24, metrics.columns * 2), direction: direction)
        hasViewportDemand = !indices.isEmpty || !nearby.isEmpty
        onViewport?(indices.map { items[$0] }, nearby.map { items[$0] })
    }

    func scrollToTop(animated: Bool = true) {
        loadViewIfNeeded()
        let top = NSPoint(x: 0, y: scrollView.gridDocumentTopY)
        guard scrollView.contentView.bounds.origin != top else { return }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                scrollView.contentView.animator().setBoundsOrigin(top)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
                    self.scheduleViewport()
                }
            }
        } else {
            scrollView.contentView.scroll(to: top)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            scheduleViewport()
        }
    }

    @discardableResult
    func select(_ references: Set<WallpaperReference>, focus: WallpaperReference?) -> Bool {
        let previous = selection
        let previousPage = page
        selection.references = references
        selection.focusedReference = focus
        if let onSelection {
            let receipt = onSelection(references, focus)
            // A callback may synchronously install a reset or another page.
            // Rejection must not roll that newer input back to this gesture.
            guard selection.sessionID == previous.sessionID, page == previousPage else {
                applyNativeSelection()
                return false
            }
            guard let receipt else {
                selection = previous
                applyNativeSelection()
                return false
            }
            selection.sessionID = receipt
            if gestureSessionID != nil { gestureSessionID = receipt }
        }
        applyNativeSelection()
        if let window = collection.window, window.firstResponder !== collection { window.makeFirstResponder(collection) }
        return true
    }

    private func applyNativeSelection() {
        applying = true
        collection.selectionIndexPaths = Set(items.indices.compactMap {
            selection.references.contains(items[$0].reference) ? IndexPath(item: $0, section: 0) : nil
        })
        applying = false
        refreshVisibleCells()
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        guard gestureRecognizer !== selectionPan || selection.isSelecting else { return false }
        var hit = collection.hitTest(collection.convert(event.locationInWindow, from: nil))
        while let target = hit, target !== collection {
            if WallpaperCardInteractionView.isInteractiveControl(target) { return false }
            hit = target.superview
        }
        if event.type == .leftMouseDown {
            gestureSessionID = selection.sessionID
            selectionOrigin = collection.convert(event.locationInWindow, from: nil)
            collection.cancelSelectionTracking = false
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        selection.isSelecting && gestureRecognizer === coverClick && otherGestureRecognizer === selectionPan
    }

    @objc private func clickCover(_ sender: NSClickGestureRecognizer) {
        guard sender.state == .ended else { return }
        defer { gestureSessionID = nil; mouseDownSelectionReceipt = nil; selectionOrigin = nil }
        if let event = NSApp.currentEvent, event.type == .leftMouseUp, event.clickCount > 1 { return }
        guard !collection.cancelSelectionTracking, gestureSessionID == selection.sessionID else { return }
        let point = sender.location(in: collection)
        let index = collection.indexPathForItem(at: point)
        if selection.isSelecting {
            collection.window?.makeFirstResponder(collection)
            if let value = item(at: index) { _ = activateCover(value) }
            else { boxSelect(index, rect: NSRect(origin: point, size: .zero), finished: true) }
            return
        }
        guard let value = item(at: index) else { select([], focus: nil); return }
        if let receipt = mouseDownSelectionReceipt {
            // Native drag admission already selected this target on mouseDown.
            // Reuse only that same gesture's accepted value, never a previous
            // click's selected state or a receipt from another page/session.
            guard receipt.reference == value.reference, receipt.page == page, receipt.sessionID == selection.sessionID,
                  selection.references == [value.reference], selection.focusedReference == value.reference else { return }
            onInspect?(value)
        } else {
            _ = activateCover(value)
        }
    }

    @discardableResult
    private func activateCover(_ content: WallpaperContentItem) -> Bool {
        if selection.isSelecting {
            return select(selection.references.symmetricDifference([content.reference]), focus: content.reference)
        }
        guard select([content.reference], focus: content.reference) else { return false }
        onInspect?(content)
        return true
    }

    @objc private func panSelection(_ sender: NSPanGestureRecognizer) {
        guard selection.isSelecting, !collection.cancelSelectionTracking,
              gestureSessionID == selection.sessionID else { return }
        let point = sender.location(in: collection)
        if sender.state == .began { collection.window?.makeFirstResponder(collection) }
        guard let origin = selectionOrigin else { return }
        switch sender.state {
        case .began, .changed, .ended:
            let rect = NSRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                width: abs(point.x - origin.x), height: abs(point.y - origin.y))
            collection.onBoxSelection?(collection.indexPathForItem(at: origin), rect, sender.state == .ended)
            if sender.state == .changed, let event = NSApp.currentEvent { collection.autoscroll(with: event) }
            if sender.state == .ended { gestureSessionID = nil; selectionOrigin = nil }
        case .cancelled, .failed:
            boxSelection = nil; gestureSessionID = nil; selectionOrigin = nil
            reportScrollAnchor()
        default: break
        }
    }

    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        !applying && selection.isSelecting ? [] : indexPaths
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !applying else { return }
        let references = Set(collectionView.selectionIndexPaths.compactMap { item(at: $0)?.reference })
        let focus = indexPaths.sorted().last.flatMap { item(at: $0)?.reference }
        select(references, focus: focus)
    }

    func collectionView(_ collectionView: NSCollectionView, shouldDeselectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        guard !applying else { return indexPaths }
        if selection.isSelecting { return [] }
        // mouseDown already admitted the sole target before native tracking.
        // Its programmatic update clears the previous item while applying is
        // true; keep the new focused cover selected during Command tracking too.
        // NSApp.currentEvent can change inside that native tracking loop.
        return Set(indexPaths.filter { item(at: $0)?.reference != selection.focusedReference })
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !applying else { return }
        let references = Set(collectionView.selectionIndexPaths.compactMap { item(at: $0)?.reference })
        select(references, focus: selection.focusedReference.flatMap { references.contains($0) ? $0 : nil })
    }

    private func boxSelect(_ index: IndexPath?, rect: NSRect, finished: Bool) {
        guard selection.isSelecting, !collection.cancelSelectionTracking else { return }
        if boxSelection == nil {
            let deselect = item(at: index).map { selection.references.contains($0.reference) } ?? false
            boxSelection = BoxSelectionState(mode: deselect ? .deselect : .select,
                initialIDs: Set(selection.references.map(\.storageKey)))
            gestureSessionID = selection.sessionID
        }
        guard gestureSessionID == selection.sessionID else { return }
        let query = NSRect(x: rect.minX, y: rect.minY, width: max(1, rect.width), height: max(1, rect.height))
        let touched = Set(layout.layoutAttributesForElements(in: query).compactMap { attribute -> String? in
            guard attribute.representedElementCategory == .item else { return nil }
            return item(at: attribute.indexPath)?.reference.storageKey
        })
        if let resolved = boxSelection?.resolve(touching: touched) {
            select(Set(resolved.compactMap(WallpaperReference.init(storageKey:))), focus: item(at: index)?.reference)
        }
        if finished {
            boxSelection = nil; gestureSessionID = nil
            reportScrollAnchor()
        }
    }

    private func menu(at index: IndexPath?) -> NSMenu? {
        if let value = item(at: index), !selection.references.contains(value.reference) {
            guard select([value.reference], focus: value.reference) else { return nil }
        }
        let targets = index == nil ? [] : items.filter { selection.references.contains($0.reference) }
        return menuProvider?(targets)
    }

    private func selectAllInSelectionMode() {
        guard selection.isSelecting else { return }
        select(Set(items.map(\.reference)), focus: selection.focusedReference)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "a", selection.isSelecting {
            selectAllInSelectionMode()
            return true
        }
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 123, 124, 125, 126:
            guard !items.isEmpty else { return true }
            let metrics = WallpaperLibraryGridMetrics(clipWidth: scrollView.contentView.bounds.width, preferredColumns: preferredColumns)
            let current = selection.focusedReference.flatMap { ref in items.firstIndex { $0.reference == ref } }
            let delta = event.keyCode == 123 ? -1 : event.keyCode == 124 ? 1 : event.keyCode == 125 ? metrics.columns : -metrics.columns
            let index = current.map { min(items.count - 1, max(0, $0 + delta)) } ?? 0
            let value = items[index]
            guard select(selection.isSelecting ? selection.references : [value.reference], focus: value.reference) else { return true }
            if let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame {
                collection.scrollToVisible(frame)
            }
            if !selection.isSelecting { onInspect?(value) }
        case 36, 76:
            if selection.isSelecting {
                if let button = collection.window?.defaultButtonCell, button.isEnabled { button.performClick(nil) }
                return true
            }
            guard !selection.isSelecting, selection.references.count == 1,
                  let value = items.first(where: { selection.references.contains($0.reference) }) else { return true }
            onPrimaryAction?(value)
        case 49:
            if selection.references.count == 1,
               let value = items.first(where: { selection.references.contains($0.reference) }) { onQuickLook?(value) }
        case 51, 117: onDelete?(items.filter { selection.references.contains($0.reference) })
        case 53: onEscape?()
        default: return false
        }
        return true
    }

    private func visibleAnchor() -> (reference: WallpaperReference, offset: CGFloat)? {
        let viewport = scrollView.gridViewportRect
        let paths = layout.layoutAttributesForElements(in: collection.visibleRect.intersection(viewport)).compactMap { attribute -> (IndexPath, NSRect)? in
            guard attribute.representedElementCategory == .item, let path = attribute.indexPath else { return nil }
            return (path, attribute.frame)
        }.sorted { $0.1.minY == $1.1.minY ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY }
        guard let first = paths.first, let value = item(at: first.0) else { return nil }
        return (value.reference, first.1.minY - viewport.minY)
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard permitsDragging, let page, !page.isRemoteBrowse, page != .playlists,
              !selection.isSelecting, let value = item(at: indexPath), value.capabilities.contains(.organize) else { return nil }
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(value.reference.storageKey, forType: Self.referencesType)
        pasteboard.setString(selection.sessionID.uuidString, forType: Self.playlistSessionType)
        return pasteboard
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        mouseDownSelectionReceipt = nil
        // The live card and its thumbnail demand stay mounted. A second native
        // flyback image would briefly cover that source after cancellation.
        session.animatesToStartingPositionsOnCancelOrFail = false
    }


    /// The native source object and its current page/session must both match.
    /// A bare copied reference cannot grant local relationship capabilities.
    func referencesForPlaylistDrop(from info: NSDraggingInfo) -> [WallpaperReference]? {
        guard permitsDragging, info.draggingSource as? NSCollectionView === collection,
              let page, !page.isRemoteBrowse, page != .playlists, !selection.isSelecting,
              info.draggingPasteboard.string(forType: Self.playlistSessionType) == selection.sessionID.uuidString,
              let raw = info.draggingPasteboard.string(forType: Self.referencesType),
              let reference = WallpaperReference(storageKey: raw),
              let content = items.first(where: { $0.reference == reference }), content.capabilities.contains(.organize) else { return nil }
        return [reference]
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard draggingInfo.draggingSource as? NSCollectionView !== collection else { return [] }
        return onImportFiles != nil && !fileURLs(from: draggingInfo).isEmpty ? .copy : []
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard draggingInfo.draggingSource as? NSCollectionView !== collection else { return false }
        let files = fileURLs(from: draggingInfo)
        guard !files.isEmpty, let onImportFiles else { return false }
        return onImportFiles(files)
    }

    private func fileURLs(from draggingInfo: NSDraggingInfo) -> [URL] {
        (draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

}

/// Preserve native item hit testing and dragging. The controller's native click
/// and selection-only pan recognizers own the product's explicit selection mode.
@MainActor final class WallpaperLibraryCollectionView: NSCollectionView {
    var onBoxSelection: ((IndexPath?, NSRect, Bool) -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    var onSelectAll: (() -> Void)?
    var onMouseDownSelection: ((IndexPath?) -> Bool)?
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var cancelSelectionTracking = false

    override func mouseDown(with event: NSEvent) {
        // Admit the ordinary single target before AppKit snapshots selection
        // for a drag, including its Command/Shift tracking paths. Inspection
        // remains with the click recognizer after a completed non-drag click.
        let path = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        guard onMouseDownSelection?(path) != false else { return }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?(indexPathForItem(at: convert(event.locationInWindow, from: nil)))
    }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
    override func selectAll(_ sender: Any?) { onSelectAll?() }
}

private final class WallpaperLibraryGridHeader: NSView {
    func setContent(_ content: NSView?) {
        guard subviews.first !== content else { return }
        subviews.forEach { $0.removeFromSuperview() }
        guard let content else { return }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

/// Native visibility callbacks include ancestor hiding and reparenting; they
/// revoke viewport consumers even when no collection display event occurs.
private final class WallpaperLibraryGridRootView: NSView {
    var onVisibilityChanged: (() -> Void)?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onVisibilityChanged?() }
    override func viewDidHide() { super.viewDidHide(); onVisibilityChanged?() }
    override func viewDidUnhide() { super.viewDidUnhide(); onVisibilityChanged?() }
}
