import AppKit
import Combine

/// A bounded main-window modal over the same local projections and original cards.
/// It holds a fixed target/epoch and a selection only, never another media index.
@MainActor final class WallpaperPlaylistPickerController: NSObject, NSSearchFieldDelegate, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let workspace: WallpaperLibraryWorkspace
    private let manager: WallpaperManager
    private let target: UUID
    private let epoch: UUID
    private let hostWindow: () -> NSWindow?
    private let panel = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
    private let search = NSSearchField()
    private let source = NSSegmentedControl(labels: ["全部", "我的视频", "我的图片", "我的下载"], trackingMode: .selectOne, target: nil, action: nil)
    private let zoom = WallpaperLibraryZoomControl()
    private let count = NSTextField(labelWithString: "未选择壁纸")
    private let add = NSButton(title: "添加", target: nil, action: nil)
    private var preferredColumns = 5
    private var selection = WallpaperLibrarySelectionState(isSelecting: true)
    private var items: [WallpaperContentItem] = []
    private var cardState: WallpaperLibraryCardStateProjection?
    private var existingReferences = Set<WallpaperReference>()
    private var lastRefresh: RefreshSignature?
    private struct RefreshSignature: Equatable {
        let catalogRevision: UInt64
        let relationshipsRevision: Int64
        let ticket: PlaybackSwitchTicket?
        let segment: Int
        let search: String
        let preferredColumns: Int
    }
    private var subscriptions = Set<AnyCancellable>()
    private var isApplying = false
    private var isClosed = false
    private let gridDemand = UUID()
    private var adapter: WallpaperLibraryCellAdapter!
    private var grid: WallpaperLibraryGridController!

    init(workspace: WallpaperLibraryWorkspace, manager: WallpaperManager, images: SILService,
         steam: SteamWorkshopService, online: OnlineLibraryService, target: UUID, hostWindow: @escaping () -> NSWindow?) {
        self.workspace = workspace; self.manager = manager; self.target = target; self.hostWindow = hostWindow
        epoch = workspace.relationships.resetEpoch
        super.init()
        adapter = WallpaperLibraryCellAdapter(manager: manager, images: images, steam: steam, online: online,
            isFavorite: { [weak self] in self?.cardState?.isFavorite($0) ?? false }, isPlaying: { [weak self] in self?.cardState?.isPlaying($0) ?? false },
            makePrimaryAction: { _ in nil })
        grid = WallpaperLibraryGridController { [weak self] collection, path, content, state in
            guard let self else { return NSCollectionViewItem() }
            let cell = self.adapter.makeCell(collection: collection, indexPath: path, content: content, state: state)
            self.configureExistingMarker(cell, reference: content.reference, visible: false)
            return cell
        }
        grid.updateCell = { [weak self] cell, content, state in
            guard let self else { return }
            self.adapter.updateCell(cell, content: content, state: state)
            self.configureExistingMarker(cell, reference: content.reference)
        }
        grid.needsCellReplacement = { [weak self] in self?.adapter.needsCellReplacement($0, content: $1) ?? false }
        grid.setCellVisible = { [weak self] in self?.setCellVisible($0, $1) }
        grid.onClipWidthChange = { [weak self] _ in self?.refreshZoom() }
        grid.onViewport = { [weak self] visible, prefetch in
            guard let self else { return }
            self.adapter.updateViewport(visible: visible, prefetch: prefetch)
            self.workspace.catalog.setVisibleReferences(Set(visible.map(\.providerReference)), sourceToken: self.gridDemand)
        }
        grid.onSelection = { [weak self] refs, focus in
            guard let self, !self.isApplying, self.ownsInput else { return nil }
            self.selection.references = refs; self.selection.focusedReference = focus; self.selection.sessionID = UUID()
            self.refreshCount()
            return self.selection.sessionID
        }
        grid.onEscape = { [weak self] in guard let self, self.ownsInput else { return }; self.close() }
        workspace.presentation.$state.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        workspace.catalog.visibleLocalFactsRefreshed.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.adapter.repairVisiblePreviews()
        }.store(in: &subscriptions)
        workspace.playbackChanges.receive(on: DispatchQueue.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        configure()
    }

    private func configure() {
        panel.title = "添加壁纸"
        panel.minSize = NSSize(width: 680, height: 480)
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        source.selectedSegment = 0
        source.segmentStyle = .capsule
        source.borderShape = .capsule
        zoom.borderShape = .capsule
        source.target = self; source.action = #selector(filterChanged(_:))
        search.delegate = self
        search.placeholderString = "查找本地或已下载壁纸"
        search.sendsSearchStringImmediately = true
        search.widthAnchor.constraint(equalToConstant: 220).isActive = true
        zoom.makeAction = { [weak self] in self?.makeZoomAction($0) }
        let top = NSStackView(views: [source, zoom, search])
        top.spacing = 16
        top.distribution = .fill
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel(_:)))
        WallpaperLibraryControlStyle.sheetCapsule(cancel)
        cancel.keyEquivalent = "\u{1b}"
        add.target = self; add.action = #selector(accept(_:)); WallpaperLibraryControlStyle.sheetCapsule(add)
        add.keyEquivalent = "\r"
        let footer = NSStackView(views: [count, NSView(), cancel, add])
        footer.spacing = 12
        let root = WallpaperLibrarySheetSurface()
        panel.contentView = root
        let gridView = grid.view
        for child in [top, gridView, footer] { child.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(child) }
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            gridView.leadingAnchor.constraint(equalTo: root.leadingAnchor), gridView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            gridView.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 4), gridView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
    }

    func show() {
        refresh()
        guard !isClosed else { return }
        let host = hostWindow()
        guard WallpaperLibrarySheetPresentation.present(panel, in: host) else {
            close()
            guard host == nil || WallpaperLibrarySheetPresentation.permitsInput(in: host) else { return }
            presentAppAlert(makeAppAlert(title: "无法打开壁纸选择", message: "请先打开主窗口，再重试。"))
            return
        }
        refreshZoom()
    }

    /// The main menu delegates only to the controller of its actual key panel.
    /// A disabled Picker command must never fall through to the host page.
    private var ownsInput: Bool {
        !isClosed && NSApp.keyWindow === panel && WallpaperLibrarySheetPresentation.permitsInput(in: panel) && workspace.relationships.resetEpoch == epoch
            && workspace.presentation.canEditCollections && workspace.relationships.playlists.contains { $0.id == target }
    }
    var canFocusSearch: Bool { ownsInput && search.isEnabled }
    func focusSearch() { if canFocusSearch { panel.makeFirstResponder(search) } }
    func canZoom(_ delta: Int) -> Bool {
        guard ownsInput, delta == -1 || delta == 1, zoom.isEnabled else { return false }
        return zoom.isEnabled(forSegment: delta == -1 ? 0 : 1)
    }
    func performZoom(_ delta: Int) { makeZoomAction(delta)?() }
    private func makeZoomAction(_ delta: Int) -> (() -> Void)? {
        guard canZoom(delta) else { return nil }
        return { [weak self] in
            guard let self, self.canZoom(delta) else { return }
            self.preferredColumns = WallpaperLibraryGridMetrics.zoomedColumns(
                preferredColumns: self.preferredColumns, delta: delta, clipWidth: self.grid.scrollView.contentView.bounds.width)
            self.refresh()
        }
    }
    private func refreshZoom() {
        zoom.update(preferredColumns: preferredColumns, clipWidth: grid.scrollView.contentView.bounds.width, canDispatch: !isClosed)
    }

    private func refresh() {
        guard !isClosed else { return }
        guard workspace.relationships.resetEpoch == epoch, workspace.presentation.canEditCollections,
              workspace.relationships.playlists.contains(where: { $0.id == target }) else { close(); return }
        let relationships = workspace.relationships, catalog = workspace.catalog.catalog
        let signature = RefreshSignature(catalogRevision: catalog.revision, relationshipsRevision: relationships.revision,
            ticket: manager.playbackSwitch.committed?.ticket, segment: source.selectedSegment, search: search.stringValue,
            preferredColumns: preferredColumns)
        guard signature != lastRefresh else { return }
        do {
            var query = WallpaperLibraryQueryState(); query.search = search.stringValue
            let pages: [WallpaperLibraryPage] = source.selectedSegment == 1 ? [.videos] : source.selectedSegment == 2 ? [.images]
                : source.selectedSegment == 3 ? [.downloads] : [.videos, .images, .downloads]
            var seen = Set<WallpaperReference>()
            let projected = try pages.flatMap { try WallpaperLibraryQuery.project(page: $0, state: query, catalog: catalog,
                relationships: relationships).items }.filter { $0.capabilities.contains(.organize) && seen.insert($0.reference).inserted }
            let committed = manager.libraryPlaybackSequence.committed
            let targetReferences = relationships.members.filter { $0.playlistID == target }.map(\.reference)
            let selectionReferences = Array(selection.references) + (selection.focusedReference.map { [$0] } ?? [])
            let state = try WallpaperLibraryCardStateProjection(items: projected, relationships: relationships,
                committedReference: committed?.reference, sequenceTicket: committed?.ticket, runtimeTicket: manager.playbackSwitch.committed?.ticket,
                additionalReferences: targetReferences + selectionReferences)
            cardState = state
            existingReferences = Set(targetReferences.map(state.canonical))
            items = projected
            lastRefresh = signature
            // Filtering doesn't redirect a target. Keep only the currently
            // displayed selection so the Add count never hides pending items.
            let visible = Set(items.map(\.reference)), previous = selection
            selection.references = Set(selection.references.map(state.canonical)).intersection(visible)
            selection.focusedReference = selection.focusedReference.map(state.canonical).flatMap { visible.contains($0) ? $0 : nil }
            if previous.references != selection.references || previous.focusedReference != selection.focusedReference { selection.sessionID = UUID() }
            grid.update(page: .playlist(target), items: items, selection: selection, preferredColumns: preferredColumns, permitsDragging: false, scrollAnchor: nil)
            refreshZoom()
            refreshCount()
        } catch { workspace.presentation.report(error); close() }
    }

    private func refreshCount() {
        let selected = items.filter { selection.references.contains($0.reference) }
        let already = selected.filter { existingReferences.contains($0.reference) }.count
        let added = selected.count - already
        count.stringValue = "已选 \(selected.count) 项 · 将新增 \(added) 项 · \(already) 项已在列表"
        add.title = "添加 \(added) 项"
        add.isEnabled = added > 0 && !isApplying
    }

    func controlTextDidChange(_ notification: Notification) { refresh() }
    @objc private func filterChanged(_ sender: Any?) { if ownsInput { refresh() } }
    @objc private func cancel(_ sender: Any?) { if ownsInput { close() } }

    @objc private func accept(_ sender: Any?) {
        guard ownsInput, !isApplying, workspace.relationships.resetEpoch == epoch, workspace.presentation.canEditCollections,
              let collections = workspace.collections else { return }
        let fixed = items.filter { selection.references.contains($0.reference) }.map(\.reference)
        guard !fixed.isEmpty else { return }
        isApplying = true; refreshCount()
        Task { @MainActor [self] in
            do {
                let relationships = workspace.relationships
                let memberReferences = Set(relationships.members.filter { $0.playlistID == target }.map(\.reference))
                let existing = Set(try WallpaperLibraryQuery.canonicalReferences(memberReferences, relationships: relationships).values)
                var seen = Set<WallpaperReference>()
                let current = try WallpaperLibraryQuery.resolve(fixed, catalog: workspace.catalog.catalog, relationships: relationships)
                    .filter { !existing.contains($0.reference) && seen.insert($0.reference).inserted }
                guard !current.isEmpty else {
                    if !isClosed { isApplying = false; lastRefresh = nil; refresh() }
                    return
                }
                guard current.allSatisfy({ $0.capabilities.contains(.organize) }) else { throw UserCollectionsError.unavailableForOrganization }
                try await collections.perform(.addMembers(target, current.map(\.organizationItem), Date()), undoName: "添加到列表", expectedEpoch: epoch)
                guard workspace.relationships.resetEpoch == epoch, !collections.isResetting else { close(); return }
                workspace.didEditMembers(of: .playlist(target))
                close()
            } catch {
                guard !isClosed else { return }
                if workspace.relationships.resetEpoch == epoch {
                    isApplying = false; refreshCount()
                    presentAppAlert(makeAppAlert(title: "添加壁纸未完成", message: error.localizedDescription), in: panel)
                } else { close() }
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { if ownsInput { close() }; return false }
    func windowWillClose(_ notification: Notification) { close() }
    func close() {
        guard !isClosed else { return }
        isClosed = true
        WallpaperLibrarySheetPresentation.dismiss(panel)
        grid.collection.visibleItems().forEach { setCellVisible($0, false) }
        adapter.updateViewport(visible: [], prefetch: [])
        workspace.catalog.setVisibleReferences([], sourceToken: gridDemand)
        subscriptions.removeAll()
        refreshZoom()
        onClose?()
    }

    private func configureExistingMarker(_ cell: NSCollectionViewItem, reference: WallpaperReference, visible: Bool? = nil) {
        let marker: PickerExistingMemberMarker
        if let current = cell.view.subviews.compactMap({ $0 as? PickerExistingMemberMarker }).first { marker = current }
        else {
            marker = PickerExistingMemberMarker()
            cell.view.addSubview(marker)
            NSLayoutConstraint.activate([
                marker.leadingAnchor.constraint(equalTo: cell.view.leadingAnchor, constant: 8),
                marker.topAnchor.constraint(equalTo: cell.view.topAnchor, constant: 8),
                marker.trailingAnchor.constraint(lessThanOrEqualTo: cell.view.trailingAnchor, constant: -8)
            ])
        }
        if let visible { marker.isInViewport = visible }
        marker.isHidden = !marker.isInViewport || !existingReferences.contains(reference)
    }

    private func setCellVisible(_ cell: NSCollectionViewItem, _ visible: Bool) {
        adapter.setVisible(cell, visible)
        if visible, let path = grid.collection.indexPath(for: cell), grid.items.indices.contains(path.item) {
            configureExistingMarker(cell, reference: grid.items[path.item].reference, visible: true)
        } else {
            cell.view.subviews.compactMap { $0 as? PickerExistingMemberMarker }.forEach { $0.isInViewport = false; $0.isHidden = true }
        }
    }
}

/// A Picker-only decoration; the original card remains the input and AX target.
@MainActor private final class PickerExistingMemberMarker: NSView {
    var isInViewport = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.cornerRadius = 5
        setAccessibilityElement(false)
        let text = NSTextField(labelWithString: "已在列表")
        text.font = .systemFont(ofSize: 10, weight: .medium)
        text.setAccessibilityElement(false)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 3), text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
        updateBackground()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateBackground() }
    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor }
    }
}
