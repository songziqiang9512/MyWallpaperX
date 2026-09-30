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
    private var cancellables = Set<AnyCancellable>()

    private var currentWallpaper: VideoWallpaper {
        wallpaperManager.wallpapers.first { $0.id == wallpaperID } ?? initialWallpaper
    }

    init(wallpaper: VideoWallpaper, wallpaperManager: WallpaperManager) {
        self.wallpaperID = wallpaper.id
        self.initialWallpaper = wallpaper
        self.wallpaperManager = wallpaperManager
        super.init(frame: .zero)
        setup()
        observeManager()
        loadDetails()
        loadPreviewImage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        loadingTask?.cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            loadingTask?.cancel()
            loadingTask = nil
        }
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: currentWallpaper.path)
    }

    /// 预览图异步加载：走 VideoLibraryThumbnailStore 共享缓存（后台解码、主线程补图），
    /// 不再在主线程同步 NSImage(contentsOfFile:) 整图解码。
    private var previewImage: NSImage?
    /// 预览加载完成后才允许展示「未找到缩略图」提示，加载中的占位不算缺失
    private var hasFinishedPreviewLoad = false

    private func loadPreviewImage() {
        let manager = wallpaperManager
        let wallpaper = currentWallpaper
        weak let weakSelf = self
        // 路径解析含文件存在性 stat，放后台执行
        DispatchQueue.global(qos: .userInitiated).async {
            let thumbPath = manager.resolvedThumbnailPath(for: wallpaper)
            // 缩略图缺失时回退静帧；降采样解码结果用独立键，避免同键不同解码形状互覆
            var staticFramePath: String?
            if thumbPath == nil,
               let path = wallpaper.staticFramePath,
               FileManager.default.fileExists(atPath: path) {
                staticFramePath = path
            }
            guard let sourcePath = thumbPath ?? staticFramePath else {
                DispatchQueue.main.async {
                    weakSelf?.hasFinishedPreviewLoad = true
                    weakSelf?.rebuildContent()
                }
                return
            }
            let isStaticFrameFallback = thumbPath == nil
            let key = isStaticFrameFallback
                ? "inspector-static-frame:\(sourcePath)"
                : sourcePath
            VideoLibraryThumbnailStore.sharedCache.load(forKey: key, loader: {
                // 与网格共用缩略图路径键；静帧回退按预览所需尺寸降采样解码
                isStaticFrameFallback
                    ? Self.downscaledPreviewImage(from: sourcePath)
                    : NSImage(contentsOfFile: sourcePath)
            }, completion: { image in
                // ThumbnailCache 内存命中会在调用线程同步回调，统一收敛回主线程。
                DispatchQueue.main.async {
                    weakSelf?.previewImage = image
                    weakSelf?.hasFinishedPreviewLoad = true
                    weakSelf?.rebuildContent()
                }
            })
        }
    }

    /// Inspector 预览高度仅 156pt；静帧原图按 4096px 上限生成（WallpaperManager+StaticFramePipeline），
    /// 整图直接解码最坏 ~67MB，这里按 800px 上限在后台降采样
    /// （模式同 SteamWorkshopPreviewImageSupport 的网格解码上限）。
    private static func downscaledPreviewImage(from path: String, maxPixelSize: Int = 800) -> NSImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
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

    private var noticeItems: [(icon: String, text: String)] {
        var items: [(icon: String, text: String)] = []
        if !fileExists {
            items.append(("exclamationmark.triangle.fill", "源文件不存在，详情信息可能不是最新状态"))
        }
        if hasFinishedPreviewLoad, previewImage == nil {
            items.append(("photo.on.rectangle.angled", "当前未找到缩略图，正在使用占位预览"))
        }
        return items
    }

    private func setup() {
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
        rebuildContent()
        let documentContainer = NSView()
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
            contentStack.centerYAnchor.constraint(equalTo: documentContainer.centerYAnchor),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: documentContainer.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: documentContainer.bottomAnchor),
            footerActions.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    private func observeManager() {
        wallpaperManager.$wallpapers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.loadedDetailsPath != nil,
                   self.loadedDetailsPath != self.currentWallpaper.path {
                    self.loadDetails()
                } else {
                    self.rebuildContent()
                    self.refreshFooterActions()
                }
            }
            .store(in: &cancellables)
    }

    private func makeContentStack() -> NSStackView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 16)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        return stack
    }

    private func rebuildContent() {
        guard let contentStack else { return }
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        addContentSection(makePreviewSection())
        addContentSection(makeContentSection())
        addContentSection(makeTagsSection())
        if details != nil {
            addContentSection(makeFileLocationSection())
        }
        if !noticeItems.isEmpty {
            addContentSection(makeNoticeSection())
        }
    }

    private func addContentSection(_ section: NSView) {
        guard let contentStack else { return }
        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func makePreviewSection() -> NSView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 8)

        let preview = VideoLibraryInspectorPreviewSurfaceView(image: previewImage)
        stack.addArrangedSubview(preview)
        NSLayoutConstraint.activate([
            preview.heightAnchor.constraint(equalToConstant: 156),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        let title = VideoLibraryInspectorViews.makeLabel(
            currentWallpaper.displayTitle,
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: .labelColor
        )
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(title)

        if let secondaryFactText {
            let facts = VideoLibraryInspectorViews.makeLabel(
                secondaryFactText,
                font: .systemFont(ofSize: 11, weight: .medium),
                color: .secondaryLabelColor
            )
            facts.maximumNumberOfLines = 2
            stack.addArrangedSubview(facts)
        }

        return stack
    }

    private func makeContentSection() -> NSView {
        if details == nil {
            return VideoLibraryInspectorViews.makeLoadingView("正在读取文件信息…")
        }

        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 14)
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeDivider())
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeSectionTitle("原数据"))
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeFactsGrid(metadataFacts))
        return stack
    }

    private func makeTagsSection() -> NSView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 14)
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeDivider())
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeSectionTitle("标签"))

        if currentWallpaper.tags.isEmpty {
            stack.addArrangedSubview(
                VideoLibraryInspectorViews.makeLabel("当前未加入任何标签", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
            )
        } else {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            currentWallpaper.tags.forEach { row.addArrangedSubview(VideoLibraryInspectorViews.makeBadge($0)) }
            stack.addArrangedSubview(row)
        }

        return stack
    }

    private func makeFileLocationSection() -> NSView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 14)
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeDivider())
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeSectionTitle("文件位置"))

        let path = VideoLibraryInspectorViews.makeLabel(
            details?.pathText ?? currentWallpaper.path,
            font: .systemFont(ofSize: 13),
            color: .labelColor
        )
        path.maximumNumberOfLines = 3
        path.lineBreakMode = .byTruncatingMiddle
        path.allowsExpansionToolTips = true
        path.isSelectable = true
        stack.addArrangedSubview(path)

        return stack
    }

    private func makeNoticeSection() -> NSView {
        let stack = VideoLibraryInspectorViews.makeVerticalStack(spacing: 8)
        stack.addArrangedSubview(VideoLibraryInspectorViews.makeDivider())
        noticeItems.forEach { item in
            stack.addArrangedSubview(VideoLibraryInspectorViews.makeNotice(icon: item.icon, text: item.text))
        }
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
        let revealButton = VideoLibraryInspectorViews.makeFooterButton(
            title: "查看文件",
            symbolName: "folder.fill",
            target: self,
            action: #selector(revealInFinder)
        )
        let favoriteButton = VideoLibraryInspectorViews.makeIconButton(
            symbolName: currentWallpaper.isFavorite ? "heart.fill" : "heart",
            title: currentWallpaper.isFavorite ? "取消收藏" : "收藏",
            target: self,
            action: #selector(toggleFavorite)
        )
        self.favoriteButton = favoriteButton
        let tagButton = VideoLibraryInspectorViews.makeIconButton(
            symbolName: "tag",
            title: "添加标签",
            target: self,
            action: #selector(presentTagPicker)
        )

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

    private func refreshFooterActions() {
        let title = currentWallpaper.isFavorite ? "取消收藏" : "收藏"
        favoriteButton?.setSymbol(
            currentWallpaper.isFavorite ? "heart.fill" : "heart",
            accessibilityDescription: title
        )
        favoriteButton?.toolTip = title
        favoriteButton?.setAccessibilityLabel(title)
    }

    private func loadDetails() {
        loadingTask?.cancel()
        details = nil
        loadedDetailsPath = nil
        rebuildContent()
        let wallpaper = currentWallpaper
        loadedDetailsPath = wallpaper.path
        loadingTask = loadWallpaperInspectorDetails(for: wallpaper) { [weak self] loadedDetails in
            self?.details = loadedDetails
            self?.rebuildContent()
        }
    }

    @objc private func setAsWallpaper() {
        wallpaperManager.markCardInteraction()
        wallpaperManager.requestSetAsWallpaper(currentWallpaper)
    }

    @objc private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: currentWallpaper.path)])
    }

    @objc private func toggleFavorite() {
        UIActionHelper.toggleFavoriteSelection(
            manager: wallpaperManager,
            selection: wallpaperManager.currentSelectionContext
        )
        // $wallpapers 订阅是唯一重建源：toggleFavoriteSelection 同步写入
        // manager.wallpapers 后订阅回调会 rebuild + refreshFooterActions，
        // 这里再手动刷一次会造成同帧双重建（重复读盘解码 + 路径 label 选中态丢失）。
    }

    @objc private func presentTagPicker() {
        UIActionHelper.presentTagPicker(
            manager: wallpaperManager,
            window: window
        ) { [weak self] in
            self?.rebuildContent()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
