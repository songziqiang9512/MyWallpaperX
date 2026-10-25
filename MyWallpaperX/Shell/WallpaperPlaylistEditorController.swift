import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

/// A draft over one fixed collection identity. The original Store commits all
/// metadata and the owned image copy together; closing the sheet writes nothing.
@MainActor final class WallpaperPlaylistEditorController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onSaved: ((UUID) -> Void)?
    private let collections: UserCollectionsController
    private let original: WallpaperPlaylist?
    private let members: [WallpaperOrganizationItem]
    private let epoch: UUID
    private let hostWindow: () -> NSWindow?
    private let permitsEditing: () -> Bool
    private let panel = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
        styleMask: [.borderless], backing: .buffered, defer: false)
    private let preview = PlaylistEditorCoverView()
    private let name = NSTextField(string: "")
    private let descriptionInput = NSTextView()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let errorScroll = NSScrollView()
    private var errorHeight: NSLayoutConstraint!
    private let save = NSButton(title: "完成", target: nil, action: nil)
    private let choose = NSButton(title: "选择封面…", target: nil, action: nil)
    private let automatic = NSButton(title: "恢复自动封面", target: nil, action: nil)
    private var coverID: UUID?
    private var preparedCover: WallpaperPlaylistCoverAsset?
    private var imageGeneration = UUID()
    private var isPreparing = false
    private var isSaving = false
    private var isClosed = false
    private var subscription: AnyCancellable?
    private let automaticImage: NSImage?
    private var body: NSStackView!

    init(collections: UserCollectionsController, playlist: WallpaperPlaylist?, members: [WallpaperOrganizationItem] = [],
         automaticImage: NSImage?,
         permitsEditing: @escaping () -> Bool = { true }, availabilityChanges: AnyPublisher<Void, Never>? = nil,
         hostWindow: @escaping () -> NSWindow?) {
        self.collections = collections; original = playlist; self.members = members
        epoch = collections.snapshot.resetEpoch
        self.hostWindow = hostWindow; self.automaticImage = automaticImage; self.permitsEditing = permitsEditing
        coverID = playlist?.customCoverAssetID
        super.init()
        configure()
        subscription = collections.$snapshot.map { _ in () }
            .merge(with: availabilityChanges ?? Empty<Void, Never>().eraseToAnyPublisher())
            .receive(on: DispatchQueue.main).sink { [weak self] in self?.refreshAvailability() }
    }

    private func configure() {
        panel.title = original == nil ? "新建播放列表" : "编辑播放列表"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        let root = WallpaperLibrarySheetSurface()
        panel.contentView = root
        let heading = NSTextField(labelWithString: panel.title)
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 14
        preview.layer?.masksToBounds = true
        preview.setAccessibilityLabel("播放列表封面")
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([preview.widthAnchor.constraint(equalToConstant: 112), preview.heightAnchor.constraint(equalTo: preview.widthAnchor)])
        showAutomaticPreview()
        choose.target = self; choose.action = #selector(chooseCover(_:))
        automatic.target = self; automatic.action = #selector(useAutomatic(_:))
        let imageActions = NSStackView(views: [choose, automatic]); imageActions.spacing = 12
        name.stringValue = original?.name ?? "未命名列表"
        name.font = .systemFont(ofSize: 16)
        name.bezelStyle = .roundedBezel
        name.delegate = self
        name.setAccessibilityLabel("播放列表名称")
        name.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        let descriptionTitle = NSTextField(labelWithString: "描述（可选）")
        descriptionTitle.textColor = .secondaryLabelColor
        descriptionInput.isRichText = false
        descriptionInput.font = .systemFont(ofSize: 14)
        descriptionInput.string = original?.descriptionText ?? ""
        descriptionInput.textColor = .labelColor
        descriptionInput.backgroundColor = .textBackgroundColor
        descriptionInput.isVerticallyResizable = true
        descriptionInput.isHorizontallyResizable = false
        descriptionInput.autoresizingMask = [.width]
        descriptionInput.minSize = NSSize(width: 0, height: 58)
        descriptionInput.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        descriptionInput.textContainer?.containerSize = NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        descriptionInput.textContainer?.widthTracksTextView = true
        descriptionInput.setAccessibilityLabel("播放列表描述，可选")
        let descriptionScroll = NSScrollView()
        descriptionScroll.borderType = .bezelBorder
        descriptionScroll.hasVerticalScroller = true
        descriptionScroll.autohidesScrollers = true
        descriptionScroll.documentView = descriptionInput
        descriptionScroll.heightAnchor.constraint(equalToConstant: 60).isActive = true
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 0
        errorLabel.isSelectable = true
        errorLabel.isHidden = true
        errorLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        errorScroll.drawsBackground = false
        errorScroll.hasVerticalScroller = true
        errorScroll.autohidesScrollers = true
        errorScroll.documentView = errorLabel
        errorScroll.isHidden = true
        errorHeight = errorScroll.heightAnchor.constraint(equalToConstant: 0)
        errorHeight.isActive = true
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        save.target = self; save.action = #selector(accept(_:)); save.keyEquivalent = "\r"
        for button in [choose, automatic, cancel, save] { WallpaperLibraryControlStyle.sheetCapsule(button) }
        let footer = NSStackView(views: [cancel, NSView(), save]); footer.spacing = 12
        body = NSStackView(views: [heading, preview, imageActions, name, descriptionTitle, descriptionScroll, errorScroll, footer])
        body.orientation = .vertical; body.alignment = .centerX; body.spacing = 10
        body.detachesHiddenViews = true
        body.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            body.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            body.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        let fullWidth: [NSView] = [name, descriptionTitle, descriptionScroll, errorScroll, footer]
        for field in fullWidth {
            field.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        panel.initialFirstResponder = name
        refreshAvailability()
    }

    func show() {
        guard !isClosed else { return }
        fitPanel()
        let host = hostWindow()
        guard WallpaperLibrarySheetPresentation.present(panel, in: host) else {
            close()
            guard host == nil || WallpaperLibrarySheetPresentation.permitsInput(in: host) else { return }
            presentAppAlert(makeAppAlert(title: "无法打开列表编辑", message: "请先打开主窗口，再重试。"))
            return
        }
        guard let assetID = coverID else { return }
        let generation = imageGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let asset = try await collections.playlistCoverAsset(id: assetID, expectedEpoch: epoch)
                guard !isClosed, imageGeneration == generation, coverID == assetID, collections.snapshot.resetEpoch == epoch else { return }
                guard let asset, let image = NSImage(data: asset.imageData) else {
                    report("原封面暂不可用，可以重新选择或恢复自动封面。"); return
                }
                preview.image = image; preview.contentTintColor = nil
            } catch { if !isClosed, imageGeneration == generation { report(error.localizedDescription) } }
        }
    }

    private var acceptsEdit: Bool {
        guard !isClosed, permitsEditing(), !collections.isResetting, collections.snapshot.resetEpoch == epoch else { return false }
        return original.map { old in collections.snapshot.playlists.contains(where: { $0.id == old.id }) } ?? true
    }

    private func refreshAvailability() {
        if !acceptsEdit { WallpaperLibrarySheetPresentation.dismissNestedSheets(in: panel) }
        save.isEnabled = acceptsEdit && !isPreparing && !isSaving && !name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        choose.isEnabled = acceptsEdit && !isSaving
        automatic.isEnabled = acceptsEdit && !isSaving && coverID != nil
    }
    func controlTextDidChange(_ obj: Notification) { refreshAvailability() }

    @objc private func chooseCover(_ sender: NSButton) {
        guard acceptsEdit, !isSaving, WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return }
        let chooser = NSOpenPanel()
        chooser.allowedContentTypes = [.image]
        chooser.allowsMultipleSelection = false
        chooser.canChooseDirectories = false
        chooser.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = chooser.url, let self, self.acceptsEdit else { return }
            self.prepareCover(url)
        }
    }

    private func prepareCover(_ url: URL) {
        let generation = UUID(); imageGeneration = generation
        isPreparing = true; report("正在准备封面…", isError: false); refreshAvailability()
        Task { @MainActor [weak self] in
            do {
                let asset = try await Task.detached(priority: .userInitiated) { try PlaylistCoverPreparation.prepare(url) }.value
                guard let self, !self.isClosed, self.imageGeneration == generation else { return }
                self.isPreparing = false
                guard self.acceptsEdit else { self.refreshAvailability(); return }
                self.preparedCover = asset; self.coverID = asset.id
                self.preview.image = NSImage(data: asset.imageData); self.preview.contentTintColor = nil
                self.clearReport()
                self.refreshAvailability()
            } catch {
                guard let self, !self.isClosed, self.imageGeneration == generation else { return }
                self.isPreparing = false
                if self.acceptsEdit { self.report(error.localizedDescription) }
                self.refreshAvailability()
            }
        }
    }

    @objc private func useAutomatic(_ sender: NSButton) {
        guard acceptsEdit, !isSaving, WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return }
        imageGeneration = UUID(); isPreparing = false
        preparedCover = nil; coverID = nil
        showAutomaticPreview()
        if automaticImage == nil { report("保存后将自动使用列表成员的缩略图。", isError: false) }
        else { clearReport() }
        refreshAvailability()
    }

    private func showAutomaticPreview() {
        preview.image = automaticImage ?? NSImage(systemSymbolName: WallpaperLibrarySymbols.playlist, accessibilityDescription: nil)
        preview.contentTintColor = automaticImage == nil ? .controlAccentColor : nil
    }

    @objc private func accept(_ sender: NSButton) {
        guard save.isEnabled, acceptsEdit, WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return }
        let metadata = WallpaperPlaylistMetadata(name: name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            descriptionText: descriptionInput.string, customCoverAssetID: coverID)
        let cover = preparedCover
        isSaving = true; report("正在保存…", isError: false); refreshAvailability()
        Task { @MainActor [self] in
            do {
                let id: UUID
                if let original {
                    _ = try await collections.editPlaylistMetadata(id: original.id, expected: original.metadata,
                        replacement: metadata, coverAsset: cover, expectedEpoch: epoch)
                    id = original.id
                } else {
                    id = try await collections.createPlaylist(metadata: metadata, coverAsset: cover, members: members, expectedEpoch: epoch)
                }
                guard !isClosed else { return }
                guard !collections.isResetting, collections.snapshot.resetEpoch == epoch else {
                    isSaving = false
                    close()
                    return
                }
                onSaved?(id); close()
            } catch {
                guard !isClosed else { return }
                isSaving = false; report(error.localizedDescription); refreshAvailability()
            }
        }
    }

    private func report(_ message: String, isError: Bool = true) {
        errorLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        errorLabel.stringValue = message
        errorLabel.toolTip = message
        errorLabel.isHidden = false
        errorScroll.isHidden = false
        let width: CGFloat = 320
        let height = ceil((message as NSString).boundingRect(with: NSSize(width: width - 16, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: errorLabel.font ?? NSFont.systemFont(ofSize: 13)]).height) + 4
        errorLabel.preferredMaxLayoutWidth = width - 16
        errorLabel.frame = NSRect(x: 0, y: 0, width: width - 16, height: max(20, height))
        errorHeight.constant = min(120, max(20, height))
        fitPanel()
    }
    private func clearReport() {
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
        errorScroll.isHidden = true
        fitPanel()
    }
    private func fitPanel() {
        guard let root = panel.contentView else { return }
        root.layoutSubtreeIfNeeded()
        let height = ceil(body.fittingSize.height + 32)
        if abs(root.bounds.height - height) > 0.5 { panel.setContentSize(NSSize(width: 360, height: height)) }
        root.layoutSubtreeIfNeeded()
    }
    @objc private func cancel(_ sender: Any?) {
        guard !isSaving, WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return }
        close()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isSaving, WallpaperLibrarySheetPresentation.permitsInput(in: panel) else { return false }
        close()
        return false
    }
    func windowWillClose(_ notification: Notification) { finishClose() }
    func close() {
        guard !isClosed else { return }
        WallpaperLibrarySheetPresentation.dismiss(panel)
        finishClose()
    }
    private func finishClose() {
        guard !isClosed else { return }
        isClosed = true; imageGeneration = UUID(); subscription = nil
        let completion = onClose; onClose = nil; completion?()
    }
}

private final class PlaylistEditorCoverView: NSImageView {
    override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
}

private nonisolated enum PlaylistCoverPreparation {
    static func prepare(_ url: URL) throws -> WallpaperPlaylistCoverAsset {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: WallpaperPlaylistCoverAsset.maxDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return WallpaperPlaylistCoverAsset(imageData: bytes as Data, pixelWidth: image.width, pixelHeight: image.height)
    }
}
