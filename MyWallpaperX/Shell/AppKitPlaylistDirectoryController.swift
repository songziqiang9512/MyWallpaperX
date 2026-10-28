import AppKit

/// Presentation only: relationship commands, cover production and navigation
/// are injected. A menu always carries the UUID captured when it was opened.
final class AppKitPlaylistDirectoryController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onAction: ((PlaylistOrganizationAction) -> Void)?
    var onReorder: (([UUID], @escaping (Result<Int64, Error>) -> Void) -> Void)?
    var onCoverDemand: ((Set<UUID>) -> Void)? { didSet { updateCoverDemand(force: true) } }
    var onScrollAnchor: ((UUID?, Double, Bool) -> Void)?
    var onClipWidthChange: ((CGFloat) -> Void)?
    var clipWidth: CGFloat { isViewLoaded ? scrollView.contentView.bounds.width : 0 }
    var permitsPullCountInput: (() -> Bool)? {
        get { scrollView.permitsPullCountInput }
        set { scrollView.permitsPullCountInput = newValue }
    }
    func setPullCountText(_ text: String?) { scrollView.pullCountText = text }
    var selectedPlaylistID: UUID? { collection.selectionIndexPaths.first.flatMap { entry(at: $0.item)?.id } }
    var canDeleteSelectedPlaylist: Bool { canEdit && collection.window?.firstResponder === collection && selectedPlaylistID != nil }
    private(set) var entries: [WallpaperPlaylistDirectoryEntry] = []
    private var covers: [UUID: WallpaperPlaylistArtwork] = [:]
    private var authoritativeEntries: [WallpaperPlaylistDirectoryEntry] = []
    private var resetEpoch: UUID?
    private var dragEpoch: UUID?
    private var activeDragID: UUID?
    private var originalOrder: [UUID] = []
    private var validatedDrop = false
    private var reorderToken: UUID?
    private var pendingOrder: [UUID]?
    private var acceptedRevision: Int64?
    private var relationshipsRevision: Int64?
    private var dragDemand = Set<UUID>()
    private var isMoving = false
    private var queuedEntries: [WallpaperPlaylistDirectoryEntry]?
    private var demandUpdateDepth = 0
    private var permitsReordering = false
    private var canEdit = true
    private var scrollApplicationDepth = 0
    private var restoredScroll = false
    private var acceptsScrollReceipts = true
    private var lastReportedAnchor: UUID?
    private var lastReportedOffset: Double?
    private var lastReportedAtTop: Bool?
    private var pendingAnchor: (id: UUID?, offset: CGFloat?, atTop: Bool?)?
    private var preferredColumns = 5
    private var lastClipWidth: CGFloat = 0
    private let scrollView = WallpaperGridScrollView()
    private let collection = PlaylistDirectoryCollectionView()
    private let layout = PlaylistDirectoryFlowLayout()
    private var artworkObservation: WallpaperArtworkDemandObservation?
    private var lastCoverDemand = Set<UUID>()
    private static let itemID = NSUserInterfaceItemIdentifier("PlaylistDirectoryCard")
    private static let pasteboardType = NSPasteboard.PasteboardType("com.songziqiang.MyWallpaperX.playlist-order")

    override func loadView() {
        let content = PlaylistDirectoryDemandView()
        view = content
        content.onVisibilityChange = { [weak self] in self?.updateCoverDemand() }
        content.onWindowChange = { [weak self] in self?.artworkObservation?.windowDidChange() }
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColors = [.clear]
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(PlaylistDirectoryItem.self, forItemWithIdentifier: Self.itemID)
        collection.registerForDraggedTypes([Self.pasteboardType])
        collection.setDraggingSourceOperationMask(.move, forLocal: true)
        collection.openSelected = { [weak self] in self?.activateSelected() }
        collection.deleteSelected = { [weak self] in self?.deleteSelectedPlaylist() }
        collection.makeContextMenu = { [weak self] index in self?.menu(for: index) }
        scrollView.documentView = collection
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        artworkObservation = WallpaperArtworkDemandObservation(view: view, clipView: scrollView.contentView) { [weak self] in
            self?.updateCoverDemand()
        }
        artworkObservation?.onScroll = { [weak self] in
            guard let self, !self.scrollView.isGridScrolling else { return }
            self.reportScrollAnchor()
        }
        scrollView.onScrollSettled = { [weak self] in self?.reportScrollAnchor() }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = scrollView.contentView.bounds.width
        guard width.isFinite, width > 0 else { return }
        let metrics = WallpaperLibraryGridMetrics(clipWidth: width, preferredColumns: preferredColumns)
        let size = NSSize(width: metrics.coverSide, height: metrics.coverSide + 29)
        let insets = NSEdgeInsets(top: WallpaperLibraryGridMetrics.topInset, left: metrics.horizontalInset,
                                 bottom: WallpaperLibraryGridMetrics.bottomInset, right: metrics.horizontalInset)
        if layout.itemSize != size || layout.sectionInset.left != insets.left {
            layout.itemSize = size
            layout.sectionInset = insets
            layout.minimumInteritemSpacing = WallpaperLibraryGridMetrics.horizontalSpacing
            layout.minimumLineSpacing = WallpaperLibraryGridMetrics.verticalSpacing
            layout.invalidateLayout()
        }
        applyPendingAnchor()
        updateCoverDemand()
        if lastClipWidth != width { lastClipWidth = width; onClipWidthChange?(width) }
    }

    func update(entries: [WallpaperPlaylistDirectoryEntry], covers: [UUID: WallpaperPlaylistArtwork], preferredColumns: Int,
                permitsReordering: Bool, canEdit: Bool = true, resetEpoch: UUID? = nil, relationshipsRevision: Int64? = nil) {
        loadViewIfNeeded()
        authoritativeEntries = entries
        let ids = entries.map(\.id)
        let invalid = self.resetEpoch != resetEpoch || !canEdit || !permitsReordering
            || Set(ids) != Set(self.entries.map(\.id))
            || (activeDragID != nil && reorderToken == nil && originalOrder != ids)
        if invalid { retireDrag() }
        self.resetEpoch = resetEpoch
        self.relationshipsRevision = relationshipsRevision
        self.covers = covers; self.preferredColumns = preferredColumns
        self.permitsReordering = permitsReordering; self.canEdit = canEdit
        if hasCommittedAuthority(order: ids) { retireDrag() }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let order = pendingOrder ?? (activeDragID == nil ? ids : (queuedEntries ?? self.entries).map(\.id))
        installEntries(order.compactMap { byID[$0] })
        configureVisibleItems()
        view.needsLayout = true
        updateCoverDemand()
    }

    private func configureVisibleItems() {
        guard !isMoving else { return }
        for path in collection.indexPathsForVisibleItems() {
            let row = entry(at: path.item)
            (collection.item(at: path) as? PlaylistDirectoryItem)?.configure(entry: row, cover: row.flatMap { covers[$0.id] }, canCreate: canEdit)
        }
    }

    private func installEntries(_ desired: [WallpaperPlaylistDirectoryEntry]) {
        if isMoving { queuedEntries = desired; return }
        let oldIDs = entries.map(\.id), newIDs = desired.map(\.id)
        guard oldIDs != newIDs else { entries = desired; return }
        if pendingAnchor == nil, activeDragID == nil, reorderToken == nil {
            let current = currentScrollAnchor()
            pendingAnchor = (current?.id, current?.offset, scrollView.isGridAtTop)
        }
        let selectedID = selectedPlaylistID
        let selectedCreate = collection.selectionIndexPaths.contains(IndexPath(item: 0, section: 0))
        scrollApplicationDepth += 1; demandUpdateDepth += 1
        let width = scrollView.contentView.bounds.width
        let metrics = WallpaperLibraryGridMetrics(clipWidth: width, preferredColumns: preferredColumns)
        if view.window == nil || oldIDs.isEmpty || lastClipWidth != width || layout.itemSize.width != metrics.coverSide {
            entries = desired
            collection.reloadData()
            restoreSelection(selectedID, create: selectedCreate)
            demandUpdateDepth -= 1; scrollApplicationDepth -= 1
            return
        }
        isMoving = true
        let difference = newIDs.difference(from: oldIDs).inferringMoves()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            collection.animator().performBatchUpdates({
                self.entries = desired
                for change in difference {
                    switch change {
                    case .remove(let source, _, let destination):
                        if let destination {
                            self.collection.moveItem(at: IndexPath(item: source + 1, section: 0), to: IndexPath(item: destination + 1, section: 0))
                        } else { self.collection.deleteItems(at: [IndexPath(item: source + 1, section: 0)]) }
                    case .insert(let destination, _, nil):
                        self.collection.insertItems(at: [IndexPath(item: destination + 1, section: 0)])
                    default: break
                    }
                }
            }, completionHandler: { [weak self] _ in
                guard let self else { return }
                self.isMoving = false
                self.demandUpdateDepth -= 1; self.scrollApplicationDepth -= 1
                if self.collection.selectionIndexPaths.isEmpty { self.restoreSelection(selectedID, create: selectedCreate) }
                if let queued = self.queuedEntries {
                    self.queuedEntries = nil
                    self.installEntries(queued)
                }
                self.configureVisibleItems()
                self.view.needsLayout = true
                self.updateCoverDemand()
            })
        }
    }

    private func restoreSelection(_ id: UUID?, create: Bool) {
        let paths: Set<IndexPath>
        if let id, let index = entries.firstIndex(where: { $0.id == id }) { paths = [IndexPath(item: index + 1, section: 0)] }
        else { paths = create ? [IndexPath(item: 0, section: 0)] : [] }
        if collection.selectionIndexPaths != paths { collection.selectionIndexPaths = paths }
    }

    private func hasCommittedAuthority(order: [UUID]) -> Bool {
        guard let acceptedRevision else { return false }
        // An unrelated earlier metadata echo cannot settle this commit. A newer
        // real authority may already contain another reorder or an Undo.
        if let relationshipsRevision { return relationshipsRevision >= acceptedRevision }
        return pendingOrder == order
    }

    private func retireDrag() {
        activeDragID = nil; validatedDrop = false; pendingOrder = nil
        reorderToken = nil; acceptedRevision = nil; dragDemand = []
    }

    /// Called on page entry, separately from ordinary state/cover echoes.
    func restoreScrollAnchor(_ id: UUID?, offset: Double? = nil, atTop: Bool? = nil) {
        loadViewIfNeeded()
        acceptsScrollReceipts = true
        restoredScroll = true
        pendingAnchor = (id, offset.map { CGFloat($0) }, atTop)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    private func currentScrollAnchor() -> (id: UUID?, offset: CGFloat)? {
        let viewport = scrollView.gridViewportRect
        let visible = layout.layoutAttributesForElements(in: collection.visibleRect.intersection(viewport)).compactMap { attribute -> (IndexPath, NSRect)? in
            guard attribute.representedElementCategory == .item, let path = attribute.indexPath else { return nil }
            return (path, attribute.frame)
        }.sorted { $0.1.minY == $1.1.minY ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY }
        guard let first = visible.first else { return nil }
        return (entry(at: first.0.item)?.id, first.1.minY - viewport.minY)
    }

    private func applyPendingAnchor() {
        let width = scrollView.contentView.bounds.width
        guard let anchor = pendingAnchor, width.isFinite, width > 0, !scrollView.gridViewportRect.isEmpty else { return }
        if anchor.id != nil, entries.isEmpty { return }
        scrollApplicationDepth += 1
        defer { scrollApplicationDepth -= 1 }
        layout.prepare()
        let index = anchor.id.flatMap { id in entries.firstIndex(where: { $0.id == id }).map { $0 + 1 } } ?? 0
        let legacyTop = anchor.atTop == nil && anchor.offset == nil && index <= 1
        guard let attributes = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return }
        let y = anchor.atTop == true || legacyTop ? scrollView.gridDocumentTopY
            : attributes.frame.minY - (anchor.offset ?? 0) - scrollView.contentInsets.top
        pendingAnchor = nil
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(scrollView.gridDocumentTopY, y)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        if restoredScroll { lastReportedAnchor = currentScrollAnchor()?.id }
    }

    private func reportScrollAnchor() {
        guard acceptsScrollReceipts, restoredScroll, scrollApplicationDepth == 0, pendingAnchor == nil, artworkObservation?.isVisible == true else { return }
        let anchor = currentScrollAnchor(), id = anchor?.id
        let offset = Double(anchor?.offset ?? 0), atTop = scrollView.isGridAtTop
        guard lastReportedAnchor != id || lastReportedOffset != offset || lastReportedAtTop != atTop else { return }
        lastReportedAnchor = id
        lastReportedOffset = offset
        lastReportedAtTop = atTop
        onScrollAnchor?(id, offset, atTop)
    }

    func invalidateScrollReceipt() { acceptsScrollReceipts = false }

    override func viewWillDisappear() {
        reportScrollAnchor()
        super.viewWillDisappear()
    }

    func deleteSelectedPlaylist() {
        guard canDeleteSelectedPlaylist, let id = selectedPlaylistID else { return }
        onAction?(.delete(id))
    }

    private func updateCoverDemand(force: Bool = false) {
        if !isViewLoaded || artworkObservation?.isVisible != true {
            let hadDrag = activeDragID != nil || reorderToken != nil
            retireDrag()
            if hadDrag { installEntries(authoritativeEntries) }
            if force || !lastCoverDemand.isEmpty { lastCoverDemand = []; onCoverDemand?([]) }
            return
        }
        guard demandUpdateDepth == 0 else { return }
        var demand: Set<UUID>
        if isViewLoaded, artworkObservation?.isVisible == true {
            let viewport = collection.gridVisibleRect
            // willDisplay arrives before AppKit adds that item to its visible
            // index set. The native viewport geometry already includes it.
            demand = Set(layout.layoutAttributesForElements(in: viewport).compactMap { attribute -> UUID? in
                guard attribute.representedElementCategory == .item, attribute.frame.intersects(viewport),
                      let path = attribute.indexPath, path.section == 0 else { return nil }
                return entry(at: path.item)?.id
            })
        } else { demand = [] }
        demand.formUnion(dragDemand)
        guard force || demand != lastCoverDemand else { return }
        lastCoverDemand = demand
        onCoverDemand?(demand)
    }

    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        updateCoverDemand()
    }
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        updateCoverDemand()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { entries.count + 1 }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.itemID, for: indexPath) as! PlaylistDirectoryItem
        let entry = entry(at: indexPath.item)
        item.configure(entry: entry, cover: entry.flatMap { covers[$0.id] }, canCreate: canEdit)
        let id = entry?.id
        item.onActivate = { [weak self, weak item] in
            guard let self, let item, let window = self.view.window, window.isVisible,
                  !self.view.isHiddenOrHasHiddenAncestor, item.view.window === window,
                  let path = self.collection.indexPath(for: item), self.collection.item(at: path) === item,
                  let onAction = self.onAction else { return false }
            if let id {
                guard self.entry(at: path.item)?.id == id else { return false }
                onAction(.open(id))
            } else {
                guard path.item == 0, self.canEdit else { return false }
                onAction(.create)
            }
            return true
        }
        return item
    }

    private func entry(at index: Int) -> WallpaperPlaylistDirectoryEntry? {
        guard index > 0, entries.indices.contains(index - 1) else { return nil }
        return entries[index - 1]
    }

    private func activateSelected() {
        guard let index = collection.selectionIndexPaths.first?.item else { return }
        if let target = entry(at: index) { onAction?(.open(target.id)) }
        else if index == 0, canEdit { onAction?(.create) }
    }

    private func menu(for index: Int?) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, action: Selector, id: UUID? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = id as NSUUID?
            menu.addItem(item)
        }
        if let index, let target = entry(at: index) {
            add("打开播放列表", action: #selector(openFromMenu(_:)), id: target.id)
            add("编辑列表…", action: #selector(renameFromMenu(_:)), id: target.id)
            add("复制列表", action: #selector(duplicateFromMenu(_:)), id: target.id)
            menu.addItem(.separator())
            add("删除列表…", action: #selector(deleteFromMenu(_:)), id: target.id)
        } else { add("新建列表…", action: #selector(createFromMenu(_:))) }
        for item in menu.items where item.action != #selector(openFromMenu(_:)) { item.isEnabled = canEdit }
        menu.autoenablesItems = false
        return menu
    }

    @objc private func createFromMenu(_ sender: NSMenuItem) { if canEdit { onAction?(.create) } }
    @objc private func openFromMenu(_ sender: NSMenuItem) { if let id = sender.representedObject as? UUID { onAction?(.open(id)) } }
    @objc private func renameFromMenu(_ sender: NSMenuItem) { if canEdit, let id = sender.representedObject as? UUID { onAction?(.rename(id)) } }
    @objc private func duplicateFromMenu(_ sender: NSMenuItem) { if canEdit, let id = sender.representedObject as? UUID { onAction?(.duplicate(id)) } }
    @objc private func deleteFromMenu(_ sender: NSMenuItem) { if canEdit, let id = sender.representedObject as? UUID { onAction?(.delete(id)) } }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard canEdit, permitsReordering, reorderToken == nil, !isMoving, onReorder != nil,
              let target = entry(at: indexPath.item) else { return nil }
        activeDragID = target.id; dragEpoch = resetEpoch; originalOrder = authoritativeEntries.map(\.id)
        dragDemand = lastCoverDemand.union([target.id]); validatedDrop = false
        let value = NSPasteboardItem()
        value.setString(target.id.uuidString, forType: Self.pasteboardType)
        return value
    }

    private func dragID(_ info: NSDraggingInfo) -> UUID? {
        guard canEdit, permitsReordering, reorderToken == nil, dragEpoch == resetEpoch,
              info.draggingSource as? NSCollectionView === collection,
              let raw = info.draggingPasteboard.string(forType: Self.pasteboardType), let id = UUID(uuidString: raw),
              id == activeDragID, Set(originalOrder) == Set(authoritativeEntries.map(\.id)) else { return nil }
        return id
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo,
                        proposedIndexPath path: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation operation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard let id = dragID(info), path.pointee.section == 0, path.pointee.item > 0 else { validatedDrop = false; return [] }
        // AppKit's index belongs to the currently installed data source, even
        // while a preceding move is animating and later orders are queued.
        let before = min(entries.count, path.pointee.item - 1)
        let target = entries.dropFirst(before).first { $0.id != id }?.id
        var order = (queuedEntries ?? entries).map(\.id)
        guard let from = order.firstIndex(of: id) else { validatedDrop = false; return [] }
        order.remove(at: from)
        let destination = target.flatMap { order.firstIndex(of: $0) } ?? order.count
        order.insert(id, at: destination)
        let byID = Dictionary(uniqueKeysWithValues: authoritativeEntries.map { ($0.id, $0) })
        installEntries(order.compactMap { byID[$0] })
        let targetIndex = target.flatMap { target in entries.firstIndex { $0.id == target } } ?? entries.count
        path.pointee = IndexPath(item: targetIndex + 1, section: 0) as NSIndexPath
        operation.pointee = .before
        validatedDrop = true
        return .move
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard dragID(info) != nil, validatedDrop, indexPath.section == 0, indexPath.item > 0,
              let onReorder else { return false }
        let order = (queuedEntries ?? entries).map(\.id)
        guard order != authoritativeEntries.map(\.id) else { retireDrag(); updateCoverDemand(); return true }
        let token = UUID(); reorderToken = token; pendingOrder = order; acceptedRevision = nil
        onReorder(order) { [weak self] result in
            guard let self, self.reorderToken == token else { return }
            switch result {
            case .success(let revision):
                self.acceptedRevision = revision
                if self.hasCommittedAuthority(order: self.authoritativeEntries.map(\.id)) {
                    self.retireDrag(); self.installEntries(self.authoritativeEntries); self.updateCoverDemand()
                }
            case .failure:
                self.retireDrag(); self.installEntries(self.authoritativeEntries); self.updateCoverDemand()
            }
        }
        return true
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        if reorderToken == nil { retireDrag(); installEntries(authoritativeEntries); updateCoverDemand() }
    }

}

private final class PlaylistDirectoryDemandView: NSView {
    var onVisibilityChange: (() -> Void)?
    var onWindowChange: (() -> Void)?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindowChange?() }
    override func viewDidHide() { super.viewDidHide(); onVisibilityChange?() }
    override func viewDidUnhide() { super.viewDidUnhide(); onVisibilityChange?() }
}

private final class PlaylistDirectoryCollectionView: NSCollectionView {
    var openSelected: (() -> Void)?
    var deleteSelected: (() -> Void)?
    var makeContextMenu: ((Int?) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty, [UInt16(51), 117].contains(event.keyCode) {
            deleteSelected?()
        } else if event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           [UInt16(36), 76, 49].contains(event.keyCode) {
            openSelected?()
        } else { super.keyDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return makeContextMenu?(indexPathForItem(at: point)?.item)
    }
    override func rightMouseDown(with event: NSEvent) {
        let scroll = enclosingScrollView as? WallpaperGridScrollView
        let card = indexPathForItem(at: convert(event.locationInWindow, from: nil)).flatMap { item(at: $0)?.view }
        let anchor = card.map { $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? event.locationInWindow
        scroll?.beginContextMenu(at: anchor)
        defer { scroll?.endContextMenu() }
        super.rightMouseDown(with: event)
    }
}

private final class PlaylistDirectoryItem: NSCollectionViewItem, WallpaperGridHoverItem {
    private let hoverTracking = WallpaperGridHoverTracking()
    var onActivate: (() -> Bool)?
    private let card = PlaylistDirectoryCardView()
    private let cover = NSView()
    private let selectionOutline = NSBox()
    private let artwork = PlaylistDirectoryArtworkView()
    private let name = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let caption = NSStackView()

    override var isSelected: Bool { didSet { updateSelectionAppearance() } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { updateSelectionAppearance() } }

    override func prepareForReuse() {
        super.prepareForReuse()
        cover.applyGridHoverScale(false, animated: false)
        selectionOutline.applyGridHoverScale(false, animated: false)
        isSelected = false
        highlightState = .none
        onActivate = nil
        updateSelectionAppearance()
    }

    override func loadView() {
        view = card
        card.clipsToBounds = false
        cover.wantsLayer = true
        card.setAccessibilityRole(.button)
        card.setAccessibilityElement(true)
        card.onPress = { [weak self] in self?.onActivate?() ?? false }
        let click = NSClickGestureRecognizer(target: self, action: #selector(activate(_:)))
        click.numberOfClicksRequired = 1
        // Preserve NSCollectionView's own selection and drag tracking.
        click.delaysPrimaryMouseButtonEvents = false
        card.addGestureRecognizer(click)
        cover.translatesAutoresizingMaskIntoConstraints = false
        cover.setAccessibilityElement(false)
        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 12
        artwork.layer?.masksToBounds = true
        artwork.imageScaling = .scaleAxesIndependently
        artwork.imageAlignment = .alignCenter
        artwork.setAccessibilityElement(false)
        cover.addSubview(artwork)
        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            artwork.topAnchor.constraint(equalTo: cover.topAnchor),
            artwork.bottomAnchor.constraint(equalTo: cover.bottomAnchor)
        ])
        name.translatesAutoresizingMaskIntoConstraints = false
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1
        name.setAccessibilityElement(false)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        count.translatesAutoresizingMaskIntoConstraints = false
        count.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        count.setAccessibilityElement(false)
        caption.orientation = .horizontal
        caption.spacing = 6
        caption.alignment = .firstBaseline
        caption.distribution = .fill
        caption.detachesHiddenViews = true
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.addArrangedSubview(name)
        caption.addArrangedSubview(count)
        selectionOutline.wantsLayer = true
        selectionOutline.boxType = .custom
        selectionOutline.titlePosition = .noTitle
        selectionOutline.contentView = nil
        selectionOutline.fillColor = .clear
        selectionOutline.borderColor = .controlAccentColor
        selectionOutline.borderWidth = 1.5
        selectionOutline.cornerRadius = 12
        selectionOutline.translatesAutoresizingMaskIntoConstraints = false
        selectionOutline.setAccessibilityElement(false)
        for child in [cover, selectionOutline, caption] { card.addSubview(child) }
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cover.topAnchor.constraint(equalTo: card.topAnchor),
            cover.heightAnchor.constraint(equalTo: cover.widthAnchor),
            selectionOutline.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            selectionOutline.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            selectionOutline.topAnchor.constraint(equalTo: cover.topAnchor),
            selectionOutline.bottomAnchor.constraint(equalTo: cover.bottomAnchor),
            caption.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            caption.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 8)
        ])
        updateSelectionAppearance()
    }

    func configure(entry: WallpaperPlaylistDirectoryEntry?, cover: WallpaperPlaylistArtwork?, canCreate: Bool = true) {
        loadViewIfNeeded()
        let isCreate = entry == nil
        name.stringValue = entry?.name ?? "新建列表"
        name.textColor = isCreate && !canCreate ? .disabledControlTextColor : .labelColor
        count.stringValue = entry.map { "\($0.count)" } ?? ""
        count.isHidden = isCreate
        card.setAccessibilityLabel(entry.map { "打开播放列表，\($0.name)，\($0.count) 张壁纸" } ?? "新建列表")
        card.setAccessibilityEnabled(!isCreate || canCreate)
        card.toolTip = entry?.name ?? (canCreate ? "新建播放列表" : "资料库当前只读，暂时不能新建列表")
        card.setAccessibilityHelp(card.toolTip)
        if let image = cover?.image {
            artwork.image = image
            artwork.contentTintColor = nil
            artwork.imageScaling = .scaleAxesIndependently
        } else {
            artwork.image = NSImage(systemSymbolName: isCreate ? "plus" : WallpaperLibrarySymbols.playlist, accessibilityDescription: nil)
            artwork.contentTintColor = isCreate && !canCreate ? .disabledControlTextColor : .controlAccentColor
            artwork.imageScaling = .scaleNone
            artwork.symbolConfiguration = .init(pointSize: 44, weight: .regular)
        }
        updatePlaylistDirectoryCoverColors(artwork)
        updateSelectionAppearance()
    }

    private func updateSelectionAppearance() {
        guard isViewLoaded else { return }
        let highlighted = highlightState == .forSelection || isSelected && highlightState != .forDeselection
        selectionOutline.isHidden = !highlighted
        card.setAccessibilitySelected(isSelected)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        refreshGridHover(isScrolling: view.isGridHoverSuppressed)
    }

    func refreshGridHover(isScrolling: Bool) {
        hoverTracking.update(in: card, owner: self, isScrolling: isScrolling)
        let hovered = !isScrolling && card.isGridPointerInside
        cover.applyGridHoverScale(hovered, animated: !isScrolling)
        selectionOutline.applyGridHoverScale(hovered, animated: !isScrolling)
    }
    override func mouseEntered(with event: NSEvent) { refreshGridHover(isScrolling: view.isGridHoverSuppressed) }
    override func mouseExited(with event: NSEvent) {
        cover.applyGridHoverScale(false, animated: true)
        selectionOutline.applyGridHoverScale(false, animated: true)
    }
    override func mouseMoved(with event: NSEvent) { refreshGridHover(isScrolling: view.isGridHoverSuppressed) }

    @objc private func activate(_ sender: NSClickGestureRecognizer) {
        guard sender.state == .ended else { return }
        // The second click of one double click must not repeat navigation.
        if let event = NSApp.currentEvent, event.type == .leftMouseUp, event.clickCount > 1 { return }
        _ = onActivate?()
    }
}

private final class PlaylistDirectoryCardView: NSView {
    var onPress: (() -> Bool)?
    override func mouseDown(with event: NSEvent) {
        nextResponder?.mouseDown(with: event)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Artwork/labels are decorative. Their NSControl tracking must not
        // consume the collection view's native selection/drag mouse events.
        super.hitTest(point) == nil ? nil : self
    }
    override func accessibilityPerformPress() -> Bool {
        onPress?() ?? false
    }
}

/// Resolve each existing layer after its own effective appearance changes;
/// a parent's callback can still observe the children's previous appearance.
private func updatePlaylistDirectoryCoverColors(_ view: NSView) {
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

private final class PlaylistDirectoryArtworkView: NSImageView {
    // A cover's square geometry belongs to the grid. Symbol baseline/alignment
    // insets must not expand its actual frame beyond that square.
    override var alignmentRectInsets: NSEdgeInsets { .init() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePlaylistDirectoryCoverColors(self)
    }
}

/// Preserve AppKit's real insertion target while suppressing its marker view.
private final class PlaylistDirectoryFlowLayout: NSCollectionViewFlowLayout {
    override func layoutAttributesForInterItemGap(before indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let attributes = super.layoutAttributesForInterItemGap(before: indexPath)?.copy() as? NSCollectionViewLayoutAttributes else { return nil }
        attributes.alpha = 0
        return attributes
    }
}
