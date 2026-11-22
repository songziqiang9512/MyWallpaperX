import AppKit
import Combine

/// A clicked work/page uses the existing Inspector host and the publication
/// owner's facts. This view never creates local identities or playback tickets.
@MainActor
final class OnlineImageInspectorView: NSView {
    private var artwork: OnlineImageArtwork
    private let library: OnlineImageLibrary
    private let makeLibraryActions: (WallpaperReference) -> WallpaperInspectorActions?
    private let onAuthor: ((OnlineImageAuthor) -> Void)?
    private let initialReference: WallpaperReference
    private var firstThumbnailURL: URL?
    private var previewRequest: ThumbnailRequest?
    private var pageIndex: Int
    private var assets: [OnlineImageAsset] = []
    private var boundActions: (WallpaperReference, WallpaperInspectorActions)?
    private let preview = SILInspectorPreviewSurfaceView(image: nil)
    private let content = SILInspectorViews.makeVerticalStack(spacing: 16)
    private let titleLabel = SILInspectorViews.makeLabel("", font: .systemFont(ofSize: 19, weight: .semibold), color: .labelColor)
    private let facts = SILInspectorViews.makeVerticalStack(spacing: 12)
    private let notice = SILInspectorViews.makeLabel("", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
    private let pageLabel = NSTextField(labelWithString: "")
    private let authorButton = SILInspectorViews.makeFooterButton(title: String(localized: "Artist Info Unavailable"), symbolName: "person.crop.circle", target: nil, action: #selector(openAuthor))
    private let previousButton = SILInspectorViews.makeFooterButton(title: "", symbolName: "chevron.left", target: nil, action: #selector(previousPage))
    private let nextButton = SILInspectorViews.makeFooterButton(title: "", symbolName: "chevron.right", target: nil, action: #selector(nextPage))
    private let primaryButton = SILInspectorViews.makeFooterButton(title: String(localized: "Download Image"), symbolName: "arrow.down.to.line", target: nil, action: #selector(performPrimary), kind: .primary)
    private let sourceButton = SILInspectorViews.makeFooterButton(title: String(localized: "Open Original Page"), symbolName: "safari", target: nil, action: #selector(openSource))
    private let localThumbnails = SILThumbnailProvider()
    private var detailTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var localCancellation: ThumbnailCacheRequestCancellation?
    private var subscriptions = Set<AnyCancellable>()
    private var sessionSubscription: AnyCancellable?
    private var observedScope: String?
    private var loadID = UUID(), previewID = UUID()
    private var displayedPage: OnlineImageAssetID?
    private var lastPreviewKey: String?
    private var errorText: String?
    private var isResolving = true
    private var hasMounted = false
    private var isRetired = false
    private var renderedControls: ControlState?
    private var renderedProgress: Double?
    private struct ControlState: Equatable {
        let local: Bool
        let downloading: Bool
        let switching: Bool
        let applied: Bool
        let canApply: Bool
    }

    init(artwork: OnlineImageArtwork, library: OnlineImageLibrary,
         makeLibraryActions: @escaping (WallpaperReference) -> WallpaperInspectorActions?,
         onAuthor: ((OnlineImageAuthor) -> Void)? = nil, initialPageIndex: Int = 0) {
        self.artwork = artwork; self.library = library
        self.makeLibraryActions = makeLibraryActions; self.onAuthor = onAuthor
        firstThumbnailURL = artwork.thumbnailURL ?? artwork.previewURL
        pageIndex = max(0, initialPageIndex)
        initialReference = OnlineImageAssetID(source: artwork.source, artworkID: artwork.artworkID, pageIndex: max(0, initialPageIndex)).reference
        super.init(frame: .zero)
        setup()
        observeLibrary()
        loadPreview()
        resolveDetails()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    deinit { detailTask?.cancel(); previewTask?.cancel(); localCancellation?.cancel() }

    private var assetID: OnlineImageAssetID { .init(source: artwork.source, artworkID: artwork.artworkID, pageIndex: pageIndex) }
    private var currentAsset: OnlineImageAsset? { assets.first { $0.id == assetID } }
    private var currentRecord: OnlineImageLocalRecord? { library.record(for: assetID.reference) }
    private var isLocalAvailable: Bool { library.content(for: assetID.reference)?.publishedAvailability.isAvailable == true }
    private var pageIndices: [Int] {
        let local = library.snapshot.records.filter { $0.id.source == artwork.source && $0.id.artworkID == artwork.artworkID }.map { $0.id.pageIndex }
        return Set(assets.map { $0.id.pageIndex } + local + [pageIndex]).sorted()
    }
    private var currentActions: WallpaperInspectorActions? {
        boundActions?.0 == assetID.reference ? boundActions?.1 : nil
    }

    func updateLibraryActions(_ actions: WallpaperInspectorActions) {
        let reference = assetID.reference
        if let fresh = makeLibraryActions(reference) { boundActions = (reference, fresh) }
        else if reference == initialReference, isLocalAvailable { boundActions = (reference, actions) }
        else { boundActions = nil }
        updateControls()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            hasMounted = true
            if isRetired {
                // Prepare loading state before observation catches up synchronously.
                isRetired = false; resolveDetails(); observeLibrary()
            }
            loadPreview()
        } else if hasMounted { retire() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        loadPreview()
    }

    private func setup() {
        preview.onSizeChange = { [weak self] in self?.loadPreview() }
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        let root = SILInspectorViews.makeVerticalStack(spacing: 12)
        root.alignment = .centerX
        let scroll = InspectorFadingScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = InspectorContentDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        content.edgeInsets = NSEdgeInsets(top: InspectorFadingScrollView.contentTopInset, left: 0, bottom: 16, right: 0)
        document.addSubview(content)
        scroll.documentView = document
        preview.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        authorButton.target = self; authorButton.action = #selector(openAuthor)
        WallpaperLibraryControlStyle.authorPill(authorButton)
        authorButton.setContentHuggingPriority(.required, for: .horizontal)
        let authorRow = NSStackView(views: [authorButton, NSView()])
        authorRow.spacing = 0
        authorRow.alignment = .centerY
        let pager = NSStackView(views: [pageLabel, previousButton, nextButton, NSView()])
        pager.spacing = 8
        previousButton.target = self; previousButton.action = #selector(previousPage)
        nextButton.target = self; nextButton.action = #selector(nextPage)
        previousButton.setAccessibilityLabel(String(localized: "Previous")); previousButton.toolTip = String(localized: "Previous")
        nextButton.setAccessibilityLabel(String(localized: "Next")); nextButton.toolTip = String(localized: "Next")
        pageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        pageLabel.textColor = .secondaryLabelColor
        notice.maximumNumberOfLines = 0
        primaryButton.target = self; sourceButton.target = self
        sourceButton.setAccessibilityLabel(String(localized: "Open Artwork in Browser")); sourceButton.toolTip = String(localized: "Open Artwork in Browser")
        for section in [preview, titleLabel, authorRow, pager, WallpaperLibraryControlStyle.sectionDivider(), facts, notice] as [NSView] {
            content.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        preview.heightAnchor.constraint(equalToConstant: 156).isActive = true
        let footer = NSStackView(views: [primaryButton, sourceButton])
        footer.orientation = .horizontal; footer.spacing = 8; footer.distribution = .fill
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        root.addArrangedSubview(scroll); root.addArrangedSubview(footer)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor), root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor), root.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor), footer.widthAnchor.constraint(equalTo: content.widthAnchor),
            footer.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),
            sourceButton.widthAnchor.constraint(equalTo: primaryButton.widthAnchor),
            authorButton.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: InspectorFooterMetrics.iconWidth),
            nextButton.widthAnchor.constraint(equalToConstant: InspectorFooterMetrics.iconWidth),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 2),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -2),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor)
        ])
    }

    private func observeLibrary() {
        library.$snapshot.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, !isRetired else { return }
            refreshContent(); loadPreview()
        }.store(in: &subscriptions)
        library.$progress.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, renderedProgress != library.progress[assetID] else { return }
            updateControls()
        }.store(in: &subscriptions)
        observeSession()
        refreshContent()
    }

    private func observeSession() {
        guard artwork.source == .pixiv, sessionSubscription == nil, let session = library.pixivSession else { return }
        observedScope = session.scopeID
        sessionSubscription = session.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
            guard let self, !isRetired, observedScope != state.scopeID else { return }
            observedScope = state.scopeID
            loadID = UUID(); detailTask?.cancel(); detailTask = nil; assets = []; isResolving = false
            previewID = UUID(); previewTask?.cancel(); previewTask = nil
            localCancellation?.cancel(); localCancellation = nil; lastPreviewKey = nil
            if !isLocalAvailable { preview.updateImage(nil) }
            // Local receipts remain usable; account-scoped remote metadata does not.
            firstThumbnailURL = nil
            artwork = OnlineImageArtwork(source: .pixiv, artworkID: artwork.artworkID,
                title: "Pixiv #\(artwork.artworkID)", sourceURL: artwork.sourceURL)
            errorText = String(localized: "The account session has changed. Close the details and open them again.")
            refreshContent(); loadPreview()
        }
    }

    private func resolveDetails() {
        detailTask?.cancel()
        let token = UUID(); loadID = token
        let seed = artwork, library = library
        isResolving = true
        detailTask = Task { [weak self] in
            do {
                let value = try await library.detail(seed)
                guard !Task.isCancelled, self?.accepts(token) == true else { return }
                self?.errorText = nil
                self?.artwork = value
                self?.observeSession()
                self?.refreshContent(); self?.loadPreview()
                if value.kind == .image, value.isMasked != true {
                    let values = try await library.assets(for: value)
                    guard !Task.isCancelled, self?.accepts(token) == true else { return }
                    self?.assets = values
                }
                guard self?.accepts(token) == true else { return }
                self?.isResolving = false; self?.detailTask = nil
                self?.refreshContent(); self?.loadPreview()
            } catch is CancellationError { }
            catch let error as URLError where error.code == .cancelled { }
            catch {
                guard !Task.isCancelled, self?.accepts(token) == true else { return }
                self?.isResolving = false; self?.detailTask = nil
                self?.errorText = error.localizedDescription
                self?.refreshContent()
            }
        }
    }

    private func accepts(_ token: UUID) -> Bool { !isRetired && loadID == token }

    private func refreshContent() {
        let record = currentRecord, asset = currentAsset
        titleLabel.stringValue = record?.title ?? asset?.title ?? artwork.title
        let author = record?.author ?? asset?.author ?? artwork.author ?? ""
        authorButton.setTitle(author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Artist Info Unavailable") : author)
        authorButton.isEnabled = onAuthor != nil && resolvedAuthor != nil
        let indices = pageIndices
        let position = indices.firstIndex(of: pageIndex) ?? 0
        previousButton.isEnabled = position > 0
        nextButton.isEnabled = position + 1 < indices.count
        previousButton.isHidden = indices.count < 2; nextButton.isHidden = indices.count < 2
        pageLabel.stringValue = asset != nil
            ? String(localized: "Image \(pageIndex + 1) of \(assets.count)") : String(localized: "Image \(pageIndex + 1)\(record == nil ? "" : String(localized: " · Local Image"))")
        facts.arrangedSubviews.forEach { facts.removeArrangedSubview($0); $0.removeFromSuperview() }
        var values: [(String, String)] = [(String(localized: "Source"), artwork.source.displayName)]
        if let width = record?.pixelWidth ?? asset?.width ?? (pageIndex == 0 ? artwork.width : nil),
           let height = record?.pixelHeight ?? asset?.height ?? (pageIndex == 0 ? artwork.height : nil) { values.append((String(localized: "Resolution"), "\(width) × \(height)")) }
        if let bytes = record?.fileSizeBytes ?? asset?.expectedBytes ?? (pageIndex == 0 ? artwork.fileSizeBytes : nil) {
            values.append((String(localized: "File Size"), ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
        }
        let rating: String
        switch artwork.rating { case .safe: rating = String(localized: "All Ages"); case .sensitive: rating = String(localized: "May Contain Sensitive Content"); case .adult: rating = String(localized: "Age Restricted"); case .unknown: rating = String(localized: "Unconfirmed") }
        values.append((String(localized: "Content Rating"), rating))
        let grid = WallpaperLibraryControlStyle.inspectorFacts(values)
        facts.addArrangedSubview(grid); grid.widthAnchor.constraint(equalTo: facts.widthAnchor).isActive = true
        let tags = record?.tags ?? asset?.tags ?? artwork.tags
        if !tags.isEmpty {
            let tagsLabel = SILInspectorViews.makeLabel(tags.joined(separator: " · "), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
            tagsLabel.maximumNumberOfLines = 4
            WallpaperLibraryControlStyle.addSectionDivider(to: facts)
            facts.addArrangedSubview(tagsLabel)
            tagsLabel.widthAnchor.constraint(equalTo: facts.widthAnchor).isActive = true
        }
        if let fresh = makeLibraryActions(assetID.reference) { boundActions = (assetID.reference, fresh) }
        else { boundActions = nil }
        if let errorText { notice.stringValue = "\(errorText)\(isLocalAvailable ? " 已下载图片仍可使用。" : "")" }
        else if !isLocalAvailable, artwork.kind == .animation { notice.stringValue = String(localized: "Animated images can’t be downloaded or applied yet. You can view them on the original site.") }
        else if !isLocalAvailable, artwork.kind == .unknown, !isResolving { notice.stringValue = String(localized: "The artwork type isn’t confirmed yet, so it can’t be downloaded or applied.") }
        else if !isLocalAvailable, artwork.isMasked == true { notice.stringValue = String(localized: "This item is restricted by the site's display permissions. Open the original site to check your settings.") }
        else { notice.stringValue = isResolving ? String(localized: "Fetching item details…") : "" }
        notice.isHidden = notice.stringValue.isEmpty
        updateControls()
    }

    private func updateControls() {
        guard !isRetired else { return }
        let progress = library.progress[assetID]
        let local = isLocalAvailable
        let actions = currentActions?.state
        let switching = actions?.isSwitching == true
        let state = ControlState(local: local, downloading: progress != nil,
            switching: switching, applied: actions?.isPlaying == true,
            canApply: !switching && (local ? actions?.canPerformPrimary == true
                : currentAsset != nil && artwork.kind == .image && artwork.isMasked != true))
        if renderedProgress != progress { renderedProgress = progress; primaryButton.setProgressFill(progress) }
        guard state != renderedControls else { return }
        renderedControls = state
        let title = switching ? String(localized: "Switching Wallpaper") : local ? actions?.primaryTitle ?? String(localized: "Set as Wallpaper") : progress != nil ? String(localized: "Cancel Download") : String(localized: "Download Image")
        primaryButton.setTitle(title)
        primaryButton.setSymbol(switching ? "hourglass" : local ? actions?.primarySymbolName ?? "photo.fill" : progress != nil ? "xmark" : "arrow.down.to.line", accessibilityDescription: title)
        primaryButton.isEnabled = state.canApply || progress != nil
    }

    private func loadPreview() {
        guard !isRetired, let window, let target = ThumbnailRequest(size: preview.bounds.size,
            scale: window.backingScaleFactor, mode: .fill) else { return }
        let id = assetID
        let local = isLocalAvailable ? currentRecord.flatMap(library.localURL(for:)) : nil
        // The first page keeps the grid URL even when richer detail metadata arrives.
        let remote = pageIndex == 0 ? firstThumbnailURL ?? artwork.thumbnailURL ?? artwork.previewURL : currentAsset?.previewURL
        let key = local.map { "local:\($0.path):\(currentRecord?.revision.uuidString ?? "")" }
            ?? remote.map { "remote:\(artwork.source == .pixiv ? library.pixivScope : "public"):\($0.absoluteString)" }
        guard key != lastPreviewKey || displayedPage != id || previewRequest != target else { return }
        lastPreviewKey = key; previewRequest = target
        previewTask?.cancel(); previewTask = nil; localCancellation?.cancel(); localCancellation = nil
        let token = UUID(); previewID = token
        if displayedPage != id { preview.updateImage(nil); displayedPage = id }
        if let local {
            let cancellation = ThumbnailCacheRequestCancellation(); localCancellation = cancellation
            localThumbnails.load(path: local.path, request: target, cancellation: cancellation) { [weak self] result in
                guard let self, !isRetired, previewID == token, assetID == id, !cancellation.cancelled else { return }
                localCancellation = nil
                if case .image(let image) = result { preview.updateImage(image) }
            }
        } else if let remote {
            let request = library.thumbnailRequest(url: remote, source: artwork.source)
            if let image = OnlineImageThumbnailCache.shared.readyImage(for: request, request: target) { preview.updateImage(image); return }
            previewTask = Task { [weak self] in
                let image = await OnlineImageThumbnailCache.shared.image(for: request, request: target, priority: .visible)
                guard let self, !Task.isCancelled, !isRetired, previewID == token, assetID == id else { return }
                previewTask = nil
                if let image { preview.updateImage(image) }
            }
        }
    }

    private func changePage(_ offset: Int) {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
        let indices = pageIndices
        guard let current = indices.firstIndex(of: pageIndex), indices.indices.contains(current + offset) else { return }
        pageIndex = indices[current + offset]
        boundActions = nil
        refreshContent(); loadPreview()
    }
    @objc private func previousPage() { changePage(-1) }
    @objc private func nextPage() { changePage(1) }
    @objc private func performPrimary() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
        if library.progress[assetID] != nil { library.cancel(assetID) }
        else if isLocalAvailable, let actions = currentActions,
                !actions.state.isSwitching, actions.state.canPerformPrimary { actions.onPrimary() }
        else if !isLocalAvailable, artwork.kind == .image, artwork.isMasked != true, let asset = currentAsset { library.download(asset) }
    }
    @objc private func openSource() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
        NSWorkspace.shared.open(artwork.sourceURL)
    }
    @objc private func openAuthor() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: window),
              let author = resolvedAuthor else { return }
        onAuthor?(author)
    }
    private var resolvedAuthor: OnlineImageAuthor? {
        let record = currentRecord
        let asset = record?.author == nil || record?.authorID == nil ? currentAsset : nil
        let name = record?.author ?? asset?.author ?? artwork.author
        guard let id = record?.authorID ?? asset?.authorID ?? artwork.authorID
            ?? (artwork.source == .wallhaven ? name : nil), !id.isEmpty else { return nil }
        return .init(source: artwork.source, id: id, name: name)
    }
    private func retire() {
        isRetired = true; loadID = UUID(); previewID = UUID()
        detailTask?.cancel(); detailTask = nil; previewTask?.cancel(); previewTask = nil
        localCancellation?.cancel(); localCancellation = nil; lastPreviewKey = nil
        subscriptions.removeAll()
        sessionSubscription = nil; observedScope = nil
    }
}
