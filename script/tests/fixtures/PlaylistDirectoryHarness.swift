import AppKit
import Foundation
import Combine

enum MainWindowCoordinator { static func mainWindow() -> NSWindow? { nil } }

private final class DirectoryUnifiedToolbarProbe: NSObject, NSToolbarDelegate {
    private let titleID = NSToolbarItem.Identifier("directory-native-insets-title")
    private let actionID = NSToolbarItem.Identifier("directory-native-insets-action")
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [titleID, .flexibleSpace, actionID] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = id == titleID ? "原生目录顶部回归" : "视图"
        if id == titleID { item.view = NSTextField(labelWithString: item.label) }
        else { item.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) }
        return item
    }
}


@main struct PlaylistDirectoryHarness {
    static func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }

    static func pump(file: StaticString = #file, line: UInt = #line, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(condition(), "native action did not settle", file: file, line: line)
    }

    static func awaitValue<T>(_ operation: @escaping () async throws -> T) -> T {
        var result: Result<T, Error>?
        Task { @MainActor in
            do { result = .success(try await operation()) }
            catch { result = .failure(error) }
        }
        pump { result != nil }
        return try! result!.get()
    }

    static func selectionPresentation(_ item: NSCollectionViewItem, selected: Bool, highlighted: Bool? = nil) -> Bool {
        guard let outline = descendants(item.view, of: NSBox.self).first,
              let title = descendants(item.view, of: NSTextField.self).first else { return false }
        let visible = highlighted ?? selected
        return item.isSelected == selected && item.view.isAccessibilitySelected() == selected
            && outline.isHidden == !visible && !title.drawsBackground
            && !title.isEditable && !title.isSelectable && title.currentEditor() == nil
    }

    static func main() {
        initializeNativeAppHarness()
        var checks: [String: Bool] = [:]
        let first = WallpaperPlaylistDirectoryEntry(id: UUID(), name: "同名 🎵", count: 3, coverReference: nil)
        let second = WallpaperPlaylistDirectoryEntry(id: UUID(), name: "同名 🎵", count: 0, coverReference: nil)
        let controller = AppKitPlaylistDirectoryController()
        var actions: [PlaylistOrganizationAction] = []
        controller.onAction = { actions.append($0) }
        // This first phase observes native drag admission, not a store commit.
        // Explicit success/failure and the real Actions/SQLite bridge run below.
        controller.onReorder = { _, completion in completion(.failure(UserCollectionsError.invalidOrder)) }
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.setFrameOrigin(NSPoint(x: 14000, y: 14000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        controller.update(entries: [first, second], covers: [:], preferredColumns: 5, permitsReordering: true)
        window.contentView?.layoutSubtreeIfNeeded()
        let collection = descendants(controller.view, of: NSCollectionView.self).first!
        collection.layoutSubtreeIfNeeded()
        let flow = collection.collectionViewLayout as! NSCollectionViewFlowLayout
        flow.prepare()
        checks["directory-fixes-new-first-and-retains-empty-duplicate-names"] = collection.numberOfItems(inSection: 0) == 3
            && controller.entries.map(\.id) == [first.id, second.id]
        let metric = WallpaperLibraryGridMetrics(clipWidth: collection.enclosingScrollView!.contentView.bounds.width, preferredColumns: 5)
        let frame0 = flow.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        let frame1 = flow.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame
        checks["native-layout-keeps-shared-music-insets-spacing-and-cover-side"] = frame0.width == metric.coverSide
            && frame0.height == metric.coverSide + 29 && frame0.minX == metric.horizontalInset
            && frame0.minY == 8 && frame1.minX - frame0.maxX >= 8
        let createItem = collection.item(at: IndexPath(item: 0, section: 0))!
        let firstItem = collection.item(at: IndexPath(item: 1, section: 0))!
        let createCard = createItem.view
        let firstCard = firstItem.view
        createCard.layoutSubtreeIfNeeded(); firstCard.layoutSubtreeIfNeeded()
        checks["directory-card-shows-name-with-right-count-and-keeps-full-accessibility"] = descendants(firstCard, of: NSTextField.self).filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.stringValue) == [first.name, "3"]
            && firstCard.accessibilityLabel() == "打开播放列表，\(first.name)，3 张壁纸"
            && descendants(createCard, of: NSTextField.self).filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.stringValue) == ["新建列表"]
        let firstName = descendants(firstCard, of: NSTextField.self).first!
        let firstCount = descendants(firstCard, of: NSTextField.self).last!
        let firstCaption = firstName.superview as! NSStackView
        func alignedRect(_ field: NSTextField, in card: NSView) -> NSRect {
            card.convert(field.alignmentRect(forFrame: field.frame), from: field.superview!)
        }
        let titleRect = alignedRect(firstName, in: firstCard), countRect = alignedRect(firstCount, in: firstCard)
        checks["directory-single-row-footer-keeps-native-name-and-small-count-inside-card"] = titleRect.height > 0 && countRect.height > 0
            && firstCard.bounds.contains(titleRect) && firstCard.bounds.contains(countRect)
            && firstCaption.orientation == .horizontal && firstCaption.alignment == .firstBaseline
            && abs(titleRect.minX - firstCard.bounds.minX) < 0.01 && abs(countRect.maxX - firstCard.bounds.maxX) < 0.01
            && countRect.minX - titleRect.maxX >= 5.99 && firstCount.alignment == .right
            && firstCount.font!.pointSize < firstName.font!.pointSize && firstCount.textColor == .secondaryLabelColor
            && !firstName.isAccessibilityElement() && !firstCount.isAccessibilityElement()
        let createArtwork = descendants(createCard, of: NSImageView.self).last!
        let firstArtwork = descendants(firstCard, of: NSImageView.self).last!
        let coverHost = firstArtwork.superview!
        let plates = coverHost.subviews.filter { $0 !== firstArtwork }
        checks["playlist-uses-an-available-shared-media-symbol"] = WallpaperLibrarySymbols.playlist.hasPrefix("photo.")
            && NSImage(systemSymbolName: WallpaperLibrarySymbols.playlist, accessibilityDescription: nil) != nil
        checks["empty-playlist-and-create-have-one-artwork-view-without-backplates"] = plates.isEmpty
            && firstArtwork.frame == coverHost.bounds && firstArtwork.image != nil
            && createArtwork.superview!.subviews.count == 1 && createArtwork.frame == createArtwork.superview!.bounds
        let readyCover = NSImage(size: NSSize(width: 32, height: 32))
        let replacementCover = NSImage(size: NSSize(width: 40, height: 40))
        func project(_ image: NSImage?, custom: Bool = false) {
            controller.update(entries: [first, second], covers: [first.id: WallpaperPlaylistArtwork(image: image, isCustom: custom)], preferredColumns: 5, permitsReordering: true)
            window.contentView?.layoutSubtreeIfNeeded()
        }
        project(readyCover)
        let coverGeometry = firstArtwork.frame
        checks["one-cover-fills-shared-square-without-extra-image-surfaces"] = firstArtwork.image === readyCover
            && coverHost.subviews.count == 1 && coverHost.bounds.width == metric.coverSide
            && coverHost.bounds.height == metric.coverSide && firstArtwork.frame == coverHost.bounds
        project(replacementCover)
        checks["new-single-cover-keeps-original-native-item-and-square"] = collection.item(at: IndexPath(item: 1, section: 0)) === firstItem
            && firstArtwork.image === replacementCover && firstArtwork.frame == coverGeometry && coverHost.subviews.count == 1
        project(nil)
        checks["failed-cover-restores-media-placeholder-without-retaining-previous-image"] = firstArtwork.image != nil
            && firstArtwork.image !== readyCover && firstArtwork.image !== replacementCover
            && firstArtwork.contentTintColor == .controlAccentColor && firstArtwork.frame == coverGeometry
            && coverHost.subviews.count == 1
        project(readyCover, custom: true)
        checks["custom-cover-is-one-full-square-on-the-original-item"] = firstArtwork.image === readyCover
            && firstArtwork.frame == coverHost.bounds && coverHost.subviews.count == 1
        checks["single-cover-hit-still-belongs-to-original-collection-card"] = firstCard.hitTest(
            coverHost.convert(NSPoint(x: coverHost.bounds.midX, y: coverHost.bounds.midY), to: firstCard.superview)) === firstCard
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            firstCard.appearance = NSAppearance(named: appearanceName)
            window.contentView?.layoutSubtreeIfNeeded()
            var expected: NSColor!
            firstCard.effectiveAppearance.performAsCurrentDrawingAppearance {
                expected = NSColor.controlBackgroundColor.usingColorSpace(.deviceRGB)
            }
            let actual = firstArtwork.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.deviceRGB) }
            checks["single-cover-background-follows-own-appearance-\(appearanceName.rawValue)"] = actual.map {
                abs($0.redComponent - expected.redComponent) < 0.001 && abs($0.greenComponent - expected.greenComponent) < 0.001
                    && abs($0.blueComponent - expected.blueComponent) < 0.001
            } == true
        }
        firstCard.appearance = nil
        // Exercise the same production item across configure/reuse boundaries;
        // the collection's actual click/drag/selection checks remain below.
        let reused = PlaylistDirectoryItem(nibName: nil, bundle: nil)
        reused.view.frame = NSRect(x: 0, y: 0, width: 180, height: 209)
        reused.configure(entry: first, cover: WallpaperPlaylistArtwork(image: readyCover))
        reused.view.layoutSubtreeIfNeeded()
        let reusedArtwork = descendants(reused.view, of: NSImageView.self).last!
        let reusedHost = reusedArtwork.superview!
        let reusedPlates = reusedHost.subviews.filter { $0 !== reusedArtwork }
        reused.prepareForReuse()
        reused.configure(entry: nil, cover: nil)
        reused.view.layoutSubtreeIfNeeded()
        FileHandle.standardError.write(Data("directory-stack-reuse create front=\(reusedArtwork.frame) host=\(reusedHost.bounds) hidden=\(reusedPlates.map(\.isHidden)) sameImage=\(reusedArtwork.image === readyCover) ax=\(String(describing: reused.view.accessibilityLabel()))\n".utf8))
        checks["same-item-playlist-to-create-clears-single-cover-and-accessibility"] = reusedPlates.isEmpty
            && reusedArtwork.frame == reusedHost.bounds && reusedArtwork.image != nil && reusedArtwork.image !== readyCover
            && reused.view.accessibilityLabel() == "新建列表"
            && descendants(reused.view, of: NSTextField.self).filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.stringValue) == ["新建列表"]
        reused.prepareForReuse()
        reused.configure(entry: second, cover: nil)
        reused.view.layoutSubtreeIfNeeded()
        checks["same-item-create-to-empty-playlist-clears-old-cover-and-restores-accessibility"] = reusedPlates.isEmpty
            && reusedPlates.isEmpty && reusedArtwork.image != nil
            && reusedArtwork.frame == reusedHost.bounds
            && reused.view.accessibilityLabel() == "打开播放列表，\(second.name)，0 张壁纸"
        let reusedGeometry = [reused.view.frame, reusedHost.frame, reusedArtwork.frame] + reusedPlates.map(\.frame)
        reused.isSelected = false
        reused.highlightState = .forSelection
        checks["native-selection-proposal-shows-cue-without-forging-committed-ax-selection"] = selectionPresentation(reused,
            selected: false, highlighted: true)
        reused.isSelected = true
        reused.highlightState = .forDeselection
        checks["native-deselection-proposal-withdraws-cue-without-changing-committed-ax-selection"] = selectionPresentation(reused,
            selected: true, highlighted: false)
        reused.highlightState = .none
        checks["ending-native-proposal-restores-only-committed-selection"] = selectionPresentation(reused, selected: true)
            && reusedGeometry == [reused.view.frame, reusedHost.frame, reusedArtwork.frame] + reusedPlates.map(\.frame)
        reused.prepareForReuse()
        reused.configure(entry: nil, cover: nil)
        checks["selected-item-reuse-clears-selection-highlight-name-fill-and-ax-for-create"] = selectionPresentation(reused,
            selected: false) && reused.highlightState == .none && reused.onActivate == nil
            && reused.view.accessibilityLabel() == "新建列表" && reusedPlates.isEmpty
        reused.configure(entry: second, cover: nil)
        checks["reused-playlist-does-not-inherit-the-previous-selection"] = selectionPresentation(reused, selected: false)
            && reused.view.accessibilityLabel() == "打开播放列表，\(second.name)，0 张壁纸"
        checks["reused-directory-card-restores-only-the-current-name-and-count"] = descendants(reused.view, of: NSTextField.self).filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.stringValue) == [second.name, "0"]
        let longEntry = WallpaperPlaylistDirectoryEntry(id: UUID(), name: String(repeating: "长名称 🎵 ", count: 20), count: 123456, coverReference: nil)
        let longItem = PlaylistDirectoryItem(nibName: nil, bundle: nil)
        longItem.view.frame = NSRect(x: 0, y: 0, width: 180, height: 209)
        longItem.configure(entry: longEntry, cover: nil)
        longItem.view.layoutSubtreeIfNeeded()
        let longFields = descendants(longItem.view, of: NSTextField.self)
        let longName = longFields.first!, longCount = longFields.last!
        let longNameRect = alignedRect(longName, in: longItem.view), longCountRect = alignedRect(longCount, in: longItem.view)
        checks["long-directory-name-truncates-before-a-complete-right-count-without-an-extra-row"] = longFields.map(\.stringValue) == [longEntry.name, "123456"]
            && longName.lineBreakMode == .byTruncatingTail && longName.maximumNumberOfLines == 1
            && longName.intrinsicContentSize.width > longNameRect.width && longNameRect.width > 0
            && longItem.view.bounds.contains(longNameRect) && longItem.view.bounds.contains(longCountRect)
            && abs(longCountRect.maxX - longItem.view.bounds.maxX) < 0.01 && longCountRect.minX - longNameRect.maxX >= 5.99
            && longCount.contentCompressionResistancePriority(for: .horizontal) == .required
            && longItem.view.accessibilityLabel() == "打开播放列表，\(longEntry.name)，123456 张壁纸"

        let originalSelection = collection.selectionIndexPaths
        let beforeSelectionActions = actions.count
        let cardGeometry = [firstCard.frame, coverHost.frame, firstArtwork.frame] + plates.map(\.frame)
        collection.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
        window.contentView?.layoutSubtreeIfNeeded()
        let selectionOutline = descendants(firstCard, of: NSBox.self).first!
        let selectedName = descendants(firstCard, of: NSTextField.self).first!
        checks["native-directory-selection-projects-border-name-and-ax-to-only-the-selected-card"] = selectionPresentation(firstItem,
            selected: true) && selectionPresentation(createItem, selected: false)
            && controller.selectedPlaylistID == first.id && actions.count == beforeSelectionActions
        checks["native-directory-selection-uses-system-colors-without-moving-stack-or-cover"] = selectionOutline.boxType == .custom
            && selectionOutline.borderWidth == 1.5 && selectionOutline.borderColor == .controlAccentColor
            && selectionOutline.fillColor == .clear && !selectedName.drawsBackground && selectedName.currentEditor() == nil
            && cardGeometry == [firstCard.frame, coverHost.frame, firstArtwork.frame] + plates.map(\.frame)
            && selectionOutline.convert(selectionOutline.bounds, to: firstCard) == coverHost.convert(coverHost.bounds, to: firstCard)
        checks["selection-outline-remains-passive-to-native-card-hit-and-accessibility"] = !selectionOutline.isAccessibilityElement()
            && firstCard.hitTest(selectionOutline.convert(NSPoint(x: selectionOutline.bounds.midX,
                y: selectionOutline.bounds.maxY - 1), to: firstCard.superview)) === firstCard
        collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        checks["selecting-create-revokes-playlist-cue-without-granting-delete"] = selectionPresentation(firstItem, selected: false)
            && selectionPresentation(createItem, selected: true) && controller.selectedPlaylistID == nil
            && actions.count == beforeSelectionActions
        collection.selectionIndexPaths = originalSelection
        checks["new-and-playlist-cards-have-distinct-accessible-press-actions"] = createCard.accessibilityRole() == .button && createCard.accessibilityLabel() == "新建列表"
            && firstCard.accessibilityRole() == .button && firstCard.accessibilityLabel()?.contains("3 张壁纸") == true
        checks["both-directory-card-accessibility-presses-succeed"] = createCard.accessibilityPerformPress() && firstCard.accessibilityPerformPress()
        checks["accessibility-actions-use-create-or-stable-uuid-without-playback"] = actions == [.create, .open(first.id)]

        window.makeKey()
        func click(_ card: NSView, clickCount: Int = 1) {
            let artwork = descendants(card, of: NSImageView.self).last!
            let point = artwork.convert(NSPoint(x: artwork.bounds.midX, y: artwork.bounds.midY), to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 2, clickCount: clickCount, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber,
                context: nil, eventNumber: 3, clickCount: clickCount, pressure: 0)!
            NSApp.postEvent(up, atStart: true)
            window.sendEvent(down)
            let until = Date().addingTimeInterval(0.02)
            repeat {
                while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.002))
            } while Date() < until
        }
        click(createCard)
        click(createCard, clickCount: 2)
        click(firstCard)
        checks["real-cover-click-reaches-native-gesture-and-double-click-does-not-duplicate-create"] = actions
            == [.create, .open(first.id), .create, .open(first.id)]

        func drag(_ card: NSView) {
            let artwork = descendants(card, of: NSImageView.self).last!
            let point = artwork.convert(NSPoint(x: artwork.bounds.midX, y: artwork.bounds.midY), to: nil)
            let moved = NSPoint(x: point.x + 80, y: point.y + 30)
            func event(_ type: NSEvent.EventType, _ location: NSPoint, _ time: TimeInterval) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: time,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 8, clickCount: 1,
                    pressure: type == .leftMouseUp ? 0 : 1)!
            }
            let time = ProcessInfo.processInfo.systemUptime
            NSApp.postEvent(event(.leftMouseUp, moved, time + 0.03), atStart: true)
            NSApp.postEvent(event(.leftMouseDragged, moved, time + 0.02), atStart: true)
            window.sendEvent(event(.leftMouseDown, point, time))
            let deadline = Date().addingTimeInterval(0.1)
            repeat {
                while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
                RunLoop.main.run(until: Date().addingTimeInterval(0.002))
            } while Date() < deadline
        }
        let beforeDragActions = actions.count
        NSApp.activate()
        window.setFrameOrigin(NSPoint(x: 160, y: 160))
        window.makeKeyAndOrderFront(nil)
        pump { NSApp.isActive && window.isKeyWindow }
        checks["native-drag-delegate-observation-is-installed"] = controller.responds(to: NSSelectorFromString("collectionView:draggingSession:willBeginAtPoint:forItemsAtIndexPaths:"))
        drag(firstCard)
        checks["real-cover-drag-starts-native-collection-session-without-opening-list"] = DirectoryNativeDragProbe.beginnings == [[IndexPath(item: 1, section: 0)]] && actions.count == beforeDragActions
        let draggedCards = collection.visibleItems()
        checks["native-cover-drag-keeps-decorative-titles-without-text-selection-background"] = draggedCards.count == 3 && draggedCards.allSatisfy { item in
            descendants(item.view, of: NSTextField.self).allSatisfy { !$0.drawsBackground && $0.currentEditor() == nil }
        }
        drag(createCard)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        checks["fixed-create-card-cannot-start-native-drag-session"] = DirectoryNativeDragProbe.beginnings.count == 1

        func menu(at index: Int) -> NSMenu {
            let frame = flow.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame
            let location = collection.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            return collection.menu(for: event)!
        }
        let existingMenu = menu(at: 1)
        let createMenu = menu(at: 0)
        checks["context-does-not-navigate-and-create-menu-has-no-destructive-actions"] = actions.count == 4
            && createMenu.items.map(\.title) == ["新建列表…"]
            && existingMenu.items.map(\.title) == ["打开播放列表", "编辑列表…", "复制列表", "", "删除列表…"]
        // This observes the original native menu getter, not an OS right-click
        // selection policy. A menu's captured UUID is separate from selection.
        collection.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
        let beforeMenuActions = actions.count
        let otherMenu = menu(at: 2)
        checks["context-menu-construction-preserves-native-selection-and-its-visible-cue"] = collection.selectionIndexPaths == [IndexPath(item: 1, section: 0)]
            && selectionPresentation(firstItem, selected: true) && actions.count == beforeMenuActions
            && otherMenu.items.first?.representedObject as? UUID == second.id
        // Reorder the live presentation while a menu is open. Its target must
        // remain the UUID captured before that asynchronous change.
        controller.update(entries: [second, first], covers: [:], preferredColumns: 5, permitsReordering: true)
        let rename = existingMenu.items[1]
        NSApp.sendAction(rename.action!, to: rename.target, from: rename)
        checks["open-menu-never-retargets-after-reorder-or-same-name"] = actions.last == .rename(first.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        collection.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36)!
        collection.keyDown(with: enter)
        checks["return-opens-keyboard-selected-list-on-current-display-order"] = actions.last == .open(second.id)
        controller.update(entries: [first, second], covers: [:], preferredColumns: 4, permitsReordering: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        checks["directory-update-preserves-focused-uuid-across-reorder"] = collection.selectionIndexPaths == [IndexPath(item: 2, section: 0)]
        window.contentView?.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
        let reorderedSelection = collection.item(at: IndexPath(item: 2, section: 0))!
        checks["native-selection-presentation-follows-the-same-uuid-after-reorder"] = controller.selectedPlaylistID == second.id
            && selectionPresentation(reorderedSelection, selected: true)
            && reorderedSelection.view.accessibilityLabel() == "打开播放列表，\(second.name)，0 张壁纸"
            && collection.visibleItems().filter(\.isSelected).count == 1
        let beforeRemovedFocus = actions.count
        controller.update(entries: [first], covers: [:], preferredColumns: 4, permitsReordering: false)
        collection.keyDown(with: enter)
        checks["removed-or-filtered-focus-clears-selection-without-return-creating-list"] = collection.selectionIndexPaths.isEmpty && actions.count == beforeRemovedFocus
        window.contentView?.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
        checks["removing-the-selected-uuid-clears-all-visible-selection-cues-and-ax"] = collection.visibleItems().allSatisfy {
            selectionPresentation($0, selected: false)
        } && actions.count == beforeRemovedFocus
        collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        collection.keyDown(with: enter)
        checks["explicit-keyboard-selection-of-create-card-remains-reachable"] = actions.last == .create

        let widths: [CGFloat] = [0, 575, 799, 800, 1099, 1100, 1400]
        for width in widths {
            for zoom in [-99, 3, 4, 5, 6, 999] {
                let m = WallpaperLibraryGridMetrics(clipWidth: width, preferredColumns: zoom)
                let available = max(1, width - 2 * m.horizontalInset)
                checks["grid-metrics-fit-clip-\(width)-\(zoom)"] = m.columns >= 1 && m.coverSide >= 1
                    && m.coverSide * CGFloat(m.columns) + 8 * CGFloat(m.columns - 1) <= available
            }
        }
        checks["invalid-geometry-does-not-produce-nan-or-overflow"] = WallpaperLibraryGridMetrics(clipWidth: .nan, preferredColumns: 5).coverSide == 1
        for width in [CGFloat(900), 1200, 1440] {
            checks["normal-window-starts-with-five-cards-\(width)"] = WallpaperLibraryGridMetrics(clipWidth: width, preferredColumns: 5).columns == 5
        }
        checks["zoom-direction-and-clamped-width-change-on-the-first-click"] = WallpaperLibraryGridMetrics.zoomedColumns(preferredColumns: 6, delta: 1, clipWidth: 550) == 4
            && WallpaperLibraryGridMetrics.zoomedColumns(preferredColumns: 5, delta: -1, clipWidth: 900) == 6
            && !WallpaperLibraryGridMetrics.zoomAvailability(preferredColumns: 3, clipWidth: 900).canZoomIn
            && !WallpaperLibraryGridMetrics.zoomAvailability(preferredColumns: 6, clipWidth: 900).canZoomOut
        let database = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("directory-actions.sqlite3")
        let store = UserCollectionsStore(url: database)
        let initial = awaitValue { try await store.snapshot() }
        let collections = UserCollectionsController(store: store, snapshot: initial)
        let organization = PlaylistOrganizationActions(collections: collections, hostWindow: { window })
        var opened: [UUID] = [], createdWithMembers: [UUID] = []
        organization.onOpen = { opened.append($0) }
        organization.onCreatedFromMembers = { createdWithMembers.append($0) }
        func currentEditor() -> WallpaperLibraryModalPanel? {
            (window.attachedSheet as? WallpaperLibraryModalPanel).flatMap { $0.isVisible ? $0 : nil }
        }
        organization.create()
        let createSheet = currentEditor()!
        let nameField = descendants(createSheet.contentView!, of: NSTextField.self).first { $0.isEditable }!
        let accept = descendants(createSheet.contentView!, of: NSButton.self).first { $0.title == "完成" }!
        checks["organization-create-presents-the-real-native-editor"] = createSheet.delegate is WallpaperPlaylistEditorController
            && createSheet.sheetParent === window && window.attachedSheet === createSheet && createSheet.isSheet
            && !WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && descendants(createSheet.contentView!, of: NSTextView.self).contains { $0.accessibilityLabel() == "播放列表描述，可选" }
        nameField.stringValue = " \n "
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: nameField)
        checks["native-name-sheet-rejects-only-blank-name"] = !accept.isEnabled
        nameField.stringValue = "  中文 / 🎵  "
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: nameField)
        checks["native-name-sheet-allows-nonfilename-characters"] = accept.isEnabled
        accept.performClick(nil)
        pump { collections.snapshot.playlists.count == 1 && opened.count == 1 }
        checks["successful-empty-create-opens-only-committed-new-id"] = collections.snapshot.playlists[0].name == "中文 / 🎵"
            && opened == [collections.snapshot.playlists[0].id]
        let item = WallpaperOrganizationItem(reference: .init(provider: .staticImageLibrary, sourceID: "local"),
            locator: .init(path: "/offline/still.png", mediaKind: .image), isPublishedLocally: true, isAvailable: true)
        organization.create(members: [item])
        let membersSheet = currentEditor()!
        descendants(membersSheet.contentView!, of: NSButton.self).first { $0.title == "完成" }!.performClick(nil)
        pump { collections.snapshot.playlists.count == 2 && createdWithMembers.count == 1 }
        checks["create-from-captured-members-preserves-page-and-publishes-one-related-list"] = opened.count == 1
            && createdWithMembers == [collections.snapshot.playlists.last!.id]
            && collections.snapshot.members.map(\.reference) == [item.reference]
        let notice = WallpaperPlaylistCreationNotice()
        var receiptOpens = 0
        func noticeButtons() -> [NSButton] {
            NSApp.windows.filter(\.isVisible).flatMap { $0.contentView.map { descendants($0, of: NSButton.self) } ?? [] }
                .filter { $0.title == "打开列表" }
        }
        notice.show(name: "中文 / 🎵", in: window) { receiptOpens += 1 }
        pump { noticeButtons().count == 1 }
        let firstReceiptButton = noticeButtons()[0]
        checks["created-list-receipt-is-native-nonmodal-and-does-not-navigate-until-requested"] = window.attachedSheet == nil
            && currentEditor() == nil && WallpaperLibrarySheetPresentation.permitsInput(in: window)
            && receiptOpens == 0 && opened.count == 1
        firstReceiptButton.performClick(nil)
        pump { receiptOpens == 1 && noticeButtons().isEmpty }
        firstReceiptButton.performClick(nil)
        checks["open-list-receipt-is-consumed-exactly-once"] = receiptOpens == 1
        notice.show(name: "稍后建立的列表", in: window) { receiptOpens += 10 }
        pump { noticeButtons().count == 1 }
        firstReceiptButton.performClick(nil)
        checks["retired-receipt-button-cannot-open-later-list"] = receiptOpens == 1
        let currentReceiptButton = noticeButtons()[0]
        notice.dismiss()
        currentReceiptButton.performClick(nil)
        checks["dismissing-receipt-revokes-navigation-without-touching-relationships"] = receiptOpens == 1
            && collections.snapshot.playlists.count == 2 && collections.snapshot.members.map(\.reference) == [item.reference]
        organization.create()
        let staleSheet = currentEditor()!
        awaitValue { try await collections.reset() }
        let staleAccept = descendants(staleSheet.contentView!, of: NSButton.self).first { $0.title == "完成" }!
        pump { !staleAccept.isEnabled }
        staleAccept.performClick(nil)
        checks["reset-revokes-open-editor-without-ghost-list-or-navigation"] = collections.snapshot.playlists.isEmpty
            && opened.count == 1 && createdWithMembers.count == 1 && !staleAccept.isEnabled
        descendants(staleSheet.contentView!, of: NSButton.self).first { $0.title == "取消" }!.performClick(nil)
        pump { currentEditor() == nil }
        // Reset is queued from the real committed snapshot publication, before
        // the create caller resumes. Admission-only epoch checks miss this gap.
        var acceptedReset = false
        var committedReset: Task<Void, Error>?
        let resetOnCommit = collections.$snapshot.sink { snapshot in
            if !acceptedReset, snapshot.playlists.contains(where: { $0.name == "Commit then reset" }) {
                acceptedReset = true
                committedReset = Task { @MainActor in try await collections.reset() }
            }
        }
        organization.create()
        let racingSheet = currentEditor()!
        let raceName = descendants(racingSheet.contentView!, of: NSTextField.self).first { $0.isEditable }!
        raceName.stringValue = "Commit then reset"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: raceName)
        descendants(racingSheet.contentView!, of: NSButton.self).first { $0.title == "完成" }!.performClick(nil)
        pump { acceptedReset && !collections.isResetting && collections.snapshot.playlists.isEmpty }
        awaitValue { try await committedReset!.value }
        pump { !racingSheet.isVisible || opened.count > 1 }
        checks["reset-between-commit-and-create-continuation-revokes-navigation-and-retires-old-editor"] = opened.count == 1
            && createdWithMembers.count == 1 && !racingSheet.isVisible && window.attachedSheet == nil
            && currentEditor() == nil && WallpaperLibrarySheetPresentation.permitsInput(in: window)
        resetOnCommit.cancel()
        var artworkDemands: [Set<UUID>] = []
        controller.onCoverDemand = { artworkDemands.append($0) }
        let many = (0..<40).map { WallpaperPlaylistDirectoryEntry(id: UUID(), name: "List \($0)", count: 1, coverReference: nil) }
        controller.update(entries: many, covers: [:], preferredColumns: 5, permitsReordering: true)
        window.contentView?.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
        pump { !(artworkDemands.last ?? []).isEmpty }
        checks["directory-artwork-demand-is-visible-subset-without-fixed-create-card"] = artworkDemands.last!.count < many.count
            && artworkDemands.last!.isSubset(of: Set(many.map(\.id)))
        let visiblePath = collection.indexPathsForVisibleItems().first { $0.item > 0 }!
        let visibleCell = collection.item(at: visiblePath)!
        let oldOrigin = collection.enclosingScrollView!.contentView.bounds.origin
        collection.selectionIndexPaths = [visiblePath]
        controller.update(entries: many, covers: [many[visiblePath.item - 1].id: WallpaperPlaylistArtwork(image: NSImage(size: .init(width: 20, height: 20)))], preferredColumns: 5, permitsReordering: true)
        checks["cover-completion-preserves-native-cell-selection-and-scroll"] = collection.item(at: visiblePath) === visibleCell
            && collection.selectionIndexPaths == [visiblePath] && collection.enclosingScrollView!.contentView.bounds.origin == oldOrigin
        let beforeCoverActions = actions.count
        checks["cover-completion-preserves-selected-border-name-and-ax-on-the-same-item"] = selectionPresentation(visibleCell,
            selected: true) && controller.selectedPlaylistID == many[visiblePath.item - 1].id
        controller.update(entries: many, covers: [:], preferredColumns: 5, permitsReordering: true)
        checks["cover-revocation-preserves-selected-target-without-navigation"] = collection.item(at: visiblePath) === visibleCell
            && selectionPresentation(visibleCell, selected: true) && actions.count == beforeCoverActions
            && collection.enclosingScrollView!.contentView.bounds.origin == oldOrigin
        collection.scrollToItems(at: [IndexPath(item: many.count, section: 0)], scrollPosition: .bottom)
        collection.layoutSubtreeIfNeeded()
        pump { artworkDemands.last?.contains(many.last!.id) == true }
        checks["native-scroll-transfers-demand-to-final-visible-list"] = artworkDemands.last!.contains(many.last!.id)
            && !artworkDemands.last!.contains(many.first!.id)
        controller.view.isHidden = true
        pump { artworkDemands.last == [] }
        checks["hidden-directory-clears-visible-cover-demand"] = artworkDemands.last == []
        controller.view.isHidden = false
        window.orderOut(nil)
        pump { artworkDemands.last == [] }
        checks["offwindow-directory-clears-visible-cover-demand"] = artworkDemands.last == []
        window.makeKeyAndOrderFront(nil)
        controller.restoreScrollAnchor(nil)
        var anchors: [UUID?] = []
        controller.onScrollAnchor = { id, _, _ in anchors.append(id) }
        collection.scrollToItems(at: [IndexPath(item: many.count, section: 0)], scrollPosition: .bottom)
        collection.layoutSubtreeIfNeeded()
        pump { (anchors.last ?? nil) != nil }
        let savedAnchor = anchors.last!!
        checks["native-directory-scroll-publishes-fixed-playlist-anchor"] = many.contains(where: { $0.id == savedAnchor })
        let savedIndex = many.firstIndex(where: { $0.id == savedAnchor })! + 1
        let savedOffset = flow.layoutAttributesForItem(at: IndexPath(item: savedIndex, section: 0))!.frame.minY - collection.enclosingScrollView!.contentView.bounds.minY
        let reordered = Array(many.reversed())
        func traceDirectoryViewport(_ stage: String) {
            let scroll = collection.enclosingScrollView as! WallpaperGridScrollView
            let createPath = IndexPath(item: 0, section: 0), firstPath = IndexPath(item: 1, section: 0)
            let receipt: [String: Any] = ["stage": stage,
                "clip": String(describing: scroll.contentView.bounds), "viewport": String(describing: scroll.gridViewportRect),
                "collectionFrame": String(describing: collection.frame), "collectionVisible": String(describing: collection.visibleRect),
                "createFrame": String(describing: flow.layoutAttributesForItem(at: createPath)?.frame),
                "firstFrame": String(describing: flow.layoutAttributesForItem(at: firstPath)?.frame),
                "visibleItems": collection.indexPathsForVisibleItems().map(\.item).sorted(),
                "hasCreateItem": collection.item(at: createPath) != nil, "hasFirstItem": collection.item(at: firstPath) != nil,
                "selected": collection.selectionIndexPaths.map(\.item).sorted(), "count": collection.numberOfItems(inSection: 0),
                "entries": controller.entries.map { $0.id.uuidString }, "windowVisible": window.isVisible,
                "hidden": controller.view.isHiddenOrHasHiddenAncestor, "nativeBatch": PlaylistDirectoryBatchCompletionProbe.receipt,
                "failedChecks": checks.filter { !$0.value }.map(\.key).sorted()]
            FileHandle.standardError.write(Data("directory-viewport ".utf8))
            FileHandle.standardError.write(try! JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]))
            FileHandle.standardError.write(Data("\n".utf8))
        }
        traceDirectoryViewport("before-reverse-at-bottom")
        let reverseBatchArrivals = PlaylistDirectoryBatchCompletionProbe.arrivals
        let reverseBatchDeliveries = PlaylistDirectoryBatchCompletionProbe.delivered
        controller.update(entries: reordered, covers: [:], preferredColumns: 5, permitsReordering: true)
        // NSCollectionView's animation proxy can finish after the context's
        // requested duration. Wait for this actual batch callback, not time or
        // the desired item/geometry result; pump's deadline remains a failure.
        pump {
            PlaylistDirectoryBatchCompletionProbe.arrivals == reverseBatchArrivals + 1
                && PlaylistDirectoryBatchCompletionProbe.delivered == reverseBatchDeliveries + 1
                && PlaylistDirectoryBatchCompletionProbe.arrivals == PlaylistDirectoryBatchCompletionProbe.delivered
        }
        window.contentView?.layoutSubtreeIfNeeded()
        traceDirectoryViewport("after-reverse-native-completion")
        let newIndex = reordered.firstIndex(where: { $0.id == savedAnchor })! + 1
        let newOffset = flow.layoutAttributesForItem(at: IndexPath(item: newIndex, section: 0))!.frame.minY - collection.enclosingScrollView!.contentView.bounds.minY
        checks["ordinary-directory-reorder-preserves-visible-anchor-offset"] = abs(savedOffset - newOffset) < 1
        controller.restoreScrollAnchor(savedAnchor)
        let restoredOrigin = collection.enclosingScrollView!.contentView.bounds.origin
        let anchorCount = anchors.count
        controller.restoreScrollAnchor(savedAnchor)
        checks["explicit-directory-anchor-restore-is-idempotent-and-does-not-echo"] = collection.enclosingScrollView!.contentView.bounds.origin == restoredOrigin
            && anchors.count == anchorCount
        controller.restoreScrollAnchor(reordered[0].id)
        checks["legacy-first-row-directory-anchor-retains-top-safe-spacing"] = collection.enclosingScrollView!.contentView.bounds.minY == 0
            && flow.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame.minY == 8
        controller.restoreScrollAnchor(reordered[1].id)
        checks["legacy-nonfirst-directory-anchor-in-the-first-row-retains-reference-semantics"] = collection.enclosingScrollView!.contentView.bounds.minY == 8
        controller.restoreScrollAnchor(reordered[10].id, offset: -17, atTop: false)
        let preciseFrame = flow.layoutAttributesForItem(at: IndexPath(item: 11, section: 0))!.frame
        checks["directory-restores-exact-partially-scrolled-row"] = abs(preciseFrame.minY - collection.enclosingScrollView!.contentView.bounds.minY + 17) < 1
        controller.restoreScrollAnchor(reordered[10].id, offset: -17, atTop: true)
        traceDirectoryViewport("after-explicit-true-top")
        checks["explicit-directory-true-top-overrides-old-row-geometry"] = collection.enclosingScrollView!.contentView.bounds.minY == 0
        let receiptsBeforeReset = anchors.count
        controller.invalidateScrollReceipt()
        collection.enclosingScrollView!.contentView.scroll(to: NSPoint(x: 0, y: 50))
        checks["revoked-directory-scroll-receipt-cannot-recreate-reset-state"] = anchors.count == receiptsBeforeReset
        controller.restoreScrollAnchor(nil, atTop: true)
        traceDirectoryViewport("after-reset-receipt-true-top")
        collection.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
        checks["directory-selection-exposes-exact-playlist-uuid"] = controller.selectedPlaylistID == reordered.first!.id
        let beforeDeleteActions = actions.count
        let search = NSTextField(string: "Search")
        search.frame = NSRect(x: 0, y: 0, width: 180, height: 28); controller.view.addSubview(search)
        window.makeFirstResponder(search)
        controller.deleteSelectedPlaylist()
        checks["directory-delete-command-refuses-search-field-focus"] = actions.count == beforeDeleteActions
        search.removeFromSuperview(); window.makeFirstResponder(collection)
        let deleteKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
        window.sendEvent(deleteKey)
        checks["native-directory-delete-routes-only-selected-uuid-to-shared-actions"] = actions.count == beforeDeleteActions + 1
            && actions.last == .delete(reordered.first!.id)
        collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        window.sendEvent(deleteKey)
        checks["fixed-create-card-can-never-be-deleted"] = actions.count == beforeDeleteActions + 1 && controller.selectedPlaylistID == nil
        collection.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
        traceDirectoryViewport("before-readonly-echo")
        controller.update(entries: reordered, covers: [:], preferredColumns: 5, permitsReordering: false, canEdit: false)
        window.sendEvent(deleteKey)
        checks["recovery-readonly-revokes-directory-keyboard-delete"] = actions.count == beforeDeleteActions + 1
        collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        window.contentView?.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
        traceDirectoryViewport("after-readonly-layout-before-create-lookup")
        let readonlyCreateItem = collection.item(at: IndexPath(item: 0, section: 0))!
        let readonlyCreateCard = readonlyCreateItem.view
        let beforeReadonlyCreate = actions.count
        checks["readonly-fixed-create-card-stays-visible-with-disabled-accessibility-and-explanation"] =
            collection.numberOfItems(inSection: 0) == reordered.count + 1 && readonlyCreateCard.isAccessibilityEnabled() == false
            && readonlyCreateCard.accessibilityLabel() == "新建列表" && readonlyCreateCard.toolTip?.contains("只读") == true
        window.sendEvent(enter)
        checks["readonly-create-return-never-publishes-a-create-action"] = actions.count == beforeReadonlyCreate
        click(readonlyCreateCard)
        checks["readonly-create-native-cover-click-never-publishes-a-create-action"] = actions.count == beforeReadonlyCreate
        checks["readonly-create-accessibility-press-reports-false-instead-of-fake-success"] =
            !readonlyCreateCard.accessibilityPerformPress() && actions.count == beforeReadonlyCreate
        let readableItem = collection.item(at: IndexPath(item: 1, section: 0))!
        checks["readonly-directory-keeps-existing-playlist-navigation-enabled"] = readableItem.view.isAccessibilityEnabled()
            && readableItem.view.accessibilityPerformPress() && actions.last == .open(reordered[0].id)
        controller.update(entries: reordered, covers: [:], preferredColumns: 5, permitsReordering: false, canEdit: true)
        let enabledCreate = collection.item(at: IndexPath(item: 0, section: 0)) as! PlaylistDirectoryItem
        let heldEnabledActivation = enabledCreate.onActivate!
        let beforeRestoredCreate = actions.count
        checks["editing-recovery-reuses-the-create-cell-and-restores-real-accessibility-action"] =
            enabledCreate === readonlyCreateItem && enabledCreate.view.isAccessibilityEnabled()
            && enabledCreate.view.accessibilityPerformPress() && actions.count == beforeRestoredCreate + 1 && actions.last == .create
        controller.update(entries: reordered, covers: [:], preferredColumns: 5, permitsReordering: false, canEdit: false)
        checks["held-enabled-create-activation-rechecks-current-readonly-authority"] =
            !heldEnabledActivation() && actions.count == beforeRestoredCreate + 1 && !enabledCreate.view.accessibilityPerformPress()
        let delayed = AppKitPlaylistDirectoryController()
        delayed.loadViewIfNeeded()
        delayed.view.frame = .zero
        delayed.view.layoutSubtreeIfNeeded()
        delayed.update(entries: [], covers: [:], preferredColumns: 5, permitsReordering: false)
        delayed.restoreScrollAnchor(many[20].id, offset: -17, atTop: false)
        delayed.update(entries: many, covers: [:], preferredColumns: 5, permitsReordering: false)
        delayed.view.layoutSubtreeIfNeeded()
        checks["directory-saved-position-arrives-before-nonempty-zero-width-view-mounts"] = delayed.clipWidth == 0
        let delayedWindow = NSWindow(contentViewController: delayed)
        delayedWindow.isReleasedWhenClosed = false
        delayedWindow.setContentSize(NSSize(width: 1000, height: 700))
        delayedWindow.setFrameOrigin(NSPoint(x: 14000, y: 14000)); delayedWindow.orderFrontRegardless()
        defer { delayedWindow.orderOut(nil); delayedWindow.close() }
        delayedWindow.contentView?.layoutSubtreeIfNeeded()
        let delayedCollection = descendants(delayed.view, of: NSCollectionView.self).first!
        let delayedFlow = delayedCollection.collectionViewLayout as! NSCollectionViewFlowLayout
        delayedFlow.prepare()
        let delayedFrame = delayedFlow.layoutAttributesForItem(at: IndexPath(item: 21, section: 0))!.frame
        checks["directory-layout-retries-zero-width-position-without-losing-stable-uuid-or-offset"] = abs(delayedFrame.minY - delayedCollection.enclosingScrollView!.contentView.bounds.minY + 17) < 1
        // A plain NSWindow cannot expose unified-toolbar occlusion. Keep all
        // prior zero-inset checks, then compare actual card/window coordinates
        // in the same full-size-content configuration used by the real App.
        let unified = AppKitPlaylistDirectoryController()
        unified.loadViewIfNeeded()
        unified.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let unifiedEntries = (0..<80).map { WallpaperPlaylistDirectoryEntry(id: UUID(), name: "Native \($0)", count: 1, coverReference: nil) }
        unified.update(entries: unifiedEntries, covers: [:], preferredColumns: 5, permitsReordering: true)
        unified.restoreScrollAnchor(nil, atTop: true)
        unified.view.layoutSubtreeIfNeeded()
        checks["unified-directory-prepublication-starts-without-window-or-native-insets"] = unified.view.window == nil
            && descendants(unified.view, of: NSScrollView.self).first!.contentInsets.top == 0
        let unifiedHost = AppKitDetailHostViewController()
        unifiedHost.loadViewIfNeeded()
        unifiedHost.view.frame = unified.view.frame
        unifiedHost.present(unified)
        let unifiedWindow = NSWindow(contentViewController: unifiedHost)
        unifiedWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        unifiedWindow.titleVisibility = .hidden
        unifiedWindow.titlebarAppearsTransparent = false
        unifiedWindow.titlebarSeparatorStyle = .shadow
        unifiedWindow.toolbarStyle = .unified
        unifiedWindow.isReleasedWhenClosed = false
        unifiedWindow.setContentSize(NSSize(width: 1000, height: 700))
        unifiedWindow.setFrameOrigin(NSPoint(x: 15000, y: 15000))
        let unifiedToolbarDelegate = DirectoryUnifiedToolbarProbe()
        let unifiedToolbar = NSToolbar(identifier: "directory-native-insets-toolbar")
        unifiedToolbar.delegate = unifiedToolbarDelegate
        unifiedWindow.toolbar = unifiedToolbar
        unifiedWindow.orderFrontRegardless()
        defer {
            withExtendedLifetime(unifiedToolbarDelegate) {}
            unifiedWindow.orderOut(nil); unifiedWindow.close()
        }
        let unifiedCollection = descendants(unified.view, of: NSCollectionView.self).first!
        let unifiedScroll = unifiedCollection.enclosingScrollView!
        let unifiedFlow = unifiedCollection.collectionViewLayout as! NSCollectionViewFlowLayout
        func settleUnified() {
            for _ in 0..<3 {
                unifiedWindow.contentView?.layoutSubtreeIfNeeded()
                unified.view.layoutSubtreeIfNeeded()
                unifiedCollection.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        func itemTopInWindow(_ index: Int) -> CGFloat? {
            guard let item = unifiedCollection.item(at: IndexPath(item: index, section: 0)) else { return nil }
            return item.view.convert(item.view.bounds, to: nil).maxY
        }
        func firstCardHasNativeSafeSpacing() -> Bool {
            guard let top = itemTopInWindow(0) else { return false }
            return abs(top - (unifiedWindow.contentLayoutRect.maxY - 8)) < 1
        }
        settleUnified()
        checks["unified-directory-mount-after-t0-publication-preserves-uncovered-top-spacing"] = firstCardHasNativeSafeSpacing()
        unified.restoreScrollAnchor(nil, atTop: true)
        settleUnified()
        checks["unified-directory-fixture-produces-real-native-top-inset"] = unifiedScroll.contentInsets.top > 0
            && unifiedWindow.contentLayoutRect.maxY < unifiedWindow.contentView!.bounds.maxY
        checks["unified-directory-first-entry-keeps-create-card-eight-points-below-uncovered-window"] = firstCardHasNativeSafeSpacing()
        FileHandle.standardError.write(Data("unified-directory-insets top=\(unifiedScroll.contentInsets.top) clipY=\(unifiedScroll.contentView.bounds.minY) cardTop=\(itemTopInWindow(0) ?? -1) layoutTop=\(unifiedWindow.contentLayoutRect.maxY)\n".utf8))
        unified.update(entries: unifiedEntries, covers: [:], preferredColumns: 3, permitsReordering: true)
        settleUnified()
        let largeTop = firstCardHasNativeSafeSpacing()
        unified.update(entries: unifiedEntries, covers: [:], preferredColumns: 6, permitsReordering: true)
        settleUnified()
        checks["unified-directory-density-changes-preserve-uncovered-top-spacing"] = largeTop && firstCardHasNativeSafeSpacing()
        let middle = unifiedFlow.layoutAttributesForItem(at: IndexPath(item: 24, section: 0))!.frame
        unifiedScroll.contentView.scroll(to: NSPoint(x: 0, y: middle.minY + 9))
        unifiedScroll.reflectScrolledClipView(unifiedScroll.contentView)
        settleUnified()
        checks["unified-directory-return-top-test-starts-below-initial-row"] = unifiedScroll.contentView.bounds.minY > 0
        unified.restoreScrollAnchor(nil, atTop: true)
        settleUnified()
        checks["unified-directory-explicit-return-to-top-keeps-native-safe-spacing"] = firstCardHasNativeSafeSpacing()
        unified.restoreScrollAnchor(unifiedEntries[1].id)
        settleUnified()
        checks["unified-directory-legacy-nonfirst-entry-aligns-with-uncovered-viewport"] = itemTopInWindow(2).map {
            abs($0 - unifiedWindow.contentLayoutRect.maxY) < 1
        } ?? false
        unified.restoreScrollAnchor(nil, atTop: true)
        settleUnified()
        let nativeInset = unifiedScroll.contentInsets.top
        let partialNativeY = -nativeInset * 0.5
        var partialReceipt: (UUID?, Double, Bool)?
        unified.onScrollAnchor = { id, offset, atTop in partialReceipt = (id, offset, atTop) }
        unifiedScroll.contentView.scroll(to: NSPoint(x: 0, y: partialNativeY))
        unifiedScroll.reflectScrolledClipView(unifiedScroll.contentView)
        settleUnified()
        let partialCardTop = itemTopInWindow(0)
        let expectedSafeOffset = partialCardTop.map { Double(unifiedWindow.contentLayoutRect.maxY - $0) }
        checks["unified-directory-partial-negative-origin-is-a-real-intermediate-scroll"] = nativeInset > 0
            && unifiedScroll.contentView.bounds.minY < 0 && unifiedScroll.contentView.bounds.minY > -nativeInset
        checks["unified-directory-partial-negative-origin-receipt-is-not-true-top"] = partialReceipt?.2 == false
        checks["unified-directory-scroll-offset-measures-the-uncovered-window-edge"] = expectedSafeOffset.map {
            abs((partialReceipt?.1 ?? .infinity) - $0) < 1
        } ?? false
        let capturedPartial = partialReceipt
        let otherPage = NSViewController()
        otherPage.view = NSView()
        let sizeBeforePageChange = unifiedWindow.contentView!.frame.size
        unifiedHost.present(otherPage)
        unifiedWindow.contentView?.layoutSubtreeIfNeeded()
        unifiedHost.present(unified)
        unified.restoreScrollAnchor(capturedPartial?.0, offset: capturedPartial?.1, atTop: capturedPartial?.2)
        settleUnified()
        checks["unified-directory-real-detail-host-page-roundtrip-preserves-window-geometry"] = unifiedWindow.contentView!.frame.size == sizeBeforePageChange
            && unifiedScroll.contentInsets.top == nativeInset
        checks["unified-directory-partial-negative-origin-and-card-offset-survive-page-roundtrip"] = capturedPartial != nil
            && abs(unifiedScroll.contentView.bounds.minY - partialNativeY) < 1
            && partialCardTop.map { abs((itemTopInWindow(0) ?? .infinity) - $0) < 1 } == true
        unified.restoreScrollAnchor(unifiedEntries[23].id, offset: -17, atTop: false)
        settleUnified()
        let middleSafeOffset = itemTopInWindow(24).map { unifiedWindow.contentLayoutRect.maxY - $0 }
        let shownInset = unifiedScroll.contentInsets.top
        let shownOrigin = unifiedScroll.contentView.bounds.minY
        unifiedToolbar.isVisible = false
        settleUnified()
        let hiddenInset = unifiedScroll.contentInsets.top
        let hiddenOrigin = unifiedScroll.contentView.bounds.minY
        let hiddenSafeOffset = itemTopInWindow(24).map { unifiedWindow.contentLayoutRect.maxY - $0 }
        checks["unified-directory-visibility-test-has-real-inset-change-and-middle-anchor"] = middleSafeOffset.map { abs($0 + 17) < 1 } == true
            && shownOrigin > 0 && hiddenInset < shownInset
        checks["unified-directory-toolbar-hiding-preserves-fixed-middle-card-relative-to-uncovered-top"] = middleSafeOffset != nil
            && hiddenSafeOffset.map { abs($0 - middleSafeOffset!) < 1 } == true
        unifiedToolbar.isVisible = true
        settleUnified()
        let reshownSafeOffset = itemTopInWindow(24).map { unifiedWindow.contentLayoutRect.maxY - $0 }
        checks["unified-directory-toolbar-showing-preserves-fixed-middle-card-relative-to-uncovered-top"] = middleSafeOffset != nil
            && reshownSafeOffset.map { abs($0 - middleSafeOffset!) < 1 } == true
        FileHandle.standardError.write(Data("unified-directory-toolbar-toggle shownInset=\(shownInset) hiddenInset=\(hiddenInset) shownOrigin=\(shownOrigin) hiddenOrigin=\(hiddenOrigin) initialOffset=\(middleSafeOffset ?? .infinity) hiddenOffset=\(hiddenSafeOffset ?? .infinity) reshownOffset=\(reshownSafeOffset ?? .infinity)\n".utf8))

        // The directory intentionally delegates arrows to NSCollectionView.
        // A selected item alone cannot prove that native keyboard scrolling
        // reveals it below a real unified toolbar.
        var keyboardActions: [PlaylistOrganizationAction] = []
        unified.onAction = { keyboardActions.append($0) }
        func keyboardReveal(_ name: String, target: Int, up: Bool) {
            unified.update(entries: unifiedEntries, covers: [:], preferredColumns: 6, permitsReordering: true)
            settleUnified()
            let source = up ? target + 6 : target - 6
            let path = IndexPath(item: target, section: 0)
            unifiedCollection.selectionIndexPaths = [IndexPath(item: source, section: 0)]
            unifiedWindow.makeFirstResponder(unifiedCollection)
            let frame = unifiedFlow.layoutAttributesForItem(at: path)!.frame
            let inset = unifiedScroll.contentInsets.top
            let y = up ? frame.minY - inset * 0.5 : frame.maxY - unifiedScroll.contentView.bounds.height - 20
            unifiedScroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            unifiedScroll.reflectScrolledClipView(unifiedScroll.contentView)
            settleUnified()
            let before = unifiedCollection.item(at: path)!.view
            let beforeRect = before.convert(before.bounds, to: nil)
            let layoutRect = unifiedWindow.contentLayoutRect
            checks["unified-directory-keyboard-\(name)-starts-with-real-occlusion"] = inset > 0
                && frame.height < layoutRect.height && unifiedWindow.firstResponder === unifiedCollection
                && (up ? beforeRect.maxY > layoutRect.maxY + 1 : beforeRect.minY < layoutRect.minY - 1)
                && (!up || unifiedScroll.contentView.bounds.contains(frame))
            let previousActions = keyboardActions.count
            let text = String(UnicodeScalar(up ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)!)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: unifiedWindow.windowNumber,
                context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false,
                keyCode: up ? 126 : 125)!
            unifiedWindow.sendEvent(event)
            settleUnified()
            let selectedItem = unifiedCollection.item(at: path)!
            let after = selectedItem.view
            let afterRect = after.convert(after.bounds, to: nil)
            let expectedID = target == 0 ? nil : unifiedEntries[target - 1].id
            checks["unified-directory-keyboard-\(name)-moves-native-uuid-without-open-or-create"] = unifiedCollection.selectionIndexPaths == [path]
                && unified.selectedPlaylistID == expectedID && keyboardActions.count == previousActions
            checks["unified-directory-keyboard-\(name)-reveals-whole-card-in-window-content-layout"] = afterRect.maxY <= layoutRect.maxY + 1
                && afterRect.minY >= layoutRect.minY - 1
            checks["unified-directory-keyboard-\(name)-projects-only-native-selected-border-name-and-ax"] = selectionPresentation(selectedItem,
                selected: true) && unifiedCollection.visibleItems().allSatisfy { item in
                    guard let currentPath = unifiedCollection.indexPath(for: item) else { return false }
                    return selectionPresentation(item, selected: currentPath == path)
                } && keyboardActions.count == previousActions
            FileHandle.standardError.write(Data("unified-directory-keyboard \(name) before=\(beforeRect) after=\(afterRect) contentLayout=\(layoutRect) clipY=\(unifiedScroll.contentView.bounds.minY)\n".utf8))
        }
        keyboardReveal("up-middle", target: 24, up: true)
        keyboardReveal("down-middle", target: 36, up: false)
        keyboardReveal("up-create-row", target: 0, up: true)

        // The actual delete command opens its existing native confirmation.
        // Cancelling leaves both SQLite and the original native target intact.
        let cancelID = awaitValue { try await collections.createPlaylist(name: "删除取消目标") }
        let cancelEntry = WallpaperPlaylistDirectoryEntry(id: cancelID, name: "删除取消目标", count: 0, coverReference: nil)
        controller.update(entries: [cancelEntry], covers: [:], preferredColumns: 5, permitsReordering: true)
        controller.restoreScrollAnchor(nil, atTop: true)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(collection)
        window.contentView?.layoutSubtreeIfNeeded(); collection.layoutSubtreeIfNeeded()
        collection.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
        let cancelItem = collection.item(at: IndexPath(item: 1, section: 0))!
        let beforeCancelSnapshot = awaitValue { try await store.snapshot() }
        let beforeCancelOpens = opened.count, beforeCancelCreates = createdWithMembers.count
        var deleteRequests: [PlaylistOrganizationAction] = []
        controller.onAction = { action in
            deleteRequests.append(action)
            organization.handle(action)
        }
        window.sendEvent(deleteKey)
        pump { window.attachedSheet != nil }
        let deleteSheet = window.attachedSheet!
        checks["native-delete-confirmation-retains-selected-target-and-accessible-cue"] = deleteRequests == [.delete(cancelID)]
            && controller.selectedPlaylistID == cancelID && selectionPresentation(cancelItem, selected: true)
        let removalButtons = descendants(deleteSheet.contentView!, of: NSButton.self).filter { !$0.title.isEmpty }
        checks["playlist-confirmation-uses-short-remove-cancel-actions-and-preserves-members-scope"] = Set(removalButtons.map(\.title)) == ["移除", "取消"]
            && removalButtons.first { $0.title == "移除" }?.keyEquivalent == "\r"
            && descendants(deleteSheet.contentView!, of: NSTextField.self).contains {
                $0.stringValue == "仅移除此列表，保留其中 0 张壁纸和其他列表。"
            }
        let cancelButton = descendants(deleteSheet.contentView!, of: NSButton.self).first { $0.title == "取消" }!
        cancelButton.performClick(nil)
        pump { window.attachedSheet == nil }
        let afterCancelSnapshot = awaitValue { try await store.snapshot() }
        checks["native-delete-cancel-keeps-sqlite-selection-and-card-appearance-without-create-or-open"] = beforeCancelSnapshot == afterCancelSnapshot
            && controller.selectedPlaylistID == cancelID && selectionPresentation(cancelItem, selected: true)
            && deleteRequests == [.delete(cancelID)] && opened.count == beforeCancelOpens
            && createdWithMembers.count == beforeCancelCreates
        checkDirectoryReordering(first: first, second: second, collections: collections, store: store,
                                 organization: organization, checks: &checks)
        checkDirectoryAnimations(checks: &checks)
        let output = try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(data: output, encoding: .utf8)!)
    }
}

// The production delegate's native AppKit callback is observed by this test-only
// extension. No direct pasteboard/acceptDrop call can satisfy this assertion.
enum DirectoryNativeDragProbe { static var beginnings: [Set<IndexPath>] = []; static var session: NSDraggingSession? }
extension AppKitPlaylistDirectoryController {
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        DirectoryNativeDragProbe.beginnings.append(indexPaths)
        DirectoryNativeDragProbe.session = session
    }
}
