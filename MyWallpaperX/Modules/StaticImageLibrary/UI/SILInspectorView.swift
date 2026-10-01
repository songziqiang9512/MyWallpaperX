//
//  SILInspectorView.swift
//  MyWallpaperX
//

import AppKit

final class SILInspectorView: NSView {
    private let wallpaperID: String
    private var contentStack: NSStackView?
    private var footerStack: NSStackView?

    private var wallpaper: SILWallpaper {
        SILService.shared.wallpapers.first { $0.id == wallpaperID } ?? initialWallpaper
    }
    private let initialWallpaper: SILWallpaper

    init(wallpaper: SILWallpaper) {
        self.wallpaperID = wallpaper.id
        self.initialWallpaper = wallpaper
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// 预览图异步加载（共享缓存内存命中同步回调，其余后台解码后主线程补图）
    private var previewImage: NSImage?

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
                self.previewImage = image
                self.rebuildContent()
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
        if SILService.shared.currentActiveWallpaperPath == wallpaper.path {
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

        let preview = SILInspectorPreviewSurfaceView(image: previewImage)
        preview.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(preview)
        NSLayoutConstraint.activate([
            preview.heightAnchor.constraint(equalToConstant: 156),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

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
        stack.addArrangedSubview(SILInspectorViews.makeSectionTitle("标签"))

        if wallpaper.tags.isEmpty {
            stack.addArrangedSubview(
                SILInspectorViews.makeLabel("当前未加入任何标签", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
            )
        } else {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            wallpaper.tags.forEach { row.addArrangedSubview(SILInspectorViews.makeBadge($0)) }
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

        // 主操作：设为壁纸（经 staticImageWallpaperReadyToApply 统一入口
        // 应用系统桌面）；查看文件/添加标签收缩为次级宽度。
        let wallpaperButton = SILInspectorViews.makeFooterButton(
            title: "设为壁纸",
            symbolName: "photo.fill",
            target: self,
            action: #selector(setAsDesktopWallpaper),
            kind: .primary
        )
        wallpaperButton.isEnabled = FileManager.default.fileExists(atPath: wallpaper.path)
        let revealButton = SILInspectorViews.makeFooterButton(
            title: "",
            symbolName: "folder.fill",
            target: self,
            action: #selector(revealInFinder)
        )
        revealButton.setAccessibilityLabel("查看文件")
        revealButton.toolTip = "查看文件"
        let tagButton = SILInspectorViews.makeFooterButton(
            title: "",
            symbolName: "tag",
            target: self,
            action: #selector(presentTagPicker)
        )
        tagButton.isEnabled = !SILService.shared.silTags.isEmpty
        tagButton.setAccessibilityLabel("添加标签")
        tagButton.toolTip = "添加标签"

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

            // 主按钮与视频库面板的「设为壁纸」同款宽度（面板 368 − 4 内边距
            // 平分两键 ≈ 179；此处 356 面板取 172 保持同量级主宽度）。
            wallpaperButton.leadingAnchor.constraint(equalTo: buttonGroup.leadingAnchor),
            wallpaperButton.widthAnchor.constraint(equalToConstant: 172),
            wallpaperButton.topAnchor.constraint(equalTo: buttonGroup.topAnchor),
            wallpaperButton.bottomAnchor.constraint(equalTo: buttonGroup.bottomAnchor),
            wallpaperButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),

            revealButton.leadingAnchor.constraint(equalTo: wallpaperButton.trailingAnchor, constant: 6),
            revealButton.topAnchor.constraint(equalTo: buttonGroup.topAnchor),
            revealButton.bottomAnchor.constraint(equalTo: buttonGroup.bottomAnchor),
            revealButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),

            tagButton.leadingAnchor.constraint(equalTo: revealButton.trailingAnchor, constant: 6),
            tagButton.topAnchor.constraint(equalTo: buttonGroup.topAnchor),
            tagButton.bottomAnchor.constraint(equalTo: buttonGroup.bottomAnchor),
            tagButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),
            // 次级两键为纯图标：宽度取图标键规格，图标由按钮内部居中；
            // 链条在主按钮之后左排，不钉 buttonGroup 右缘。
            revealButton.widthAnchor.constraint(equalToConstant: InspectorFooterMetrics.iconWidth),
            tagButton.widthAnchor.constraint(equalToConstant: InspectorFooterMetrics.iconWidth)
        ])
        return stack
    }

    /// 与网格右键菜单同一入口：经 MainWindowCoordinator 的静态图应用通道
    /// 统一写系统桌面并收尾动态 runtime。
    @objc private func setAsDesktopWallpaper() {
        NotificationCenter.default.post(
            name: .staticImageWallpaperReadyToApply,
            object: nil,
            userInfo: ["imageURL": URL(fileURLWithPath: wallpaper.path)]
        )
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
        let service = SILService.shared
        guard !service.silTags.isEmpty else { return }

        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        picker.addItems(withTitles: service.silTags)
        picker.selectItem(at: 0)

        let alert = makeAppAlert(
            title: "添加图片标签",
            message: "请选择要添加的标签",
            buttons: ["确定", "取消"],
            accessoryView: picker
        )

        presentAppAlert(alert, in: appModalHostWindow()) { [weak self] response in
            guard let self,
                  response == .alertFirstButtonReturn,
                  let tag = picker.titleOfSelectedItem,
                  !tag.isEmpty else { return }
            SILService.shared.addSILTag(tag, toSelected: [self.wallpaperID])
            self.rebuildContent()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
