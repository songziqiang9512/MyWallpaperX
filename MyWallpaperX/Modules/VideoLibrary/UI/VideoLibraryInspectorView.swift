//
//  VideoLibraryInspectorView.swift
//  MyWallpaperX
//

import AppKit
import Combine

final class VideoLibraryInspectorView: NSView {
    private let wallpaperID: String
    private let initialWallpaper: VideoWallpaper
    private let wallpaperManager: WallpaperManager
    private var details: WallpaperInspectorDetails?
    private var loadingTask: Task<Void, Never>?
    private var loadedDetailsPath: String?
    private var contentStack: NSStackView?
    private weak var favoriteButton: InspectorFooterButton?
    private weak var setAsWallpaperButton: InspectorFooterButton?
    private var cancellables = Set<AnyCancellable>()
    private var libraryActions: WallpaperInspectorActions
    private weak var playlistButton: InspectorFooterButton?
    private var titleField: NSTextField?
    private var summaryField: NSTextField?
    private var pathField: NSTextField?
    private var metadataSection: NSStackView?
    private var metadataFields: [(label: String, value: NSTextField)] = []
    private var playlistSection: NSStackView?
    private var noticeSection: NSView?

    private var currentWallpaper: VideoWallpaper {
        wallpaperManager.wallpapers.first { $0.id.utf8.elementsEqual(wallpaperID.utf8) } ?? initialWallpaper
    }

    init(wallpaper: VideoWallpaper, wallpaperManager: WallpaperManager, libraryActions: WallpaperInspectorActions) {
        self.libraryActions = libraryActions
        self.wallpaperID = wallpaper.id
        self.initialWallpaper = wallpaper
        self.wallpaperManager = wallpaperManager
        super.init(frame: .zero)
        setup()
        observeManager()
        loadDetails(for: currentWallpaper)
        refreshFooterActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        loadingTask?.cancel()
        previewCancellation?.cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            hasMounted = true
            let wallpaper = currentWallpaper
            loadPreviewImage(for: wallpaper)
            if loadingTask == nil,
               details?.isLoading != false || loadedDetailsPath != wallpaper.path { loadDetails(for: wallpaper) }
        } else if hasMounted {
            loadingTask?.cancel()
            loadingTask = nil
            previewCancellation?.cancel()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        loadPreviewImage()
    }

    /// 预览图异步加载：走 VideoLibraryThumbnailStore 共享缓存（后台解码、主线程补图），
    /// 不再在主线程同步 NSImage(contentsOfFile:) 整图解码。
    private let previewSurface = VideoLibraryInspectorPreviewSurfaceView(image: nil)
    private lazy var previewHeightConstraint = previewSurface.heightAnchor.constraint(equalToConstant: 156)
    /// One consumer lease covers path resolution, queued decode and main-thread
    /// delivery. Replacing or removing the view cancels only this consumer.
    private var previewCancellation: ThumbnailCacheRequestCancellation?
    private var hasMounted = false
    /// 上一次预览加载的资产身份：$wallpapers 的无关 publish（收藏切换等）不重复触发磁盘解码。
    private var lastPreviewLoadIdentity: PreviewAssetIdentity?
    private var previewRequest: ThumbnailRequest?
    private lazy var previewThumbnails = AppKitThumbnailProvider(wallpaperManager: wallpaperManager)

    /// 预览资产的解析输入身份：源路径 + 两个派生资产路径。
    private struct PreviewAssetIdentity: Equatable {
        let path: String
        let thumbnailPath: String?
        let staticFramePath: String?
    }

    private func loadPreviewImage(for wallpaper: VideoWallpaper? = nil) {
        guard let window, let request = ThumbnailRequest(size: previewSurface.bounds.size,
            scale: window.backingScaleFactor, mode: .fill) else { return }
        let wallpaper = wallpaper ?? currentWallpaper
        let identity = PreviewAssetIdentity(path: wallpaper.path,
            thumbnailPath: wallpaper.thumbnailPath, staticFramePath: wallpaper.staticFramePath)
        guard identity != lastPreviewLoadIdentity || previewRequest != request || previewCancellation?.cancelled == true else { return }
        previewCancellation?.cancel()
        if let previous = lastPreviewLoadIdentity, previous.path != identity.path { previewSurface.updateImage(nil, missing: false) }
        lastPreviewLoadIdentity = identity; previewRequest = request
        previewCancellation = previewThumbnails.loadThumbnail(for: wallpaper, request: request,
            fallbackImagePath: wallpaper.staticFramePath) { [weak self] image in
                self?.previewCancellation = nil
                self?.previewSurface.updateImage(image, missing: image == nil)
            }
    }

    private var secondaryFactText: String? {
        guard let details else { return nil }
        return [details.fileSizeText, details.formatText, details.durationText]
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
            .nilIfEmpty
    }

    private var metadataFacts: [(String, String)] {
        guard let details else { return [] }
        return [
            ("编解码器", details.codecText),
            ("分辨率", details.resolutionText),
            ("添加时间", details.addedDateText)
        ].filter { !$0.1.isEmpty }
    }

    private func setup() {
        previewSurface.onSizeChange = { [weak self] in self?.loadPreviewImage() }
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = InspectorFadingScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = makeContentStack()
        self.contentStack = contentStack
        let documentContainer = InspectorContentDocumentView()
        documentContainer.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(contentStack)
        scrollView.documentView = documentContainer

        let footerActions = makeFooterActions()

        addSubview(rootStack)
        rootStack.addArrangedSubview(scrollView)
        rootStack.addArrangedSubview(footerActions)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            documentContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentContainer.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentContainer.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: documentContainer.bottomAnchor),
            footerActions.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    private func observeManager() {
        wallpaperManager.$wallpapers
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // 派生图片补齐或清空也会发布模型，视频源路径可以保持不变。
                let wallpaper = self.currentWallpaper
                self.loadPreviewImage(for: wallpaper)
                if self.loadedDetailsPath != nil,
                   self.loadedDetailsPath != wallpaper.path {
                    self.loadDetails(for: wallpaper)
                } else {
                    self.refreshContent(for: wallpaper)
                }
            }
            .store(in: &cancellables)
        // 缩略图生成完成不必然伴随库内容 publish——generateThumbnail 只写磁盘与
        // 路径索引，模型 thumbnailPath 可能为 nil（WallpaperManager+CachePipeline）。
        // 与网格（AppKitLibraryGridView）同一刷新通道：按标准化路径过滤后重载预览，
        // resolvedThumbnailPath 每次重新解析磁盘，补齐后的文件可直接命中。
        wallpaperManager.thumbnailReadyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changedPath in
                guard let self, self.window != nil, self.previewCancellation == nil else { return }
                let wallpaper = self.currentWallpaper
                guard self.wallpaperManager.normalizedPath(wallpaper.path) == changedPath else { return }
                self.previewRequest = nil
                self.loadPreviewImage(for: wallpaper)
            }
            .store(in: &cancellables)
    }

    private func makeContentStack() -> NSStackView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 16)
        stack.edgeInsets = NSEdgeInsets(top: InspectorFadingScrollView.contentTopInset, left: 2, bottom: 0, right: 2)
        return stack
    }

    private func refreshContent(for wallpaper: VideoWallpaper) {
        guard let details else { return }
        let sourceMissing = !FileManager.default.fileExists(atPath: wallpaper.path)
        if titleField == nil {
            addContentSection(makePreviewSection(for: wallpaper))
            addContentSection(makeContentSection())
            addContentSection(makeTagsSection())
            addContentSection(makeFileLocationSection(for: wallpaper))
            addContentSection(makeNoticeSection(missing: sourceMissing))
            return
        }

        updateText(wallpaper.displayTitle, in: titleField)
        let summary = secondaryFactText
        updateText(summary ?? "", in: summaryField)
        if summaryField?.isHidden != (summary == nil) { summaryField?.isHidden = summary == nil }
        updateText(details.pathText, in: pathField)
        updateMetadataFacts()
        if noticeSection?.isHidden != !sourceMissing { noticeSection?.isHidden = !sourceMissing }
    }

    private func updateText(_ text: String, in field: NSTextField?) {
        if field?.stringValue != text { field?.stringValue = text }
    }

    private func updateMetadataFacts() {
        guard let metadataSection else { return }
        let facts = metadataFacts
        if metadataFields.count != facts.count || zip(metadataFields, facts).contains(where: { $0.0.label != $0.1.0 }) {
            metadataSection.arrangedSubviews.last?.removeFromSuperview()
            metadataSection.addArrangedSubview(makeMetadataGrid(facts))
            return
        }
        for (binding, fact) in zip(metadataFields, facts) {
            updateText(fact.1, in: binding.value)
        }
    }

    private func makeMetadataGrid(_ facts: [(String, String)]) -> NSView {
        metadataFields.removeAll(keepingCapacity: true)
        return WallpaperLibraryControlStyle.inspectorFacts(facts) { label, value in
            self.metadataFields.append((label, value))
        }
    }

    private func addContentSection(_ section: NSView) {
        guard let contentStack else { return }
        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func makePreviewSection(for wallpaper: VideoWallpaper) -> NSView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 8)

        let preview = previewSurface
        stack.addArrangedSubview(preview)
        previewHeightConstraint.isActive = true
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let title = VideoLibraryInspectorViews.makeLabel(
            wallpaper.displayTitle,
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: .labelColor
        )
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(title)
        titleField = title

        let summary = secondaryFactText
        let facts = VideoLibraryInspectorViews.makeLabel(
            summary ?? "",
            font: .systemFont(ofSize: 11, weight: .medium),
            color: .secondaryLabelColor
        )
        facts.maximumNumberOfLines = 2
        stack.addArrangedSubview(facts)
        facts.isHidden = summary == nil
        summaryField = facts

        return stack
    }

    private func makeContentSection() -> NSView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 14)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeSectionTitle("原数据"))
        stack.addArrangedSubview(makeMetadataGrid(metadataFacts))
        metadataSection = stack
        return stack
    }

    private func makeTagsSection() -> NSView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 14)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeSectionTitle("播放列表"))
        stack.addArrangedSubview(makePlaylistContent())
        playlistSection = stack
        return stack
    }

    private func refreshPlaylistContent() {
        guard let playlistSection else { return }
        playlistSection.arrangedSubviews.last?.removeFromSuperview()
        playlistSection.addArrangedSubview(makePlaylistContent())
    }

    private func makePlaylistContent() -> NSView {
        let names = libraryActions.state.playlistNames
        if names.isEmpty {
            return VideoLibraryInspectorViews.makeLabel("当前未加入任何播放列表", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        }
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        names.forEach { row.addArrangedSubview(InspectorBadgeView(text: $0, truncatesText: true)) }
        return row
    }

    private func makeFileLocationSection(for wallpaper: VideoWallpaper) -> NSView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 14)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeSectionTitle("文件位置"))

        let path = VideoLibraryInspectorViews.makeLabel(
            details?.pathText ?? wallpaper.path,
            font: .systemFont(ofSize: 13),
            color: .labelColor
        )
        path.maximumNumberOfLines = 3
        path.lineBreakMode = .byTruncatingMiddle
        path.allowsExpansionToolTips = true
        path.isSelectable = true
        stack.addArrangedSubview(path)
        pathField = path

        return stack
    }

    private func makeNoticeSection(missing: Bool) -> NSView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 8)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeNotice(
            icon: "exclamationmark.triangle.fill", text: "源文件不存在，详情信息可能不是最新状态"))
        stack.isHidden = !missing
        noticeSection = stack
        return stack
    }

    private func makeFooterActions() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        let setButton = VideoLibraryInspectorViews.makeFooterButton(
            title: "设为壁纸",
            symbolName: "photo.fill",
            target: self,
            action: #selector(setAsWallpaper),
            kind: .primary
        )
        self.setAsWallpaperButton = setButton
        let revealButton = VideoLibraryInspectorViews.makeFooterButton(
            title: "查看文件",
            symbolName: "folder.fill",
            target: self,
            action: #selector(revealInFinder)
        )
        let favoriteButton = VideoLibraryInspectorViews.makeIconButton(
            symbolName: libraryActions.state.isFavorite ? "heart.fill" : "heart",
            title: libraryActions.state.isFavorite ? "取消特别喜爱" : "特别喜爱",
            target: self,
            action: #selector(toggleFavorite)
        )
        self.favoriteButton = favoriteButton
        let tagButton = VideoLibraryInspectorViews.makeIconButton(
            symbolName: "tag",
            title: "添加到列表",
            target: self,
            action: #selector(presentTagPicker)
        )
        self.playlistButton = tagButton

        let textGroup = NSView()
        textGroup.translatesAutoresizingMaskIntoConstraints = false
        textGroup.addSubview(setButton)
        textGroup.addSubview(revealButton)

        let iconGroup = NSView()
        iconGroup.translatesAutoresizingMaskIntoConstraints = false
        iconGroup.addSubview(favoriteButton)
        iconGroup.addSubview(tagButton)

        stack.addArrangedSubview(textGroup)
        stack.addArrangedSubview(iconGroup)

        [setButton, revealButton].forEach {
            $0.setContentHuggingPriority(.defaultLow, for: .horizontal)
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        [favoriteButton, tagButton].forEach {
            $0.setContentHuggingPriority(.required, for: .horizontal)
            $0.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        [setButton, revealButton, favoriteButton, tagButton].forEach {
            $0.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height).isActive = true
        }
        [favoriteButton, tagButton].forEach {
            $0.widthAnchor.constraint(equalToConstant: InspectorFooterMetrics.iconWidth).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),
            textGroup.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 2),
            textGroup.topAnchor.constraint(equalTo: stack.topAnchor),
            textGroup.bottomAnchor.constraint(equalTo: stack.bottomAnchor),

            setButton.leadingAnchor.constraint(equalTo: textGroup.leadingAnchor),
            setButton.topAnchor.constraint(equalTo: textGroup.topAnchor),
            setButton.bottomAnchor.constraint(equalTo: textGroup.bottomAnchor),

            revealButton.leadingAnchor.constraint(equalTo: setButton.trailingAnchor, constant: 6),
            revealButton.trailingAnchor.constraint(equalTo: textGroup.trailingAnchor),
            revealButton.topAnchor.constraint(equalTo: textGroup.topAnchor),
            revealButton.bottomAnchor.constraint(equalTo: textGroup.bottomAnchor),
            setButton.widthAnchor.constraint(equalTo: revealButton.widthAnchor),

            iconGroup.leadingAnchor.constraint(equalTo: textGroup.trailingAnchor, constant: 6),
            iconGroup.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -2),
            iconGroup.topAnchor.constraint(equalTo: stack.topAnchor),
            iconGroup.bottomAnchor.constraint(equalTo: stack.bottomAnchor),

            favoriteButton.leadingAnchor.constraint(equalTo: iconGroup.leadingAnchor),
            favoriteButton.topAnchor.constraint(equalTo: iconGroup.topAnchor),
            favoriteButton.bottomAnchor.constraint(equalTo: iconGroup.bottomAnchor),

            tagButton.leadingAnchor.constraint(equalTo: favoriteButton.trailingAnchor, constant: 6),
            tagButton.trailingAnchor.constraint(equalTo: iconGroup.trailingAnchor),
            tagButton.topAnchor.constraint(equalTo: iconGroup.topAnchor),
            tagButton.bottomAnchor.constraint(equalTo: iconGroup.bottomAnchor)
        ])

        return stack
    }

    func updateLibraryActions(_ actions: WallpaperInspectorActions) {
        let changed = libraryActions.state != actions.state
        let playlistsChanged = libraryActions.state.playlistNames != actions.state.playlistNames
        libraryActions = actions
        if playlistsChanged { refreshPlaylistContent() }
        if changed { refreshContent(for: currentWallpaper) }
        refreshFooterActions()
    }

    private func refreshFooterActions() {
        let favorite = libraryActions.state.isFavorite
        let title = favorite ? "取消特别喜爱" : "特别喜爱"
        favoriteButton?.setSymbol(
            favorite ? "heart.fill" : "heart",
            accessibilityDescription: title
        )
        favoriteButton?.toolTip = title
        favoriteButton?.setAccessibilityLabel(title)
        // 设为壁纸/停止播放互斥：当前正在播放这张壁纸时按钮切换为停止形态
        // （与卡片徽章同一互斥语义）。
        let isPlaying = libraryActions.state.isPlaying
        favoriteButton?.isEnabled = libraryActions.state.canFavorite
        playlistButton?.isEnabled = libraryActions.state.canOrganize
        setAsWallpaperButton?.isEnabled = libraryActions.state.canPerformPrimary
        setAsWallpaperButton?.setTitle(isPlaying ? "停止播放" : "设为壁纸")
        setAsWallpaperButton?.setSymbol(
            isPlaying ? "stop.fill" : "photo.fill",
            accessibilityDescription: isPlaying ? "停止播放" : "设为壁纸"
        )
    }

    private func loadDetails(for wallpaper: VideoWallpaper) {
        guard !hasMounted || window != nil else { return }
        loadingTask?.cancel()
        details = nil
        loadedDetailsPath = nil
        loadedDetailsPath = wallpaper.path
        loadingTask = loadWallpaperInspectorDetails(for: wallpaper) { [weak self] loadedDetails in
            guard let self else { return }
            // The placeholder is synchronous; final values may follow a model publication.
            let current = self.details == nil ? wallpaper : self.currentWallpaper
            self.details = loadedDetails
            self.refreshContent(for: current)
        }
    }

    @objc private func setAsWallpaper() {
        guard libraryActions.state.canPerformPrimary else { return }
        libraryActions.onPrimary()
    }

    @objc private func revealInFinder() {
        FinderRevealCoordinator.shared.reveal([URL(fileURLWithPath: currentWallpaper.path)])
    }

    @objc private func toggleFavorite() {
        guard libraryActions.state.canFavorite else { return }
        libraryActions.onToggleFavorite()
    }

    @objc private func presentTagPicker() {
        guard libraryActions.state.canOrganize else { return }
        libraryActions.onChoosePlaylist(playlistButton)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
