import AppKit

/// Actual native event/menu/sheet dispatch, with controlled command effects.
/// This is not the production Picker: its collection selection is an input
/// leaf, so this gate claims menu-domain isolation rather than Picker behavior.
@MainActor private final class SheetMenuCollection: NSCollectionView, NSCollectionViewDataSource {
    var selectionCommands = 0
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        collectionViewLayout = NSCollectionViewFlowLayout()
        isSelectable = true
        allowsMultipleSelection = true
        dataSource = self
        register(SheetMenuCell.self, forItemWithIdentifier: .init("SheetMenuCell"))
    }
    required init?(coder: NSCoder) { nil }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { 3 }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt path: IndexPath) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: .init("SheetMenuCell"), for: path)
    }
    override func selectAll(_ sender: Any?) {
        selectionCommands += 1
        selectionIndexPaths = Set((0..<3).map { IndexPath(item: $0, section: 0) })
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectAll(self)
        } else { super.keyDown(with: event) }
    }
}

@MainActor private final class SheetMenuCell: NSCollectionViewItem {
    override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50)) }
}

@MainActor private final class SheetMenuButtons: NSObject {
    var adds = 0, cancels = 0, sheetCloses = 0
    @objc func add(_ sender: Any?) { adds += 1 }
    @objc func cancel(_ sender: Any?) { cancels += 1 }
    @objc func sheetWillClose(_ notification: Notification) { sheetCloses += 1 }
}

@main enum MainMenuSheetCommandChecks {
    @MainActor static func main() {
        initializeNativeAppHarness()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
            MainActor.assumeIsolated {
                do { try run() }
                catch { fatalError("Menu sheet fixture: \(error)") }
                NSApp.stop(nil)
                if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
            }
        }
        withExtendedLifetime(timer) { NSApp.run() }
    }

    @MainActor static func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        MainMenuBuilder.installMainMenu()
        let host = MenuTestWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 380),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        let controller = MainWindowController(window: host)
        MainWindowCoordinator.mainWindowController = controller
        let mainGrid = SheetMenuCollection(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
        host.contentView!.addSubview(mainGrid)
        let reference = WallpaperReference(provider: .staticImageLibrary, sourceID: "background-selection")
        controller.libraryCommands.selection = [.init(reference: reference, providerReference: reference,
            locator: .init(path: "/controlled/background.png", mediaKind: .image), title: "Background selection", kind: .image,
            publishedAvailability: .available, capabilities: [.play, .organize, .inspect, .quickLook, .reveal],
            metadata: .init(), acquisition: .idle, update: .idle, aliases: [])]
        controller.libraryPresentation.page = .images
        let sheet = WallpaperLibraryModalPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.borderless], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        let sheetGrid = SheetMenuCollection(frame: NSRect(x: 10, y: 55, width: 400, height: 220))
        sheet.contentView!.addSubview(sheetGrid)
        let buttons = SheetMenuButtons()
        NotificationCenter.default.addObserver(buttons, selector: #selector(SheetMenuButtons.sheetWillClose(_:)),
            name: NSWindow.willCloseNotification, object: sheet)
        let add = NSButton(title: "添加", target: buttons, action: #selector(SheetMenuButtons.add(_:)))
        add.frame = NSRect(x: 320, y: 10, width: 80, height: 30)
        add.bezelStyle = .rounded
        add.keyEquivalent = "\r"
        let cancel = NSButton(title: "取消", target: buttons, action: #selector(SheetMenuButtons.cancel(_:)))
        cancel.frame = NSRect(x: 230, y: 10, width: 80, height: 30)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        sheet.contentView!.addSubview(add)
        sheet.contentView!.addSubview(cancel)
        defer {
            NotificationCenter.default.removeObserver(buttons, name: NSWindow.willCloseNotification, object: sheet)
            WallpaperLibrarySheetPresentation.dismiss(sheet)
            host.close()
            MainWindowCoordinator.mainWindowController = nil
        }
        func pump(_ context: String, until condition: () -> Bool) throws {
            let end = Date().addingTimeInterval(3)
            while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
            guard condition() else {
                throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey:
                    "Native \(context) precondition did not settle; active=\(app.isActive), hostKey=\(host.isKeyWindow), sheetKey=\(sheet.isKeyWindow), attached=\(host.attachedSheet === sheet)"])
            }
        }
        func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = .command, menuFirst: Bool = true) {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: app.keyWindow?.windowNumber ?? 0,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else {
                preconditionFailure("Native key event could not be created")
            }
            // Exercise native menu validation/key-equivalent dispatch, including
            // bare Return/Space; unmatched keys retain native window dispatch.
            if !menuFirst || app.mainMenu?.performKeyEquivalent(with: event) != true { app.sendEvent(event) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        func entries(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(entries) ?? []) } }
        let menuEntries = entries(app.mainMenu!)
        func item(_ command: MainMenuCommand) -> NSMenuItem { menuEntries.first { $0.identifier == command.identifier }! }
        func recordModalState(_ stage: String) {
            let details: [String] = [
                "Menu modal \(stage):", "active=\(app.isActive)",
                "key=\(app.keyWindow?.windowNumber ?? 0)", "main=\(app.mainWindow?.windowNumber ?? 0)",
                "host=\(host.windowNumber)", "sheet=\(sheet.windowNumber)",
                "visible=\(sheet.isVisible)", "keySheet=\(sheet.isKeyWindow)",
                "parent=\(sheet.parent?.windowNumber ?? 0)", "hostAttached=\(host.attachedSheet?.windowNumber ?? 0)",
                "sheetParent=\(sheet.sheetParent?.windowNumber ?? 0)", "modal=\(app.modalWindow?.windowNumber ?? 0)",
                "hostPermits=\(WallpaperLibrarySheetPresentation.permitsInput(in: host))",
                "sheetPermits=\(WallpaperLibrarySheetPresentation.permitsInput(in: sheet))",
                "sheetResponder=\(String(describing: sheet.firstResponder))",
                "keyResponder=\(String(describing: app.keyWindow?.firstResponder))",
                "adds=\(buttons.adds)", "cancels=\(buttons.cancels)", "closes=\(buttons.sheetCloses)",
                "default=\(String(describing: sheet.defaultButtonCell?.title))",
                "cancelEnabled=\(cancel.isEnabled)", "cancelMounted=\(cancel.window === sheet)",
                "cancelHidden=\(cancel.isHiddenOrHasHiddenAncestor)",
                "navigation=\(CrossRuntimeWallpaperNavigator.directions.count)",
                "directoryDeletes=\(controller.playlistDeleteCalls)"
            ]
            FileHandle.standardError.write(Data((details.joined(separator: " ") + "\n").utf8))
        }
        var checks: [String: Bool] = [:]
        app.activate()
        host.makeKeyAndOrderFront(nil)
        try pump("main input") { app.isActive && host.isKeyWindow }
        precondition(host.makeFirstResponder(mainGrid))
        key("f", code: 3)
        checks["main-window-positive-control-reaches-real-menu-key-equivalent"] = controller.searches == 1
        // Capture the real online-image menu lease before a login/Key-style
        // child modal takes input. This controlled onPrimary has no guard of
        // its own, so only the production menu consumer can revoke it.
        var retainedImageApplies = 0
        controller.libraryPresentation.page = .pixiv
        let remote = WallpaperReference(provider: .pixiv, sourceID: "child-modal")
        controller.browser.onlineImages.selectedContent = .init(reference: remote, providerReference: remote,
            locator: .init(mediaKind: .image), title: "Image", kind: .image, publishedAvailability: .remote,
            capabilities: [.download], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        controller.browser.onlineImages.primary = ("下载原图", { retainedImageApplies += 1 })
        let imageApplyValidated = delegate.validateMenuItem(item(.applyWallpaper))
        let retainedImageApply = NSMenuItem(title: "Retained image apply", action: item(.applyWallpaper).action, keyEquivalent: "")
        retainedImageApply.target = item(.applyWallpaper).target
        retainedImageApply.representedObject = item(.applyWallpaper).representedObject
        _ = app.sendAction(retainedImageApply.action!, to: retainedImageApply.target, from: retainedImageApply)
        let retainedImageWasLive = imageApplyValidated && retainedImageApplies == 1
        controller.libraryPresentation.page = .images
        controller.browser.onlineImages.selectedContent = nil
        controller.browser.onlineImages.primary = nil
        let before = (controller.libraryCommands.selectAllCalls, controller.libraryCommands.deletes,
            controller.libraryCommands.favorites, controller.libraryCommands.applies, controller.libraryCommands.previews,
            controller.libraryCommands.imports, controller.libraryCommands.infos, controller.libraryCommands.reveals,
            controller.libraryCommands.selectionCalls, controller.libraryCommands.adds, controller.libraryCommands.playlists!.creates,
            controller.searches, controller.zooms.count)
        precondition(WallpaperLibrarySheetPresentation.present(sheet, in: host))
        try pump("native sheet input") { sheet.sheetParent === host && sheet.isKeyWindow }
        precondition(sheet.makeFirstResponder(sheetGrid))
        checks["native-sheet-and-collection-are-the-real-input-domain"] = app.keyWindow === sheet && sheet.firstResponder === sheetGrid
            && host.attachedSheet === sheet && sheet.isSheet && !WallpaperLibrarySheetPresentation.permitsInput(in: host)
        checks["native-sheet-default-cell-is-the-enabled-visible-add-button"] = sheet.defaultButtonCell === add.cell && add.isEnabled
        key("a", code: 0, menuFirst: false)
        checks["sheet-command-a-does-not-select-background-wallpapers"] = controller.libraryCommands.selectAllCalls == before.0
        checks["sheet-command-a-remains-reachable-by-its-native-collection"] = sheetGrid.selectionCommands == 1 && sheetGrid.selectionIndexPaths.count == 3
        sheetGrid.selectionIndexPaths = []
        key("a", code: 0)
        checks["native-menu-and-application-event-select-all-share-the-current-sheet-domain"] = sheetGrid.selectionCommands == 2
            && sheetGrid.selectionIndexPaths.count == 3 && controller.libraryCommands.selectAllCalls == before.0
        key("\u{8}", code: 51)
        checks["sheet-delete-key-equivalent-does-not-remove-background-wallpapers"] = controller.libraryCommands.deletes == before.1
        key("d", code: 2); key("t", code: 17); key("e", code: 14); key("n", code: 45); key("o", code: 31)
        checks["sheet-organization-and-import-keys-cannot-write-background-selection"] = controller.libraryCommands.favorites == before.2
            && controller.libraryCommands.adds == before.9 && controller.libraryCommands.selectionCalls == before.8
            && controller.libraryCommands.playlists!.creates == before.10 && controller.libraryCommands.imports == before.5
        var heldBrowserActions = 0
        for command in [MainMenuCommand.favorite, .addToPlaylist] {
            let entry = item(command)
            entry.representedObject = { heldBrowserActions += 1 }
            _ = app.sendAction(entry.action!, to: entry.target, from: entry)
            entry.representedObject = nil
        }
        checks["held-browser-menu-closures-are-revoked-when-another-window-owns-input"] = heldBrowserActions == 0
        key("f", code: 3); key("+", code: 24); key("-", code: 27)
        checks["sheet-search-and-zoom-cannot-mutate-background-page"] = controller.searches == before.11 && controller.zooms.count == before.12
        key("i", code: 34); key("r", code: 15); key(" ", code: 49, modifiers: [])
        checks["sheet-info-preview-and-reveal-do-not-borrow-background-selection"] = controller.libraryCommands.infos == before.6
            && controller.libraryCommands.reveals == before.7 && controller.libraryCommands.previews == before.4
        key("\r", code: 36, modifiers: [])
        checks["sheet-return-keeps-native-default-add-without-applying-background-wallpaper"] = buttons.adds == 1 && controller.libraryCommands.applies == before.3
        checks["sheet-return-menu-title-describes-the-real-default-action"] = delegate.validateMenuItem(item(.applyWallpaper))
            && item(.applyWallpaper).title == add.title
        add.isEnabled = false
        let disabledDefault = delegate.validateMenuItem(item(.applyWallpaper))
        _ = app.sendAction(item(.applyWallpaper).action!, to: item(.applyWallpaper).target, from: item(.applyWallpaper))
        key("\r", code: 36, modifiers: [])
        checks["sheet-disabled-default-never-submits-or-falls-through-to-background-apply"] = !disabledDefault
            && buttons.adds == 1 && controller.libraryCommands.applies == before.3
        add.isEnabled = true
        sheet.defaultButtonCell = nil
        let missingDefault = delegate.validateMenuItem(item(.applyWallpaper))
        _ = app.sendAction(item(.applyWallpaper).action!, to: item(.applyWallpaper).target, from: item(.applyWallpaper))
        checks["sheet-without-default-never-borrows-background-apply"] = !missingDefault
            && buttons.adds == 1 && controller.libraryCommands.applies == before.3
        _ = app.sendAction(retainedImageApply.action!, to: retainedImageApply.target, from: retainedImageApply)
        checks["retained-online-image-apply-cannot-run-after-account-or-key-modal-takes-input"] = retainedImageWasLive
            && retainedImageApplies == 1 && controller.libraryCommands.applies == before.3 && buttons.adds == 1
        sheet.defaultButtonCell = add.cell as? NSButtonCell
        let scoped: [MainMenuCommand] = [.createPlaylist, .importFiles, .toggleSelection, .deleteSelected, .search,
            .zoomIn, .zoomOut, .favorite, .addToPlaylist, .info, .preview, .revealOrRefresh]
        checks["sheet-disables-only-unowned-page-menu-commands"] = scoped.allSatisfy { !delegate.validateMenuItem(item($0)) }
        let navigationCount = CrossRuntimeWallpaperNavigator.directions.count
        key(String(UnicodeScalar(NSRightArrowFunctionKey)!), code: 124)
        key(String(UnicodeScalar(NSLeftArrowFunctionKey)!), code: 123)
        checks["sheet-nontext-command-arrows-never-change-background-wallpaper-navigation"] = CrossRuntimeWallpaperNavigator.directions.count == navigationCount
            && !delegate.validateMenuItem(item(.nextWallpaper)) && !delegate.validateMenuItem(item(.previousWallpaper))
            && delegate.validateMenuItem(item(.settings))
        controller.libraryPresentation.page = .playlists
        controller.canDeleteSelectedPlaylist = true
        let deleteEntry = item(.deleteSelected)
        let directoryDeletes = controller.playlistDeleteCalls
        let directoryDeleteEnabled = delegate.validateMenuItem(deleteEntry)
        _ = app.sendAction(deleteEntry.action!, to: deleteEntry.target, from: deleteEntry)
        checks["sheet-revokes-background-directory-delete-at-validation-and-action-time"] = !directoryDeleteEnabled
            && controller.playlistDeleteCalls == directoryDeletes
        controller.libraryPresentation.page = .images
        let editor = NativeMenuEditor(frame: NSRect(x: 10, y: 150, width: 280, height: 80))
        editor.isEditable = true; editor.allowsUndo = true
        sheet.contentView!.addSubview(editor)
        precondition(sheet.makeFirstResponder(editor))
        recordModalState("before-text-domain")
        let beforeText = (controller.libraryCommands.selectAllCalls, controller.libraryCommands.deletes)
        editor.string = "sheet text"; editor.setSelectedRange(NSRange(location: 0, length: 0))
        key(String(UnicodeScalar(NSRightArrowFunctionKey)!), code: 124)
        checks["sheet-text-command-right-keeps-native-line-end-without-background-navigation"] = editor.selectedRange().location == editor.string.utf16.count
            && CrossRuntimeWallpaperNavigator.directions.count == navigationCount
        key(String(UnicodeScalar(NSLeftArrowFunctionKey)!), code: 123)
        checks["sheet-text-command-left-keeps-native-line-start-without-background-navigation"] = editor.selectedRange().location == 0
            && CrossRuntimeWallpaperNavigator.directions.count == navigationCount
        key("a", code: 0)
        checks["sheet-text-select-all-retains-editor-priority"] = editor.selectedRange().length == editor.string.utf16.count
            && controller.libraryCommands.selectAllCalls == beforeText.0
        key("\u{8}", code: 51)
        checks["sheet-text-delete-retains-editor-priority"] = editor.string.isEmpty && controller.libraryCommands.deletes == beforeText.1
        editor.string = "可选择复制的确认说明"; editor.isEditable = false
        let addsBeforeReadOnlyReturn = buttons.adds
        let appliesBeforeReadOnlyReturn = controller.libraryCommands.applies
        key("\r", code: 36, modifiers: [])
        checks["read-only-sheet-message-keeps-the-real-default-button-without-background-apply"] = buttons.adds == addsBeforeReadOnlyReturn + 1
            && controller.libraryCommands.applies == appliesBeforeReadOnlyReturn
        recordModalState("after-text-and-readonly-domain")
        cancel.performClick(nil)
        checks["owned-sheet-cancel-button-retains-its-native-target-and-action"] = buttons.cancels == 1
            && sheet.isVisible && sheet.sheetParent === host && app.keyWindow === sheet
        precondition(sheet.makeFirstResponder(sheetGrid))
        recordModalState("before-Escape")
        key("\u{1b}", code: 53, modifiers: [])
        recordModalState("after-Escape")
        try pump("main restored after native Escape") { app.keyWindow === host && sheet.sheetParent == nil && !sheet.isVisible }
        checks["owned-sheet-native-escape-closes-once-without-reinvoking-the-cancel-button"] = buttons.sheetCloses == 1
            && buttons.cancels == 1 && sheet.sheetParent == nil && !sheet.isVisible && app.keyWindow === host
            && WallpaperLibrarySheetPresentation.permitsInput(in: host)
        precondition(host.makeFirstResponder(mainGrid))
        checks["closing-sheet-restores-original-main-page-menu-capabilities"] = scoped.allSatisfy { delegate.validateMenuItem(item($0)) }
            && delegate.validateMenuItem(item(.applyWallpaper)) && item(.applyWallpaper).title == "设为壁纸"
        let searchAfterSheet = controller.searches
        key("f", code: 3)
        checks["main-search-key-equivalent-remains-live-after-sheet-closes"] = controller.searches == searchAfterSheet + 1
        let close = item(.closeWindow)
        checks["close-menu-retains-command-w"] = close.keyEquivalent == "w"
            && close.keyEquivalentModifierMask == [.command]
        let popover = NSPopover()
        popover.animates = false
        popover.behavior = .transient
        let popoverController = NSViewController()
        popoverController.view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        let field = NSTextField(string: "Popover editor")
        field.frame = NSRect(x: 16, y: 16, width: 200, height: 24)
        popoverController.view.addSubview(field)
        popover.contentViewController = popoverController
        defer { popover.close() }
        for attempt in 0..<2 {
            popover.show(relativeTo: NSRect(x: 30, y: 30, width: 10, height: 10),
                of: host.contentView!, preferredEdge: .maxY)
            precondition(popoverController.view.window?.makeFirstResponder(field) == true)
            try pump("popover editor") { popover.isShown && field.currentEditor() != nil }
            checks["popover-close-target-is-its-owner-\(attempt)"] = app.target(forAction: #selector(NSWindow.performClose(_:)), to: nil, from: close) as AnyObject? === popover
            if attempt == 0 { _ = app.sendAction(close.action!, to: close.target, from: close) }
            else { key("w", code: 13) }
            try pump("only popover closed while host remains visible") { !popover.isShown && host.isVisible }
            checks["popover-close-preserves-host-and-original-page-\(attempt)"] = host.isVisible
                && controller.libraryPresentation.page == .images && host.attachedSheet == nil
            precondition(host.makeFirstResponder(mainGrid))
        }
        precondition(WallpaperLibrarySheetPresentation.present(sheet, in: host))
        try pump("reopened sheet input") { sheet.isKeyWindow && sheet.sheetParent === host }
        precondition(sheet.makeFirstResponder(sheetGrid))
        key("w", code: 13)
        try pump("sheet closed by command-w") { !sheet.isVisible && sheet.sheetParent == nil && host.isKeyWindow }
        checks["command-w-closes-owned-sheet-once-and-keeps-host"] = host.isVisible && buttons.sheetCloses == 2
        precondition(host.makeFirstResponder(mainGrid))
        key("w", code: 13)
        try pump("ordinary window closed by command-w") { !host.isVisible }
        checks["command-w-still-closes-ordinary-application-window"] = !host.isVisible
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
