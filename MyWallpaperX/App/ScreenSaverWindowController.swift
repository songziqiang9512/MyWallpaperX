import AppKit
import Combine

/// One configuration surface for Settings, cards and the system component.
/// Opening it reads published state and shared thumbnails only.
@MainActor final class ScreenSaverWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ScreenSaverWindowController()
    private let integration = ScreenSaverIntegration.shared
    private let mode = NSPopUpButton()
    private let fill = NSPopUpButton()
    private let battery = NSSwitch()
    private let selected = NSTextField(wrappingLabelWithString: "选择一段喜欢的视频")
    private let selectionHint = NSTextField(wrappingLabelWithString: "")
    private let selectedPreview = NSImageView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var actionFeedback = ""
    private let saveButton = NSButton(title: "保存屏保", target: nil, action: nil)
    private let chooseButton = NSButton(title: "选择视频", target: nil, action: nil)
    private lazy var artworkLoader = WallpaperLibraryArtworkProvider.liveLoader(manager: .shared, images: .shared, steam: .shared, pixabay: .shared)
    private let posterLoader = SILThumbnailProvider()
    private var selectedArtworkIdentity: WallpaperLibraryArtworkProvider.Identity?
    private var selectedArtworkCancellation: (() -> Void)?
    private var savedPosterURL: URL?
    private var savedImage: NSImage?
    private var savedArtworkCancellation: ThumbnailCacheRequestCancellation?
    private var draft = ScreenSaverPreferences()
    private var original = ScreenSaverPreferences()
    private var isSaving = false
    private var subscriptions = Set<AnyCancellable>()
    private var presentationEpoch: UInt64 = 0
    private var picker: WallpaperPlaylistPickerController?

    private init() {
        let panel = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 640),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.title = "锁屏与屏保"
        panel.identifier = NSUserInterfaceItemIdentifier("ScreenSaverSettings")
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        buildContent(in: panel)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func show(reference: WallpaperReference? = nil, relativeTo parent: NSWindow? = nil) {
        guard let window else { return }
        let opening = !window.isVisible
        if !opening, reference == nil {
            WallpaperLibrarySheetPresentation.topWindow(in: window).makeKeyAndOrderFront(nil)
            return
        }
        if !opening {
            picker?.close(); picker = nil
            WallpaperLibrarySheetPresentation.dismissNestedSheets(in: window)
        }
        presentationEpoch &+= 1
        if isSaving { ScreenSaverCoordinator.shared.cancel(); isSaving = false }
        actionFeedback = ""
        if opening {
            original = WallpaperManager.shared.settings.screenSaver
            draft = original
            if draft.reference == nil,
               let current = WallpaperManager.shared.libraryPlaybackSequence.committed?.reference,
               (try? MyWallpaperXApplication.libraryWorkspace?.content(for: current).kind) == .video {
                draft.reference = current
            }
        }
        if let reference { draft.mode = .fixed; draft.reference = reference }
        if let reference = draft.reference,
           let content = try? MyWallpaperXApplication.libraryWorkspace?.content(for: reference), content.kind != .video,
           integration.configuration?.content?.sourceIdentity != reference.storageKey {
            draft.reference = nil
        }
        mode.selectItem(at: draft.mode == .fixed ? 0 : 1)
        fill.selectItem(at: draft.fillMode == "aspectFit" ? 0 : 1)
        battery.state = draft.playsOnBattery ? .on : .off
        integration.refresh()
        subscriptions.removeAll()
        for changes in [integration.objectWillChange.eraseToAnyPublisher(), ScreenSaverCoordinator.shared.objectWillChange.eraseToAnyPublisher()] {
            changes.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        }
        MyWallpaperXApplication.libraryWorkspace?.presentation.$state.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        if opening {
            if let parent, let panel = window as? WallpaperLibraryModalPanel {
                guard WallpaperLibrarySheetPresentation.present(panel, in: parent) else { subscriptions.removeAll(); return }
            } else { window.center(); window.makeKeyAndOrderFront(nil) }
        } else { window.makeKeyAndOrderFront(nil) }
        refresh()
        // Opening the sheet must not give the first button a keyboard-focus ring.
        window.makeFirstResponder(nil)
    }

    private func buildContent(in panel: NSWindow) {
        let root = WallpaperPanelSurface()
        panel.contentView = root
        let symbol = NSImageView(image: NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: nil)!)
        symbol.contentTintColor = .controlAccentColor
        symbol.symbolConfiguration = .init(pointSize: 26, weight: .medium)
        symbol.translatesAutoresizingMaskIntoConstraints = false
        let title = label("锁屏与屏保")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        let close = WallpaperPanelCloseButton()
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        close.target = self; close.action = #selector(cancelAction)
        let header = NSStackView(views: [symbol, title, NSView(), close])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 12
        let headerRule = WallpaperLibraryControlStyle.sectionDivider()
        let footerRule = WallpaperLibraryControlStyle.sectionDivider()
        let cancel = button("取消", #selector(cancelAction))
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self; saveButton.action = #selector(saveAction)
        saveButton.keyEquivalent = "\r"
        WallpaperLibraryControlStyle.sheetCapsule(saveButton)
        let buttons = NSStackView(views: [cancel, saveButton])
        buttons.orientation = .horizontal; buttons.alignment = .centerY; buttons.spacing = 12
        let management = NSStackView(views: [button("清除内容", #selector(clearAction)), button("卸载组件", #selector(uninstallAction))])
        management.orientation = .horizontal; management.alignment = .centerY; management.spacing = 8
        let footer = NSStackView(views: [management, NSView(), buttons])
        footer.orientation = .horizontal; footer.alignment = .centerY
        footer.distribution = .fill; footer.spacing = 12
        for group in [management, buttons] {
            group.setContentHuggingPriority(.required, for: .horizontal)
            group.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading
        stack.distribution = .equalSpacing; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [header, headerRule, stack, footerRule, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.bodyView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            symbol.widthAnchor.constraint(equalToConstant: 36), symbol.heightAnchor.constraint(equalToConstant: 36),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            headerRule.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            headerRule.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            headerRule.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            footerRule.leadingAnchor.constraint(equalTo: headerRule.leadingAnchor), footerRule.trailingAnchor.constraint(equalTo: headerRule.trailingAnchor),
            footerRule.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: headerRule.bottomAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: footerRule.topAnchor, constant: -18)
        ])
        selected.maximumNumberOfLines = 2
        selected.font = .systemFont(ofSize: 14, weight: .semibold)
        selected.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        selectionHint.font = .systemFont(ofSize: 12); selectionHint.textColor = .secondaryLabelColor
        chooseButton.target = self; chooseButton.action = #selector(chooseAction)
        WallpaperLibraryControlStyle.sheetCapsule(chooseButton)
        chooseButton.setContentHuggingPriority(.required, for: .horizontal)
        chooseButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        let chosen = NSStackView(views: [selected, selectionHint])
        chosen.orientation = .vertical; chosen.alignment = .leading; chosen.spacing = 6
        chosen.setContentHuggingPriority(.defaultLow, for: .horizontal)
        configureThumbnail(selectedPreview, label: "所选视频缩略图")
        let selectedContent = NSStackView(views: [selectedPreview, chosen, chooseButton])
        selectedContent.orientation = .horizontal; selectedContent.alignment = .centerY
        selectedContent.distribution = .fill; selectedContent.spacing = 16
        add(selectedContent, to: stack)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        mode.addItems(withTitles: ["固定所选视频", "跟随最近播放的视频"])
        mode.target = self; mode.action = #selector(changed)
        mode.toolTip = "跟随最近成功播放的视频，切换 Scene、Web 或图片时保留原视频。"
        let options = NSStackView()
        options.orientation = .vertical; options.alignment = .leading; options.spacing = 8
        options.setHuggingPriority(.required, for: .vertical)
        add(row(label("内容模式"), trailing: mode), to: options)
        fill.addItems(withTitles: ["完整显示", "填充屏幕"])
        fill.target = self; fill.action = #selector(changed)
        add(row(label("画面布局"), trailing: fill), to: options)
        battery.controlSize = .small; battery.target = self; battery.action = #selector(changed)
        battery.toolTip = "关闭时使用视频静帧；系统低电量模式始终显示静帧。"
        add(row(label("使用电池时播放"), trailing: battery), to: options)
        add(label("始终静音循环。使用电池时关闭此项即可改为静帧。", secondary: true), to: options)
        add(options, to: stack)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        let guide = NSStackView()
        guide.orientation = .vertical; guide.alignment = .leading; guide.spacing = 12
        guide.setHuggingPriority(.required, for: .vertical)
        let guideTitle = label("在 macOS 中启用")
        guideTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        add(row(guideTitle, trailing: status), to: guide)
        let steps = NSStackView()
        steps.orientation = .vertical; steps.alignment = .leading; steps.spacing = 6
        steps.setHuggingPriority(.required, for: .vertical)
        for text in ["1  点击右下角“保存屏保”，自动安装并保存视频。",
                     "2  打开屏保设置：屏幕保护程序… → 自定义 →\n    其他 → 全部显示 → MyWallpaperX。",
                     "3  设定“启动屏幕保护程序…”的时间，再点“完成”。"] {
            add(label(text, secondary: true), to: steps)
        }
        add(steps, to: guide)
        let lockSettings = button("锁屏设置", #selector(openLockSettings))
        lockSettings.toolTip = "在“锁屏”页调整“屏幕保护程序启动或显示器关闭后需要密码”和显示器关闭时间；屏保启动时间应早于熄屏时间。"
        let actions = NSStackView(views: [button("打开屏保设置", #selector(openScreenSaverSettings)), lockSettings])
        actions.orientation = .horizontal; actions.distribution = .fillEqually; actions.spacing = 12
        add(actions, to: guide)
        add(label("屏保应早于熄屏；密码要求可在“锁屏设置”调整。", secondary: true), to: guide)
        feedback.font = .systemFont(ofSize: 12); feedback.textColor = .secondaryLabelColor
        feedback.maximumNumberOfLines = 2
        feedback.lineBreakMode = .byTruncatingTail
        add(feedback, to: guide)
        add(guide, to: stack)
    }

    private func label(_ text: String, secondary: Bool = false) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = .systemFont(ofSize: secondary ? 12 : 13)
        value.textColor = secondary ? .secondaryLabelColor : .labelColor
        return value
    }

    private func configureThumbnail(_ view: NSImageView, label: String) {
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = false
        view.contentTintColor = .tertiaryLabelColor
        view.wantsLayer = true; view.layer?.cornerRadius = 8; view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 144).isActive = true
        view.heightAnchor.constraint(equalToConstant: 90).isActive = true
        view.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        view.setAccessibilityLabel(label)
    }

    private func button(_ title: String, _ selector: Selector) -> NSButton {
        let value = NSButton(title: title, target: self, action: selector)
        WallpaperLibraryControlStyle.sheetCapsule(value)
        return value
    }

    private func row(_ title: NSView, trailing: NSView) -> NSView {
        let view = NSStackView(views: [title, NSView(), trailing])
        view.orientation = .horizontal; view.alignment = .centerY; view.spacing = 12
        view.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        return view
    }

    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func refresh() {
        guard window?.isVisible == true else { return }
        let content = draft.reference.flatMap { try? MyWallpaperXApplication.libraryWorkspace?.content(for: $0) }
        let actual = integration.configuration?.content
        if let reference = draft.reference {
            let savedTitle = actual.flatMap { $0.sourceIdentity == reference.storageKey ? $0.title : nil }
            selected.stringValue = content.flatMap { $0.kind == .video && $0.publishedAvailability.isAvailable ? $0.title : nil }
                ?? savedTitle ?? content?.title ?? "原视频暂不可用，请重新选择"
        } else { selected.stringValue = "选择一段喜欢的视频" }
        let matchesSaved = draft.reference != nil && draft.reference?.storageKey == actual?.sourceIdentity
        selectionHint.stringValue = draft.reference == nil ? "本地与已下载的视频均可选择"
            : (matchesSaved ? "当前屏保视频" : "所选视频 · 尚未保存")
        chooseButton.isEnabled = !isSaving
        status.stringValue = integration.isInstalled ? "组件已安装" : "保存时自动安装组件"
        refreshArtwork(content: content)
        let coordinator = ScreenSaverCoordinator.shared
        if isSaving { feedback.stringValue = actionFeedback }
        else if coordinator.isPreparing { feedback.stringValue = "正在同步最近播放的视频…" }
        else if let error = coordinator.errorMessage { feedback.stringValue = "尚未同步：" + error }
        else { feedback.stringValue = actionFeedback }
        feedback.isHidden = feedback.stringValue.isEmpty
        feedback.toolTip = feedback.stringValue
        saveButton.isEnabled = !isSaving && draft.reference != nil
        mode.isEnabled = !isSaving; fill.isEnabled = !isSaving; battery.isEnabled = !isSaving
    }

    private func refreshArtwork(content: WallpaperContentItem?) {
        let loadable = content.flatMap { $0.kind == .video && $0.publishedAvailability.isAvailable ? $0 : nil }
        let identity = loadable.map(WallpaperLibraryArtworkProvider.Identity.init)
        if identity != selectedArtworkIdentity {
            selectedArtworkCancellation?(); selectedArtworkCancellation = nil
            selectedArtworkIdentity = identity
            selectedPreview.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
            if let loadable {
                selectedArtworkCancellation = artworkLoader(loadable) { [weak self] image in
                    guard let self, self.selectedArtworkIdentity == identity else { return }
                    if let image {
                        self.selectedPreview.image = image
                    }
                }
            }
        }
        let matchesSaved = draft.reference != nil && draft.reference?.storageKey == integration.configuration?.content?.sourceIdentity
        let url = identity == nil && matchesSaved ? ScreenSaverCoordinator.shared.publishedPosterURL() : nil
        guard savedPosterURL != url else {
            if identity == nil { selectedPreview.image = savedImage ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil) }
            return
        }
        savedArtworkCancellation?.cancel(); savedArtworkCancellation = nil
        savedPosterURL = url; savedImage = nil
        if identity == nil { selectedPreview.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil) }
        guard let url else { return }
        let cancellation = ThumbnailCacheRequestCancellation()
        savedArtworkCancellation = cancellation
        posterLoader.load(path: url.path, cancellation: cancellation) { [weak self] result in
            guard let self, self.savedPosterURL == url, !cancellation.cancelled, case let .image(image) = result else { return }
            self.savedImage = image; self.selectedPreview.image = image
        }
    }

    private func stopArtwork() {
        selectedArtworkCancellation?(); selectedArtworkCancellation = nil
        savedArtworkCancellation?.cancel(); savedArtworkCancellation = nil
        selectedArtworkIdentity = nil; savedPosterURL = nil; savedImage = nil
        selectedPreview.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
    }

    @objc private func changed() {
        draft.mode = mode.indexOfSelectedItem == 0 ? .fixed : .followDesktop
        draft.fillMode = fill.indexOfSelectedItem == 0 ? "aspectFit" : "aspectFill"
        draft.playsOnBattery = battery.state == .on
        refresh()
    }

    @objc private func chooseAction() {
        guard let workspace = MyWallpaperXApplication.libraryWorkspace else { return }
        let presentation = presentationEpoch
        let picker = WallpaperPlaylistPickerController(workspace: workspace, manager: .shared, images: .shared,
            steam: .shared, pixabay: .shared, destination: .video(initial: draft.reference, accept: { [weak self] item in
                guard let self, self.presentationEpoch == presentation else { return }
                self.draft.reference = item.reference
                self.draft.mode = .fixed
                self.mode.selectItem(at: 0)
                self.refresh()
            }), hostWindow: { [weak self] in self?.window })
        self.picker = picker
        picker.onClose = { [weak self] in self?.picker = nil }
        picker.show()
    }

    @objc private func saveAction() {
        changed()
        isSaving = true
        actionFeedback = "正在准备视频，原屏保会保留到保存完成…"
        refresh()
        presentationEpoch &+= 1
        let operation = presentationEpoch
        let opensSystemSettings = integration.configuration?.content == nil
        let optionsOnly = original.reference == draft.reference && original.mode == draft.mode
            && integration.configuration?.content != nil && original != draft
        ScreenSaverCoordinator.shared.save(draft, optionsOnly: optionsOnly) { [weak self] result in
            guard let self, self.presentationEpoch == operation else { return }
            self.isSaving = false
            switch result {
            case .success:
                self.original = WallpaperManager.shared.settings.screenSaver
                self.draft = self.original
                self.actionFeedback = "已保存。首次使用请在系统设置中选择 MyWallpaperX。"
                if opensSystemSettings { self.openScreenSaverSettings() }
            case .failure(let error): self.actionFeedback = error.localizedDescription
            }
            self.refresh()
        }
    }

    @objc private func cancelAction() {
        if isSaving { ScreenSaverCoordinator.shared.cancel() }
        close()
    }

    override func close() {
        stopArtwork()
        picker?.close(); picker = nil
        presentationEpoch &+= 1
        subscriptions.removeAll()
        super.close()
    }

    func windowWillClose(_ notification: Notification) {
        if isSaving { ScreenSaverCoordinator.shared.cancel(); isSaving = false }
        presentationEpoch &+= 1
        subscriptions.removeAll()
        picker?.close(); picker = nil
        stopArtwork()
    }

    @objc private func openScreenSaverSettings() { openSettings("x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") }
    @objc private func openLockSettings() { openSettings("x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension") }
    private func openSettings(_ string: String) {
        guard let url = URL(string: string) else { return }
        if !NSWorkspace.shared.open(url), let fallback = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(fallback)
        }
    }

    @objc private func clearAction() { confirmRemoval(uninstall: false) }
    @objc private func uninstallAction() { confirmRemoval(uninstall: true) }
    private func confirmRemoval(uninstall: Bool) {
        guard let window else { return }
        let presentation = presentationEpoch
        let alert = makeAppAlert(title: uninstall ? "卸载屏保组件？" : "清除屏保内容？",
            message: "将停止跟随并清除已发布内容。桌面壁纸不受影响；系统屏保选择请在系统设置中调整。",
            style: .warning, buttons: [uninstall ? "卸载" : "清除", "取消"])
        presentAppAlert(alert, in: window) { [weak self] response in
            guard let self, self.presentationEpoch == presentation, response == .alertFirstButtonReturn else { return }
            self.presentationEpoch &+= 1
            let operation = self.presentationEpoch
            self.isSaving = true
            self.actionFeedback = uninstall ? "正在卸载组件…" : "正在清除内容…"
            self.refresh()
            ScreenSaverCoordinator.shared.clear(uninstall: uninstall) { [weak self] result in
                guard let self, self.presentationEpoch == operation else { return }
                self.isSaving = false
                self.original = WallpaperManager.shared.settings.screenSaver; self.draft = self.original
                self.mode.selectItem(at: 0)
                self.fill.selectItem(at: self.draft.fillMode == "aspectFit" ? 0 : 1)
                self.battery.state = self.draft.playsOnBattery ? .on : .off
                if case .failure(let error) = result { self.actionFeedback = error.localizedDescription }
                else { self.actionFeedback = uninstall ? "已卸载。系统可能在下次重新加载时退出旧组件。" : "已清除内容。" }
                self.refresh()
            }
        }
    }
}
