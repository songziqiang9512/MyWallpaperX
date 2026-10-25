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

    /// 预览图异步加载（共享缓存内存命中同步回调，其余后台解码后主线程补图）
    private let previewSurface = SILInspectorPreviewSurfaceView(image: nil)
    private lazy var previewHeightConstraint = previewSurface.heightAnchor.constraint(equalToConstant: 156)

    private func loadPreviewImage() {
        let sourcePath = wallpaper.path
        weak let weakSelf = self
        // 与 SIL 网格共用同一缓存键（图片路径）：网格已解码 512px 版本时直接命中，
        // 未命中才在本 loader 里按 Inspector 预览所需尺寸（156pt 高 → 800px）后台降采样解码。
        SILThumbnailStore.sharedCache.load(forKey: sourcePath, loader: {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cgImage, size: .zero)
        }, completion: { image in
            DispatchQueue.main.async {
                guard let self = weakSelf else { return }
                self.previewSurface.updateImage(image)
            }
        })
    }

    private var secondaryFactText: String? {
        [fileSizeText, formatText]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
            .nilIfEmpty
    }

    private var metadataFacts: [(String, String)] {
        [
            resolutionText.map { ("分辨率", $0) },
            ("添加时间", dateFormatter.string(from: wallpaper.addedAt)),
            wallpaper.lastUsed > .distantPast ? ("最近使用", dateFormatter.string(from: wallpaper.lastUsed)) : nil
        ]
        .compactMap { $0 }
    }

    private var notices: [(icon: String, text: String)] {
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
            contentStack.centerYAnchor.constraint(equalTo: documentContainer.centerYAnchor),
            contentStack.topAnchor.constraint(greaterThanOrEqualTo: documentContainer.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: documentContainer.bottomAnchor),
            footerStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])

        loadPreviewImage()
    }

    private func makeContentStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        stack.translatesAutoresizingMaskIntoConstraints = false
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
        if !notices.isEmpty {
            addContentSection(makeNoticeSection())
        }
    }

    private func addContentSection(_ section: NSView) {
        guard let contentStack else { return }
        contentStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func makePreviewSection() -> NSView {
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

    private func makeContentSection() -> NSView {
        let stack = SILInspectorViews.makeVerticalStack(spacing: 14)

        if !metadataFacts.isEmpty {
            stack.addArrangedSubview(SILInspectorViews.makeDivider())
            stack.addArrangedSubview(SILInspectorViews.makeSectionTitle("原数据"))
            stack.addArrangedSubview(SILInspectorViews.makeFactsGrid(metadataFacts))
        }

        stack.addArrangedSubview(SILInspectorViews.makeDivider())
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
        stack.addArrangedSubview(SILInspectorViews.makeDivider())
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

    private func makeNoticeSection() -> NSView {
        let stack = SILInspectorViews.makeVerticalStack(spacing: 8)
        stack.addArrangedSubview(SILInspectorViews.makeDivider())
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
            title: "设为壁纸",
            symbolName: "photo.fill",
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
        primaryButton?.setTitle(actions.state.isPlaying ? "已应用" : "设为壁纸")
        primaryButton?.setSymbol(actions.state.isPlaying ? "checkmark.circle.fill" : "photo.fill", accessibilityDescription: actions.state.isPlaying ? "已应用" : "设为壁纸")
        playlistButton?.isEnabled = actions.state.canOrganize
        if changed { rebuildContent() }
    }

    @objc private func setAsDesktopWallpaper() {
        guard libraryActions.state.canPerformPrimary else { return }
        libraryActions.onPrimary()
    }

    private var fileSizeText: String? {
        guard let fileSize = wallpaper.fileSize else { return nil }
        return String(format: "%.2f MB", Double(fileSize) / 1_048_576)
    }

    private var formatText: String? {
        let ext = URL(fileURLWithPath: wallpaper.path).pathExtension.uppercased()
        return ext.isEmpty ? nil : ext
    }

    private var resolutionText: String? {
        guard let width = wallpaper.pixelWidth,
              let height = wallpaper.pixelHeight else { return nil }
        return "\(width) × \(height)"
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    @objc private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wallpaper.path)])
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
