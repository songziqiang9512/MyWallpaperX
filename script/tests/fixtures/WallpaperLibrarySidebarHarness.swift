import AppKit
import Foundation

enum MainWindowCoordinator { static func mainWindow() -> NSWindow? { nil } }

@MainActor final class SidebarDropInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let source: NSView?
    var draggingSource: Any? { source }
    var draggingDestinationWindow: NSWindow? { source?.window }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(source: NSView?, board: NSPasteboard) { self.source = source; draggingPasteboard = board }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

/// A stock cell in the same native source-list context supplies the platform
/// font and symbol style. It never calls the product row's configure/setup
/// methods or seeds its label with the product's already resolved font.
@MainActor final class SidebarNativeSymbolBaseline: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let outline = NSOutlineView()
    let cell = NSTableCellView()
    private let node = NSObject()
    init(source: NSOutlineView) {
        super.init()
        outline.style = source.style
        outline.rowSizeStyle = source.rowSizeStyle
        outline.headerView = nil
        let column = NSTableColumn(identifier: .init("NativeSymbolBaseline"))
        outline.addTableColumn(column); outline.outlineTableColumn = column
        let label = NSTextField(labelWithString: "Native baseline")
        label.frame = NSRect(x: 28, y: 0, width: 160, height: 30)
        let icon = NSImageView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        icon.image = NSImage(systemSymbolName: WallpaperLibrarySymbols.playlist, accessibilityDescription: nil)
        cell.addSubview(label); cell.addSubview(icon)
        cell.textField = label; cell.imageView = icon
        outline.dataSource = self; outline.delegate = self
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? 1 : 0 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { node }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { 30 }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? { cell }
}

@main enum WallpaperLibrarySidebarHarness {
    static func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, type) }
    }
    static func pump(_ duration: TimeInterval = 0.03) {
        let end = Date().addingTimeInterval(duration)
        repeat {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        } while Date() < end
    }
    static func main() {
        initializeNativeAppHarness()
        var checks: [String: Bool] = [:]
        let first = WallpaperPlaylist(name: "同名 🎵", sidebarRank: 0)
        let second = WallpaperPlaylist(name: "同名 🎵", sidebarRank: 1)
        let suite = "mwx.sidebar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WallpaperLibrarySidebarController(defaults: defaults)
        var navigation: [WallpaperLibraryPage] = [], actions: [PlaylistOrganizationAction] = [], orders: [[UUID]] = []
        controller.onNavigate = { navigation.append($0) }
        controller.onPlaylistAction = { actions.append($0) }
        var reorderCompletion: ((Result<Int64, Error>) -> Void)?
        controller.onReorder = { order, completion in orders.append(order); reorderCompletion = completion }
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 260, height: 760))
        window.setFrameOrigin(NSPoint(x: 160, y: 160))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        controller.update(page: .videos, playlists: [second, first], counts: [.videos: 7, .playlists: 2, .playlist(second.id): 0], covers: [:], canEdit: true)
        window.contentView?.layoutSubtreeIfNeeded()
        let outline = descendants(controller.view, SidebarOutlineView.self).first!
        window.makeFirstResponder(outline)
        pump()
        let deadline = Date().addingTimeInterval(3)
        while !NSApp.isActive || !window.isKeyWindow {
            precondition(Date() < deadline, "native fixture did not become active")
            pump(0.005)
        }
        func item(_ row: Int) -> Any { outline.item(atRow: row)! }
        func cell(_ row: Int) -> NSTableCellView { outline.view(atColumn: 0, row: row, makeIfNecessary: true) as! NSTableCellView }
        func titleX(_ cell: NSTableCellView) -> CGFloat { cell.textField!.convert(.zero, to: cell).x }
        func usesPlaylistSymbol(_ imageView: NSImageView?, nativePixels: Data?) -> Bool {
            guard let imageView, let image = imageView.image, let actualConfiguration = imageView.symbolConfiguration,
                  let actualPixels = image.withSymbolConfiguration(actualConfiguration)?.tiffRepresentation,
                  let nativePixels else { return false }
            return actualPixels == nativePixels
        }
        func nativeFontSemantics(_ font: NSFont?) -> [Double]? {
            guard let font, font.pointSize > 0, font.xHeight > 0, font.capHeight > 0 else { return nil }
            let traits = font.fontDescriptor.object(forKey: .traits) as? [String: Any] ?? [:]
            let weight = (traits[NSFontDescriptor.TraitKey.weight.rawValue] as? NSNumber)?.doubleValue ?? 0
            let slant = (traits[NSFontDescriptor.TraitKey.slant.rawValue] as? NSNumber)?.doubleValue ?? 0
            let visibleTraits = font.fontDescriptor.symbolicTraits.intersection([.bold, .italic, .expanded, .condensed, .monoSpace, .vertical])
            return [Double(font.pointSize), weight, slant, Double(visibleTraits.rawValue),
                Double(font.xHeight), Double(font.capHeight), Double(font.ascender), Double(font.descender)]
        }
        var iconDiagnostics: [[String: String]] = []
        func recordIcon(_ stage: String, cell: NSTableCellView) {
            guard let icon = cell.imageView, let slot = icon.superview else { return }
            let insets = icon.alignmentRectInsets
            let font = cell.textField?.font
            let diagnostic: [String: String] = ["stage": stage, "frame": NSStringFromRect(icon.frame),
                "alignment": NSStringFromRect(icon.alignmentRect(forFrame: icon.frame)),
                "slot": NSStringFromRect(slot.bounds), "titleX": String(describing: titleX(cell)),
                "symbolConfiguration": icon.symbolConfiguration.map { String(describing: $0) } ?? "nil",
                "cellFrame": NSStringFromRect(cell.frame),
                "rowSuperviewFrame": cell.superview.map { NSStringFromRect($0.frame) } ?? "nil",
                "labelFrame": cell.textField.map { NSStringFromRect($0.frame) } ?? "nil",
                "font": font.map { String(describing: $0) } ?? "nil",
                "fontPointSize": font.map { String(describing: $0.pointSize) } ?? "nil",
                "fontTraits": font.map { String(describing: $0.fontDescriptor.object(forKey: .traits)) } ?? "nil",
                "fontXHeight": font.map { String(describing: $0.xHeight) } ?? "nil",
                "outlineStyle": String(describing: outline.style),
                "outlineRowSizeStyle": String(describing: outline.rowSizeStyle),
                "cellRowSizeStyle": String(describing: cell.rowSizeStyle),
                "insets": "\(insets.top),\(insets.left),\(insets.bottom),\(insets.right)"]
            iconDiagnostics.append(diagnostic)
        }
        func uniformIconIsCentered(_ cell: NSTableCellView) -> Bool {
            guard let icon = cell.imageView, let slot = icon.superview else { return false }
            let alignment = icon.alignmentRect(forFrame: icon.frame)
            return alignment.size == NSSize(width: 22, height: 22) && slot.bounds.size == NSSize(width: 22, height: 22)
                && alignment.midX == slot.bounds.midX && alignment.midY == slot.bounds.midY
        }
        let library = item(0), browse = item(5), playlistGroup = item(9)
        let titles = (0..<outline.numberOfRows).map { cell($0).textField!.stringValue }
        checks["three-groups-have-exact-fixed-order-and-empty-duplicate-name-playlists"] = titles == ["资料库", "我的视频", "我的图片", "我的下载", "最近使用", "浏览", "创意工坊", "工坊订阅", "Pixabay", "播放列表", "所有播放列表", "特别喜爱", first.name, second.name]
        checks["group-rows-cannot-navigate"] = !controller.outlineView(outline, shouldSelectItem: library)
            && !controller.outlineView(outline, shouldSelectItem: browse) && navigation.isEmpty
        checks["sidebar-uses-opaque-system-base-and-neutral-selection-row"] = !(controller.view is NSVisualEffectView) && controller.view.isOpaque
            && outline.rowView(atRow: 1, makeIfNecessary: true) is SidebarRowView
            && (outline.rowView(atRow: 1, makeIfNecessary: true) as! SidebarRowView).isEmphasized == false
        let tint = controller.backgroundTintHost, originalScroll = outline.enclosingScrollView!
        let tintIndex = controller.view.subviews.firstIndex(of: tint)!, scrollIndex = controller.view.subviews.firstIndex(of: originalScroll)!
        checks["one-passive-tint-host-sits-below-original-transparent-scroll-and-native-selection"] = tint.superview === controller.view
            && !originalScroll.drawsBackground && originalScroll.documentView === outline && tintIndex < scrollIndex
            && descendants(controller.view, NSScrollView.self).count == 1 && descendants(controller.view, AppKitListTintSurface.self).count == 1
            && tint.hitTest(.zero) == nil && !tint.isAccessibilityElement()
        let emptyPlaylistCell = cell(12)
        controller.view.layoutSubtreeIfNeeded()
        let emptyTitleX = titleX(emptyPlaylistCell)
        let originalRowHeight = outline.rect(ofRow: 12).height
        let baseline = SidebarNativeSymbolBaseline(source: outline)
        baseline.outline.frame = NSRect(x: 0, y: 0, width: 230, height: 40)
        controller.view.addSubview(baseline.outline)
        baseline.outline.reloadData()
        _ = baseline.outline.view(atColumn: 0, row: 0, makeIfNecessary: true)
        controller.view.layoutSubtreeIfNeeded(); pump()
        let nativeConfiguration = baseline.cell.imageView?.symbolConfiguration
        let nativeFont = baseline.cell.textField?.font
        let nativeRowFrame = baseline.outline.rect(ofRow: 0)
        let nativeCellFrame = baseline.cell.frame
        let nativePixels = nativeConfiguration.flatMap { configuration in
            NSImage(systemSymbolName: WallpaperLibrarySymbols.playlist, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)?.tiffRepresentation
        }
        baseline.outline.removeFromSuperview()
        checks["symbol-reference-comes-from-independent-mounted-native-source-list-cell"] = nativeConfiguration != nil && nativePixels != nil
            && baseline.outline.style == outline.style && baseline.cell.rowSizeStyle == (emptyPlaylistCell as! SidebarRowCellView).rowSizeStyle
        iconDiagnostics.append(["stage": "independent-native-baseline", "symbolConfiguration": nativeConfiguration.map { String(describing: $0) } ?? "nil",
            "font": nativeFont.map { String(describing: $0) } ?? "nil",
            "fontTraits": nativeFont.map { String(describing: $0.fontDescriptor.object(forKey: .traits)) } ?? "nil",
            "fontInput": "independent-stock-label-default-font; mounted-native-source-list",
            "rowFrame": NSStringFromRect(nativeRowFrame), "cellFrame": NSStringFromRect(nativeCellFrame)])
        let actualFontSemantics = nativeFontSemantics(emptyPlaylistCell.textField?.font)
        let baselineFontSemantics = nativeFontSemantics(nativeFont)
        let fontMatchesNative = actualFontSemantics != nil && baselineFontSemantics != nil && actualFontSemantics == baselineFontSemantics
        iconDiagnostics.append(["stage": "font-and-hit-height-contract",
            "actualFontSemantics": String(describing: actualFontSemantics),
            "independentNativeFontSemantics": String(describing: baselineFontSemantics),
            "actualRowHeight": String(describing: originalRowHeight),
            "outlineRowHeightProperty": String(describing: outline.rowHeight),
            "actualFontMatchesIndependentNative": String(describing: fontMatchesNative)])
        recordIcon("empty", cell: emptyPlaylistCell)
        checks["empty-playlist-keeps-media-symbol-centered-in-uniform-22-point-slot"] = usesPlaylistSymbol(emptyPlaylistCell.imageView, nativePixels: nativePixels)
            && uniformIconIsCentered(emptyPlaylistCell)
            && NSImage(systemSymbolName: WallpaperLibrarySymbols.playlist, accessibilityDescription: nil) != nil
        checks["every-fixed-page-and-playlist-icon-uses-the-same-visible-22-point-alignment-slot"] = (0..<outline.numberOfRows)
            .filter { ![0, 5, 9].contains($0) }.allSatisfy { uniformIconIsCentered(cell($0)) }
        checks["sidebar-symbols-match-independent-mounted-native-source-list-configuration"] = usesPlaylistSymbol(emptyPlaylistCell.imageView, nativePixels: nativePixels)
        checks["sidebar-labels-match-independent-native-font-semantics-with-original-hit-height"] = fontMatchesNative && originalRowHeight == 30
        let directoryIcon = cell(10).imageView
        let expectedGrid = directoryIcon?.symbolConfiguration.flatMap {
            NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: nil)?.withSymbolConfiguration($0)?.tiffRepresentation
        }
        let actualGrid = directoryIcon.flatMap { icon in
            icon.symbolConfiguration.flatMap { icon.image?.withSymbolConfiguration($0)?.tiffRepresentation }
        }
        checks["all-playlists-entry-uses-native-three-by-three-grid-symbol"] = expectedGrid != nil
            && actualGrid == expectedGrid
        checks["counts-are-accessible-without-visible-numeric-column"] = cell(1).accessibilityLabel() == "我的视频，7 张壁纸"
            && cell(3).accessibilityLabel() == "我的下载" && cell(13).accessibilityLabel() == second.name + "，0 张壁纸"
            && !descendants(cell(1), NSTextField.self).contains { !$0.isHidden && $0.stringValue == "7" }
        checks["directory-accessibility-count-uses-playlist-unit-without-visible-count-label"] = cell(10).accessibilityLabel() == "所有播放列表，2 个播放列表"
            && cell(10).textField?.stringValue == "所有播放列表"
        func event(_ type: NSEvent.EventType, row: Int, at offset: NSPoint = .zero, time: TimeInterval = 0) -> NSEvent {
            let rect = outline.rect(ofRow: row)
            let point = outline.convert(NSPoint(x: max(80, rect.midX) + offset.x, y: rect.midY + offset.y), to: nil)
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        func click(_ row: Int) {
            let time = ProcessInfo.processInfo.systemUptime
            NSApp.postEvent(event(.leftMouseUp, row: row, time: time + 0.01), atStart: true)
            window.sendEvent(event(.leftMouseDown, row: row, time: time))
            pump()
        }
        click(2)
        checks["real-row-click-requests-only-fixed-page-navigation"] = navigation == [.images]
        controller.update(page: .images, playlists: [first, second], counts: [:], covers: [:], canEdit: true)
        click(2)
        checks["same-selected-row-click-uses-existing-shared-behavior-once"] = navigation == [.images, .images]
        let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{f701}",
            charactersIgnoringModifiers: "\u{f701}", isARepeat: false, keyCode: 125)!
        outline.keyDown(with: down)
        checks["native-keyboard-arrow-requests-adjacent-page"] = navigation.last == .downloads
        let beforeContextNavigation = navigation
        let selectedBeforeContext = outline.selectedRowIndexes
        let menu = outline.menu(for: event(.rightMouseDown, row: 12))!
        checks["right-click-captures-menu-without-selection-or-navigation"] = navigation == beforeContextNavigation
            && outline.selectedRowIndexes == selectedBeforeContext
            && menu.items.map(\.title) == ["打开播放列表", "编辑列表…", "复制列表", "", "删除列表…"]
        var renamedFirst = first; renamedFirst.name = "已改名"
        var movedSecond = second; movedSecond.sidebarRank = 0
        renamedFirst.sidebarRank = 1
        outline.collapseItem(browse)
        let cover = NSImage(size: NSSize(width: 20, height: 20))
        controller.update(page: .playlist(first.id), playlists: [movedSecond, renamedFirst], counts: [:], covers: [first.id: cover], canEdit: true)
        controller.view.layoutSubtreeIfNeeded()
        let selectedIDRow = outline.selectedRow
        checks["update-keeps-native-collapse-and-selects-uuid-after-rename-reorder"] = !outline.isItemExpanded(browse)
            && cell(selectedIDRow).textField?.stringValue == "已改名" && navigation == beforeContextNavigation
        checks["playlist-cover-is-22-points-and-uses-real-image"] = cell(selectedIDRow).imageView?.image === cover
            && cell(selectedIDRow).imageView?.alignmentRect(forFrame: cell(selectedIDRow).imageView!.frame).width == 22
        recordIcon("cover", cell: cell(selectedIDRow))
        checks["cover-arrival-keeps-playlist-title-and-fixed-row-height"] = titleX(cell(selectedIDRow)) == emptyTitleX
            && cell(selectedIDRow).imageView?.superview?.frame.width == 22 && originalRowHeight > 0
            && outline.rect(ofRow: selectedIDRow).height == originalRowHeight
        controller.update(page: .playlist(first.id), playlists: [movedSecond, renamedFirst], counts: [:], covers: [:], canEdit: true)
        controller.view.layoutSubtreeIfNeeded()
        recordIcon("revoked", cell: cell(selectedIDRow))
        checks["cover-revocation-restores-uniform-symbol-without-title-shift"] = titleX(cell(selectedIDRow)) == emptyTitleX
            && usesPlaylistSymbol(cell(selectedIDRow).imageView, nativePixels: nativePixels) && uniformIconIsCentered(cell(selectedIDRow))
        var longNamedFirst = renamedFirst
        longNamedFirst.name = String(repeating: "很长的播放列表 🌟 ", count: 8)
        window.setContentSize(NSSize(width: 220, height: 760))
        controller.update(page: .playlist(first.id), playlists: [movedSecond, longNamedFirst], counts: [:], covers: [first.id: cover], canEdit: true)
        controller.view.layoutSubtreeIfNeeded(); pump()
        checks["narrow-sidebar-long-name-keeps-the-same-title-line-and-native-truncation"] = titleX(cell(outline.selectedRow)) == emptyTitleX
            && cell(outline.selectedRow).textField?.stringValue == longNamedFirst.name
            && (cell(outline.selectedRow).textField?.frame.width ?? 0) > 0
            && cell(outline.selectedRow).textField?.lineBreakMode == .byTruncatingTail
            && outline.rect(ofRow: outline.selectedRow).height == originalRowHeight
        window.setContentSize(NSSize(width: 260, height: 760))
        controller.update(page: .playlist(first.id), playlists: [movedSecond, renamedFirst], counts: [:], covers: [:], canEdit: true)
        controller.view.layoutSubtreeIfNeeded(); pump()
        let rename = menu.items[1], duplicate = menu.items[2], delete = menu.items[4]
        for command in [rename, duplicate, delete] { NSApp.sendAction(command.action!, to: command.target, from: command) }
        checks["open-menu-organization-actions-retain-original-uuid"] = actions == [.rename(first.id), .duplicate(first.id), .delete(first.id)]
        let blankPoint = outline.convert(NSPoint(x: 80, y: outline.bounds.maxY - 4), to: nil)
        let blank = NSEvent.mouseEvent(with: .rightMouseDown, location: blankPoint, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!
        let createMenu = outline.menu(for: blank)!
        let create = createMenu.items[0]
        NSApp.sendAction(create.action!, to: create.target, from: create)
        checks["blank-sidebar-shares-create-action-with-directory"] = createMenu.items.map(\.title) == ["新建列表…"] && actions.last == .create

        let actualGroup = (0..<outline.numberOfRows).first { cell($0).textField?.stringValue == "播放列表" }.map(item)!
        let firstNode = item(selectedIDRow)
        let fixedAll = controller.outlineView(outline, child: 0, ofItem: actualGroup)
        let fixedFavorites = controller.outlineView(outline, child: 1, ofItem: actualGroup)
        checks["fixed-items-and-groups-have-no-drag-writer"] = controller.outlineView(outline, pasteboardWriterForItem: fixedAll) == nil
            && controller.outlineView(outline, pasteboardWriterForItem: fixedFavorites) == nil
            && controller.outlineView(outline, pasteboardWriterForItem: actualGroup) == nil
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let writer = controller.outlineView(outline, pasteboardWriterForItem: firstNode)!
        board.writeObjects([writer])
        let drag = SidebarDropInfo(source: outline, board: board)
        checks["native-delegate-reorder-only-targets-custom-playlist-range"] = controller.outlineView(outline, validateDrop: drag, proposedItem: actualGroup, proposedChildIndex: 2) == .move
            && controller.outlineView(outline, validateDrop: drag, proposedItem: actualGroup, proposedChildIndex: 1).isEmpty
            && controller.outlineView(outline, validateDrop: drag, proposedItem: library, proposedChildIndex: 0).isEmpty
        checks["accept-reorder-requests-one-uuid-order-without-owning-store"] = controller.outlineView(outline, acceptDrop: drag, item: actualGroup, childIndex: 2)
            && orders == [[first.id, second.id]]
        checks["internal-reorder-uses-native-gap-and-blocks-reentrant-writer"] = outline.draggingDestinationFeedbackStyle == .gap
            && controller.outlineView(outline, pasteboardWriterForItem: firstNode) == nil
        // Settle a real failed receipt before the independent native drag below.
        reorderCompletion?(.failure(UserCollectionsError.invalidOrder))
        checks["failed-reorder-restores-authoritative-order-and-keeps-selected-uuid"] = outline.selectedRow == selectedIDRow
            && cell(selectedIDRow).textField?.stringValue == renamedFirst.name && orders.count == 1
            && cell(outline.row(forItem: firstNode)).textField?.stringValue == renamedFirst.name
        let external = SidebarDropInfo(source: NSView(), board: board)
        checks["external-drag-cannot-forge-local-playlist-order"] = controller.outlineView(outline, validateDrop: external, proposedItem: actualGroup, proposedChildIndex: 2).isEmpty
            && !controller.outlineView(outline, acceptDrop: external, item: actualGroup, childIndex: 2)
        let fixedInfo = SidebarDropInfo(source: outline, board: .withUniqueName())
        defer { fixedInfo.draggingPasteboard.releaseGlobally() }
        fixedInfo.draggingPasteboard.setString("external wallpaper", forType: .string)
        checks["unbound-wallpaper-drop-is-rejected-by-native-validation"] = controller.outlineView(outline, validateDrop: fixedInfo, proposedItem: firstNode, proposedChildIndex: -1).isEmpty
            && !controller.outlineView(outline, acceptDrop: fixedInfo, item: firstNode, childIndex: -1)

        // Observe a genuine outline drag, not a direct writer/delegate call.
        func dragRow(_ row: Int) {
            let time = ProcessInfo.processInfo.systemUptime
            NSApp.postEvent(event(.leftMouseUp, row: row, at: NSPoint(x: 70, y: 25), time: time + 0.03), atStart: true)
            NSApp.postEvent(event(.leftMouseDragged, row: row, at: NSPoint(x: 70, y: 25), time: time + 0.02), atStart: true)
            window.sendEvent(event(.leftMouseDown, row: row, time: time))
            pump(0.1)
        }
        let beforeDragNavigation = navigation.count
        dragRow(selectedIDRow)
        checks["native-drag-delegate-observation-is-installed"] = controller.responds(to: NSSelectorFromString("outlineView:draggingSession:willBeginAtPoint:forItems:"))
        checks["actual-row-drag-enters-native-outline-session"] = SidebarNativeDragProbe.started == 1 && navigation.count == beforeDragNavigation
        let session = SidebarNativeDragProbe.session!
        checks["native-drag-source-advertises-move-only-within-application"] = outline.draggingSession(session, sourceOperationMaskFor: .withinApplication) == .move
            && outline.draggingSession(session, sourceOperationMaskFor: .outsideApplication).isEmpty
        let fixedRow = outline.row(forItem: fixedAll)
        controller.update(page: .playlists, playlists: [movedSecond, renamedFirst], counts: [:], covers: [:], canEdit: true)
        dragRow(fixedRow)
        checks["actual-fixed-row-drag-cannot-start-native-outline-session"] = SidebarNativeDragProbe.started == 1
        // Selecting the fixed row by mouse is allowed; subsequent checks measure
        // source-driven updates against the navigation count after that gesture.
        let afterFixedDragNavigation = navigation.count
        let beforeReadOnlyActions = actions.count
        controller.update(page: .playlist(first.id), playlists: [movedSecond, renamedFirst], counts: [:], covers: [:], canEdit: false)
        NSApp.sendAction(rename.action!, to: rename.target, from: rename)
        checks["recovery-revokes-open-menu-and-drag-capability"] = actions.count == beforeReadOnlyActions
            && controller.outlineView(outline, pasteboardWriterForItem: firstNode) == nil
            && controller.outlineView(outline, validateDrop: drag, proposedItem: actualGroup, proposedChildIndex: 2).isEmpty
            && !controller.outlineView(outline, acceptDrop: drag, item: actualGroup, childIndex: 2)
        controller.update(page: .playlists, playlists: [movedSecond], counts: [:], covers: [:], canEdit: true)
        checks["removed-current-id-obeys-external-directory-page-without-navigation"] = cell(outline.selectedRow).textField?.stringValue == "所有播放列表"
            && navigation.count == afterFixedDragNavigation
        controller.update(page: .playlists, playlists: [], counts: [.playlists: 0], covers: [:], canEdit: true)
        checks["empty-playlist-section-retains-two-fixed-entries"] = controller.outlineView(outline, numberOfChildrenOfItem: playlistGroup) == 2
        checks["empty-directory-accessibility-count-keeps-playlist-unit"] = cell(outline.selectedRow).accessibilityLabel() == "所有播放列表，0 个播放列表"
        controller.onReorder = nil
        checks["missing-reorder-binding-never-advertises-drop"] = controller.outlineView(outline, validateDrop: drag, proposedItem: actualGroup, proposedChildIndex: 2).isEmpty
        var artworkDemands: [Set<UUID>] = []
        controller.onCoverDemand = { artworkDemands.append($0) }
        let longLists = (0..<40).map { WallpaperPlaylist(name: "List \($0)", sidebarRank: $0) }
        window.setContentSize(NSSize(width: 260, height: 320))
        controller.update(page: .playlists, playlists: longLists, counts: [:], covers: [:], canEdit: true)
        window.contentView?.layoutSubtreeIfNeeded(); pump()
        outline.scrollRowToVisible(outline.numberOfRows - 1); pump()
        let demanded = artworkDemands.last ?? []
        checks["artwork-demand-contains-only-real-visible-playlist-rows"] = !demanded.isEmpty && demanded.count < longLists.count
            && demanded.isSubset(of: Set(longLists.map(\.id))) && demanded.contains(longLists.last!.id)
        let lastRow = outline.numberOfRows - 1
        let retainedCell = outline.view(atColumn: 0, row: lastRow, makeIfNecessary: true)
        controller.update(page: .playlists, playlists: longLists, counts: [:], covers: [longLists.last!.id: NSImage(size: .init(width: 20, height: 20))], canEdit: true)
        checks["artwork-only-update-retains-native-row-and-scroll-position"] = retainedCell === outline.view(atColumn: 0, row: lastRow, makeIfNecessary: false)
            && artworkDemands.last == demanded
        outline.collapseItem(playlistGroup); pump()
        checks["collapsed-playlist-group-releases-artwork-demand"] = artworkDemands.last == []
        outline.expandItem(playlistGroup); outline.scrollRowToVisible(outline.numberOfRows - 1); pump()
        controller.view.isHidden = true; pump()
        checks["hidden-sidebar-releases-artwork-demand"] = artworkDemands.last == []
        controller.view.isHidden = false; pump()
        window.orderOut(nil); pump()
        checks["offwindow-sidebar-releases-artwork-demand"] = artworkDemands.last == []
        outline.collapseItem(browse)
        let savedState = defaults.data(forKey: WallpaperLibrarySidebarController.stateKey)
        let restored = WallpaperLibrarySidebarController(defaults: defaults)
        restored.loadViewIfNeeded()
        let restoredOutline = descendants(restored.view, SidebarOutlineView.self).first!
        let restoredBrowse = restoredOutline.item(atRow: 5)!
        checks["fixed-group-collapse-persists-across-controller-recreation"] = savedState != nil && !restoredOutline.isItemExpanded(restoredBrowse)
        restored.update(page: .images, playlists: [], counts: [:], covers: [:], canEdit: true)
        checks["ordinary-page-echo-does-not-rewrite-persisted-fold-state"] = defaults.data(forKey: WallpaperLibrarySidebarController.stateKey) == savedState
        restored.resetSidebarState()
        checks["explicit-sidebar-reset-clears-only-fold-key-and-expands-groups"] = defaults.object(forKey: WallpaperLibrarySidebarController.stateKey) == nil
            && restoredOutline.isItemExpanded(restoredBrowse)
        let unknownState = Data("unknown sidebar format".utf8)
        defaults.set(unknownState, forKey: WallpaperLibrarySidebarController.stateKey)
        let unknownSidebar = WallpaperLibrarySidebarController(defaults: defaults)
        unknownSidebar.loadViewIfNeeded(); unknownSidebar.update(page: .videos, playlists: [], counts: [:], covers: [:], canEdit: true)
        checks["unknown-fold-state-remains-raw-through-read-and-page-echo"] = defaults.data(forKey: WallpaperLibrarySidebarController.stateKey) == unknownState

        window.setContentSize(NSSize(width: 260, height: 760)); window.makeKeyAndOrderFront(nil)
        controller.update(page: .playlists, playlists: [first, second], counts: [:], covers: [:], canEdit: true)
        outline.expandItem(playlistGroup); outline.scrollRowToVisible(outline.numberOfRows - 1); pump()
        let target = outline.item(atRow: outline.numberOfRows - 2)!
        let grid = WallpaperLibraryGridController { collection, path, _, _ in
            let id = NSUserInterfaceItemIdentifier("SidebarGridDragProbe")
            collection.register(SidebarGridDragCell.self, forItemWithIdentifier: id)
            return collection.makeItem(withIdentifier: id, for: path)
        }
        grid.onSelection = { _, _ in UUID() }
        let reference = WallpaperReference(provider: .videoLibrary, sourceID: "drag-local")
        let content = WallpaperContentItem(reference: reference, providerReference: reference, locator: .init(path: "/drag-local"), title: "Drag",
            kind: .video, publishedAvailability: .available, capabilities: [.inspect, .organize], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        let gridWindow = NSWindow(contentViewController: grid)
        gridWindow.isReleasedWhenClosed = false; gridWindow.setContentSize(.init(width: 500, height: 420))
        gridWindow.setFrameOrigin(.init(x: 460, y: 160)); gridWindow.makeKeyAndOrderFront(nil)
        defer { gridWindow.orderOut(nil); gridWindow.close() }
        grid.update(page: .videos, items: [content], selection: .init(), preferredColumns: 5, permitsDragging: true, scrollAnchor: nil)
        gridWindow.contentView?.layoutSubtreeIfNeeded(); pump()
        let cell = grid.collection.item(at: IndexPath(item: 0, section: 0))!
        let origin = cell.view.convert(NSPoint(x: cell.view.bounds.midX, y: cell.view.bounds.midY), to: nil)
        let moved = NSPoint(x: origin.x + 70, y: origin.y + 30)
        func gridEvent(_ type: NSEvent.EventType, _ point: NSPoint, _ time: TimeInterval) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time, windowNumber: gridWindow.windowNumber,
                context: nil, eventNumber: 14, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        let dragTime = ProcessInfo.processInfo.systemUptime
        NSApp.postEvent(gridEvent(.leftMouseUp, moved, dragTime + 0.03), atStart: true)
        NSApp.postEvent(gridEvent(.leftMouseDragged, moved, dragTime + 0.02), atStart: true)
        gridWindow.sendEvent(gridEvent(.leftMouseDown, origin, dragTime)); pump(0.1)
        let sourceBoard = SidebarGridNativeDragProbe.session?.draggingPasteboard ?? NSPasteboard.withUniqueName()
        let wallpaperDrag = SidebarDropInfo(source: grid.collection, board: sourceBoard)
        var additions: [([WallpaperReference], UUID)] = []
        controller.onAddReferences = { references, id in additions.append((references, id)); return true }
        checks["actual-local-grid-image-starts-native-drag-with-current-session-receipt"] = SidebarGridNativeDragProbe.session != nil
            && grid.referencesForPlaylistDrop(from: wallpaperDrag) == [reference]
        checks["native-grid-references-can-drop-on-only-fixed-target-playlist-uuid"] = controller.outlineView(outline, validateDrop: wallpaperDrag, proposedItem: target, proposedChildIndex: -1) == .copy
            && controller.outlineView(outline, acceptDrop: wallpaperDrag, item: target, childIndex: -1)
            && additions.count == 1 && additions[0].0 == [reference] && additions[0].1 == first.id
        checks["wallpaper-drop-never-targets-fixed-directory-or-order-insertion"] = controller.outlineView(outline, validateDrop: wallpaperDrag, proposedItem: fixedAll, proposedChildIndex: -1).isEmpty
            && !controller.outlineView(outline, acceptDrop: wallpaperDrag, item: target, childIndex: 2)
        let forged = SidebarDropInfo(source: NSCollectionView(), board: sourceBoard)
        checks["external-pasteboard-with-real-reference-cannot-forge-grid-authority"] = controller.outlineView(outline, validateDrop: forged, proposedItem: target, proposedChildIndex: -1).isEmpty
        grid.update(page: .images, items: [content], selection: .init(), preferredColumns: 5, permitsDragging: true, scrollAnchor: nil)
        checks["new-page-revokes-old-grid-drag-receipt-before-acceptance"] = !controller.outlineView(outline, acceptDrop: wallpaperDrag, item: target, childIndex: -1) && additions.count == 1
        let currentBoard = NSPasteboard.withUniqueName()
        defer { currentBoard.releaseGlobally() }
        let currentWriter = grid.collectionView(grid.collection, pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))!
        currentBoard.writeObjects([currentWriter])
        currentBoard.setString(WallpaperReference(provider: .videoLibrary, sourceID: "unknown-id").storageKey, forType: WallpaperLibraryGridController.referencesType)
        let unknownDrag = SidebarDropInfo(source: grid.collection, board: currentBoard)
        checks["current-grid-session-still-rejects-unknown-reference"] = controller.outlineView(outline, validateDrop: unknownDrag, proposedItem: target, proposedChildIndex: -1).isEmpty
            && !controller.outlineView(outline, acceptDrop: unknownDrag, item: target, childIndex: -1) && additions.count == 1
        grid.update(page: .workshop, items: [content], selection: .init(), preferredColumns: 5, permitsDragging: true, scrollAnchor: nil)
        let remoteWriter = grid.collectionView(grid.collection, pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))
        checks["remote-page-cannot-grant-drop-capability-even-with-organize-bit"] = remoteWriter == nil
            && grid.referencesForPlaylistDrop(from: wallpaperDrag) == nil
            && controller.outlineView(outline, validateDrop: wallpaperDrag, proposedItem: target, proposedChildIndex: -1).isEmpty
            && !controller.outlineView(outline, acceptDrop: wallpaperDrag, item: target, childIndex: -1)
            && !controller.outlineView(outline, acceptDrop: unknownDrag, item: target, childIndex: -1) && additions.count == 1
        grid.update(page: .images, items: [content], selection: .init(), preferredColumns: 5, permitsDragging: true, scrollAnchor: nil)
        currentBoard.clearContents()
        currentBoard.writeObjects([grid.collectionView(grid.collection, pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))!])
        grid.update(page: .images, items: [], selection: grid.selection, preferredColumns: 5, permitsDragging: true, scrollAnchor: nil)
        checks["source-item-removal-revokes-drop-without-changing-session"] = !controller.outlineView(outline, acceptDrop: unknownDrag, item: target, childIndex: -1) && additions.count == 1
        let ordering = WallpaperLibrarySidebarController(defaults: defaults)
        var authority = (0..<3).map { WallpaperPlaylist(name: "Order \($0)", sidebarRank: $0) }
        let originalAuthority = authority, orderEpoch = UUID()
        var authorityRevision: Int64?
        var epoch = orderEpoch, requested: [[UUID]] = [], results: [(Result<Int64, Error>) -> Void] = []
        let images = Dictionary(uniqueKeysWithValues: authority.map { ($0.id, NSImage(size: .init(width: 24, height: 24))) })
        ordering.onReorder = { order, done in requested.append(order); results.append(done) }
        let orderWindow = NSWindow(contentViewController: ordering)
        orderWindow.isReleasedWhenClosed = false; orderWindow.setContentSize(.init(width: 280, height: 760))
        orderWindow.setFrameOrigin(.init(x: 180, y: 180)); orderWindow.makeKeyAndOrderFront(nil)
        defer { orderWindow.orderOut(nil); orderWindow.close() }
        func publishOrder(editable: Bool = true) {
            ordering.update(page: .playlist(originalAuthority[1].id), playlists: authority, counts: [:], covers: images, canEdit: editable, resetEpoch: epoch, relationshipsRevision: authorityRevision)
            orderWindow.contentView?.layoutSubtreeIfNeeded(); pump(0.15)
        }
        publishOrder()
        let orderOutline = descendants(ordering.view, SidebarOutlineView.self).first!
        let orderGroup = (0..<orderOutline.numberOfRows).first { row in
            (orderOutline.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue == "播放列表"
        }.map { orderOutline.item(atRow: $0)! }!
        orderOutline.expandItem(orderGroup); orderWindow.contentView?.layoutSubtreeIfNeeded(); pump()
        func node(_ index: Int) -> Any { ordering.outlineView(orderOutline, child: index + 2, ofItem: orderGroup) }
        func displayedNames() -> [String] {
            (0..<authority.count).map { index in
                let row = orderOutline.row(forItem: node(index))
                return (orderOutline.view(atColumn: 0, row: row, makeIfNecessary: true) as! NSTableCellView).textField!.stringValue
            }
        }
        let stableCells = Dictionary(uniqueKeysWithValues: (0..<3).map { index in
            let row = orderOutline.row(forItem: node(index))
            return (originalAuthority[index].id, orderOutline.view(atColumn: 0, row: row, makeIfNecessary: true)!)
        })
        let orderBoard = NSPasteboard.withUniqueName()
        defer { orderBoard.releaseGlobally() }
        func beginOrder(_ index: Int) -> SidebarDropInfo {
            let value = ordering.outlineView(orderOutline, pasteboardWriterForItem: node(index))!
            orderBoard.clearContents(); orderBoard.writeObjects([value])
            return SidebarDropInfo(source: orderOutline, board: orderBoard)
        }
        let movingOrder = beginOrder(0)
        checks["sidebar-native-hover-gap-does-not-write-or-reorder-authority"] = ordering.outlineView(orderOutline, validateDrop: movingOrder,
            proposedItem: orderGroup, proposedChildIndex: 5) == .move && orderOutline.draggingDestinationFeedbackStyle == .gap
            && displayedNames() == authority.map(\.name) && requested.isEmpty
        _ = ordering.outlineView(orderOutline, acceptDrop: movingOrder, item: orderGroup, childIndex: 5)
        checks["sidebar-one-drop-submits-all-playlist-uuids-once-and-forbids-reentry"] = requested == [[authority[1].id, authority[2].id, authority[0].id]]
            && ordering.outlineView(orderOutline, pasteboardWriterForItem: node(0)) == nil
            && !ordering.outlineView(orderOutline, acceptDrop: movingOrder, item: orderGroup, childIndex: 5)
        results[0](.failure(UserCollectionsError.invalidOrder)); pump(0.15)
        checks["sidebar-failure-terminal-restores-order-selection-cell-and-cover-identities"] = displayedNames() == authority.map(\.name)
            && orderOutline.draggingDestinationFeedbackStyle == .regular
            && (0..<3).allSatisfy { index in
                let row = orderOutline.row(forItem: node(index)), id = authority[index].id
                let current = orderOutline.view(atColumn: 0, row: row, makeIfNecessary: true)
                return current === stableCells[id] && (current as? NSTableCellView)?.imageView?.image === images[id]
            } && orderOutline.selectedRow == orderOutline.row(forItem: node(1))
        let successfulOrder = beginOrder(0)
        _ = ordering.outlineView(orderOutline, validateDrop: successfulOrder, proposedItem: orderGroup, proposedChildIndex: 5)
        _ = ordering.outlineView(orderOutline, acceptDrop: successfulOrder, item: orderGroup, childIndex: 5)
        results[1](.success(0)); publishOrder()
        checks["sidebar-success-keeps-preview-through-stale-content-echo"] = displayedNames() == [authority[1].name, authority[2].name, authority[0].name]
            && ordering.outlineView(orderOutline, pasteboardWriterForItem: node(0)) == nil
        authority = [authority[1], authority[2], authority[0]]
        for index in authority.indices { authority[index].sidebarRank = index }
        publishOrder()
        let noOpOrder = beginOrder(0)
        checks["sidebar-original-gap-is-zero-write"] = ordering.outlineView(orderOutline, acceptDrop: noOpOrder, item: orderGroup, childIndex: 2)
            && requested.count == 2
        let cancelledOrder = beginOrder(0)
        _ = ordering.outlineView(orderOutline, validateDrop: cancelledOrder, proposedItem: orderGroup, proposedChildIndex: 5)
        ordering.outlineView(orderOutline, draggingSession: session, endedAt: .zero, operation: [])
        checks["sidebar-cancel-retires-gap-and-writer-with-zero-write"] = orderOutline.draggingDestinationFeedbackStyle == .regular
            && !ordering.outlineView(orderOutline, acceptDrop: cancelledOrder, item: orderGroup, childIndex: 5) && requested.count == 2
        let obsoleteOrder = beginOrder(0)
        _ = ordering.outlineView(orderOutline, acceptDrop: obsoleteOrder, item: orderGroup, childIndex: 5)
        epoch = UUID(); publishOrder(); results[2](.success(0)); pump(0.15)
        checks["sidebar-new-epoch-rejects-late-transaction-receipt"] = displayedNames() == authority.map(\.name) && requested.count == 3
        let readonlyOrder = beginOrder(0)
        let readonlyGap = ordering.outlineView(orderOutline, validateDrop: readonlyOrder, proposedItem: orderGroup, proposedChildIndex: 5) == .move
            && orderOutline.draggingDestinationFeedbackStyle == .gap
        publishOrder(editable: false)
        checks["sidebar-readonly-revokes-active-native-drop"] = readonlyGap && orderOutline.draggingDestinationFeedbackStyle == .regular
            && !ordering.outlineView(orderOutline, acceptDrop: readonlyOrder, item: orderGroup, childIndex: 5)
            && requested.count == 3 && displayedNames() == authority.map(\.name)
        publishOrder()
        let resetOrder = beginOrder(0)
        let resetGap = ordering.outlineView(orderOutline, validateDrop: resetOrder, proposedItem: orderGroup, proposedChildIndex: 5) == .move
            && orderOutline.draggingDestinationFeedbackStyle == .gap
        epoch = UUID(); publishOrder()
        checks["sidebar-reset-clears-validated-gap-without-an-ended-callback-or-write"] = resetGap
            && orderOutline.draggingDestinationFeedbackStyle == .regular
            && !ordering.outlineView(orderOutline, acceptDrop: resetOrder, item: orderGroup, childIndex: 5) && requested.count == 3
        let hiddenOrder = beginOrder(0)
        let hiddenGap = ordering.outlineView(orderOutline, validateDrop: hiddenOrder, proposedItem: orderGroup, proposedChildIndex: 5) == .move
            && orderOutline.draggingDestinationFeedbackStyle == .gap
        ordering.view.isHidden = true; pump()
        checks["sidebar-hidden-clears-validated-gap-without-an-ended-callback-or-write"] = hiddenGap
            && orderOutline.draggingDestinationFeedbackStyle == .regular
            && !ordering.outlineView(orderOutline, acceptDrop: hiddenOrder, item: orderGroup, childIndex: 5) && requested.count == 3
        ordering.view.isHidden = false; publishOrder()
        let replacedOrder = beginOrder(0)
        let replacedGap = ordering.outlineView(orderOutline, validateDrop: replacedOrder, proposedItem: orderGroup, proposedChildIndex: 5) == .move
            && orderOutline.draggingDestinationFeedbackStyle == .gap
        authority.removeLast(); publishOrder()
        checks["sidebar-collection-change-revokes-obsolete-uuid-set"] = replacedGap && orderOutline.draggingDestinationFeedbackStyle == .regular
            && !ordering.outlineView(orderOutline, acceptDrop: replacedOrder, item: orderGroup, childIndex: 4)
            && requested.count == 3 && displayedNames() == authority.map(\.name)
        var probeRevision: Int64 = 100
        for callbackFirst in [true, false] {
            for undoToOriginal in [true, false] {
                authority = originalAuthority; authorityRevision = probeRevision; publishOrder()
                let input = beginOrder(0)
                _ = ordering.outlineView(orderOutline, validateDrop: input, proposedItem: orderGroup, proposedChildIndex: 5)
                _ = ordering.outlineView(orderOutline, acceptDrop: input, item: orderGroup, childIndex: 5)
                let complete = results.last!, preview = [authority[1].name, authority[2].name, authority[0].name]
                authorityRevision = probeRevision + 1; publishOrder()
                let earlyMetadataHeld = displayedNames() == preview && ordering.outlineView(orderOutline, pasteboardWriterForItem: node(0)) == nil
                if callbackFirst { complete(.success(probeRevision + 2)) }
                let preAuthorityHeld = displayedNames() == preview && ordering.outlineView(orderOutline, pasteboardWriterForItem: node(0)) == nil
                authority = undoToOriginal ? originalAuthority : [originalAuthority[2], originalAuthority[0], originalAuthority[1]]
                for index in authority.indices { authority[index].sidebarRank = index }
                authorityRevision = probeRevision + 3; publishOrder()
                let waitingForReceipt = callbackFirst || displayedNames() == preview
                if !callbackFirst { complete(.success(probeRevision + 2)); pump(0.15) }
                let released = ordering.outlineView(orderOutline, pasteboardWriterForItem: node(0)) != nil
                checks["sidebar-commit-revision-settles-skipped-A-\(undoToOriginal ? "undo-original" : "newer-B")-callback-\(callbackFirst ? "first" : "last")"] = earlyMetadataHeld
                    && preAuthorityHeld && waitingForReceipt && released && displayedNames() == authority.map(\.name)
                ordering.outlineView(orderOutline, draggingSession: session, endedAt: .zero, operation: [])
                probeRevision += 10
            }
        }
        FileHandle.standardError.write(try! JSONSerialization.data(withJSONObject: ["sidebarIconGeometry": iconDiagnostics], options: [.sortedKeys]))
        print(String(data: try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}

private final class SidebarGridDragCell: NSCollectionViewItem {
    override func loadView() {
        view = WallpaperCardInteractionView()
        let image = NSImageView(image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!)
        image.frame = NSRect(x: 0, y: 0, width: 220, height: 220)
        view.addSubview(image)
    }
}
enum SidebarGridNativeDragProbe { static var session: NSDraggingSession? }

enum SidebarNativeDragProbe {
    static var started = 0
    static var session: NSDraggingSession?
}
extension WallpaperLibrarySidebarController {
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        SidebarNativeDragProbe.started += 1
        SidebarNativeDragProbe.session = session
    }
}
