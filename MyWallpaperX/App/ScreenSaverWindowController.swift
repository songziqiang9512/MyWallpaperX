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
    private let selected = NSTextField(wrappingLabelWithString: String(localized: "Choose a Video You Like"))
    private let selectionHint = NSTextField(wrappingLabelWithString: "")
    private let selectedPreview = NSImageView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var actionFeedback = ""
    private let saveButton = NSButton(title: String(localized: "Save Screen Saver"), target: nil, action: nil)
    private let chooseButton = NSButton(title: String(localized: "Choose Video"), target: nil, action: nil)
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
        panel.title = String(localized: "Lock Screen & Screen Saver")
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
        let title = label(String(localized: "Lock Screen & Screen Saver"))
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        let close = WallpaperPanelCloseButton()
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Close"))
        close.target = self; close.action = #selector(cancelAction)
        let header = NSStackView(views: [symbol, title, NSView(), close])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 12
        let headerRule = WallpaperLibraryControlStyle.sectionDivider()
        let footerRule = WallpaperLibraryControlStyle.sectionDivider()
        let cancel = button(String(localized: "Cancel"), #selector(cancelAction))
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self; saveButton.action = #selector(saveAction)
        saveButton.keyEquivalent = "\r"
        WallpaperLibraryControlStyle.sheetCapsule(saveButton)
        let buttons = NSStackView(views: [cancel, saveButton])
        buttons.orientation = .horizontal; buttons.alignment = .centerY; buttons.spacing = 12
        let clear = button(String(localized: "Clear Content"), #selector(clearAction))
        let footer = NSStackView(views: [clear, NSView(), buttons])
        footer.orientation = .horizontal; footer.alignment = .centerY
        footer.distribution = .fill; footer.spacing = 12
        for group in [clear as NSView, buttons] {
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
        configureThumbnail(selectedPreview, label: String(localized: "Selected Video Thumbnail"))
        let selectedContent = NSStackView(views: [selectedPreview, chosen, chooseButton])
        selectedContent.orientation = .horizontal; selectedContent.alignment = .centerY
        selectedContent.distribution = .fill; selectedContent.spacing = 16
        add(selectedContent, to: stack)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        mode.addItems(withTitles: [String(localized: "Pin Selected Video"), String(localized: "Follow the Most Recently Played Video")])
        mode.target = self; mode.action = #selector(changed)
        mode.toolTip = String(localized: "Follow the most recently played video and keep it when switching to Scene, Web, or images.")
        let options = NSStackView()
        options.orientation = .vertical; options.alignment = .leading; options.spacing = 8
        options.setHuggingPriority(.required, for: .vertical)
        add(row(label(String(localized: "Content Mode")), trailing: mode), to: options)
        fill.addItems(withTitles: [String(localized: "Fit"), String(localized: "Fill Screen")])
        fill.target = self; fill.action = #selector(changed)
        add(row(label(String(localized: "Screen Layout")), trailing: fill), to: options)
        battery.controlSize = .small; battery.target = self; battery.action = #selector(changed)
        battery.toolTip = String(localized: "Use a video still frame when closed; Low Power Mode always shows a still frame.")
        add(row(label(String(localized: "Play on Battery")), trailing: battery), to: options)
        add(label(String(localized: "Always loops muted. Turn this off on battery to show a still frame instead."), secondary: true), to: options)
        add(options, to: stack)
        WallpaperLibraryControlStyle.addSectionDivider(to: stack)
        let guide = NSStackView()
        guide.orientation = .vertical; guide.alignment = .leading; guide.spacing = 12
        guide.setHuggingPriority(.required, for: .vertical)
        let guideTitle = label(String(localized: "Enable in macOS"))
        guideTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        add(row(guideTitle, trailing: status), to: guide)
        let steps = NSStackView()
        steps.orientation = .vertical; steps.alignment = .leading; steps.spacing = 6
        steps.setHuggingPriority(.required, for: .vertical)
        for text in [String(localized: "1  After saving the video, click “Open Screen Saver Settings”."),
                     String(localized: "2  Click “Screen Saver…” → Customize → MyWallpaperX group,\n    then select the saved video."),
                     String(localized: "3  Set when the screen saver starts, then click “Done”. You don’t need to change the desktop wallpaper.")] {
            add(label(text, secondary: true), to: steps)
        }
        add(steps, to: guide)
        let lockSettings = button(String(localized: "Lock Screen Settings"), #selector(openLockSettings))
        lockSettings.toolTip = String(localized: "On the “Lock Screen” pane, set “Require password after the screen saver begins or the display turns off” and the display-off time. The screen saver should start before the display turns off.")
        let actions = NSStackView(views: [button(String(localized: "Open Screen Saver Settings"), #selector(openScreenSaverSettings)), lockSettings])
        actions.orientation = .horizontal; actions.distribution = .fillEqually; actions.spacing = 12
        add(actions, to: guide)
        add(label(String(localized: "The screen saver start time must be earlier than the display-off time. Desktop wallpaper stays as is."), secondary: true), to: guide)
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
                ?? savedTitle ?? content?.title ?? String(localized: "The original video isn’t available. Please choose another one.")
        } else { selected.stringValue = String(localized: "Choose a Video You Like") }
        let matchesSaved = draft.reference != nil && draft.reference?.storageKey == actual?.sourceIdentity
        selectionHint.stringValue = draft.reference == nil ? String(localized: "Local and downloaded videos can both be selected")
            : (matchesSaved ? String(localized: "Current Screen Saver Video") : String(localized: "Selected video · Not saved"))
        chooseButton.isEnabled = !isSaving
        status.stringValue = integration.hasBundledComponent ? String(localized: "System components are included with the app") : String(localized: "System Component Missing")
        refreshArtwork(content: content)
        let coordinator = ScreenSaverCoordinator.shared
        if isSaving { feedback.stringValue = actionFeedback }
        else if coordinator.isPreparing { feedback.stringValue = String(localized: "Syncing the most recently played video…") }
        else if let error = coordinator.errorMessage { feedback.stringValue = String(localized: "Not synced yet:") + error }
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
        actionFeedback = String(localized: "Preparing the video. The current screen saver remains until saving finishes…")
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
                self.actionFeedback = String(localized: "Saved. On first use, choose MyWallpaperX in System Settings.")
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

    @objc private func clearAction() {
        guard let window else { return }
        let presentation = presentationEpoch
        let alert = makeAppAlert(title: String(localized: "Clear Screensaver Content?"),
            message: String(localized: "Follow mode will stop and the published video will be cleared. Change the system wallpaper and screen saver in System Settings."),
            style: .warning, buttons: [String(localized: "Clear"), String(localized: "Cancel")])
        presentAppAlert(alert, in: window) { [weak self] response in
            guard let self, self.presentationEpoch == presentation, response == .alertFirstButtonReturn else { return }
            self.presentationEpoch &+= 1
            let operation = self.presentationEpoch
            self.isSaving = true
            self.actionFeedback = String(localized: "Clearing content…")
            self.refresh()
            let finished: @MainActor (Result<Void, Error>) -> Void = { [weak self] result in
                guard let self, self.presentationEpoch == operation else { return }
                self.isSaving = false
                self.original = WallpaperManager.shared.settings.screenSaver; self.draft = self.original
                self.mode.selectItem(at: 0)
                self.fill.selectItem(at: self.draft.fillMode == "aspectFit" ? 0 : 1)
                self.battery.state = self.draft.playsOnBattery ? .on : .off
                if case .failure(let error) = result { self.actionFeedback = error.localizedDescription }
                else { self.actionFeedback = String(localized: "Content cleared.") }
                self.refresh()
            }
            ScreenSaverCoordinator.shared.clear(completion: finished)
        }
    }
}
