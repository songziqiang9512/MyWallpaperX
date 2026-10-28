//
//  PixabayDownloadsInspectorView.swift
//  MyWallpaperX — Modules/Pixabay/UI
//

import AppKit
import Combine

final class PixabayDownloadsInspectorView: NSView {
    private let itemID: Int
    private let service: PixabayService
    private var libraryActions: WallpaperInspectorActions?
    private var snapshot: PixabayDownloadsInspectorSnapshot?
    private var remoteItem: PixabayVideoItem?
    private var downloadingSubscription: AnyCancellable?
    private let rootStack = NSStackView()
    private let scrollView = InspectorFadingScrollView()
    private let documentContainer = InspectorContentDocumentView()
    private let contentStack = NSStackView()
    private let previewSurface: PixabayDownloadsPreviewSurfaceView
    private lazy var previewHeightConstraint = previewSurface.heightAnchor.constraint(equalToConstant: 156)
    private weak var primaryButton: InspectorFooterButton?
    private weak var revealButton: InspectorFooterButton?
    private var previewCancellation: ThumbnailCacheRequestCancellation?
    private var hasMounted = false

    init(itemID: Int, service: PixabayService? = nil, libraryActions: WallpaperInspectorActions? = nil, remoteItem: PixabayVideoItem? = nil) {
        self.service = service ?? .shared
        self.libraryActions = libraryActions
        self.itemID = itemID
        self.remoteItem = remoteItem
        previewSurface = PixabayDownloadsPreviewSurfaceView(itemID: itemID, previewImage: nil)
        super.init(frame: .zero)
        // The downloaded-content owner has already prepared these values.
        // Build the final top-aligned layout before mounting; no loading-size pass.
        snapshot = PixabayDownloadsInspectorSnapshot.load(itemID: itemID, service: self.service)
        setup()
        loadPreviewImage()
        downloadingSubscription = self.service.$downloadingIDs.map { $0.contains(itemID) }.removeDuplicates()
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshSnapshotIfNeeded(); self?.refreshFooterActions() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit { previewCancellation?.cancel() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            hasMounted = true
            refreshSnapshotIfNeeded()
            refreshFooterActions()
            if previewCancellation?.cancelled == true { loadPreviewImage() }
        } else if hasMounted {
            previewCancellation?.cancel()
        }
    }

    private func loadPreviewImage() {
        guard !hasMounted || window != nil else { return }
        previewCancellation?.cancel()
        let cancellation = ThumbnailCacheRequestCancellation()
        previewCancellation = cancellation
        if let entry = snapshot?.entry {
            PixabayDownloadedThumbnailStore.loadThumbnail(entry, priority: .visible, cancellation: cancellation) { [weak self] _, image in
                guard !cancellation.cancelled else { return }
                self?.previewSurface.updateImage(image)
            }
        } else if let url = remoteItem?.previewThumbnailURL {
            let task = Task { [weak self] in
                let image = await OnlineImageThumbnailCache.shared.image(for: url, maxPixelSize: 800, priority: .visible)
                cancellation.clearCancellationHandler()
                guard !cancellation.cancelled else { return }
                self?.previewSurface.updateImage(image)
            }
            cancellation.installCancellationHandler { task.cancel() }
        } else { previewSurface.updateImage(nil) }
    }

    private func refreshSnapshotIfNeeded(remoteItem suppliedItem: PixabayVideoItem? = nil) {
        let entry = service.downloadedContent.entries.first { $0.id == itemID && $0.isAvailable }
        let nextRemote = suppliedItem ?? remoteItem
        guard entry != snapshot?.entry || nextRemote != remoteItem else { return }
        let previous = snapshot?.entry
        let previousURL = remoteItem?.previewThumbnailURL
        remoteItem = nextRemote
        snapshot = entry.map { PixabayDownloadsInspectorSnapshot(entry: $0) }
        rebuildContent()
        if previous?.localURL != entry?.localURL || previous?.fileSize != entry?.fileSize
            || previous?.thumbnailSourceKey != entry?.thumbnailSourceKey || previousURL != remoteItem?.previewThumbnailURL {
            loadPreviewImage()
        }
    }

    private var secondaryFactText: String? {
        guard let snapshot else {
            return remoteItem.map { [$0.fileSizeString, $0.durationString].compactMap { $0 }.joined(separator: "  ·  ") }
        }
        return [snapshot.fileSizeText, snapshot.durationText, snapshot.fileExtension]
            .filter { !$0.isEmpty && $0 != "未知" }
            .joined(separator: "  ·  ")
            .nilIfEmpty
    }

    private var metadataFacts: [(String, String)] {
        guard let snapshot else {
            guard let remoteItem else { return [] }
            return [("分辨率", remoteItem.resolutionString ?? ""), ("作者", remoteItem.user), ("来源平台", "Pixabay")]
                .filter { !$0.1.isEmpty }
        }
        return [
            ("分辨率", snapshot.resolutionText),
            ("添加时间", snapshot.creationDateText),
            ("来源平台", snapshot.platformText)
        ]
        .filter { !$0.1.isEmpty && $0.1 != "未知" }
    }

    private var heroBadges: [String] {
        guard let snapshot else { return remoteItem == nil ? [] : ["Pixabay", "在线视频"] }
        return [
            snapshot.platformText,
            snapshot.fileExtension,
            "已下载"
        ]
    }

    private var statusFactText: String? {
        guard let snapshot else { return nil }
        return [
            snapshot.resolutionText == "未知" ? nil : snapshot.resolutionText,
            snapshot.durationText == "未知" ? nil : snapshot.durationText,
            "Pixabay ID \(snapshot.id)"
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")
        .nilIfEmpty
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 16
        contentStack.edgeInsets = NSEdgeInsets(top: InspectorFadingScrollView.contentTopInset, left: 2, bottom: 0, right: 2)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        documentContainer.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(contentStack)
        scrollView.documentView = documentContainer

        addSubview(rootStack)
        rootStack.addArrangedSubview(scrollView)
        rebuildContent()
        let footer = makeFooterActions()
        rootStack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

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
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: documentContainer.bottomAnchor)
        ])
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        buildContent(in: contentStack)
    }

    private func buildContent(in stack: NSStackView) {
        addContentSection(makePreviewSection(), to: stack)

        if !heroBadges.isEmpty {
            addContentSection(makeMetaSection(), to: stack)
        }

        if snapshot != nil || remoteItem != nil {
            addContentSection(WallpaperLibraryControlStyle.sectionDivider(), to: stack)
            if !metadataFacts.isEmpty {
                addContentSection(makeFactsGrid(), to: stack)
                addContentSection(WallpaperLibraryControlStyle.sectionDivider(), to: stack)
            }
            if let snapshot { addContentSection(makeFileLocationSection(snapshot: snapshot), to: stack) }
        } else {
            addContentSection(WallpaperLibraryControlStyle.sectionDivider(), to: stack)
            addContentSection(makeNoticeSection(), to: stack)
        }
    }

    private func addContentSection(_ section: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makePreviewSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        previewSurface.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(previewSurface)
        NSLayoutConstraint.activate([
            previewHeightConstraint,
            previewSurface.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        let title = PixabayDownloadsInspectorViews.makeLabel(
            snapshot?.title ?? remoteItem?.displayTitle ?? "Pixabay #\(itemID)",
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: .labelColor
        )
        title.maximumNumberOfLines = 2
        stack.addArrangedSubview(title)

        if let secondaryFactText {
            let facts = PixabayDownloadsInspectorViews.makeLabel(
                secondaryFactText,
                font: .systemFont(ofSize: 11, weight: .medium),
                color: .secondaryLabelColor
            )
            facts.maximumNumberOfLines = 2
            stack.addArrangedSubview(facts)
        }

        return stack
    }

    private func makeMetaSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let badgeStack = NSStackView()
        badgeStack.orientation = .horizontal
        badgeStack.alignment = .centerY
        badgeStack.spacing = 8
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        heroBadges.forEach { badgeStack.addArrangedSubview(InspectorBadgeView(text: $0)) }
        stack.addArrangedSubview(badgeStack)

        if let statusFactText {
            let status = PixabayDownloadsInspectorViews.makeLabel(
                statusFactText,
                font: .systemFont(ofSize: 11, weight: .medium),
                color: .secondaryLabelColor
            )
            status.maximumNumberOfLines = 2
            stack.addArrangedSubview(status)
        }

        return stack
    }

    private func makeFactsGrid() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        var index = 0
        while index < metadataFacts.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 12
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(PixabayDownloadsInspectorViews.makeFactView(label: metadataFacts[index].0, value: metadataFacts[index].1))
            if index + 1 < metadataFacts.count {
                row.addArrangedSubview(PixabayDownloadsInspectorViews.makeFactView(label: metadataFacts[index + 1].0, value: metadataFacts[index + 1].1))
            } else {
                row.addArrangedSubview(NSView())
            }
            stack.addArrangedSubview(row)
            NSLayoutConstraint.activate([row.widthAnchor.constraint(equalTo: stack.widthAnchor)])
            index += 2
        }

        return stack
    }

    private func makeFileLocationSection(snapshot: PixabayDownloadsInspectorSnapshot) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(
            PixabayDownloadsInspectorViews.makeLabel("文件位置", font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor)
        )

        let path = PixabayDownloadsInspectorViews.makeLabel(snapshot.path, font: .systemFont(ofSize: 13), color: .labelColor)
        path.maximumNumberOfLines = 3
        path.lineBreakMode = .byTruncatingMiddle
        path.allowsExpansionToolTips = true
        path.isSelectable = true
        stack.addArrangedSubview(path)

        return stack
    }

    private func makeNoticeSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "文件缺失")
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(icon)

        let label = PixabayDownloadsInspectorViews.makeLabel(
            "当前下载项文件可能已被移动或删除。",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        label.maximumNumberOfLines = 0
        stack.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])
        return stack
    }

    private func makeFooterActions() -> NSView {
        let setButton = PixabayDownloadsInspectorViews.makeFooterButton(
            title: "设为壁纸",
            symbolName: "photo.fill",
            target: self,
            action: #selector(setAsWallpaper),
            kind: .primary
        )
        let revealButton = PixabayDownloadsInspectorViews.makeFooterButton(
            title: "查看文件",
            symbolName: "folder.fill",
            target: self,
            action: #selector(revealInFinder)
        )
        primaryButton = setButton
        self.revealButton = revealButton
        refreshFooterActions()

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(setButton)
        footer.addSubview(revealButton)

        NSLayoutConstraint.activate([
            footer.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),
            setButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            setButton.topAnchor.constraint(equalTo: footer.topAnchor),
            setButton.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
            setButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height),

            revealButton.leadingAnchor.constraint(equalTo: setButton.trailingAnchor, constant: 6),
            revealButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            revealButton.topAnchor.constraint(equalTo: footer.topAnchor),
            revealButton.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
            revealButton.heightAnchor.constraint(equalToConstant: InspectorFooterMetrics.height)
        ])
        revealButton.widthAnchor.constraint(equalTo: setButton.widthAnchor).isActive = true
        return footer
    }



    func updateLibraryActions(_ actions: WallpaperInspectorActions, remoteItem: PixabayVideoItem? = nil) {
        libraryActions = actions
        refreshSnapshotIfNeeded(remoteItem: remoteItem)
        refreshFooterActions()
    }

    private func refreshFooterActions() {
        let remote = snapshot == nil ? remoteItem : nil
        let busy = remote != nil && service.downloadingIDs.contains(itemID)
        let title: String
        let symbol: String
        if remote != nil { title = busy ? "正在下载" : "下载视频"; symbol = busy ? "hourglass" : "arrow.down" }
        else if libraryActions?.state.isSwitching == true { title = "正在切换"; symbol = "hourglass" }
        else if libraryActions?.state.isPlaying == true { title = "停止播放"; symbol = "stop.fill" }
        else { title = "设为壁纸"; symbol = "play.fill" }
        primaryButton?.setTitle(title)
        primaryButton?.setSymbol(symbol, accessibilityDescription: title)
        primaryButton?.isEnabled = remote != nil ? !busy : libraryActions?.state.canPerformPrimary ?? (snapshot != nil)
        let revealTitle = remote == nil ? "查看文件" : "打开原网页"
        revealButton?.setTitle(revealTitle)
        revealButton?.setSymbol(remote == nil ? "folder.fill" : "safari", accessibilityDescription: revealTitle)
        revealButton?.isEnabled = snapshot != nil || remote.flatMap { URL(string: $0.pageURL) } != nil
    }

    @objc private func setAsWallpaper() {
        if snapshot == nil, let remoteItem { service.download(item: remoteItem); return }
        if let libraryActions {
            guard libraryActions.state.canPerformPrimary else { return }
            libraryActions.onPrimary(); return
        }
        guard snapshot != nil else { return }
        service.setLocalFileAsWallpaper(id: itemID)
    }

    @objc private func revealInFinder() {
        if let url = snapshot?.fileURL { FinderRevealCoordinator.shared.reveal([url]) }
        else if let remoteItem, let url = URL(string: remoteItem.pageURL) { NSWorkspace.shared.open(url) }
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
