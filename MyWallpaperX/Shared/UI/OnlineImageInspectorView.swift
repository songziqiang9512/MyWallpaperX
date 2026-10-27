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
    private var pageIndex: Int
    private var assets: [OnlineImageAsset] = []
    private var boundActions: (WallpaperReference, WallpaperInspectorActions)?
    private let preview = SILInspectorPreviewSurfaceView(image: nil)
    private let content = SILInspectorViews.makeVerticalStack(spacing: 16)
    private let titleLabel = SILInspectorViews.makeLabel("", font: .systemFont(ofSize: 19, weight: .semibold), color: .labelColor)
    private let facts = SILInspectorViews.makeVerticalStack(spacing: 12)
    private let notice = SILInspectorViews.makeLabel("", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
    private let pageLabel = NSTextField(labelWithString: "")
    private let authorButton = SILInspectorViews.makeFooterButton(title: "作者信息暂缺", symbolName: "person.crop.circle", target: nil, action: #selector(openAuthor))
    private let favoriteButton = SILInspectorViews.makeFooterButton(title: "", symbolName: "heart", target: nil, action: #selector(toggleFavorite))
    private let previousButton = SILInspectorViews.makeFooterButton(title: "", symbolName: "chevron.left", target: nil, action: #selector(previousPage))
    private let nextButton = SILInspectorViews.makeFooterButton(title: "", symbolName: "chevron.right", target: nil, action: #selector(nextPage))
    private let downloadButton = SILInspectorViews.makeFooterButton(title: "下载当前图片", symbolName: "arrow.down.to.line", target: nil, action: #selector(downloadCurrent))
    private let applyButton = SILInspectorViews.makeFooterButton(title: "下载并设为壁纸", symbolName: "photo.fill", target: nil, action: #selector(applyCurrent), kind: .primary)
    private let sourceButton = SILInspectorViews.makeFooterButton(title: "", symbolName: "safari", target: nil, action: #selector(openSource))
    private let playlistButton = SILInspectorViews.makeFooterButton(title: "", symbolName: "tag", target: nil, action: #selector(choosePlaylist))
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
        let canDownload: Bool
        let switching: Bool
        let applied: Bool
        let canApply: Bool
        let canOrganize: Bool
        let canFavorite: Bool
        let favorite: Bool
    }

    init(artwork: OnlineImageArtwork, library: OnlineImageLibrary,
         makeLibraryActions: @escaping (WallpaperReference) -> WallpaperInspectorActions?,
         onAuthor: ((OnlineImageAuthor) -> Void)? = nil, initialPageIndex: Int = 0) {
        self.artwork = artwork; self.library = library
        self.makeLibraryActions = makeLibraryActions; self.onAuthor = onAuthor
        pageIndex = max(0, initialPageIndex)
        initialReference = OnlineImageAssetID(source: artwork.source, artworkID: artwork.artworkID, pageIndex: max(0, initialPageIndex)).reference
        super.init(frame: .zero)
        setup()
        observeLibrary()
        refreshContent()
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
                isRetired = false; observeLibrary(); loadPreview(); resolveDetails()
            }
        } else if hasMounted { retire() }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        let root = SILInspectorViews.makeVerticalStack(spacing: 12)
        root.alignment = .leading
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
        favoriteButton.target = self; favoriteButton.action = #selector(toggleFavorite)
        favoriteButton.setAccessibilityLabel("特别喜爱")
        favoriteButton.toolTip = "特别喜爱"
        let authorRow = NSStackView(views: [authorButton, favoriteButton])
        authorRow.spacing = 8
        let pager = NSStackView(views: [previousButton, NSView(), pageLabel, NSView(), nextButton])
        pager.spacing = 8
        previousButton.target = self; previousButton.action = #selector(previousPage)
        nextButton.target = self; nextButton.action = #selector(nextPage)
        previousButton.setAccessibilityLabel("上一张"); previousButton.toolTip = "上一张"
        nextButton.setAccessibilityLabel("下一张"); nextButton.toolTip = "下一张"
        pageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        pageLabel.textColor = .secondaryLabelColor
        notice.maximumNumberOfLines = 0
        downloadButton.target = self
        applyButton.target = self; sourceButton.target = self; playlistButton.target = self
        sourceButton.setAccessibilityLabel("在浏览器打开作品"); sourceButton.toolTip = "在浏览器打开作品"
        playlistButton.setAccessibilityLabel("添加到列表"); playlistButton.toolTip = "添加到列表"
        for section in [preview, titleLabel, authorRow, pager, facts, notice, downloadButton] as [NSView] {
            content.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        preview.heightAnchor.constraint(equalToConstant: 156).isActive = true
        let footer = NSStackView(views: [applyButton, sourceButton, playlistButton])
        footer.orientation = .horizontal; footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        root.addArrangedSubview(scroll); root.addArrangedSubview(footer)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor), root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor), root.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor), footer.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),
            sourceButton.widthAnchor.constraint(equalToConstant: InspectorFooterMetrics.iconWidth),
            playlistButton.widthAnchor.constraint(equalToConstant: InspectorFooterMetrics.iconWidth),
            favoriteButton.widthAnchor.constraint(equalToConstant: InspectorFooterMetrics.iconWidth),
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
        library.$snapshot.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, !isRetired else { return }
            refreshContent(); loadPreview()
        }.store(in: &subscriptions)
        library.$progress.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateControls() }.store(in: &subscriptions)
        observeSession()
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
            artwork = OnlineImageArtwork(source: .pixiv, artworkID: artwork.artworkID,
                title: "Pixiv #\(artwork.artworkID)", sourceURL: artwork.sourceURL)
            errorText = "账号会话已变化，请关闭详情后重新打开。"
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
        let author = record?.author ?? asset?.author ?? artwork.author
        authorButton.setTitle(author ?? "作者信息暂缺")
        authorButton.isEnabled = onAuthor != nil && resolvedAuthor != nil
        let indices = pageIndices
        let position = indices.firstIndex(of: pageIndex) ?? 0
        previousButton.isEnabled = position > 0
        nextButton.isEnabled = position + 1 < indices.count
        previousButton.isHidden = indices.count < 2; nextButton.isHidden = indices.count < 2
        pageLabel.stringValue = assets.contains(where: { $0.id == assetID })
            ? "第\(pageIndex + 1) / 共\(assets.count)张" : "第\(pageIndex + 1)张\(record == nil ? "" : " · 本地图片")"
        facts.arrangedSubviews.forEach { facts.removeArrangedSubview($0); $0.removeFromSuperview() }
        var values: [(String, String)] = [("来源", artwork.source.displayName)]
        if let width = record?.pixelWidth ?? asset?.width ?? (pageIndex == 0 ? artwork.width : nil),
           let height = record?.pixelHeight ?? asset?.height ?? (pageIndex == 0 ? artwork.height : nil) { values.append(("分辨率", "\(width) × \(height)")) }
        if let bytes = record?.fileSizeBytes ?? asset?.expectedBytes ?? (pageIndex == 0 ? artwork.fileSizeBytes : nil) {
            values.append(("文件大小", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
        }
        let rating: String
        switch artwork.rating { case .safe: rating = "全年龄"; case .sensitive: rating = "可能含敏感内容"; case .adult: rating = "年龄限制"; case .unknown: rating = "暂未确认" }
        values.append(("内容分级", rating))
        let grid = SILInspectorViews.makeFactsGrid(values)
        facts.addArrangedSubview(grid); grid.widthAnchor.constraint(equalTo: facts.widthAnchor).isActive = true
        let tags = record?.tags ?? asset?.tags ?? artwork.tags
        if !tags.isEmpty {
            let tagsLabel = SILInspectorViews.makeLabel(tags.joined(separator: " · "), font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
            tagsLabel.maximumNumberOfLines = 4
            facts.addArrangedSubview(tagsLabel)
            tagsLabel.widthAnchor.constraint(equalTo: facts.widthAnchor).isActive = true
        }
        if let fresh = makeLibraryActions(assetID.reference) { boundActions = (assetID.reference, fresh) }
        else { boundActions = nil }
        if let errorText { notice.stringValue = "\(errorText)\(isLocalAvailable ? " 已下载图片仍可使用。" : "")" }
        else if !isLocalAvailable, artwork.kind == .animation { notice.stringValue = "动图暂不支持下载或应用，可打开原站查看。" }
        else if !isLocalAvailable, artwork.kind == .unknown, !isResolving { notice.stringValue = "作品类型尚未确认，暂不支持下载或应用。" }
        else if !isLocalAvailable, artwork.isMasked == true { notice.stringValue = "此作品受当前站内显示权限限制，请打开原站检查设置。" }
        else { notice.stringValue = isResolving ? "正在获取作品详情…" : "" }
        notice.isHidden = notice.stringValue.isEmpty
        updateControls()
    }

    private func updateControls() {
        guard !isRetired else { return }
        let progress = library.progress[assetID]
        let local = isLocalAvailable
        let canDownload = currentAsset != nil && artwork.kind == .image && artwork.isMasked != true
        let actions = currentActions?.state
        let switching = actions?.isSwitching == true
        let state = ControlState(local: local, downloading: progress != nil, canDownload: canDownload,
            switching: switching, applied: actions?.isPlaying == true,
            canApply: !switching && (local ? actions?.canPerformPrimary == true : canDownload && progress == nil),
            canOrganize: local && actions?.canOrganize == true, canFavorite: local && actions?.canFavorite == true,
            favorite: actions?.isFavorite == true)
        if renderedProgress != progress { renderedProgress = progress; downloadButton.setProgressFill(progress) }
        guard state != renderedControls else { return }
        renderedControls = state
        downloadButton.setTitle(progress != nil ? "取消下载" : local ? "查看图片文件" : "下载当前图片")
        downloadButton.setSymbol(progress != nil ? "xmark" : local ? "folder" : "arrow.down.to.line", accessibilityDescription: nil)
        downloadButton.isEnabled = progress != nil || local || canDownload
        applyButton.setTitle(switching ? "正在切换壁纸" : local ? state.applied ? "已应用" : "设为壁纸" : "下载并设为壁纸")
        applyButton.setSymbol(switching ? "hourglass" : "photo.fill", accessibilityDescription: nil)
        applyButton.isEnabled = state.canApply
        playlistButton.isEnabled = state.canOrganize
        favoriteButton.isEnabled = state.canFavorite
        favoriteButton.setSymbol(state.favorite ? "heart.fill" : "heart", accessibilityDescription: nil)
        favoriteButton.setAccessibilityLabel(state.favorite ? "取消特别喜爱" : "特别喜爱")
        favoriteButton.toolTip = state.favorite ? "取消特别喜爱" : "特别喜爱"
    }

    private func loadPreview() {
        guard !isRetired else { return }
        let id = assetID
        let local = isLocalAvailable ? currentRecord.flatMap(library.localURL(for:)) : nil
        let remote = currentAsset?.previewURL ?? (pageIndex == 0 ? artwork.previewURL ?? artwork.thumbnailURL : nil)
        let key = local.map { "local:\($0.path):\(currentRecord?.revision.uuidString ?? "")" }
            ?? remote.map { "remote:\(artwork.source == .pixiv ? library.pixivScope : "public"):\($0.absoluteString)" }
        guard key != lastPreviewKey || displayedPage != id else { return }
        lastPreviewKey = key
        previewTask?.cancel(); previewTask = nil; localCancellation?.cancel(); localCancellation = nil
        let token = UUID(); previewID = token
        if displayedPage != id { preview.updateImage(nil); displayedPage = id }
        if let local {
            let cancellation = ThumbnailCacheRequestCancellation(); localCancellation = cancellation
            localThumbnails.load(path: local.path, cancellation: cancellation) { [weak self] result in
                guard let self, !isRetired, previewID == token, assetID == id, !cancellation.cancelled else { return }
                localCancellation = nil
                if case .image(let image) = result { preview.updateImage(image) }
            }
        } else if let remote {
            let request = library.thumbnailRequest(url: remote, source: artwork.source)
            for pixels in [800, 512, 256, 1200] {
                if let image = OLThumbnailCache.shared.readyImage(for: request, maxPixelSize: pixels) { preview.updateImage(image); return }
            }
            previewTask = Task { [weak self] in
                let image = await OLThumbnailCache.shared.image(for: request, maxPixelSize: 800, priority: .visible)
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
    @objc private func downloadCurrent() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
        if library.progress[assetID] != nil { library.cancel(assetID) }
        else if isLocalAvailable, let record = currentRecord, let url = library.localURL(for: record) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else if artwork.kind == .image, artwork.isMasked != true, let asset = currentAsset { library.download(asset) }
    }
    @objc private func applyCurrent() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: window) else { return }
        if isLocalAvailable, let actions = makeLibraryActions(assetID.reference),
           !actions.state.isSwitching, actions.state.canPerformPrimary { actions.onPrimary() }
        else if !isLocalAvailable, library.progress[assetID] == nil, artwork.kind == .image, artwork.isMasked != true, let asset = currentAsset { library.download(asset, apply: true) }
    }
    @objc private func choosePlaylist() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: window), isLocalAvailable,
              let actions = makeLibraryActions(assetID.reference), actions.state.canOrganize else { return }
        actions.onChoosePlaylist(playlistButton)
    }
    @objc private func toggleFavorite() {
        guard WallpaperLibrarySheetPresentation.permitsInput(in: window), isLocalAvailable,
              let actions = makeLibraryActions(assetID.reference), actions.state.canFavorite else { return }
        actions.onToggleFavorite()
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
        let name = currentRecord?.author ?? currentAsset?.author ?? artwork.author
        guard let id = currentRecord?.authorID ?? currentAsset?.authorID ?? artwork.authorID
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
