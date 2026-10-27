import AppKit
import Combine

@MainActor final class OnlineImageBrowserController: NSViewController {
    let session: OnlineImageBrowserSession
    private let library: OnlineImageLibrary
    private let status = NSTextField(labelWithString: "")
    private let more = NSButton(title: "加载更多", target: nil, action: nil)
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var subscriptions = Set<AnyCancellable>()
    private var selection = WallpaperLibrarySelectionState()
    private var anchor: (WallpaperReference?, Double?, Bool?) = (nil, nil, true)
    private var returnAnchor: ((WallpaperReference?, Double?, Bool?), Int)?
    private var resetScroll = false
    private var shown = false
    private var permitsDisplay = true
    private var prefetched: [WallpaperReference: Task<Void, Never>] = [:]
    private var autoLoadedCount: Int?
    private var projectedItems: [WallpaperContentItem] = []
    private var projectedArtworks: [OnlineImageArtwork] = []
    private var artworkByReference: [WallpaperReference: OnlineImageArtwork] = [:]
    private var contentByReference: [WallpaperReference: WallpaperContentItem] = [:]
    private var localRevision: UInt64?
    private let registeredCollections = NSHashTable<NSCollectionView>.weakObjects()
    let listThumbnailTintSource = ListThumbnailTintSource()
    var preferredColumns = WallpaperLibraryGridMetrics.defaultColumns { didSet { if oldValue != preferredColumns { render() } } }
    var onInspect: ((OnlineImageArtwork) -> Void)?
    var onSelectionChange: ((WallpaperContentItem?) -> Void)?
    var onPreview: ((WallpaperContentItem) -> Void)?
    var onEscape: (() -> Void)?
    var onRestoreColumns: ((Int) -> Void)?
    var makePrimary: ((WallpaperContentItem) -> (() -> Void)?)?
    var makeFavorite: ((WallpaperContentItem) -> (() -> Void)?)?
    var makeMenu: ((WallpaperContentItem) -> NSMenu?)?
    var isFavorite: ((WallpaperReference) -> Bool)?
    var isPlaying: ((WallpaperReference) -> Bool)?
    var isSwitching: ((WallpaperReference) -> Bool)?
    var onClipWidthChange: ((CGFloat) -> Void)?
    var onStateChange: (() -> Void)?
    private lazy var grid = WallpaperLibraryGridController { [weak self] collection, path, content, state in
        if self?.registeredCollections.contains(collection) == false {
            collection.register(OnlineImageGridItem.self, forItemWithIdentifier: OnlineImageGridItem.reuseIdentifier)
            self?.registeredCollections.add(collection)
        }
        let cell = collection.makeItem(withIdentifier: OnlineImageGridItem.reuseIdentifier, for: path)
        if let card = cell as? OnlineImageGridItem { self?.configure(card, content: content, state: state) }
        return cell
    }
    var clipWidth: CGFloat { grid.isViewLoaded ? grid.scrollView.contentView.bounds.width : 0 }
    var selectedContent: WallpaperContentItem? {
        selection.references.count == 1 ? selection.references.first.flatMap { contentByReference[$0] } : nil
    }

    init(session: OnlineImageBrowserSession, library: OnlineImageLibrary) {
        self.session = session; self.library = library
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = OnlineImageBrowserRootView(tint: listThumbnailTintSource)
        view = root
        addChild(grid); grid.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(grid.view)
        let footer = NSStackView(views: [status, more])
        footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        more.target = self; more.action = #selector(loadMore)
        WallpaperLibraryControlStyle.capsule(more)
        root.addSubview(footer)
        empty.alignment = .center; empty.textColor = .secondaryLabelColor
        empty.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(empty)
        NSLayoutConstraint.activate([
            grid.view.leadingAnchor.constraint(equalTo: root.leadingAnchor), grid.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            grid.view.topAnchor.constraint(equalTo: root.topAnchor), grid.view.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24), footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8), footer.heightAnchor.constraint(equalToConstant: 30),
            empty.centerXAnchor.constraint(equalTo: grid.view.centerXAnchor), empty.centerYAnchor.constraint(equalTo: grid.view.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualToConstant: 420), empty.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 28)
        ])
        grid.updateCell = { [weak self] cell, content, state in
            if let card = cell as? OnlineImageGridItem { self?.configure(card, content: content, state: state) }
        }
        grid.setCellVisible = { cell, visible in (cell as? OnlineImageGridItem)?.setThumbnailVisible(visible) }
        grid.onInspect = { [weak self] in self?.inspect($0) }
        grid.onQuickLook = { [weak self] content in
            guard let self, acceptsInput else { return }; onPreview?(content)
        }
        grid.onPrimaryAction = { [weak self] content in
            guard let self, acceptsInput else { return }; primary(content)?()
        }
        grid.onEscape = { [weak self] in
            guard self?.acceptsInput == true else { return }
            self?.onEscape?()
        }
        grid.onSelection = { [weak self] references, focus in
            guard let self, acceptsInput else { return nil }
            if selection.references != references || selection.focusedReference != focus { selection.sessionID = UUID() }
            selection.references = references; selection.focusedReference = focus
            onSelectionChange?(selectedContent)
            return selection.sessionID
        }
        grid.onScrollAnchor = { [weak self] _, reference, offset, top in self?.anchor = (reference, offset, top) }
        grid.onClipWidthChange = { [weak self] in self?.onClipWidthChange?($0) }
        grid.onViewport = { [weak self] visible, prefetch in self?.viewport(visible, prefetch) }
        grid.menuProvider = { [weak self] values in
            guard let self, acceptsInput else { return nil }
            return values.first.flatMap { self.makeMenu?($0) }
        }
        session.onResetScroll = { [weak self] in
            self?.resetScroll = true; self?.anchor = (nil, nil, true); self?.autoLoadedCount = nil
        }
        session.onCaptureReturnScroll = { [weak self] in
            guard let self else { return }; returnAnchor = (anchor, preferredColumns)
        }
        session.onRestoreReturnScroll = { [weak self] in
            guard let self else { return }
            anchor = returnAnchor?.0 ?? (nil, nil, true)
            if let columns = returnAnchor?.1 { onRestoreColumns?(columns) }
            returnAnchor = nil; resetScroll = true; autoLoadedCount = nil
        }
        session.$state.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.render(); self?.onStateChange?() }.store(in: &subscriptions)
        library.$snapshot.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.render() }.store(in: &subscriptions)
        library.$progress.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshVisibleTransfers() }.store(in: &subscriptions)
        render()
    }

    override func viewDidAppear() {
        super.viewDidAppear(); updateShownState()
    }
    override func viewWillDisappear() {
        super.viewWillDisappear(); setShown(false)
    }

    func setPageVisible(_ visible: Bool) { permitsDisplay = visible; updateShownState() }
    private func updateShownState() {
        setShown(permitsDisplay && view.window?.isVisible == true && view.window?.isMiniaturized == false)
    }
    private func setShown(_ value: Bool) {
        guard shown != value else { return }
        shown = value
        if value { session.enter(); render(); return }
        session.leave()
        prefetched.values.forEach { $0.cancel() }; prefetched.removeAll()
        listThumbnailTintSource.update(id: nil)
    }

    func refreshOrganization() { render() }
    private var acceptsInput: Bool { shown && WallpaperLibrarySheetPresentation.permitsInput(in: view.window) }
    func requestFocus() {
        guard acceptsInput else { return }
        view.window?.makeFirstResponder(grid.collection)
    }
    func moveSelection(with event: NSEvent) { if acceptsInput { grid.collection.keyDown(with: event) } }

    private var page: WallpaperLibraryPage { session.source == .wallhaven ? .wallhaven : .pixiv }
    private func values() -> [WallpaperContentItem] {
        if projectedArtworks != session.state.items || localRevision != library.snapshot.revision {
            projectedArtworks = session.state.items; localRevision = library.snapshot.revision
            artworkByReference = Dictionary(projectedArtworks.map { ($0.firstAssetID.reference, $0) }, uniquingKeysWith: { _, last in last })
            projectedItems = projectedArtworks.map { library.content(for: $0.firstAssetID.reference) ?? OnlineImageContentProjection.remote($0) }
            contentByReference = Dictionary(projectedItems.map { ($0.reference, $0) }, uniquingKeysWith: { _, last in last })
        }
        return projectedItems
    }

    private func render() {
        guard isViewLoaded else { return }
        let state = session.state, items = values()
        let validSelection = selection.references.filter { contentByReference[$0] != nil }
        if validSelection != selection.references {
            selection.sessionID = UUID()
            selection.references = validSelection
            if let focused = selection.focusedReference, contentByReference[focused] == nil {
                selection.focusedReference = validSelection.first
            }
            onSelectionChange?(selectedContent)
        }
        grid.update(page: page, items: items, selection: selection, preferredColumns: preferredColumns,
            permitsDragging: false, scrollAnchor: anchor.0, scrollOffset: anchor.1, scrollAtTop: anchor.2, resetScroll: resetScroll)
        resetScroll = false
        empty.isHidden = !items.isEmpty
        empty.stringValue = state.isLoading ? "正在加载…" : (state.error ?? (state.next != nil
            ? "本页没有符合条件的作品\n可以继续加载下一页" : (state.hasLoaded ? "没有可显示的作品\n试试其他关键词或筛选条件" : "准备浏览…")))
        status.stringValue = state.error ?? state.notice ?? (state.isLoading ? "正在加载…" : "已显示 \(items.count) 个作品")
        more.title = state.error != nil && state.next == nil ? "重试" : "加载更多"
        more.isHidden = !state.isLoading && state.next == nil && state.error == nil
        more.isEnabled = !state.isLoading
        updateTint()
    }

    private func artwork(_ content: WallpaperContentItem) -> OnlineImageArtwork? {
        artworkByReference[content.providerReference]
    }
    private func inspect(_ content: WallpaperContentItem) {
        guard acceptsInput, let artwork = artwork(content) else { return }
        onInspect?(artwork)
    }
    private func primary(_ content: WallpaperContentItem) -> (() -> Void)? {
        guard isSwitching?(content.reference) != true else { return nil }
        if content.publishedAvailability.isPublishedLocally { return makePrimary?(content) }
        guard content.capabilities.contains(.download), let artwork = artwork(content) else { return nil }
        return { [weak self] in
            guard let self, acceptsInput else { return }
            library.downloadArtwork(artwork)
        }
    }
    private func configure(_ card: OnlineImageGridItem, content: WallpaperContentItem, state: WallpaperLibraryGridController.CellState) {
        let artwork = artwork(content)
        let request = artwork.flatMap { value in
            (value.thumbnailURL ?? value.previewURL).map { library.thumbnailRequest(url: $0, source: value.source) }
        }
        card.configure(content: content, request: request, selected: state.isSelected, selecting: false,
            favorite: isFavorite?(content.reference) == true, playing: isPlaying?(content.reference) == true,
            switching: isSwitching?(content.reference) == true,
            busy: artwork.map { library.progress[$0.firstAssetID] != nil } == true,
            fraction: artwork.flatMap { library.progress[$0.firstAssetID] }, refreshToken: session.state.refreshToken,
            onPrimary: primary(content), onFavorite: makeFavorite?(content),
            onPreview: content.capabilities.contains(.quickLook) ? { [weak self] in
                guard let self, acceptsInput, let current = contentByReference[content.reference],
                      grid.select([current.reference], focus: current.reference) else { return }
                onPreview?(current)
            } : nil)
    }

    private func refreshVisibleTransfers() {
        guard isViewLoaded, shown else { return }
        for case let card as OnlineImageGridItem in grid.collection.visibleItems() {
            guard let reference = card.reference, let artwork = artworkByReference[reference] else { continue }
            let fraction = library.progress[artwork.firstAssetID]
            card.applyTransfer(busy: fraction != nil, fraction: fraction)
        }
    }

    private func viewport(_ visible: [WallpaperContentItem], _ nearby: [WallpaperContentItem]) {
        let wanted = Set(nearby.map(\.reference))
        for key in Array(prefetched.keys) where !wanted.contains(key) { prefetched.removeValue(forKey: key)?.cancel() }
        for content in nearby where prefetched[content.reference] == nil && !content.publishedAvailability.isAvailable {
            guard let art = artwork(content), let url = art.thumbnailURL ?? art.previewURL else { continue }
            let request = library.thumbnailRequest(url: url, source: art.source)
            let pixels = GridThumbnailDecoder.pixelLimit(width: clipWidth / CGFloat(max(1, preferredColumns)), scale: view.window?.backingScaleFactor ?? 2)
            prefetched[content.reference] = Task { _ = await OLThumbnailCache.shared.image(for: request, maxPixelSize: pixels, priority: .prefetch) }
        }
        if shown, !session.state.isLoading, session.state.next != nil, autoLoadedCount != session.state.items.count,
           let last = session.state.items.last,
           (visible.contains(where: { $0.reference == last.firstAssetID.reference })
            || nearby.contains(where: { $0.reference == last.firstAssetID.reference })) {
            autoLoadedCount = session.state.items.count
            session.loadMore()
        }
    }

    private func updateTint() {
        guard shown, let first = session.state.items.first, let url = first.thumbnailURL ?? first.previewURL else {
            listThumbnailTintSource.update(id: nil); return
        }
        let request = library.thumbnailRequest(url: url, source: first.source)
        listThumbnailTintSource.update(id: first.id, assets: [request.cacheURL.absoluteString]) { completion in
            let task = Task {
                let image = await OLThumbnailCache.shared.image(for: request, maxPixelSize: 256, priority: .prefetch)
                if !Task.isCancelled { completion(image) }
            }
            return { task.cancel() }
        }
    }

    @objc private func loadMore() {
        guard acceptsInput else { return }
        if session.state.next != nil { session.loadMore() } else { session.refresh() }
    }
}

private final class OnlineImageBrowserRootView: NSView, ListThumbnailTintProviding {
    let listThumbnailTintSource: ListThumbnailTintSource
    init(tint: ListThumbnailTintSource) { listThumbnailTintSource = tint; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
}
