import AppKit
import Combine

// Runtime/pixel leaves do not play, inspect, read files or build another index.
nonisolated struct PlaybackSwitchTicket: Hashable, Sendable { let id: UUID }
nonisolated struct PickerPlayingValue { let reference: WallpaperReference; let ticket: PlaybackSwitchTicket }
@MainActor final class WallpaperManager {
    struct Switch { var committed: PickerPlayingValue? }
    struct Sequence { var committed: PickerPlayingValue? }
    var playbackSwitch = Switch(), libraryPlaybackSequence = Sequence()
}
@MainActor final class SILService {}
// ACTUAL_CARD_STATE

@MainActor final class PickerPresentation {
    @Published var state = 0
    var canEditCollections = true
    var errors: [String] = []
    func report(_ error: Error) { errors.append(error.localizedDescription) }
}
@MainActor final class PickerCatalog {
    var catalog = WallpaperLibraryCatalog()
    let visibleLocalFactsRefreshed = PassthroughSubject<Void, Never>()
    var leases: [UUID: Set<WallpaperReference>] = [:]
    func setVisibleReferences(_ references: Set<WallpaperReference>, sourceToken: UUID) { leases[sourceToken] = references }
}
@MainActor final class WallpaperLibraryWorkspace {
    let collections: UserCollectionsController?
    var relationships: UserCollectionsSnapshot { collections!.snapshot }
    let presentation = PickerPresentation(), catalog = PickerCatalog()
    let playbackChanges = PassthroughSubject<Void, Never>()
    var memberEdits: [WallpaperLibraryPage] = []
    private var subscription: AnyCancellable?
    init(_ collections: UserCollectionsController) {
        self.collections = collections
        subscription = collections.$snapshot.sink { [weak self] _ in self?.presentation.state += 1 }
    }
    func didEditMembers(of page: WallpaperLibraryPage) { memberEdits.append(page) }
    func publish(_ value: WallpaperLibraryCatalog) { catalog.catalog = value; presentation.state += 1 }
}

@MainActor final class PickerCardLeaf: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("PickerCardLeaf")
    let titleLabel = NSTextField(labelWithString: "")
    override func loadView() {
        view = WallpaperCardInteractionView()
        titleLabel.setAccessibilityElement(false)
        view.addSubview(titleLabel)
    }
    override func viewDidLayout() { super.viewDidLayout(); titleLabel.frame = NSRect(x: 8, y: 8, width: view.bounds.width - 16, height: 20) }
}
@MainActor final class WallpaperLibraryCellAdapter {
    private let playing: (WallpaperReference) -> Bool
    var viewport: [WallpaperContentItem] = []
    init(manager: WallpaperManager, images: SILService, steam: SteamWorkshopService, pixabay: PixabayService,
         isPlaying: @escaping (WallpaperReference) -> Bool,
         makePrimaryAction: @escaping (WallpaperContentItem) -> (() -> Void)?) { playing = isPlaying }
    func makeCell(collection: NSCollectionView, indexPath: IndexPath, content: WallpaperContentItem,
                  state: WallpaperLibraryGridController.CellState) -> NSCollectionViewItem {
        collection.register(PickerCardLeaf.self, forItemWithIdentifier: PickerCardLeaf.reuseID)
        let cell = collection.makeItem(withIdentifier: PickerCardLeaf.reuseID, for: indexPath)
        updateCell(cell, content: content, state: state)
        return cell
    }
    func updateCell(_ cell: NSCollectionViewItem, content: WallpaperContentItem, state: WallpaperLibraryGridController.CellState) {
        (cell as? PickerCardLeaf)?.titleLabel.stringValue = content.title
        cell.view.setAccessibilityLabel(content.title)
        _ = playing(content.reference)
    }
    func needsCellReplacement(_ cell: NSCollectionViewItem, content: WallpaperContentItem) -> Bool { false }
    func setVisible(_ cell: NSCollectionViewItem, _ visible: Bool) {}
    func updateViewport(visible: [WallpaperContentItem], prefetch: [WallpaperContentItem]) { viewport = visible }
    func repairVisiblePreviews() {}
}
@MainActor enum PickerAlerts { static var count = 0; static var hiddenWindowAlerts = 0 }
@MainActor final class PickerSubmissionFlag { var submitted = false }
@MainActor func makeAppAlert(title: String, message: String) -> NSAlert { let alert = NSAlert(); alert.messageText = title; return alert }
@MainActor func presentAppAlert(_ alert: NSAlert, in window: NSWindow? = nil) {
    PickerAlerts.count += 1
    if window?.isVisible != true { PickerAlerts.hiddenWindowAlerts += 1 }
}

extension UserCollectionsStore {
    /// A bounded real actor queue barrier, not a replacement relationship store.
    func holdForPickerFixture(entered: DispatchSemaphore, release: DispatchSemaphore) {
        entered.signal()
        _ = release.wait(timeout: .now() + 4)
    }
}

@main enum WallpaperPlaylistPickerChecks {
    @MainActor static func main() {
        initializeNativeAppHarness()
        let app = NSApplication.shared
        Task { @MainActor in
            do { try await run() }
            catch { fatalError("Real Picker fixture: \(error)") }
            app.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { app.postEvent(event, atStart: false) }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        let app = NSApplication.shared, delegate = AppDelegate()
        app.delegate = delegate; MainMenuBuilder.installMainMenu()
        let host = MenuTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false; host.center()
        let hostController = MainWindowController(window: host)
        MainWindowCoordinator.mainWindowController = hostController
        app.activate(); host.makeKeyAndOrderFront(nil)
        let store = UserCollectionsStore(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let collections = UserCollectionsController(store: store, snapshot: try await store.snapshot())
        let workspace = WallpaperLibraryWorkspace(collections), manager = WallpaperManager()
        let images = SILService(), steam = SteamWorkshopService(), pixabay = PixabayService()
        var checks: [String: Bool] = [:]
        func content(_ provider: WallpaperProvider, _ id: String, _ kind: WallpaperMediaKind,
                     availability: WallpaperPublishedAvailability = .available) -> WallpaperContentItem {
            let reference = WallpaperReference(provider: provider, sourceID: id)
            return .init(reference: reference, providerReference: reference,
                locator: .init(path: "/controlled/\(id).media", titleHint: id, mediaKind: kind), title: id, kind: kind,
                publishedAvailability: availability, capabilities: [.play, .organize, .inspect], metadata: .init(),
                acquisition: .idle, update: .idle, aliases: [])
        }
        let values = [content(.videoLibrary, "video-one", .video), content(.videoLibrary, "video-two", .video),
            content(.staticImageLibrary, "image-one", .image), content(.staticImageLibrary, "image-two", .image),
            content(.steamWorkshop, "123456", .scene), content(.steamWorkshop, "123457", .web),
            content(.pixabay, "21", .video), content(.pixabay, "22", .video)]
        hostController.libraryCommands.selection = [values[0]]
        var catalog = WallpaperLibraryCatalog(videos: Array(values.prefix(2)), images: Array(values[2..<4]), downloads: Array(values[4..<8]))
        catalog.revision = 1; workspace.publish(catalog)
        let target = try await collections.createPlaylist(name: "Mixed", members: [values[0].organizationItem, values[6].organizationItem])
        let sharedTint = ListThumbnailTintSource()
        var tintLoads = 0
        let tintImage = NSImage(size: NSSize(width: 8, height: 8))
        tintImage.lockFocus(); NSColor.systemRed.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); tintImage.unlockFocus()
        sharedTint.update(id: "main-first") { done in tintLoads += 1; done(tintImage); return {} }
        let sourceRevision = sharedTint.request?.revision
        var keepAlive: [WallpaperPlaylistPickerController] = []
        defer {
            keepAlive.forEach { $0.close() }
            host.close(); MainWindowCoordinator.mainWindowController = nil
        }
        func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, type) }
        }
        func settle(_ seconds: Double = 0.035) async {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            app.keyWindow?.contentView?.layoutSubtreeIfNeeded()
        }
        func wait(_ label: String, until predicate: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(2)
            while !predicate(), Date() < deadline { await settle(0.005) }
            guard predicate() else { throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: label]) }
        }
        func open(_ id: UUID) async throws -> (WallpaperPlaylistPickerController, NSWindow, WallpaperLibraryGridController) {
            let picker = WallpaperPlaylistPickerController(workspace: workspace, manager: manager, images: images,
                steam: steam, pixabay: pixabay, destination: .playlist(id), hostWindow: { host })
            keepAlive.append(picker); picker.show()
            try await wait("Picker did not become the actual native key sheet") {
                host.attachedSheet?.delegate === picker && app.keyWindow === host.attachedSheet
            }
            let panel = host.attachedSheet!
            await settle()
            let collection = descendants(panel.contentView!, NSCollectionView.self).first!
            let grid = collection.delegate as! WallpaperLibraryGridController
            do {
                try await wait("Picker did not publish its real cells") { !grid.items.isEmpty && !collection.visibleItems().isEmpty }
            } catch {
                var view: NSView? = collection
                while let current = view {
                    let line = "Picker geometry \(type(of: current)) frame=\(current.frame) visible=\(current.visibleRect) hidden=\(current.isHiddenOrHasHiddenAncestor)\n"
                    FileHandle.standardError.write(Data(line.utf8))
                    view = current.superview
                }
                throw error
            }
            return (picker, panel, grid)
        }
        func entries(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(entries) ?? []) } }
        let menuItems = entries(app.mainMenu!)
        func entry(_ command: MainMenuCommand) -> NSMenuItem { menuItems.first { $0.identifier == command.identifier }! }
        func menu(_ command: MainMenuCommand) {
            let item = entry(command)
            _ = delegate.validateMenuItem(item)
            _ = app.sendAction(item.action!, to: item.target, from: item)
        }
        func key(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) async throws {
            let panel = app.keyWindow!
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
            if app.mainMenu?.performKeyEquivalent(with: event) != true { app.sendEvent(event) }
            await settle()
        }
        func addButton(_ panel: NSWindow) -> NSButton { descendants(panel.contentView!, NSButton.self).first { $0.title.hasPrefix("添加 ") }! }
        func footer(_ panel: NSWindow) -> String { descendants(panel.contentView!, NSTextField.self).first { $0.stringValue.hasPrefix("已选 ") }!.stringValue }
        func filter(_ picker: WallpaperPlaylistPickerController, _ panel: NSWindow, text: String, expectedCount: Int = 1) async throws {
            let search = descendants(panel.contentView!, NSSearchField.self).first!
            search.stringValue = text; picker.controlTextDidChange(.init(name: NSControl.textDidChangeNotification, object: search)); await settle()
            let collection = descendants(panel.contentView!, NSCollectionView.self).first!
            let grid = collection.delegate as! WallpaperLibraryGridController
            try await wait("Picker did not finish its filtered grid update") { grid.items.count == expectedCount }
        }
        func marker(_ cell: NSCollectionViewItem) -> NSView? {
            cell.view.subviews.first { view in descendants(view, NSTextField.self).contains { $0.stringValue == "已在列表" } }
        }
        func tracePicker(_ phase: String, panel: NSWindow, grid: WallpaperLibraryGridController) {
            let bindings: [[String: Any]] = grid.collection.visibleItems().map { cell in
                let path = grid.collection.indexPath(for: cell)
                let decoration = marker(cell)
                return ["index": path?.item ?? -1, "reference": path.flatMap { grid.items.indices.contains($0.item) ? grid.items[$0.item].reference.storageKey : nil } ?? "none",
                    "markerPresent": decoration != nil, "markerHidden": decoration?.isHidden ?? true,
                    "markerPassive": decoration.map { $0.hitTest(NSPoint(x: 1, y: 1)) == nil && !$0.isAccessibilityElement() } ?? false]
            }
            let facts: [String: Any] = ["phase": phase, "items": grid.items.map { $0.reference.storageKey },
                "selected": grid.selection.references.map(\.storageKey).sorted(), "selecting": grid.selection.isSelecting,
                "nativeSelection": grid.collection.selectionIndexPaths.map(\.item).sorted(), "allowsMultiple": grid.collection.allowsMultipleSelection,
                "footer": footer(panel), "add": addButton(panel).title, "addEnabled": addButton(panel).isEnabled,
                "keyPanel": app.keyWindow === panel, "gridResponder": panel.firstResponder === grid.collection,
                "firstResponder": String(describing: panel.firstResponder), "canInput": WallpaperLibrarySheetPresentation.permitsInput(in: panel),
                "members": collections.snapshot.members.filter { $0.playlistID == target }.map { $0.reference.storageKey }.sorted(),
                "markers": bindings, "viewport": NSStringFromRect(grid.scrollView.contentView.bounds)]
            FileHandle.standardError.write(Data("PickerState \(String(data: try! JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), encoding: .utf8)!)\n".utf8))
        }
        func holdStore() async throws -> DispatchSemaphore {
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            Task { await store.holdForPickerFixture(entered: entered, release: release) }
            let reached: Bool = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: entered.wait(timeout: .now() + 2) == .success)
                }
            }
            guard reached else { throw CocoaError(.coderInvalidValue) }
            return release
        }

        try await wait("Picker input positive-control host did not become active/key") { app.isActive && host.isKeyWindow }
        let backgroundProbe = WallpaperModalInputProbe.install(in: host)
        let beforeModalInput = backgroundProbe.values
        try await backgroundProbe.deliver()
        let nativeInputWasLive = WallpaperModalInputProbe.hasOneDelivery(beforeModalInput, backgroundProbe.values)
        checks["picker-main-native-queue-click-drag-and-key-have-an-unblocked-positive-control"] = nativeInputWasLive
        let (picker, panel, grid) = try await open(target)
        let beforeBackgroundInput = backgroundProbe.values
        try await backgroundProbe.deliver()
        checks["picker-native-sheet-blocks-background-click-drag-and-key-with-system-modal-backdrop"] = nativeInputWasLive
            && backgroundProbe.values == beforeBackgroundInput
            && app.keyWindow === panel && panel.sheetParent === host && host.attachedSheet === panel
            && !WallpaperLibrarySheetPresentation.permitsInput(in: host) && !panel.isOpaque && panel.backgroundColor == .clear
        checks["picker-is-the-key-panel-delegate-and-does-not-borrow-the-host-domain"] = app.keyWindow === panel && panel.delegate === picker
            && panel.sheetParent === host && panel.isSheet && grid.selection.isSelecting
        let zoom = descendants(panel.contentView!, WallpaperLibraryZoomControl.self).first!
        let source = descendants(panel.contentView!, NSSegmentedControl.self).first { $0.segmentCount == 4 }!
        let search = descendants(panel.contentView!, NSSearchField.self).first!
        checks["native-background-input-probe-keeps-the-picker-search-and-all-eight-source-facts-unchanged"] = search.stringValue.isEmpty
            && Set(grid.items.map(\.reference)) == Set(values.map(\.reference))
        checks["picker-starts-at-five-columns-with-the-shared-native-zoom"] = WallpaperLibraryGridMetrics(
            clipWidth: grid.scrollView.contentView.bounds.width, preferredColumns: 5).columns == 5
            && zoom.segmentCount == 2 && zoom.trackingMode == .momentary && picker.canZoom(-1) && picker.canZoom(1)
        panel.setContentSize(NSSize(width: 680, height: 480)); await settle()
        let controls = [source as NSView, zoom, search]
        let contentFrames = controls.map { $0.convert($0.bounds, to: panel.contentView!) }
        let topFits = zip(contentFrames, contentFrames.dropFirst()).allSatisfy { pair in pair.0.maxX + 15.5 <= pair.1.minX }
        checks["picker-minimum-680-keeps-four-source-segments-220-search-and-zoom-without-clipping"] = topFits
            && contentFrames.allSatisfy { panel.contentView!.bounds.contains($0) }
            && abs(search.frame.width - 220) <= 0.5 && source.frame.width + 0.5 >= source.fittingSize.width
            && source.segmentCount == 4 && source.label(forSegment: 3) == "我的下载"
        checks["picker-uses-detail-material-without-observing-main-tint-and-keeps-native-capsules"] = panel.contentView is WallpaperPanelSurface
            && sharedTint.request?.revision == sourceRevision && tintLoads == 0 && source.segmentStyle == .capsule
            && source.borderShape == .capsule && zoom.borderShape == .capsule
            && descendants(panel.contentView!, NSButton.self).filter { ["取消", "添加 0 项"].contains($0.title) }.allSatisfy {
                $0.borderShape == .capsule && $0.bezelStyle == .glass && $0.controlSize == .large
            }
        panel.makeFirstResponder(grid.collection)
        try await key(124, String(UnicodeScalar(NSRightArrowFunctionKey)!))
        let initialFocus = grid.selection.focusedReference
        checks["picker-arrow-focus-is-independent-of-an-empty-selection"] = initialFocus == grid.items.first?.reference && grid.selection.references.isEmpty
        let externalTicket = PlaybackSwitchTicket(id: UUID())
        let externalPlaying = PickerPlayingValue(reference: values[0].reference, ticket: externalTicket)
        manager.playbackSwitch.committed = externalPlaying; manager.libraryPlaybackSequence.committed = externalPlaying
        workspace.playbackChanges.send(); await settle()
        checks["same-items-playback-echo-preserves-unselected-keyboard-focus"] = grid.selection.focusedReference == initialFocus && grid.selection.references.isEmpty
        try await key(124, String(UnicodeScalar(NSRightArrowFunctionKey)!))
        checks["picker-next-arrow-continues-after-an-unselected-focus-echo"] = grid.selection.focusedReference == grid.items[1].reference && grid.selection.references.isEmpty
        let hostInput = (hostController.searches, hostController.zooms.count)
        try await key(3, "f", modifiers: .command)
        checks["main-menu-search-focuses-the-actual-picker-field"] = search.currentEditor() != nil && panel.firstResponder === search.currentEditor()
            && hostController.searches == hostInput.0
        try await key(27, "-", modifiers: .command)
        checks["main-menu-minus-changes-picker-to-six-without-changing-the-host"] = !picker.canZoom(-1) && zoom.isEnabled(forSegment: 0) == false
            && hostController.zooms.count == hostInput.1 && delegate.validateMenuItem(entry(.zoomOut)) == false
        menu(.zoomOut); await settle()
        checks["picker-disabled-six-column-endpoint-never-falls-through-to-the-main-window"] = !picker.canZoom(-1) && hostController.zooms.count == hostInput.1
        for _ in 0..<3 { try await key(24, "+", modifiers: .command) }
        checks["picker-plus-reaches-three-and-disables-its-opposite-endpoint"] = !picker.canZoom(1) && picker.canZoom(-1)
            && zoom.isEnabled(forSegment: 1) == false && !delegate.validateMenuItem(entry(.zoomIn))
        // Return to five so all eight cells are visible for membership markers.
        menu(.zoomOut); menu(.zoomOut); await settle()
        panel.makeFirstResponder(grid.collection)
        tracePicker("before-native-select-all", panel: panel, grid: grid)
        try await key(0, "a", modifiers: .command)
        tracePicker("after-native-select-all", panel: panel, grid: grid)
        checks["picker-command-a-selects-the-real-grid-and-reports-selected-new-existing-counts"] = grid.selection.references.count == 8
            && footer(panel) == "已选 8 项 · 将新增 6 项 · 2 项已在列表" && addButton(panel).title == "添加 6 项"
        let existing = Set([values[0].reference, values[6].reference])
        let markerBindings = grid.collection.visibleItems().allSatisfy { cell in
            guard let path = grid.collection.indexPath(for: cell), let decoration = marker(cell) else { return false }
            return decoration.isHidden == !existing.contains(grid.items[path.item].reference)
                && decoration.hitTest(NSPoint(x: 1, y: 1)) == nil && !decoration.isAccessibilityElement()
        }
        checks["existing-members-have-passive-per-cell-markers-without-hijacking-card-input-or-accessibility"] = markerBindings
            && grid.collection.visibleItems().count == 8
        try await collections.perform(.addMembers(target, [values[1].organizationItem], Date()))
        await settle()
        tracePicker("after-external-membership-publish", panel: panel, grid: grid)
        checks["external-membership-echo-recomputes-new-count-without-clearing-selection"] = footer(panel) == "已选 8 项 · 将新增 5 项 · 3 项已在列表"
            && addButton(panel).title == "添加 5 项" && grid.selection.references.count == 8
        let child = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        child.isReleasedWhenClosed = false
        panel.beginSheet(child, completionHandler: { _ in })
        try await wait("Picker nested panel not key") { child.isKeyWindow }
        let beforeNestedMembers = collections.snapshot, nestedSelection = grid.selection
        addButton(panel).performClick(nil); picker.performZoom(-1); picker.focusSearch()
        checks["nested-modal-domain-rejects-held-picker-add-search-and-zoom-without-touching-selection"] = collections.snapshot == beforeNestedMembers
            && grid.selection == nestedSelection && !picker.canFocusSearch && !picker.canZoom(-1)
            && panel.attachedSheet === child && child.isKeyWindow
        panel.endSheet(child); child.orderOut(nil)
        try await wait("Picker parent input did not return") { panel.attachedSheet == nil && panel.isKeyWindow }
        source.selectedSegment = 1; _ = app.sendAction(source.action!, to: source.target, from: source); await settle()
        tracePicker("after-native-video-filter", panel: panel, grid: grid)
        checks["source-filter-clips-selection-and-all-existing-selection-disables-add-zero"] = grid.items.count == 2
            && grid.selection.references.count == 2 && footer(panel) == "已选 2 项 · 将新增 0 项 · 2 项已在列表"
            && addButton(panel).title == "添加 0 项" && !addButton(panel).isEnabled
        let beforeNoop = collections.snapshot
        addButton(panel).performClick(nil); await settle()
        checks["all-existing-add-zero-does-not-write-or-report-a-fake-success"] = collections.snapshot == beforeNoop && workspace.memberEdits.isEmpty
        source.selectedSegment = 2; _ = app.sendAction(source.action!, to: source.target, from: source); await settle()
        try await wait("Image filter did not finish its native grid transition") { grid.items.count == 2 && grid.items.allSatisfy { $0.kind == .image } }
        tracePicker("after-native-image-filter", panel: panel, grid: grid)
        checks["reused-cells-explicitly-clear-the-former-target-membership-marker"] = grid.items.count == 2
            && grid.selection.references.isEmpty && grid.collection.visibleItems().allSatisfy { marker($0)?.isHidden == true }
        let mounted = grid.collection.visibleItems()
        picker.close(); await settle()
        checks["closing-the-picker-revokes-markers-source-leases-and-main-menu-delegation"] = mounted.allSatisfy { marker($0)?.isHidden != false }
            && workspace.catalog.leases.values.allSatisfy(\.isEmpty) && !picker.canFocusSearch && !picker.canZoom(-1)
        host.makeKeyAndOrderFront(nil); await settle()
        let afterPickerClose = backgroundProbe.values
        try await backgroundProbe.deliver()
        checks["picker-close-ends-native-modality-and-restores-background-click-drag-and-key"] = WallpaperModalInputProbe.hasOneDelivery(afterPickerClose, backgroundProbe.values)

        let (keyPicker, keyPanel, keyGrid) = try await open(target)
        try await filter(keyPicker, keyPanel, text: "video-one")
        keyPanel.makeFirstResponder(keyGrid.collection); try await key(0, "a", modifiers: .command)
        let spaceSelection = keyGrid.selection, hostSelection = hostController.libraryCommands.selection.map(\.reference)
        let hostPreviews = hostController.libraryCommands.previews, hostApplies = hostController.libraryCommands.applies
        try await key(49, " ")
        checks["picker-grid-space-preserves-single-selection-without-playing-or-previewing-the-host"] = spaceSelection.references.count == 1
            && keyGrid.selection == spaceSelection && hostController.libraryCommands.previews == hostPreviews
            && hostController.libraryCommands.applies == hostApplies && manager.playbackSwitch.committed?.ticket == externalTicket
        try await key(3, "f", modifiers: .command)
        let keySearch = descendants(keyPanel.contentView!, NSSearchField.self).first!
        let textEditor = keySearch.currentEditor() as? NSTextView
        textEditor?.setSelectedRange(NSRange(location: textEditor?.string.utf16.count ?? 0, length: 0))
        let textBeforeSpace = keySearch.stringValue
        try await key(49, " ")
        checks["picker-search-space-keeps-native-text-editing-instead-of-toggling-a-card"] = textEditor != nil
            && keySearch.stringValue == textBeforeSpace + " " && keyGrid.selection.references == spaceSelection.references
            && hostController.libraryCommands.previews == hostPreviews
        keyPanel.makeFirstResponder(keyGrid.collection)
        try await key(53, "\u{1b}")
        checks["picker-grid-escape-closes-the-real-sheet-without-changing-the-host-selection"] = !keyPanel.isVisible
            && !keyPicker.canFocusSearch && !keyPicker.canZoom(1) && hostController.libraryCommands.selection.map(\.reference) == hostSelection
            && hostSelection == [values[0].reference] && workspace.memberEdits.isEmpty
        host.makeKeyAndOrderFront(nil); await settle()

        let (aliasPicker, aliasPanel, aliasGrid) = try await open(target)
        checks["each-new-picker-starts-with-a-fresh-five-column-temporary-preference"] = aliasPicker.canZoom(-1) && aliasPicker.canZoom(1)
            && descendants(aliasPanel.contentView!, WallpaperLibraryZoomControl.self).first?.toolTip?.contains("每行 5") == true
        aliasPanel.makeFirstResponder(aliasGrid.collection)
        for _ in 0..<4 { try await key(124, String(UnicodeScalar(NSRightArrowFunctionKey)!)) }
        let focusBeforeAlias = aliasGrid.selection.focusedReference
        try await collections.perform(.linkAlias(.init(alias: values[3].reference, canonical: values[2].reference, proof: .explicitUserRelocation), Date()))
        await settle()
        checks["alias-refresh-preserves-visible-canonical-focus-without-selecting-it"] = focusBeforeAlias == values[3].reference
            && aliasGrid.selection.focusedReference == values[2].reference && aliasGrid.selection.references.isEmpty
            && aliasGrid.items.count == 7
        // The canonical title is image-one, so the old search no longer matches.
        try await filter(aliasPicker, aliasPanel, text: "image-two", expectedCount: 0)
        checks["alias-refresh-canonicalizes-then-clips-focus-that-is-no-longer-visible"] = focusBeforeAlias == values[3].reference
            && aliasGrid.items.isEmpty && aliasGrid.selection.focusedReference == nil && aliasGrid.selection.references.isEmpty
        aliasPicker.close(); host.makeKeyAndOrderFront(nil); await settle()

        let lateTarget = try await collections.createPlaylist(name: "FIFO canonical")
        let (latePicker, latePanel, lateGrid) = try await open(lateTarget)
        try await filter(latePicker, latePanel, text: "video-two")
        latePanel.makeFirstResponder(lateGrid.collection); try await key(0, "a", modifiers: .command)
        let release = try await holdStore()
        let linkSubmission = PickerSubmissionFlag()
        let linking = Task { @MainActor in
            linkSubmission.submitted = true
            try await collections.perform(.linkAlias(.init(alias: values[1].reference, canonical: values[0].reference, proof: .explicitUserRelocation), Date()))
        }
        try await wait("Earlier real alias command did not enter the controller FIFO") { linkSubmission.submitted }
        try await key(36, "\r")
        latePicker.close(); release.signal(); _ = try await linking.value; _ = await collections.flush(); await settle()
        checks["admitted-add-uses-latest-store-canonical-alias-and-notifies-after-the-sheet-closes"] = collections.snapshot.members.filter { $0.playlistID == lateTarget }.map(\.reference) == [values[0].reference]
            && workspace.memberEdits == [.playlist(lateTarget)] && PickerAlerts.count == 0
        let reopened = UserCollectionsStore(url: URL(fileURLWithPath: CommandLine.arguments[1]), allowCreate: false)
        checks["picker-add-result-is-a-real-durable-relationship-not-a-private-grid-copy"] = try await reopened.snapshot() == collections.snapshot

        let failedTarget = try await collections.createPlaylist(name: "Closed failure")
        host.makeKeyAndOrderFront(nil); await settle()
        let (failedPicker, failedPanel, failedGrid) = try await open(failedTarget)
        try await filter(failedPicker, failedPanel, text: "image-one")
        failedPanel.makeFirstResponder(failedGrid.collection); try await key(0, "a", modifiers: .command)
        let failureRelease = try await holdStore()
        let deleteSubmission = PickerSubmissionFlag()
        let deleting = Task { @MainActor in deleteSubmission.submitted = true; try await collections.perform(.deletePlaylist(failedTarget)) }
        try await wait("Earlier target deletion did not enter the controller FIFO") { deleteSubmission.submitted }
        let editsBeforeFailure = workspace.memberEdits, alertsBeforeFailure = PickerAlerts.count
        addButton(failedPanel).performClick(nil); await settle(0.02)
        failedPicker.close(); failureRelease.signal(); _ = try await deleting.value; _ = await collections.flush(); await settle()
        checks["closed-picker-fifo-failure-never-restores-controls-or-presents-a-hidden-window-alert"] = PickerAlerts.count == alertsBeforeFailure
            && PickerAlerts.hiddenWindowAlerts == 0 && workspace.memberEdits == editsBeforeFailure
            && !failedPicker.canFocusSearch && !collections.snapshot.members.contains { $0.playlistID == failedTarget }

        let resetTarget = try await collections.createPlaylist(name: "Reset revocation")
        host.makeKeyAndOrderFront(nil); await settle()
        let (resetPicker, resetPanel, _) = try await open(resetTarget)
        try await collections.reset(); await settle()
        checks["reset-closes-the-fixed-target-picker-and-revokes-search-and-zoom"] = !resetPanel.isVisible
            && !resetPicker.canFocusSearch && !resetPicker.canZoom(1) && collections.snapshot.members.isEmpty
        checks["picker-never-claims-provider-playback-or-inspector-actions"] = manager.playbackSwitch.committed?.ticket == externalTicket
            && manager.libraryPlaybackSequence.committed?.ticket == externalTicket && hostController.libraryCommands.applies == 0
            && hostController.libraryCommands.infos == 0 && workspace.presentation.errors.isEmpty
        host.makeKeyAndOrderFront(nil); await settle()
        let settings = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false; settings.contentView = WallpaperPanelSurface()
        precondition(WallpaperLibrarySheetPresentation.present(settings, in: host))
        try await wait("Video settings sheet did not become key") { settings.isKeyWindow }
        let beforeVideoSelection = collections.snapshot
        var chosenVideos: [WallpaperReference] = []
        var videoCatalog = catalog
        videoCatalog.revision += 1
        videoCatalog.downloads += [content(.steamWorkshop, "missing-video", .video, availability: .unavailable),
                                   content(.steamWorkshop, "remote-video", .video, availability: .remote)]
        workspace.publish(videoCatalog)
        func openVideo() async throws -> (WallpaperPlaylistPickerController, NSWindow, WallpaperLibraryGridController) {
            let picker = WallpaperPlaylistPickerController(workspace: workspace, manager: manager, images: images,
                steam: steam, pixabay: pixabay, destination: .video(initial: values[6].reference, accept: { chosenVideos.append($0.reference) }),
                hostWindow: { settings })
            keepAlive.append(picker); picker.show()
            try await wait("Shared video picker did not become the nested key sheet") { settings.attachedSheet?.isKeyWindow == true }
            let panel = settings.attachedSheet!
            await settle()
            let collection = descendants(panel.contentView!, NSCollectionView.self).first!
            return (picker, panel, collection.delegate as! WallpaperLibraryGridController)
        }
        let (videoPicker, videoPanel, videoGrid) = try await openVideo()
        let videoSource = descendants(videoPanel.contentView!, NSSegmentedControl.self).first { !($0 is WallpaperLibraryZoomControl) }!
        checks["video-purpose-reuses-native-grid-and-only-available-local-videos"] = Set(videoGrid.items.map(\.reference))
            == Set([values[0], values[1], values[6], values[7]].map(\.reference))
            && videoSource.segmentCount == 3 && videoSource.label(forSegment: 2) == "我的下载"
            && videoPanel.contentView is WallpaperPanelSurface && !videoGrid.collection.allowsMultipleSelection
            && videoGrid.selection.references == [values[6].reference]
        videoPanel.makeFirstResponder(videoGrid.collection)
        try await key(124, String(UnicodeScalar(NSRightArrowFunctionKey)!))
        try await key(0, "a", modifiers: .command)
        try await key(49, " ")
        checks["video-picker-keeps-one-selection-and-never-plays-the-host"] = videoGrid.selection.references.count == 1
            && hostController.libraryCommands.previews == 0 && hostController.libraryCommands.applies == 0
            && manager.playbackSwitch.committed?.ticket == externalTicket
        let acceptedVideo = videoGrid.selection.references.first!
        try await key(36, "\r")
        checks["video-return-returns-one-value-without-writing-playlist-or-publishing"] = chosenVideos == [acceptedVideo]
            && !videoPanel.isVisible && collections.snapshot == beforeVideoSelection && settings.isKeyWindow
            && !videoPicker.canFocusSearch
        let (cancelledVideoPicker, cancelledVideoPanel, cancelledVideoGrid) = try await openVideo()
        try await filter(cancelledVideoPicker, cancelledVideoPanel, text: "no-match", expectedCount: 0)
        let videoAccept = descendants(cancelledVideoPanel.contentView!, NSButton.self).first { $0.title == "选择视频" }!
        checks["video-picker-empty-search-disables-confirm"] = cancelledVideoGrid.items.isEmpty && !videoAccept.isEnabled
        cancelledVideoPanel.makeFirstResponder(cancelledVideoGrid.collection)
        try await key(53, "\u{1b}")
        checks["video-picker-cancel-keeps-draft-and-releases-demand"] = chosenVideos == [acceptedVideo]
            && collections.snapshot == beforeVideoSelection && !cancelledVideoPanel.isVisible
            && workspace.catalog.leases.values.allSatisfy(\.isEmpty)
        settings.close(); host.makeKeyAndOrderFront(nil); await settle()
        let hostClosingTarget = try await collections.createPlaylist(name: "Host lifecycle")
        host.makeKeyAndOrderFront(nil); await settle()
        let (hostClosingPicker, hostClosingPanel, _) = try await open(hostClosingTarget)
        var hostCloseCallbacks = 0
        hostClosingPicker.onClose = { hostCloseCallbacks += 1 }
        let beforeHostClose = collections.snapshot
        host.close()
        try await wait("host close left a Picker or its native sheet session alive") { !hostClosingPanel.isVisible && hostClosingPanel.sheetParent == nil }
        hostClosingPicker.close()
        checks["native-host-close-retires-picker-once-without-reentrant-close-or-relationship-write"] = hostCloseCallbacks == 1
            && collections.snapshot == beforeHostClose && !hostClosingPicker.canFocusSearch
            && workspace.catalog.leases.values.allSatisfy(\.isEmpty)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
