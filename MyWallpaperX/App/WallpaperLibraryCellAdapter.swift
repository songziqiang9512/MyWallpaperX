import AppKit
import Combine

/// App assembly only: the grid owns selection and each provider owns its media,
/// thumbnail producer and commands. Bindings below are weak-keyed view receipts,
/// not another source index or cache.
@MainActor final class WallpaperLibraryCellAdapter {
    private enum Source: Equatable {
        case video(VideoWallpaper), image(SILWallpaper)
        case steam(SteamWorkshopDownloadRecord), pixabay(PixabayDownloadedEntry), onlineImage(OnlineImageLocalRecord), missing
        var reuseIdentifier: NSUserInterfaceItemIdentifier {
            switch self {
            case .video: return AppKitWallpaperItem.reuseIdentifier
            case .image: return SILGridItem.reuseID
            case .steam: return AppKitSteamWorkshopBrowserItem.reuseIdentifier
            case .pixabay: return AppKitPixabayDownloadsItem.reuseIdentifier
            case .onlineImage: return OnlineImageGridItem.reuseIdentifier
            case .missing: return WallpaperLibraryUnavailableItem.reuseIdentifier
            }
        }
    }
    private final class Binding {
        var content: WallpaperContentItem
        var source: Source
        var visible = false
        var thumbnailRequest: ThumbnailRequest?
        init(_ content: WallpaperContentItem, source: Source) { self.content = content; self.source = source }
    }
    private let manager: WallpaperManager
    private let images: SILService
    private let steam: SteamWorkshopService
    private let pixabay: PixabayService
    private let videoThumbnails: AppKitThumbnailProvider
    private let imageThumbnails = SILThumbnailProvider()
    private let registeredCollections = NSHashTable<NSCollectionView>.weakObjects()
    private let bindings = NSMapTable<NSCollectionViewItem, Binding>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private final class Prefetch {
        let assets: [Data]
        var cancel: () -> Void = {}
        // Pending requests and original cached results remain leased. A
        // completed result evicted or invalidated by its source is reheated.
        var isWarm: () -> Bool = { true }
        init(assets: [Data]) { self.assets = assets }
    }
    private var prefetches: [WallpaperReference: Prefetch] = [:]
    private let isPlaying: (WallpaperReference) -> Bool
    private let isSwitching: (WallpaperReference) -> Bool
    private let makePrimaryAction: (WallpaperContentItem) -> (() -> Void)?
    private let onInspect: ((WallpaperContentItem) -> Void)?
    private var imageTransferSubscription: AnyCancellable?

    init(manager: WallpaperManager, images: SILService, steam: SteamWorkshopService, pixabay: PixabayService,
         isPlaying: @escaping (WallpaperReference) -> Bool,
         isSwitching: @escaping (WallpaperReference) -> Bool = { _ in false },
         makePrimaryAction: @escaping (WallpaperContentItem) -> (() -> Void)?,
         onInspect: ((WallpaperContentItem) -> Void)? = nil) {
        self.manager = manager; self.images = images; self.steam = steam; self.pixabay = pixabay
        videoThumbnails = AppKitThumbnailProvider(wallpaperManager: manager)
        self.isPlaying = isPlaying
        self.isSwitching = isSwitching
        self.makePrimaryAction = makePrimaryAction; self.onInspect = onInspect
        imageTransferSubscription = OnlineImageLibrary.shared.$progress.receive(on: DispatchQueue.main).sink { [weak self] progress in
            guard let self else { return }
            for case let cell as OnlineImageGridItem in bindings.keyEnumerator() {
                guard let binding = bindings.object(forKey: cell), binding.visible,
                      case .onlineImage(let record) = binding.source else { continue }
                cell.applyTransfer(busy: progress[record.id] != nil, fraction: progress[record.id])
            }
        }
    }

    isolated deinit {
        videoThumbnails.cancelAllPrefetch()
        prefetches.values.forEach { $0.cancel() }
    }

    /// One bounded viewport lease, shared with each original provider. Visible
    /// cards keep their existing priority and producers; an earlier prefetch
    /// remains leased while it becomes visible, without starting another one.
    func updateViewport(visible: [WallpaperContentItem], prefetch: [WallpaperContentItem], request: ThumbnailRequest? = nil) {
        let visible = visible.filter { $0.publishedAvailability.isAvailable }
        let prefetch = prefetch.filter { $0.publishedAvailability.isAvailable }
        let wanted = Set((visible + prefetch).map(\.providerReference))
        let sources = resolveSources(for: wanted)
        func video(_ content: WallpaperContentItem) -> VideoWallpaper? {
            if case .video(let value) = sources[content.providerReference, default: .missing] { return value }
            return nil
        }
        let visibleVideos = visible.compactMap(video)
        videoThumbnails.replacePrefetch(with: prefetch.compactMap(video), retainingVisible: visibleVideos, request: request)
        videoThumbnails.updateVisiblePreviewDemand(with: visibleVideos)
        for reference in Array(prefetches.keys) where !wanted.contains(reference) {
            prefetches.removeValue(forKey: reference)?.cancel()
        }
        let nearby = Set(prefetch.map(\.providerReference))
        let requestKey = request.map { "\($0.width)x\($0.height):\($0.mode == .fill ? "fill" : "fit")" } ?? ""
        let steamPixelLimit = request.map { min(800, GridThumbnailDecoder.pixelLimit(width: CGFloat($0.width), scale: 1)) } ?? 256
        var seen = Set<WallpaperReference>()
        for content in prefetch + visible {
            let reference = content.providerReference
            guard seen.insert(reference).inserted else { continue }
            let source = sources[reference, default: .missing]
            if case .video = source { continue }
            let isNearby = nearby.contains(reference)
            guard isNearby || prefetches[reference] != nil else { continue }
            let assets = prefetchAssets(content, source: source, requestKey: requestKey, steamPixelLimit: steamPixelLimit)
            if let old = prefetches[reference], old.assets == assets, old.isWarm() { continue }
            prefetches.removeValue(forKey: reference)?.cancel()
            guard isNearby else { continue }
            let demand = Prefetch(assets: assets)
            switch source {
            case .image(let value):
                let cancellation = ThumbnailCacheRequestCancellation()
                demand.cancel = { cancellation.cancel() }
                demand.isWarm = { !cancellation.cancelled }
                imageThumbnails.load(path: value.path, request: request, priority: .prefetch, cancellation: cancellation) { [weak demand, cache = imageThumbnails.cache] result in
                    guard !cancellation.cancelled, case .image = result else { return }
                    demand?.isWarm = { !cancellation.cancelled && cache.hasCachedResult(forKey: value.path, request: request) }
                }
            case .pixabay(let value):
                let cancellation = ThumbnailCacheRequestCancellation()
                demand.cancel = { cancellation.cancel() }
                demand.isWarm = { !cancellation.cancelled }
                PixabayDownloadedThumbnailStore.loadThumbnail(value, request: request, priority: .prefetch, cancellation: cancellation) { [weak demand] key, _ in
                    guard !cancellation.cancelled else { return }
                    demand?.isWarm = { !cancellation.cancelled && PixabayDownloadedThumbnailStore.sharedCache.hasCachedResult(forKey: key, request: request) }
                }
            case .steam(let value):
                let item = value.displayItem ?? SteamWorkshopDownloadGridSupport.fallbackDisplayItem(for: value)
                let urls = steamWorkshopPreviewSources(item: item, record: value)
                let preview = SteamWorkshopPreviewState(loaders: .live(priority: .prefetch))
                demand.cancel = { preview.reset() }
                preview.onChange = { [weak preview, weak demand] in
                    // Ready pixels belong to the bounded cache; this consumer never displays them.
                    if preview?.image != nil { demand?.cancel = {} }
                }
                preview.configure(previewURL: urls.primary, fallbackImageURL: urls.fallback, fallbackVideoURL: value.videoURL,
                    refreshToken: steam.previewReloadToken, maxPixelSize: steamPixelLimit)
            case .onlineImage(let record):
                guard let url = OnlineImageLibrary.shared.localURL(for: record) else { continue }
                let cancellation = ThumbnailCacheRequestCancellation()
                demand.cancel = { cancellation.cancel() }
                demand.isWarm = { !cancellation.cancelled }
                imageThumbnails.load(path: url.path, request: request, priority: .prefetch, cancellation: cancellation) { [weak demand, cache = imageThumbnails.cache] result in
                    guard !cancellation.cancelled, case .image = result else { return }
                    demand?.isWarm = { !cancellation.cancelled && cache.hasCachedResult(forKey: url.path, request: request) }
                }
            case .video, .missing: continue
            }
            prefetches[reference] = demand
        }
    }

    func repairVisiblePreviews() { videoThumbnails.repairVisiblePreviews() }

    private func prefetchAssets(_ content: WallpaperContentItem, source: Source, requestKey: String, steamPixelLimit: Int) -> [Data] {
        var values = [content.locator.path ?? "", content.metadata.thumbnailPath ?? "",
            content.metadata.previewURL?.absoluteString ?? "", content.metadata.previewVideoURL?.absoluteString ?? "",
            content.metadata.resourceRevision ?? "", String(describing: content.metadata.fileSizeBytes),
            String(describing: content.metadata.modifiedAt)]
        switch source {
        case .image(let value): values += [value.path, requestKey]
        case .pixabay(let value): values += [value.localURL.absoluteString, value.thumbnailSourceKey ?? "", requestKey]
        case .steam(let value):
            let item = value.displayItem ?? SteamWorkshopDownloadGridSupport.fallbackDisplayItem(for: value)
            let urls = steamWorkshopPreviewSources(item: item, record: value)
            values += [urls.primary?.absoluteString ?? "", urls.fallback?.absoluteString ?? "",
                value.videoURL?.absoluteString ?? "", String(steam.previewReloadToken), String(steamPixelLimit)]
        case .onlineImage(let record): values += [record.revision.uuidString, requestKey]
        case .video, .missing: break
        }
        return values.map { Data($0.utf8) }
    }

    func makeCell(collection: NSCollectionView, indexPath: IndexPath, content: WallpaperContentItem,
                  state: WallpaperLibraryGridController.CellState) -> NSCollectionViewItem {
        if !registeredCollections.contains(collection) {
            collection.register(AppKitWallpaperItem.self, forItemWithIdentifier: AppKitWallpaperItem.reuseIdentifier)
            collection.register(SILGridItem.self, forItemWithIdentifier: SILGridItem.reuseID)
            collection.register(AppKitSteamWorkshopBrowserItem.self, forItemWithIdentifier: AppKitSteamWorkshopBrowserItem.reuseIdentifier)
            collection.register(AppKitPixabayDownloadsItem.self, forItemWithIdentifier: AppKitPixabayDownloadsItem.reuseIdentifier)
            collection.register(OnlineImageGridItem.self, forItemWithIdentifier: OnlineImageGridItem.reuseIdentifier)
            collection.register(WallpaperLibraryUnavailableItem.self, forItemWithIdentifier: WallpaperLibraryUnavailableItem.reuseIdentifier)
            registeredCollections.add(collection)
        }
        let source = resolveSource(content.providerReference)
        let cell = collection.makeItem(withIdentifier: source.reuseIdentifier, for: indexPath)
        let binding = Binding(content, source: source)
        bindings.setObject(binding, forKey: cell)
        // Collection views can request a cell before display. Acquiring pixels
        // is deferred until their real willDisplay callback grants demand.
        setVisible(cell, nil)
        configure(cell, binding: binding, state: state, reloadContent: true)
        return cell
    }

    func needsCellReplacement(_ cell: NSCollectionViewItem, content: WallpaperContentItem) -> Bool {
        cell.identifier != resolveSource(content.providerReference).reuseIdentifier
    }

    func updateCell(_ cell: NSCollectionViewItem, content: WallpaperContentItem,
                    state: WallpaperLibraryGridController.CellState) {
        let source = resolveSource(content.providerReference)
        guard cell.identifier == source.reuseIdentifier else { return }
        let existing = bindings.object(forKey: cell)
        let binding = existing ?? Binding(content, source: source)
        let reload = existing == nil || binding.content != content || binding.source != source
        binding.content = content; binding.source = source
        bindings.setObject(binding, forKey: cell)
        configure(cell, binding: binding, state: state, reloadContent: reload)
    }

    func setVisible(_ cell: NSCollectionViewItem, _ state: WallpaperLibraryGridController.CellState?) {
        let visible = state != nil
        let binding = bindings.object(forKey: cell)
        binding?.visible = visible
        if let state, let binding, binding.thumbnailRequest != state.thumbnailRequest {
            configure(cell, binding: binding, state: state, reloadContent: false)
        }
        switch cell {
        case let card as AppKitWallpaperItem: card.setThumbnailVisible(visible)
        case let card as SILGridItem: card.setThumbnailVisible(visible)
        case let card as AppKitSteamWorkshopBrowserItem: card.setPreviewVisible(visible)
        case let card as AppKitPixabayDownloadsItem:
            if visible { card.beginDisplayingThumbnail() } else { card.endDisplayingThumbnail() }
        case let card as OnlineImageGridItem: card.setThumbnailVisible(visible)
        default: break
        }
    }

    private func resolveSources(for references: Set<WallpaperReference>) -> [WallpaperReference: Source] {
        var sources: [WallpaperReference: Source] = [:]
        func collect<Row>(_ values: @autoclosure () -> [Row], provider: WallpaperProvider,
                          id: (Row) -> String, source: (Row) -> Source) {
            var pending = Set(references.filter { $0.provider == provider })
            guard !pending.isEmpty else { return }
            for row in values() {
                let reference = WallpaperReference(provider: provider, sourceID: id(row))
                guard pending.remove(reference) != nil else { continue }
                sources[reference] = source(row)
                if pending.isEmpty { break }
            }
        }
        collect(manager.wallpapers, provider: .videoLibrary, id: { $0.id }, source: Source.video)
        collect(images.wallpapers, provider: .staticImageLibrary, id: { $0.id }, source: Source.image)
        collect(steam.downloads, provider: .steamWorkshop, id: { $0.id }, source: Source.steam)
        collect(pixabay.downloadedContent.entries, provider: .pixabay, id: { String($0.id) }, source: Source.pixabay)
        for reference in references where reference.provider == .wallhaven || reference.provider == .pixiv {
            sources[reference] = OnlineImageLibrary.shared.record(for: reference).map(Source.onlineImage) ?? .missing
        }
        return sources
    }

    private func resolveSource(_ reference: WallpaperReference) -> Source {
        // Source IDs are opaque UTF8. String's canonical Unicode equality must
        // not cause two distinct source records to share a card or command.
        func matches(_ id: String) -> Bool { id.utf8.elementsEqual(reference.sourceID.utf8) }
        switch reference.provider {
        case .videoLibrary: return manager.wallpapers.first(where: { matches($0.id) }).map(Source.video) ?? .missing
        case .staticImageLibrary: return images.wallpapers.first(where: { matches($0.id) }).map(Source.image) ?? .missing
        case .steamWorkshop: return steam.downloads.first(where: { matches($0.id) }).map(Source.steam) ?? .missing
        case .pixabay:
            guard let id = Int(reference.sourceID), String(id).utf8.elementsEqual(reference.sourceID.utf8) else { return .missing }
            return pixabay.downloadedContent.entries.first(where: { $0.id == id }).map(Source.pixabay) ?? .missing
        case .wallhaven, .pixiv:
            return OnlineImageLibrary.shared.record(for: reference).map(Source.onlineImage) ?? .missing
        }
    }

    private func current(_ cell: NSCollectionViewItem?, matching reference: WallpaperReference) -> WallpaperContentItem? {
        guard let cell, let content = bindings.object(forKey: cell)?.content,
              content.providerReference == reference else { return nil }
        return content
    }

    private func configure(_ cell: NSCollectionViewItem, binding: Binding,
                           state: WallpaperLibraryGridController.CellState, reloadContent: Bool) {
        let thumbnailRequestChanged = binding.thumbnailRequest != state.thumbnailRequest
        binding.thumbnailRequest = state.thumbnailRequest
        let content = binding.content, provider = content.providerReference
        let playing = isPlaying(content.reference)
        let switching = isSwitching(content.reference)
        let canRetryImage = (provider.provider == .wallhaven || provider.provider == .pixiv)
            && content.capabilities.contains(.retryDownload)
        let action = !switching && (content.capabilities.contains(.play) || playing || canRetryImage) ? makePrimaryAction(content) : nil
        let canPlay = action != nil
        let primary: () -> Void = { [weak self, weak cell] in
            guard let self, let current = self.current(cell, matching: provider),
                  current.capabilities.contains(.play) || self.isPlaying(current.reference)
                    || ((current.providerReference.provider == .wallhaven || current.providerReference.provider == .pixiv)
                        && current.capabilities.contains(.retryDownload)) else { return }
            action?()
        }
        let inspect = onInspect.map { inspect in
            { [weak self, weak cell] in
                guard let self, let current = self.current(cell, matching: provider) else { return }
                inspect(current)
            }
        }
        switch (binding.source, cell) {
        case (.video(let row), let card as AppKitWallpaperItem):
            card.onPlayRequested = canPlay ? { _ in primary() } : nil
            card.onInspectRequested = inspect.map { action in { _ in action() } }
            if reloadContent || thumbnailRequestChanged {
                card.configure(wallpaper: row, isSelected: state.isSelected, isPlaying: playing,
                    multiSelectMode: state.isSelecting, thumbnailRequest: state.thumbnailRequest,
                    wallpaperManager: manager, thumbnailProvider: videoThumbnails)
            } else {
                card.applySelectionState(isSelected: state.isSelected, multiSelectMode: state.isSelecting)
                card.applyPlayingState(isPlaying: playing)
            }
            card.applySwitchingState(isSwitching: switching)
        case (.image(let row), let card as SILGridItem):
            card.onApplyRequested = canPlay ? { _ in primary() } : nil
            card.onInspectRequested = inspect.map { action in { _ in action() } }
            if reloadContent || thumbnailRequestChanged {
                card.configure(wallpaper: row, isSelected: state.isSelected, isMultiSelectMode: state.isSelecting,
                    thumbnailVisible: binding.visible, isPlaying: playing,
                    cachedThumbnail: imageThumbnails.cache.cachedImage(forKey: row.path, request: state.thumbnailRequest)) { [weak imageThumbnails] cancellation, completion in
                        guard let imageThumbnails else { completion(.unavailable); return }
                        imageThumbnails.load(path: row.path, request: state.thumbnailRequest, cancellation: cancellation, completion: completion)
                    }
            } else {
                card.applySelectionState(isSelected: state.isSelected, multiSelectMode: state.isSelecting)
                card.applyPlayingState(isPlaying: playing)
            }
            card.applySwitchingState(isSwitching: switching)
        case (.steam(let row), let card as AppKitSteamWorkshopBrowserItem):
            let item = row.displayItem ?? SteamWorkshopDownloadGridSupport.fallbackDisplayItem(for: row)
            let canDownload = !content.capabilities.intersection([.download, .retryDownload, .retryUpdate]).isEmpty
            // Favorite commands belong to the source/Commands menus, not the card controls.
            let presentation = AppKitSteamWorkshopBrowserItem.OrganizationPresentation(
                isFavorite: false, canFavorite: false, isSwitching: switching, canPlay: canPlay,
                canDownload: canDownload, canCancel: content.capabilities.contains(.cancelDownload),
                onPrimary: primary)
            if !reloadContent {
                card.applyOrganizationState(presentation, isPlaying: playing,
                    isMultiSelectMode: state.isSelecting, isKeyboardFocused: state.isSelected)
                return
            }
            card.configureMetadataOnly(displayContext: .downloads, isPlaying: playing, item: item,
                downloadRecord: row, downloadProgressStore: steam.downloadProgressStore,
                isDownloading: row.status == .downloading, isDownloaded: content.publishedAvailability.isAvailable,
                isMultiSelectMode: state.isSelecting, isKeyboardFocused: state.isSelected,
                organization: presentation,
                onOpen: inspect, onDownload: { [weak self, weak cell] in
                    guard let self, let current = self.current(cell, matching: provider),
                          !current.capabilities.intersection([.download, .retryDownload, .retryUpdate]).isEmpty else { return }
                    self.steam.downloadWorkshopItem(id: provider.sourceID, pageTitle: item.title, item: item)
                }, onSetAsWallpaper: primary, onCancelDownload: { [weak self, weak cell] in
                    guard let self, let current = self.current(cell, matching: provider),
                          current.capabilities.contains(.cancelDownload) else { return }
                    self.steam.cancelDownload(itemID: provider.sourceID)
                })
        case (.pixabay(let row), let card as AppKitPixabayDownloadsItem):
            card.onPrimaryAction = canPlay ? { _ in primary() } : nil
            card.onInspectRequested = inspect.map { action in { _ in action() } }
            if reloadContent || thumbnailRequestChanged {
                card.configure(entry: row, isSelected: state.isSelected, isMultiSelectMode: state.isSelecting,
                    isPlaying: playing, request: state.thumbnailRequest, thumbnailDemandActive: binding.visible)
            } else {
                card.applySelectionState(state.isSelected, multiSelectMode: state.isSelecting)
                card.applyPlayingState(isPlaying: playing)
            }
            card.applySwitchingState(isSwitching: switching)
        case (.onlineImage(let record), let card as OnlineImageGridItem):
            let fraction = OnlineImageLibrary.shared.progress[record.id]
            card.configure(content: content, request: nil, selected: state.isSelected, selecting: state.isSelecting,
                playing: playing, switching: switching, busy: fraction != nil, fraction: fraction, thumbnailRequest: state.thumbnailRequest,
                onPrimary: canPlay ? primary : nil, onInspect: inspect)
        case (.missing, let card as WallpaperLibraryUnavailableItem):
            card.configure(content: content, selected: state.isSelected, selecting: state.isSelecting)
        default: break
        }
    }
}

/// A retained relationship can outlive its media/source row. It remains visible
/// with its real identity and title, with no fabricated provider model or action.
final class WallpaperLibraryUnavailableItem: NSCollectionViewItem, WallpaperGridHoverItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("WallpaperLibraryUnavailableItem")
    private let card = AppearanceAwareContainerView()
    private let symbol = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(labelWithString: "原文件不可用")
    private let selection = NSImageView()
    private var selectedState = false
    private var hovered = false
    private let hoverTracking = WallpaperGridHoverTracking()
    override func loadView() {
        view = WallpaperCardInteractionView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 14; card.layer?.borderWidth = 1; card.layer?.masksToBounds = true
        card.appearanceDidChangeHandler = { [weak self] in self?.refreshAppearance() }
        view.addSubview(card)
        symbol.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "原文件不可用")
        symbol.contentTintColor = .secondaryLabelColor
        titleLabel.alignment = .center; titleLabel.maximumNumberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        status.alignment = .center; status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        selection.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "已选中")
        selection.contentTintColor = .controlAccentColor
        [symbol, titleLabel, status, selection].forEach { card.addSubview($0) }
        refreshAppearance()
    }
    func configure(content: WallpaperContentItem, selected: Bool, selecting: Bool) {
        _ = view
        self.selectedState = selected
        titleLabel.stringValue = content.title
        selection.isHidden = !selecting
        selection.image = NSImage(systemSymbolName: selected ? "checkmark.circle.fill" : "circle", accessibilityDescription: selected ? "已选中" : "未选中")
        view.toolTip = nil
        view.setAccessibilityElement(true); view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("\(content.title)，原文件不可用")
        refreshAppearance()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        card.frame = view.bounds
        hoverTracking.update(in: card, owner: self)
        symbol.frame = NSRect(x: (view.bounds.width - 30) / 2, y: view.bounds.midY + 10, width: 30, height: 30)
        titleLabel.frame = NSRect(x: 12, y: max(30, view.bounds.midY - 42), width: max(0, view.bounds.width - 24), height: 34)
        status.frame = NSRect(x: 12, y: max(10, view.bounds.midY - 62), width: max(0, view.bounds.width - 24), height: 18)
        selection.frame = NSRect(x: view.bounds.midX - 12, y: view.bounds.midY - 12, width: 24, height: 24)
    }
    override func mouseEntered(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        hovered = true; refreshAppearance()
    }
    override func mouseExited(with event: NSEvent) {
        guard !view.isGridHoverSuppressed else { return }
        hovered = false; refreshAppearance()
    }
    func refreshGridHover(isScrolling: Bool) {
        hoverTracking.update(in: card, owner: self, isScrolling: isScrolling)
        hovered = !isScrolling && view.isGridPointerInside
        refreshAppearance()
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        selectedState = false; hovered = false; titleLabel.stringValue = ""; view.toolTip = nil
        selection.isHidden = true; refreshAppearance()
    }
    private func refreshAppearance() {
        card.effectiveAppearance.performAsCurrentDrawingAppearance {
            card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            card.layer?.borderColor = (selectedState ? NSColor.controlAccentColor : hovered ? .white : .separatorColor).cgColor
            card.layer?.borderWidth = selectedState ? 2 : 1
        }
    }
}
