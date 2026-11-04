//
//  SILInspectorView.swift
//  MyWallpaperX
//

import AppKit

final class SILInspectorView: NSView {
    private let wallpaperID: String
    private var contentStack: NSStackView?
    private var footerStack: NSStackView?
    private let service: SILService
    private var libraryActions: WallpaperInspectorActions
    private weak var primaryButton: InspectorFooterButton?
    private weak var playlistButton: InspectorFooterButton?
    private var renderedWallpaper: SILWallpaper?
    private var previewPath: String?
    private var previewRequest: ThumbnailRequest?
    private var previewCancellation: ThumbnailCacheRequestCancellation?

    private var wallpaper: SILWallpaper {
        service.wallpapers.first { $0.id.utf8.elementsEqual(wallpaperID.utf8) } ?? initialWallpaper
    }
    private let initialWallpaper: SILWallpaper

    init(wallpaper: SILWallpaper, service: SILService? = nil, libraryActions: WallpaperInspectorActions) {
        self.service = service ?? .shared
        self.libraryActions = libraryActions
        self.wallpaperID = wallpaper.id
        self.initialWallpaper = wallpaper
        super.init(frame: .zero)
        setup()
        updateLibraryActions(libraryActions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit { previewCancellation?.cancel() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            loadPreviewImage()
        } else {
            previewCancellation?.cancel()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        loadPreviewImage()
    }

    private let previewSurface = SILInspectorPreviewSurfaceView(image: nil)
    private lazy var previewHeightConstraint = previewSurface.heightAnchor.constraint(equalToConstant: 156)

    private func loadPreviewImage() {
        guard let window, let request = ThumbnailRequest(size: previewSurface.bounds.size,
            scale: window.backingScaleFactor, mode: .fill) else { return }
        let sourcePath = wallpaper.path
        guard previewPath != sourcePath || previewRequest != request || previewCancellation?.cancelled == true else { return }
        previewCancellation?.cancel()
        if previewPath != nil, previewPath != sourcePath { previewSurface.updateImage(nil) }
        let cancellation = ThumbnailCacheRequestCancellation()
        previewCancellation = cancellation
        previewPath = sourcePath; previewRequest = request
        SILThumbnailStore.sharedCache.load(forKey: sourcePath, request: request,
            cancellation: cancellation, cachesFailure: false,
            input: .sourceFile(URL(filePath: sourcePath, directoryHint: .notDirectory)), completion: { [weak self] image in
                self?.previewSurface.updateImage(image)
            })
    }

    private func metadataFacts(for wallpaper: SILWallpaper) -> [(String, String)] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let resolution = wallpaper.pixelWidth.flatMap { width in
            wallpaper.pixelHeight.map { "\(width) × \($0)" }
        }
        return [
            resolution.map { ("分辨率", $0) },
            ("添加时间", formatter.string(from: wallpaper.addedAt)),
            wallpaper.lastUsed > .distantPast ? ("最近使用", formatter.string(from: wallpaper.lastUsed)) : nil
        ]
        .compactMap { $0 }
    }

    private func notices(for wallpaper: SILWallpaper) -> [(icon: String, text: String)] {
        var result: [(String, String)] = []
        if !FileManager.default.fileExists(atPath: wallpaper.path) {
            result.append(("exclamationmark.triangle.fill", "原始图片文件当前不可用"))
        }
        if service.currentActiveWallpaperPath == wallpaper.path {
            result.append(("photo.fill", "当前桌面正在使用这张图片"))
        }
        return result
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
        rebuildContent(wallpaper)
        let documentContainer = InspectorContentDocumentView()
        documentContainer.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(contentStack)
        scrollView.documentView = documentContainer

        let footerStack = makeFooterActions()
        self.footerStack = footerStack

        addSubview(rootStack)
        rootStack.addArrangedSubview(scrollView)
        rootStack.addArrangedSubview(footerStack)

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
            footerStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])

    }

    private func makeContentStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: InspectorFadingScrollView.contentTopInset, left: 2, bottom: 0, right: 2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func rebuildContent(_ wallpaper: SILWallpaper) {
        guard let contentStack else { return }
        renderedWallpaper = wallpaper
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        addContentSection(makePreviewSection(wallpaper))
        addContentSection(makeContentSection(wallpaper))
        addContentSection(makeTagsSection())
        let notices = notices(for: wallpaper)
        if !notices.isEmpty {
            addContentSection(makeNoticeSection(notices))
        }
    }

    private func addContentSection(_ section: NSView) {
        guard let contentStack else { return }
        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func makePreviewSection(_ wallpaper: SILWallpaper) -> NSView {
        let stack = SILInspectorViews.makeVerticalStack(spacing: 8)

        let preview = previewSurface
        preview.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(preview)
        previewHeightConstraint.isActive = true
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let title = SILInspectorViews.makeLabel(
            wallpaper.title,
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: .labelColor
        )
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(title)

        let fileSize = wallpaper.fileSize.map { String(format: "%.2f MB", Double($0) / 1_048_576) }
        let format = URL(filePath: wallpaper.path, directoryHint: .notDirectory).pathExtension.uppercased()
        let secondaryFactText = [fileSize, format.isEmpty ? nil : format]
            .compactMap { $0 }.joined(separator: "  ·  ").nilIfEmpty
        if let secondaryFactText {
            let facts = SILInspectorViews.makeLabel(
                secondaryFactText,
                font: .systemFont(ofSize: 11, weight: .medium),
                color: .secondaryLabelColor
            )
            facts.maximumNumberOfLines = 2
            stack.addArrangedSubview(facts)
        }

        return stack
    }

    private func makeContentSection(_ wallpaper: SILWallpaper) -> NSView {
        let stack = SILInspectorViews.makeVerticalStack(spacing: 14)

        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        stack.addArrangedSubview(SILInspectorViews.makeSectionTitle("原数据"))
        stack.addArrangedSubview(WallpaperLibraryControlStyle.inspectorFacts(metadataFacts(for: wallpaper)))

        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        stack.addArrangedSubview(SILInspectorViews.makeSectionTitle("文件位置"))

        let path = SILInspectorViews.makeLabel(wallpaper.path, font: .systemFont(ofSize: 13), color: .labelColor)
        path.maximumNumberOfLines = 3
        path.lineBreakMode = .byTruncatingMiddle
        path.allowsExpansionToolTips = true
        path.isSelectable = true
        stack.addArrangedSubview(path)

        return stack
    }

    private func makeTagsSection() -> NSView {
        let stack = SILInspectorViews.makeVerticalStack(spacing: 14)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        let names = libraryActions.state.playlistNames
        stack.addArrangedSubview(SILInspectorViews.makeSectionTitle("播放列表"))

        if names.isEmpty {
            stack.addArrangedSubview(
                SILInspectorViews.makeLabel("当前未加入任何播放列表", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
            )
        } else {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            names.forEach { row.addArrangedSubview(InspectorBadgeView(text: $0)) }
            stack.addArrangedSubview(row)
        }

        return stack
    }

    private func makeNoticeSection(_ notices: [(icon: String, text: String)]) -> NSView {
        let stack = SILInspectorViews.makeVerticalStack(spacing: 8)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        notices.forEach { notice in
            stack.addArrangedSubview(SILInspectorViews.makeNotice(icon: notice.icon, text: notice.text))
        }
        return stack
    }

    private func makeFooterActions() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Apply and membership dispatch through the injected canonical commands;
        // metadata, preview and the original three-button geometry stay local.
        let wallpaperButton = SILInspectorViews.makeFooterButton(
            title: libraryActions.state.primaryTitle,
            symbolName: libraryActions.state.primarySymbolName,
            target: self,
            action: #selector(setAsDesktopWallpaper),
            kind: .primary
        )
        primaryButton = wallpaperButton
        wallpaperButton.isEnabled = libraryActions.state.canPerformPrimary
        let revealButton = SILInspectorViews.makeFooterButton(
            title: "查看文件",
            symbolName: "folder.fill",
            target: self,
            action: #selector(revealInFinder)
        )
        let tagButton = SILInspectorViews.makeFooterButton(
            title: "",
            symbolName: "tag",
            target: self,
            action: #selector(presentTagPicker)
        )
        playlistButton = tagButton
        tagButton.isEnabled = libraryActions.state.canOrganize
        let tagTitle = "添加到列表"
        tagButton.setAccessibilityLabel(tagTitle)
        tagButton.toolTip = tagTitle

        let buttonGroup = NSView()
        buttonGroup.translatesAutoresizingMaskIntoConstraints = false
        buttonGroup.addSubview(wallpaperButton)
        buttonGroup.addSubview(revealButton)
        buttonGroup.addSubview(tagButton)
        stack.addArrangedSubview(buttonGroup)

        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),
            buttonGroup.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 2),
            buttonGroup.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -2),
            buttonGroup.topAnchor.constraint(equalTo: stack.topAnchor),
            buttonGroup.bottomAnchor.constraint(equalTo: stack.bottomAnchor),

            // 总宽不变（面板 356，键区 352）：添加标签改纯图标键（38），
            // 腾出的宽度给设为壁纸/查看文件两键等分（各 ~151，四字标题
            // 文字区 ~104pt 不截断）；键间距保持 6pt。
            wallpaperButton.leadingAnchor.constraint(equalTo: buttonGroup.leadingAnchor),
            wallpaperButton.topAnchor.constraint(equalTo: buttonGroup.topAnchor),
            wallpaperButton.bottomAnchor.constraint(equalTo: buttonGroup.bottomAnchor),
            wallpaperButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),

            revealButton.leadingAnchor.constraint(equalTo: wallpaperButton.trailingAnchor, constant: 6),
            revealButton.topAnchor.constraint(equalTo: buttonGroup.topAnchor),
            revealButton.bottomAnchor.constraint(equalTo: buttonGroup.bottomAnchor),
            revealButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),

            tagButton.leadingAnchor.constraint(equalTo: revealButton.trailingAnchor, constant: 6),
            tagButton.trailingAnchor.constraint(equalTo: buttonGroup.trailingAnchor),
            tagButton.topAnchor.constraint(equalTo: buttonGroup.topAnchor),
            tagButton.bottomAnchor.constraint(equalTo: buttonGroup.bottomAnchor),
            tagButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),
            tagButton.widthAnchor.constraint(equalToConstant: InspectorFooterMetrics.iconWidth),

            wallpaperButton.widthAnchor.constraint(equalTo: revealButton.widthAnchor)
        ])
        return stack
    }

    /// The App supplies the same fixed-reference commands as the grid/menu.
    func updateLibraryActions(_ actions: WallpaperInspectorActions) {
        let changed = libraryActions.state != actions.state
        libraryActions = actions
        primaryButton?.isEnabled = actions.state.canPerformPrimary
        primaryButton?.setTitle(actions.state.primaryTitle)
        primaryButton?.setSymbol(actions.state.primarySymbolName, accessibilityDescription: actions.state.primaryTitle)
        playlistButton?.isEnabled = actions.state.canOrganize
        let current = wallpaper
        if changed || renderedWallpaper != current { rebuildContent(current) }
        if previewPath != current.path { loadPreviewImage() }
    }

    @objc private func setAsDesktopWallpaper() {
        guard libraryActions.state.canPerformPrimary else { return }
        libraryActions.onPrimary()
    }

    @objc private func revealInFinder() {
        FinderRevealCoordinator.shared.reveal([URL(fileURLWithPath: wallpaper.path)])
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
