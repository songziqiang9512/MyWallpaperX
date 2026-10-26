//
//  OnlineLibraryDownloadsInspectorView.swift
//  MyWallpaperX — Modules/OnlineLibrary/UI
//

import AppKit

final class OnlineLibraryDownloadsInspectorView: NSView {
    private let itemID: Int
    private let service: OnlineLibraryService
    private var libraryActions: WallpaperInspectorActions?
    private var snapshot: OnlineLibraryDownloadsInspectorSnapshot?
    private let rootStack = NSStackView()
    private let scrollView = InspectorFadingScrollView()
    private let documentContainer = InspectorContentDocumentView()
    private let contentStack = NSStackView()
    private var footerView: NSView?

    init(itemID: Int, service: OnlineLibraryService? = nil, libraryActions: WallpaperInspectorActions? = nil) {
        self.service = service ?? .shared
        self.libraryActions = libraryActions
        self.itemID = itemID
        super.init(frame: .zero)
        // The downloaded-content owner has already prepared these values.
        // Build the final top-aligned layout before mounting; no loading-size pass.
        snapshot = OnlineLibraryDownloadsInspectorSnapshot.load(itemID: itemID, service: self.service)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private var secondaryFactText: String? {
        guard let snapshot else { return nil }
        return [snapshot.fileSizeText, snapshot.durationText, snapshot.fileExtension]
            .filter { !$0.isEmpty && $0 != "未知" }
            .joined(separator: "  ·  ")
            .nilIfEmpty
    }

    private var metadataFacts: [(String, String)] {
        guard let snapshot else { return [] }
        return [
            ("分辨率", snapshot.resolutionText),
            ("添加时间", snapshot.creationDateText),
            ("来源平台", snapshot.platformText)
        ]
        .filter { !$0.1.isEmpty && $0.1 != "未知" }
    }

    private var heroBadges: [String] {
        guard let snapshot else { return [] }
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

        if let footerView {
            rootStack.removeArrangedSubview(footerView)
            footerView.removeFromSuperview()
        }
        let footer = makeFooterActions()
        footerView = footer
        rootStack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
    }

    private func buildContent(in stack: NSStackView) {
        addContentSection(makePreviewSection(), to: stack)

        if !heroBadges.isEmpty {
            addContentSection(makeMetaSection(), to: stack)
        }

        if let snapshot {
            addContentSection(makeDivider(), to: stack)
            if !metadataFacts.isEmpty {
                addContentSection(makeFactsGrid(), to: stack)
                addContentSection(makeDivider(), to: stack)
            }
            addContentSection(makeFileLocationSection(snapshot: snapshot), to: stack)
        } else {
            addContentSection(makeDivider(), to: stack)
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

        let preview = OnlineLibraryDownloadsPreviewSurfaceView(
            itemID: itemID,
            previewImage: snapshot?.previewImage
        )
        preview.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(preview)
        NSLayoutConstraint.activate([
            preview.heightAnchor.constraint(equalToConstant: 156),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        let title = OnlineLibraryDownloadsInspectorViews.makeLabel(
            snapshot?.title ?? "online_\(itemID).mp4",
            font: .systemFont(ofSize: 19, weight: .semibold),
            color: .labelColor
        )
        title.maximumNumberOfLines = 2
        stack.addArrangedSubview(title)

        if let secondaryFactText {
            let facts = OnlineLibraryDownloadsInspectorViews.makeLabel(
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
            let status = OnlineLibraryDownloadsInspectorViews.makeLabel(
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
            row.addArrangedSubview(OnlineLibraryDownloadsInspectorViews.makeFactView(label: metadataFacts[index].0, value: metadataFacts[index].1))
            if index + 1 < metadataFacts.count {
                row.addArrangedSubview(OnlineLibraryDownloadsInspectorViews.makeFactView(label: metadataFacts[index + 1].0, value: metadataFacts[index + 1].1))
            } else {
                row.addArrangedSubview(NSView())
            }
            stack.addArrangedSubview(row)
            NSLayoutConstraint.activate([row.widthAnchor.constraint(equalTo: stack.widthAnchor)])
            index += 2
        }

        return stack
    }

    private func makeFileLocationSection(snapshot: OnlineLibraryDownloadsInspectorSnapshot) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(
            OnlineLibraryDownloadsInspectorViews.makeLabel("文件位置", font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor)
        )

        let path = OnlineLibraryDownloadsInspectorViews.makeLabel(snapshot.path, font: .systemFont(ofSize: 13), color: .labelColor)
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

        let label = OnlineLibraryDownloadsInspectorViews.makeLabel(
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
        let setButton = OnlineLibraryDownloadsInspectorViews.makeFooterButton(
            title: "设为壁纸",
            symbolName: "photo.fill",
            target: self,
            action: #selector(setAsWallpaper),
            kind: .primary
        )
        let revealButton = OnlineLibraryDownloadsInspectorViews.makeFooterButton(
            title: "查看文件",
            symbolName: "folder.fill",
            target: self,
            action: #selector(revealInFinder)
        )
        setButton.isEnabled = libraryActions?.state.canPerformPrimary ?? (snapshot != nil)
        revealButton.isEnabled = snapshot != nil

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

    private func makeDivider() -> NSView {
        OnlineLibraryDownloadsInspectorViews.makeDivider()
    }

    func updateLibraryActions(_ actions: WallpaperInspectorActions) {
        let changed = libraryActions?.state != actions.state
        libraryActions = actions
        if changed { rebuildContent() }
    }

    @objc private func setAsWallpaper() {
        if let libraryActions {
            guard libraryActions.state.canPerformPrimary else { return }
            libraryActions.onPrimary(); return
        }
        guard snapshot != nil else { return }
        service.setLocalFileAsWallpaper(id: itemID)
    }

    @objc private func revealInFinder() {
        guard let url = snapshot?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
