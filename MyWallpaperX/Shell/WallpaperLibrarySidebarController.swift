import AppKit

/// Native navigation presentation only. Page and relationship snapshots arrive
/// from Shell; clicks and drop receipts request work from those existing owners.
final class WallpaperLibrarySidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onNavigate: ((WallpaperLibraryPage) -> Void)?
    var onPlaylistAction: ((PlaylistOrganizationAction) -> Void)?
    var onReorder: (([UUID], @escaping (Result<Int64, Error>) -> Void) -> Void)?
    var onCoverDemand: ((Set<UUID>) -> Void)? { didSet { updateCoverDemand(force: true) } }
    var onAddReferences: (([WallpaperReference], UUID) -> Bool)?
    var makeRecentMenu: (() -> NSMenu?)?

    private enum Group: String, CaseIterable, Codable { case library, browse, playlists }
    private struct SidebarState: Codable { let version: Int; let expanded: [String: Bool] }
    static let stateKey = "wallpaperLibrarySidebar.v1"
    private let defaults: UserDefaults
    private final class Node: NSObject {
        enum Kind { case group(Group), page(WallpaperLibraryPage) }
        let kind: Kind
        init(_ kind: Kind) { self.kind = kind }
    }
    private let groups = Group.allCases.map { Node(.group($0)) }
    private var pageNodes: [WallpaperLibraryPage: Node] = [:]
    private var playlists: [WallpaperPlaylist] = []
    private var authoritativePlaylists: [WallpaperPlaylist] = []
    private var resetEpoch: UUID?
    private var reorderToken: UUID?
    private var pendingOrder: [UUID]?
    private var acceptedRevision: Int64?
    private var relationshipsRevision: Int64?
    private var activeDragID: UUID?
    private var dragEpoch: UUID?
    private var dragOrder: [UUID] = []
    private var dragDemand = Set<UUID>()
    private var demandUpdateDepth = 0
    private var names: [UUID: String] = [:]
    private var counts: [WallpaperLibraryPage: Int] = [:]
    private var covers: [UUID: NSImage] = [:]
    private var presentedPage = WallpaperLibraryPage.videos
    private var canEdit = false
    private var isApplyingSelection = false
    private let scrollView = NSScrollView()
    private let background = PlaylistSidebarDemandView()
    private let tintSurface = AppKitListTintSurface()
    var backgroundTintHost: AppKitListTintSurface { loadViewIfNeeded(); return tintSurface }
    private let outline = SidebarOutlineView()
    private var artworkObservation: WallpaperArtworkDemandObservation?
    private var lastCoverDemand = Set<UUID>()
    private static let orderType = NSPasteboard.PasteboardType("com.songziqiang.MyWallpaperX.playlist-sidebar-order")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = background
        background.onVisibilityChange = { [weak self] in self?.updateCoverDemand() }
        background.onWindowChange = { [weak self] in self?.artworkObservation?.windowDidChange() }
        tintSurface.ignoresHitTesting = true
        tintSurface.setAccessibilityElement(false)
        tintSurface.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.floatsGroupRows = false
        outline.focusRingType = .none
        outline.indentationPerLevel = 10
        outline.intercellSpacing = NSSize(width: 0, height: 4)
        outline.backgroundColor = .clear
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("WallpaperLibrarySidebar"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = self
        outline.delegate = self
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
        outline.registerForDraggedTypes([Self.orderType, WallpaperLibraryGridController.referencesType])
        outline.draggingDestinationFeedbackStyle = .regular
        outline.rowContextMenuProvider = { [weak self] row in self?.menu(forRow: row) }
        outline.blankAreaMenuProvider = { [weak self] in self?.creationMenu() }
        outline.sameSelectionClickHandler = { [weak self] row in self?.navigate(row: row) }
        for page in [WallpaperLibraryPage.videos, .images] + Group.allCases.flatMap({ pages(in: $0) }) {
            pageNodes[page] = Node(.page(page))
        }
        scrollView.documentView = outline
        view.addSubview(tintSurface)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            tintSurface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tintSurface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tintSurface.topAnchor.constraint(equalTo: view.topAnchor),
            tintSurface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        outline.reloadData()
        let saved = defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(SidebarState.self, from: $0) }
        isApplyingSelection = true
        for group in groups {
            guard case .group(let id) = group.kind else { continue }
            if saved?.version != 1 || saved?.expanded[id.rawValue] != false { outline.expandItem(group) }
        }
        isApplyingSelection = false
        applySelection()
        artworkObservation = WallpaperArtworkDemandObservation(view: view, clipView: scrollView.contentView) { [weak self] in
            self?.updateCoverDemand()
        }
    }

    override func viewDidLayout() { super.viewDidLayout(); updateCoverDemand() }

    func setUsesThumbnailTint(_ enabled: Bool) {
        background.usesOpaqueBackground = enabled
    }

    func resetSidebarState() {
        defaults.removeObject(forKey: Self.stateKey)
        guard isViewLoaded else { return }
        isApplyingSelection = true
        for group in groups { outline.expandItem(group) }
        isApplyingSelection = false
        applySelection()
        updateCoverDemand()
    }

    private func saveSidebarState() {
        guard !isApplyingSelection else { return }
        var expanded: [String: Bool] = [:]
        for group in groups {
            if case .group(let id) = group.kind { expanded[id.rawValue] = outline.isItemExpanded(group) }
        }
        if let data = try? JSONEncoder().encode(SidebarState(version: 1, expanded: expanded)) { defaults.set(data, forKey: Self.stateKey) }
    }

    func update(page: WallpaperLibraryPage, playlists: [WallpaperPlaylist], counts: [WallpaperLibraryPage: Int],
                covers: [UUID: NSImage], canEdit: Bool, resetEpoch: UUID? = nil, relationshipsRevision: Int64? = nil) {
        loadViewIfNeeded()
        let expanded = groups.map { outline.isItemExpanded($0) }
        let ordered = playlists.enumerated().sorted {
            $0.element.sidebarRank == $1.element.sidebarRank ? $0.offset < $1.offset : $0.element.sidebarRank < $1.element.sidebarRank
        }.map(\.element)
        authoritativePlaylists = ordered
        let liveIDs = Set(ordered.map(\.id))
        if self.resetEpoch != resetEpoch || !canEdit || Set(self.playlists.map(\.id)) != liveIDs
            || (activeDragID != nil && reorderToken == nil && dragOrder != ordered.map(\.id)) {
            retireReorder()
        }
        self.resetEpoch = resetEpoch
        self.relationshipsRevision = relationshipsRevision
        if hasCommittedAuthority(order: ordered.map(\.id)) {
            retireReorder()
        }
        let byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        let displayed = pendingOrder.map { $0.compactMap { byID[$0] } } ?? ordered
        let oldIDs = self.playlists.map(\.id), newIDs = displayed.map(\.id)
        let structureChanged = Set(oldIDs) != Set(newIDs)
        self.playlists = displayed
        names = Dictionary(self.playlists.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        self.counts = counts
        self.covers = covers
        self.canEdit = canEdit
        presentedPage = page
        let live = Set(self.playlists.map { WallpaperLibraryPage.playlist($0.id) })
        pageNodes = pageNodes.filter { key, _ in
            if case .playlist = key { return live.contains(key) }
            return true
        }
        for page in live where pageNodes[page] == nil { pageNodes[page] = Node(.page(page)) }
        if structureChanged {
            isApplyingSelection = true
            outline.reloadData()
            for (group, isExpanded) in zip(groups, expanded) {
                if isExpanded { outline.expandItem(group) }
                else { outline.collapseItem(group) }
            }
            isApplyingSelection = false
        } else {
            if oldIDs != newIDs { moveRows(from: oldIDs, to: newIDs) }
            for row in 0..<outline.numberOfRows {
                guard let node = outline.item(atRow: row) as? Node, case .page(let page) = node.kind,
                      let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarRowCellView else { continue }
                configure(cell, page: page)
            }
        }
        applySelection()
        updateCoverDemand()
    }

    private func updateCoverDemand(force: Bool = false) {
        if !isViewLoaded || artworkObservation?.isVisible != true {
            let old = playlists.map(\.id)
            let hadDrag = activeDragID != nil || reorderToken != nil
            retireReorder()
            if hadDrag { playlists = authoritativePlaylists; moveRows(from: old, to: playlists.map(\.id)) }
            if force || !lastCoverDemand.isEmpty { lastCoverDemand = []; onCoverDemand?([]) }
            return
        }
        guard demandUpdateDepth == 0 else { return }
        var demand = Set<UUID>()
        if isViewLoaded, artworkObservation?.isVisible == true {
            let rows = outline.rows(in: outline.visibleRect)
            if rows.location != NSNotFound {
                for row in rows.location..<min(outline.numberOfRows, NSMaxRange(rows)) {
                    if let node = outline.item(atRow: row) as? Node, case .page(.playlist(let id)) = node.kind { demand.insert(id) }
                }
            }
        }
        demand.formUnion(dragDemand)
        guard force || demand != lastCoverDemand else { return }
        lastCoverDemand = demand
        onCoverDemand?(demand)
    }

    private func pages(in group: Group) -> [WallpaperLibraryPage] {
        switch group {
        case .library: return [.downloads, .recent]
        case .browse: return [.workshop, .wallhaven, .pixiv, .pixabay]
        case .playlists: return [.playlists, .favorites] + playlists.map { .playlist($0.id) }
        }
    }

    private func children(_ item: Any?) -> [Node] {
        guard let item else { return [WallpaperLibraryPage.videos, .images].compactMap { pageNodes[$0] } + groups }
        guard let node = item as? Node, case .group(let group) = node.kind else { return [] }
        return pages(in: group).compactMap { pageNodes[$0] }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(item).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { children(item)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        if case .group = node.kind { return true }
        return false
    }
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { self.outlineView(outlineView, isItemExpandable: item) }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { !self.outlineView(outlineView, isItemExpandable: item) }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        self.outlineView(outlineView, isItemExpandable: item) ? 28 : 30
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        guard !self.outlineView(outlineView, isGroupItem: item) else { return nil }
        let id = NSUserInterfaceItemIdentifier("WallpaperLibrarySidebarRow")
        let row = outlineView.makeView(withIdentifier: id, owner: self) as? SidebarRowView ?? SidebarRowView()
        row.identifier = id
        return row
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        if case .group(let group) = node.kind {
            let id = NSUserInterfaceItemIdentifier("WallpaperLibrarySidebarGroup")
            let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
                let cell = NSTableCellView()
                let label = NSTextField(labelWithString: "")
                label.font = .systemFont(ofSize: 12, weight: .semibold)
                label.textColor = .secondaryLabelColor
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(label)
                cell.textField = label
                NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8)])
                return cell
            }()
            cell.identifier = id
            cell.textField?.stringValue = group == .library ? "资料库" : group == .browse ? "浏览" : "播放列表"
            return cell
        }
        guard case .page(let page) = node.kind else { return nil }
        let id = NSUserInterfaceItemIdentifier("WallpaperLibrarySidebarCell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? SidebarRowCellView ?? SidebarRowCellView()
        cell.identifier = id
        configure(cell, page: page)
        return cell
    }

    private func configure(_ cell: SidebarRowCellView, page: WallpaperLibraryPage) {
        let title = title(for: page)
        let cover: NSImage?
        if case .playlist(let id) = page { cover = covers[id] } else { cover = nil }
        cell.configure(title: title, symbolName: symbol(for: page), count: nil, coverImage: cover, symbolTint: .controlAccentColor)
        let count = counts[page].flatMap { $0 >= 0 ? $0 : nil }
        let unit = page == .playlists ? "个播放列表" : "张壁纸"
        cell.setAccessibilityLabel(count.map { title + "，\($0) \(unit)" } ?? title)
    }

    private func title(for page: WallpaperLibraryPage) -> String {
        if case .playlist(let id) = page { return page.title(playlistName: names[id]) }
        return page.title()
    }

    private func symbol(for page: WallpaperLibraryPage) -> String {
        switch page {
        case .videos: return "film"
        case .images: return "photo.on.rectangle"
        case .downloads: return "arrow.down.circle"
        case .recent: return "clock.arrow.circlepath"
        case .workshop: return "shippingbox"
        case .pixabay: return "globe"
        case .wallhaven: return "photo"
        case .pixiv: return "paintpalette"
        case .playlists: return "square.grid.3x3"
        case .favorites: return "heart"
        case .playlist: return WallpaperLibrarySymbols.playlist
        }
    }

    private func applySelection() {
        let wasApplyingSelection = isApplyingSelection
        isApplyingSelection = true
        defer { isApplyingSelection = wasApplyingSelection }
        if let node = pageNodes[presentedPage], outline.row(forItem: node) >= 0 {
            outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: node)), byExtendingSelection: false)
        } else { outline.deselectAll(nil) }
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        navigate(row: outline.selectedRow)
    }
    func outlineViewItemDidExpand(_ notification: Notification) { saveSidebarState(); applySelection(); updateCoverDemand() }
    func outlineViewItemDidCollapse(_ notification: Notification) { saveSidebarState(); updateCoverDemand() }
    private func navigate(row: Int) {
        guard row >= 0, let node = outline.item(atRow: row) as? Node, case .page(let page) = node.kind else { return }
        onNavigate?(page)
    }

    private func creationMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        add("新建列表…", action: .create, to: menu, enabled: canEdit && onPlaylistAction != nil)
        return menu
    }
    private func menu(forRow row: Int) -> NSMenu? {
        guard let node = outline.item(atRow: row) as? Node else { return nil }
        if case .page(.recent) = node.kind { return makeRecentMenu?() }
        if case .page(.playlist(let id)) = node.kind {
            let menu = NSMenu()
            menu.autoenablesItems = false
            add("打开播放列表", action: .open(id), to: menu, enabled: onNavigate != nil)
            add("编辑列表…", action: .rename(id), to: menu, enabled: canEdit && onPlaylistAction != nil)
            add("复制列表", action: .duplicate(id), to: menu, enabled: canEdit && onPlaylistAction != nil)
            menu.addItem(.separator())
            add("删除列表…", action: .delete(id), to: menu, enabled: canEdit && onPlaylistAction != nil)
            return menu
        }
        if case .group(.playlists) = node.kind { return creationMenu() }
        if case .page(.playlists) = node.kind { return creationMenu() }
        return nil
    }
    private func add(_ title: String, action: PlaylistOrganizationAction, to menu: NSMenu, enabled: Bool) {
        let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        item.isEnabled = enabled
        menu.addItem(item)
    }
    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? PlaylistOrganizationAction else { return }
        if case .open(let id) = action { onNavigate?(.playlist(id)); return }
        guard canEdit else { return }
        onPlaylistAction?(action)
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard canEdit, reorderToken == nil, onReorder != nil, let node = item as? Node, case .page(.playlist(let id)) = node.kind else { return nil }
        activeDragID = id; dragEpoch = resetEpoch; dragOrder = authoritativePlaylists.map(\.id)
        dragDemand = lastCoverDemand.union([id])
        let value = NSPasteboardItem()
        value.setString(id.uuidString, forType: Self.orderType)
        return value
    }
    private func dropIndex(item: Any?, index: Int) -> Int? {
        guard let node = item as? Node else { return nil }
        if case .group(.playlists) = node.kind, index >= 2, index <= playlists.count + 2 { return index }
        if case .page(.playlist(let id)) = node.kind, index == NSOutlineViewDropOnItemIndex,
           let position = playlists.firstIndex(where: { $0.id == id }) { return position + 2 }
        return nil
    }
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        if let (_, target) = addedReferences(info, item: item, index: index) {
            outline.draggingDestinationFeedbackStyle = .regular
            outline.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }
        guard canEdit, reorderToken == nil, dragEpoch == resetEpoch, onReorder != nil, info.draggingSource as? NSOutlineView === outline,
              let raw = info.draggingPasteboard.string(forType: Self.orderType), let id = UUID(uuidString: raw),
              activeDragID == id, playlists.contains(where: { $0.id == id }), let target = dropIndex(item: item, index: index) else { return [] }
        outline.draggingDestinationFeedbackStyle = .gap
        outline.setDropItem(groups[2], dropChildIndex: target)
        return .move
    }
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        if let (references, target) = addedReferences(info, item: item, index: index),
           case .page(.playlist(let id)) = target.kind { return onAddReferences?(references, id) == true }
        guard canEdit, reorderToken == nil, dragEpoch == resetEpoch, let onReorder, info.draggingSource as? NSOutlineView === outline,
              let raw = info.draggingPasteboard.string(forType: Self.orderType), let id = UUID(uuidString: raw),
              activeDragID == id, let source = playlists.firstIndex(where: { $0.id == id }), let target = dropIndex(item: item, index: index) else { return false }
        var order = playlists.map(\.id)
        order.remove(at: source)
        let destination = target - 2 > source ? target - 3 : target - 2
        order.insert(id, at: min(order.count, max(0, destination)))
        guard order != playlists.map(\.id) else { retireReorder(); updateCoverDemand(); return true }
        let token = UUID(); reorderToken = token; pendingOrder = order; acceptedRevision = nil
        let old = playlists.map(\.id), byID = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0) })
        playlists = order.compactMap { byID[$0] }
        moveRows(from: old, to: order)
        onReorder(order) { [weak self] result in
            guard let self, self.reorderToken == token else { return }
            switch result {
            case .success(let revision):
                self.acceptedRevision = revision
                if self.hasCommittedAuthority(order: self.authoritativePlaylists.map(\.id)) { self.finishReorder() }
            case .failure: self.finishReorder()
            }
        }
        return true
    }

    private func moveRows(from original: [UUID], to order: [UUID]) {
        var current = original
        let applying = isApplyingSelection; isApplyingSelection = true
        demandUpdateDepth += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            outline.beginUpdates()
            for (destination, id) in order.enumerated() {
                guard let source = current.firstIndex(of: id), source != destination else { continue }
                current.insert(current.remove(at: source), at: destination)
                outline.moveItem(at: source + 2, inParent: groups[2], to: destination + 2, inParent: groups[2])
            }
            outline.endUpdates()
        }
        demandUpdateDepth -= 1; isApplyingSelection = applying
        applySelection(); updateCoverDemand()
    }

    private func hasCommittedAuthority(order: [UUID]) -> Bool {
        guard let acceptedRevision else { return false }
        // An unrelated earlier metadata echo cannot settle this commit. A newer
        // real authority may already contain another reorder or an Undo.
        if let relationshipsRevision { return relationshipsRevision >= acceptedRevision }
        return pendingOrder == order
    }

    private func retireReorder() {
        reorderToken = nil; pendingOrder = nil; acceptedRevision = nil; activeDragID = nil; dragDemand = []
        outline.draggingDestinationFeedbackStyle = .regular
        if isViewLoaded { outline.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex) }
    }

    private func finishReorder() {
        let old = playlists.map(\.id)
        retireReorder()
        playlists = authoritativePlaylists
        moveRows(from: old, to: playlists.map(\.id))
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        activeDragID = nil
        outline.draggingDestinationFeedbackStyle = .regular
        outline.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
        if reorderToken == nil { dragDemand = []; updateCoverDemand() }
    }

    private func addedReferences(_ info: NSDraggingInfo, item: Any?, index: Int) -> ([WallpaperReference], Node)? {
        guard canEdit, onAddReferences != nil, index == NSOutlineViewDropOnItemIndex,
              let node = item as? Node, case .page(.playlist(let id)) = node.kind,
              playlists.contains(where: { $0.id == id }), pageNodes[.playlist(id)] === node,
              let source = info.draggingSource as? NSCollectionView,
              let grid = source.delegate as? WallpaperLibraryGridController, grid.collection === source,
              let references = grid.referencesForPlaylistDrop(from: info), !references.isEmpty else { return nil }
        return (references, node)
    }
}

private final class PlaylistSidebarDemandView: NSView {
    var onVisibilityChange: (() -> Void)?
    var onWindowChange: (() -> Void)?
    var usesOpaqueBackground = true {
        didSet { if oldValue != usesOpaqueBackground { needsDisplay = true } }
    }
    override var isOpaque: Bool { usesOpaqueBackground }
    override func draw(_ dirtyRect: NSRect) {
        guard usesOpaqueBackground else { return }
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindowChange?() }
    override func viewDidHide() { super.viewDidHide(); onVisibilityChange?() }
    override func viewDidUnhide() { super.viewDidUnhide(); onVisibilityChange?() }
}
