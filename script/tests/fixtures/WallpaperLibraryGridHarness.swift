import AppKit

private final class GridProbeCell: NSCollectionViewItem {
    let thumbnail = NSImageView()
    let button = NSButton(title: "播放", target: nil, action: nil)
    var onPlay: (() -> Void)?
    var representedReference: WallpaperReference?
    override func loadView() {
        view = WallpaperCardInteractionView()
        thumbnail.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        view.addSubview(thumbnail)
        button.target = self
        button.action = #selector(play)
        view.addSubview(button)
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        thumbnail.frame = view.bounds
        button.frame = NSRect(x: 10, y: 10, width: 70, height: 28)
    }
    @objc private func play() { onPlay?() }
}

private final class GridUnavailableProbeCell: NSCollectionViewItem {
    override func loadView() { view = WallpaperCardInteractionView() }
}

private final class GridDefaultButtonProbe: NSObject {
    var count = 0
    @objc func accept(_ sender: Any?) { count += 1 }
}

private final class GridUnifiedToolbarProbe: NSObject, NSToolbarDelegate {
    private let titleID = NSToolbarItem.Identifier("grid-native-insets-title")
    private let actionID = NSToolbarItem.Identifier("grid-native-insets-action")
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [titleID, .flexibleSpace, actionID] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = id == titleID ? "原生顶部回归" : "视图"
        if id == titleID { item.view = NSTextField(labelWithString: item.label) }
        else { item.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) }
        return item
    }
}

@MainActor final class GridDropInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let source: NSView?
    var draggingSource: Any? { source }
    var draggingDestinationWindow: NSWindow? { source?.window }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .move] }
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

@main struct WallpaperLibraryGridHarness {
    static func pump() {
        let until = Date().addingTimeInterval(0.03)
        repeat {
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        } while Date() < until
    }

    /// Exercise the native count/layout transaction, without calling a data-source
    /// method ourselves. A pending scroll must not create old high-index cells
    /// after the controller has installed a shorter value projection.
    static func topologyChecks(values: [WallpaperContentItem]) -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let reuse = NSUserInterfaceItemIdentifier("grid-topology-probe")
        for name in ["shorter", "empty", "same-count-reorder", "cross-page-header"] {
            var leases: [ObjectIdentifier: WallpaperReference] = [:]
            var hidden = Set<ObjectIdentifier>()
            var visibleDemand: [WallpaperReference] = [], nearbyDemand: [WallpaperReference] = []
            var actions = 0
            let controller = WallpaperLibraryGridController { collection, path, value, _ in
                let cell = collection.makeItem(withIdentifier: reuse, for: path) as! GridProbeCell
                cell.representedReference = value.reference
                return cell
            }
            controller.loadViewIfNeeded()
            controller.collection.register(GridProbeCell.self, forItemWithIdentifier: reuse)
            controller.updateCell = { cell, value, _ in
                (cell as? GridProbeCell)?.representedReference = value.reference
            }
            controller.setCellVisible = { cell, visible in
                let key = ObjectIdentifier(cell)
                if visible, let reference = (cell as? GridProbeCell)?.representedReference { leases[key] = reference }
                else { leases.removeValue(forKey: key); hidden.insert(key) }
            }
            controller.onViewport = { visible, nearby in
                visibleDemand = visible.map(\.reference); nearbyDemand = nearby.map(\.reference)
            }
            controller.onSelection = { _, _ in actions += 1; return UUID() }
            controller.onInspect = { _ in actions += 1 }
            controller.onPrimaryAction = { _ in actions += 1 }
            let window = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 1000, height: 650),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            let toolbarDelegate = GridUnifiedToolbarProbe()
            let toolbar = NSToolbar(identifier: .init("grid-topology-\(name)"))
            toolbar.delegate = toolbarDelegate
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 1000, height: 650))
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            let activationDeadline = Date().addingTimeInterval(5)
            while !NSApp.isActive || !window.isKeyWindow {
                precondition(Date() < activationDeadline, "topology fixture did not become active")
                pump()
            }
            defer { window.orderOut(nil); window.close() }
            func settle() {
                for _ in 0..<3 {
                    window.contentView?.layoutSubtreeIfNeeded()
                    controller.collection.layoutSubtreeIfNeeded()
                    pump()
                }
            }
            controller.update(page: .videos, items: values, selection: .init(), preferredColumns: 5,
                permitsDragging: false, scrollAnchor: nil)
            settle()
            let flow = controller.collection.collectionViewLayout as! NSCollectionViewFlowLayout
            let oldCells = controller.collection.visibleItems()
            let oldCellIDs = Set(oldCells.map(ObjectIdentifier.init))
            let heldActivations = oldCells.compactMap { ($0.view as? WallpaperCardInteractionView)?.onAccessibilityActivate }
            let oldVisible = controller.collection.indexPathsForVisibleItems()
            FileHandle.standardError.write(Data("grid-topology mounted \(name) clip=\(controller.scrollView.contentView.bounds) collection=\(controller.collection.frame) itemSize=\(flow.itemSize) flowSize=\(flow.collectionViewContentSize) insets=\(controller.scrollView.contentInsets) nativeCount=\(controller.collection.numberOfItems(inSection: 0)) visible=\(oldVisible.map(\.item).sorted()) key=\(window.isKeyWindow)\n".utf8))
            precondition(!oldVisible.isEmpty && oldVisible.allSatisfy { $0.item < 60 })
            let target = flow.layoutAttributesForItem(at: IndexPath(item: 60, section: 0))!.frame.minY
            let next: [WallpaperContentItem]
            switch name {
            case "empty": next = []
            case "same-count-reorder": next = Array(values.reversed())
            default: next = Array(values.suffix(3))
            }
            let page: WallpaperLibraryPage = name == "cross-page-header" ? .playlist(UUID()) : .videos
            let header = name == "cross-page-header" ? NSView() : nil
            let focused = next.dropFirst().first?.reference
            var selection = WallpaperLibrarySelectionState(references: Set(focused.map { [$0] } ?? []), focusedReference: focused)
            selection.isSelecting = true
            // Do not pump, create an item, or settle the old collection between
            // this real clip scroll/layout invalidation and the next publication.
            controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: target))
            flow.invalidateLayout()
            controller.collection.needsLayout = true
            controller.scrollView.needsLayout = true
            hidden.removeAll()
            checks["topology-\(name)-starts-with-old-native-count-and-pending-high-scroll"] =
                controller.collection.numberOfItems(inSection: 0) == values.count
                && controller.items == values && controller.scrollView.contentView.bounds.minY > 0
                && oldCellIDs.count > 0 && heldActivations.count == oldCells.count
            FileHandle.standardError.write(Data("grid-topology before \(name) oldCount=\(controller.collection.numberOfItems(inSection: 0)) newCount=\(next.count) clipY=\(controller.scrollView.contentView.bounds.minY) oldVisible=\(oldVisible.map(\.item).sorted())\n".utf8))
            controller.update(page: page, items: next, selection: selection, preferredColumns: 6,
                permitsDragging: false, scrollAnchor: nil, scrollAtTop: true,
                header: header.map { ($0, { _ in 124 }) })
            settle()
            let expected = Set(next.map(\.reference))
            let visibleCells = controller.collection.visibleItems()
            checks["topology-\(name)-native-count-and-current-projection-agree"] =
                controller.collection.numberOfItems(inSection: 0) == next.count && controller.items == next
            checks["topology-\(name)-visible-cells-use-exact-new-index-reference"] =
                (next.isEmpty ? visibleCells.isEmpty : !visibleCells.isEmpty)
                && visibleCells.allSatisfy { cell in
                    guard let path = controller.collection.indexPath(for: cell), next.indices.contains(path.item) else { return false }
                    return (cell as? GridProbeCell)?.representedReference == next[path.item].reference
                }
            let expectedSelection = Set(next.indices.filter { selection.references.contains(next[$0].reference) }
                .map { IndexPath(item: $0, section: 0) })
            checks["topology-\(name)-canonical-selection-survives-without-index-aliasing"] =
                controller.selection == selection && controller.collection.selectionIndexPaths == expectedSelection
            checks["topology-\(name)-old-cells-retire-and-current-demand-has-no-removed-reference"] =
                oldCellIDs.isSubset(of: hidden) && Set(leases.values).isSubset(of: expected)
                && Set(visibleDemand + nearbyDemand).isSubset(of: expected)
                && (next.isEmpty ? leases.isEmpty && visibleDemand.isEmpty && nearbyDemand.isEmpty : !visibleDemand.isEmpty)
            checks["topology-\(name)-held-old-accessibility-actions-cannot-inspect-or-play"] =
                heldActivations.allSatisfy { !$0() } && actions == 0
            checks["topology-\(name)-density-and-header-use-new-geometry"] =
                flow.itemSize.width == WallpaperLibraryGridMetrics(clipWidth: controller.scrollView.contentView.bounds.width,
                    preferredColumns: 6).coverSide && flow.headerReferenceSize.height == (header == nil ? 0 : 124)
                && (header == nil || header?.window === window)
            FileHandle.standardError.write(Data("grid-topology after \(name) count=\(controller.collection.numberOfItems(inSection: 0)) visible=\(controller.collection.indexPathsForVisibleItems().map(\.item).sorted())\n".utf8))
            withExtendedLifetime(toolbarDelegate) {}
        }
        return checks
    }

    static func main() {
        initializeNativeAppHarness()
        let mode = CommandLine.arguments.contains("--continuous-drag") ? "continuous-drag-start"
            : CommandLine.arguments.contains("--topology-transitions") ? "topology-start" : "legacy-start"
        FileHandle.standardError.write(Data("grid-stage \(mode)\n".utf8))
        var checks: [String: Bool] = [:]
        let values = (0..<80).map { index -> WallpaperContentItem in
            let provider = WallpaperProvider.allCases[index % WallpaperProvider.allCases.count]
            let reference = WallpaperReference(provider: provider, sourceID: "item-\(index)")
            return WallpaperContentItem(reference: reference, providerReference: reference,
                locator: .init(mediaKind: .video), title: "壁纸 \(index)", kind: .video,
                publishedAvailability: .available, capabilities: [.inspect, .play, .organize], metadata: .init(),
                acquisition: .idle, update: .idle, aliases: [])
        }
        if CommandLine.arguments.contains("--continuous-drag") {
            let output = try! JSONSerialization.data(withJSONObject: WallpaperLibraryGridDragChecks.run(values: Array(values.prefix(4))), options: [.sortedKeys])
            print(String(data: output, encoding: .utf8)!)
            return
        }
        if CommandLine.arguments.contains("--topology-transitions") {
            let output = try! JSONSerialization.data(withJSONObject: topologyChecks(values: values), options: [.sortedKeys])
            print(String(data: output, encoding: .utf8)!)
            return
        }
        var played: [WallpaperReference] = [], inspected: [WallpaperReference] = [], deleted: [[WallpaperReference]] = []
        var quickLook: [WallpaperReference] = []
        var factoryCalls = 0, hiddenCells = 0
        let reuse = NSUserInterfaceItemIdentifier("grid-probe")
        let unavailableReuse = NSUserInterfaceItemIdentifier("grid-unavailable-probe")
        var missingFirstSource = false
        let controller = WallpaperLibraryGridController { collection, path, value, _ in
            factoryCalls += 1
            if missingFirstSource, value.reference == values[0].reference {
                return collection.makeItem(withIdentifier: unavailableReuse, for: path)
            }
            let cell = collection.makeItem(withIdentifier: reuse, for: path) as! GridProbeCell
            cell.onPlay = { played.append(value.reference) }
            return cell
        }
        controller.loadViewIfNeeded()
        let dragDelegate = GridNativeDragDelegate(controller)
        controller.collection.delegate = dragDelegate
        defer { withExtendedLifetime(dragDelegate) {} }
        controller.collection.register(GridProbeCell.self, forItemWithIdentifier: reuse)
        controller.collection.register(GridUnavailableProbeCell.self, forItemWithIdentifier: unavailableReuse)
        controller.onSelection = { _, _ in UUID() }
        controller.onInspect = { inspected.append($0.reference) }
        controller.onPrimaryAction = { played.append($0.reference) }
        controller.onDelete = { deleted.append($0.map(\.reference)) }
        controller.onQuickLook = { quickLook.append($0.reference) }
        controller.setCellVisible = { _, visible in if !visible { hiddenCells += 1 } }
        var presentedTitles: [WallpaperReference: String] = [:]
        var presentedTransfers: [WallpaperReference: WallpaperContentTransferState] = [:]
        controller.updateCell = { cell, value, _ in
            cell.view.toolTip = value.title
            presentedTitles[value.reference] = value.title
            presentedTransfers[value.reference] = value.acquisition
        }
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1000, height: 650))
        window.setFrameOrigin(NSPoint(x: 160, y: 160))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let initialActivationDeadline = Date().addingTimeInterval(5)
        while !NSApp.isActive || !window.isKeyWindow {
            precondition(Date() < initialActivationDeadline, "native grid fixture did not become active")
            pump()
        }
        defer { window.orderOut(nil); window.close() }
        func update(_ page: WallpaperLibraryPage = .videos, selection: WallpaperLibrarySelectionState? = nil,
                    items: [WallpaperContentItem]? = nil, anchor: WallpaperReference? = nil, dragging: Bool = true,
                    offset: Double? = nil, atTop: Bool? = nil, reset: Bool = false) {
            controller.update(page: page, items: items ?? values, selection: selection ?? controller.selection,
                preferredColumns: 5, permitsDragging: dragging, scrollAnchor: anchor,
                scrollOffset: offset, scrollAtTop: atTop, resetScroll: reset)
            window.contentView?.layoutSubtreeIfNeeded()
            controller.collection.layoutSubtreeIfNeeded()
            pump()
        }
        update()
        let collection = controller.collection
        let flow = collection.collectionViewLayout as! NSCollectionViewFlowLayout
        flow.prepare()
        let metrics = WallpaperLibraryGridMetrics(clipWidth: controller.scrollView.contentView.bounds.width, preferredColumns: 5)
        let firstFrame = flow.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        checks["one-native-grid-presents-all-provider-identities-in-source-order"] = collection.numberOfItems(inSection: 0) == 80
            && controller.items.prefix(WallpaperProvider.allCases.count).map(\.reference.provider) == WallpaperProvider.allCases
        checks["square-cells-use-the-shared-cover-size-and-music-content-insets"] = firstFrame.width == metrics.coverSide
            && firstFrame.width == firstFrame.height && firstFrame.minX == metrics.horizontalInset && firstFrame.minY == 8
        let secondFrame = flow.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame
        let nextRowFrame = flow.layoutAttributesForItem(at: IndexPath(item: 5, section: 0))!.frame
        checks["native-grid-default-five-and-steam-spacing"] = metrics.columns == 5
            && secondFrame.minX - firstFrame.maxX >= 8 && nextRowFrame.minY - firstFrame.maxY == 10
        let factoriesBeforeMetadata = factoryCalls, hidesBeforeMetadata = hiddenCells
        let metadataCell = controller.collection.item(at: IndexPath(item: 0, section: 0))!
        let old = values[0]
        let metadataChange = WallpaperContentItem(reference: old.reference, providerReference: old.providerReference,
            locator: old.locator, title: "新的标题和进度", kind: old.kind, publishedAvailability: old.publishedAvailability,
            capabilities: old.capabilities, metadata: old.metadata, acquisition: .init(phase: .transferring, totalBytes: 100, completedBytes: 35),
            update: old.update, aliases: old.aliases)
        update(items: [metadataChange] + values.dropFirst())
        checks["metadata-and-progress-updates-keep-native-cells-and-thumbnail-demand-alive"] = factoryCalls == factoriesBeforeMetadata
            && hiddenCells == hidesBeforeMetadata && metadataCell === controller.collection.item(at: IndexPath(item: 0, section: 0))
            && metadataCell.view.toolTip == metadataChange.title && presentedTitles[old.reference] == metadataChange.title
            && presentedTransfers[old.reference] == metadataChange.acquisition
        checks["metadata-refresh-updates-the-existing-native-accessibility-title"] = metadataCell.view.isAccessibilityElement()
            && metadataCell.view.accessibilityRole() == .group && metadataCell.view.accessibilityLabel() == metadataChange.title
        update()
        let siblingBeforeReplacement = collection.item(at: IndexPath(item: 1, section: 0))!
        controller.needsCellReplacement = { cell, value in
            value.reference == values[0].reference && (missingFirstSource ? cell is GridProbeCell : cell is GridUnavailableProbeCell)
        }
        missingFirstSource = true
        update()
        checks["missing-source-replaces-only-its-visible-cell-without-changing-identity-order"] = collection.item(at: IndexPath(item: 0, section: 0)) is GridUnavailableProbeCell
            && collection.item(at: IndexPath(item: 1, section: 0)) === siblingBeforeReplacement && controller.items == values
        missingFirstSource = false
        update()
        checks["restored-source-replaces-only-the-placeholder-with-its-provider-cell"] = collection.item(at: IndexPath(item: 0, section: 0)) is GridProbeCell
            && collection.item(at: IndexPath(item: 1, section: 0)) === siblingBeforeReplacement && controller.items == values
        func click(_ index: Int, count: Int = 1, flags: NSEvent.ModifierFlags = [], button: Bool = false) {
            let cell = collection.item(at: IndexPath(item: index, section: 0)) as! GridProbeCell
            cell.view.layoutSubtreeIfNeeded()
            let point = button ? cell.button.convert(NSPoint(x: 25, y: 14), to: nil)
                : cell.view.convert(NSPoint(x: cell.view.bounds.midX, y: cell.view.bounds.midY), to: nil)
            let timestamp = ProcessInfo.processInfo.systemUptime
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: flags,
                timestamp: timestamp, windowNumber: window.windowNumber, context: nil, eventNumber: 4, clickCount: count, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: flags,
                timestamp: timestamp + 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 5, clickCount: count, pressure: 0)!
            NSApp.postEvent(up, atStart: true)
            window.sendEvent(down)
            pump()
        }
        func key(_ code: UInt16, text: String = "", flags: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
            collection.keyDown(with: event)
            pump()
        }
        func pan(_ from: Int, to: Int) {
            func center(_ index: Int) -> NSPoint {
                let cell = collection.item(at: IndexPath(item: index, section: 0))!
                return cell.view.convert(NSPoint(x: cell.view.bounds.midX, y: cell.view.bounds.midY), to: nil)
            }
            let origin = center(from), destination = center(to)
            func event(_ type: NSEvent.EventType, _ point: NSPoint, _ time: TimeInterval) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 9, clickCount: 1,
                    pressure: type == .leftMouseUp ? 0 : 1)!
            }
            let time = ProcessInfo.processInfo.systemUptime
            NSApp.postEvent(event(.leftMouseUp, destination, time + 0.04), atStart: true)
            NSApp.postEvent(event(.leftMouseDragged, destination, time + 0.02), atStart: true)
            window.sendEvent(event(.leftMouseDown, origin, time))
            pump()
        }
        click(0)
        checks["real-cover-click-selects-and-inspects-without-starting-playback"] = controller.selection.references == [values[0].reference]
            && inspected == [values[0].reference] && played.isEmpty
        click(0, count: 2)
        checks["double-click-does-not-repeat-inspector-or-play"] = inspected.count == 1 && played.isEmpty
        click(0, flags: .command)
        checks["command-click-retains-single-selection-and-native-selection-mirror"] = controller.selection.references == [values[0].reference]
            && collection.selectionIndexPaths == [IndexPath(item: 0, section: 0)]
        let inspectedBeforeBar = inspected.count
        click(0, button: true)
        checks["real-cell-button-consumes-its-click-without-detail-or-second-play"] = played == [values[0].reference]
            && inspected.count == inspectedBeforeBar
        key(36)
        key(49)
        checks["return-and-space-use-the-selected-canonical-reference"] = played == [values[0].reference, values[0].reference]
            && quickLook == [values[0].reference]
        key(125)
        key(125)
        key(125)
        checks["down-arrow-uses-visual-columns-and-scrolls-vertically"] = controller.selection.focusedReference == values[metrics.columns * 3].reference
            && controller.scrollView.contentView.bounds.minY > 0
        var largeScrollAnchor: WallpaperReference?
        controller.onScrollAnchor = { _, reference, _, _ in largeScrollAnchor = reference }
        let largeScrollIndex = metrics.columns * 6
        let largeScrollY = flow.layoutAttributesForItem(at: IndexPath(item: largeScrollIndex, section: 0))!.frame.minY + 11
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: largeScrollY))
        checks["single-large-native-scroll-reports-layout-anchor-before-visible-cells-catch-up"] = largeScrollAnchor == values[largeScrollIndex].reference
        controller.onScrollAnchor = nil
        let restored = values[24].reference
        update(.images, selection: WallpaperLibrarySelectionState(), anchor: restored)
        let expectedY = flow.layoutAttributesForItem(at: IndexPath(item: 24, section: 0))!.frame.minY
        checks["different-page-with-identical-items-restores-its-own-anchor"] = abs(controller.scrollView.contentView.bounds.minY - expectedY) < 1
        update(.favorites, selection: WallpaperLibrarySelectionState())
        checks["different-page-with-identical-items-and-no-anchor-starts-at-top"] = controller.scrollView.contentView.bounds.minY == 0
        update(.images, selection: WallpaperLibrarySelectionState(), anchor: values[0].reference)
        checks["legacy-first-row-anchor-retains-top-safe-spacing"] = controller.scrollView.contentView.bounds.minY == 0
        update(.favorites, selection: WallpaperLibrarySelectionState(), anchor: values[20].reference, offset: -13, atTop: false)
        let preciseRow = flow.layoutAttributesForItem(at: IndexPath(item: 20, section: 0))!.frame
        checks["page-restore-preserves-partially-scrolled-row-offset"] = abs(preciseRow.minY - controller.scrollView.contentView.bounds.minY + 13) < 1
        update(.favorites, selection: WallpaperLibrarySelectionState(), atTop: true, reset: true)
        checks["same-page-reset-restores-true-top-without-losing-safe-spacing"] = controller.scrollView.contentView.bounds.minY == 0
            && flow.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame.minY == 8
        var selecting = WallpaperLibrarySelectionState()
        selecting.isSelecting = true
        update(.favorites, selection: selecting)
        let search = NSSearchField(frame: NSRect(x: 0, y: 0, width: 150, height: 24))
        controller.view.addSubview(search)
        window.makeFirstResponder(search)
        click(0)
        click(1)
        checks["explicit-selection-mode-toggles-multiple-cards-without-inspector-or-play"] = controller.selection.references == [values[0].reference, values[1].reference]
            && played.count == 2 && inspected.count == inspectedBeforeBar + 3
        checks["real-selection-mode-cover-click-takes-native-keyboard-responder-from-search"] = window.firstResponder === collection
        let hiddenBeforePan = hiddenCells, factoriesBeforePan = factoryCalls
        var sameSessionMetadataEchoes = 0
        controller.onSelection = { _, _ in
            sameSessionMetadataEchoes += 1
            // An unrelated metadata publication can synchronously echo this
            // same session while a native gesture is delivering its selection.
            controller.update(page: .favorites, items: [metadataChange] + values.dropFirst(),
                selection: controller.selection, preferredColumns: 5, permitsDragging: true, scrollAnchor: nil)
            return UUID()
        }
        pan(2, to: 6)
        checks["native-pan-adds-the-cover-rectangle-to-the-original-multiple-selection"] = controller.selection.references
            == Set([0, 1, 2, 6, 7].map { values[$0].reference }) && played.count == 2 && inspected.count == inspectedBeforeBar + 3
        pan(0, to: 6)
        checks["native-pan-from-a-selected-cover-subtracts-the-rectangle-without-opening-details"] = controller.selection.references
            == Set([2, 7].map { values[$0].reference }) && played.count == 2 && inspected.count == inspectedBeforeBar + 3
        checks["same-session-metadata-echo-does-not-reset-native-pan-or-reload-cells"] = sameSessionMetadataEchoes > 0
            && !collection.cancelSelectionTracking && hiddenCells == hiddenBeforePan && factoryCalls == factoriesBeforePan
            && presentedTitles[values[0].reference] == metadataChange.title
        controller.onSelection = { _, _ in UUID() }
        key(36)
        checks["multi-selection-return-never-batch-plays"] = played.count == 2
        let defaultProbe = GridDefaultButtonProbe()
        let acceptButton = NSButton(title: "添加", target: defaultProbe, action: #selector(GridDefaultButtonProbe.accept(_:)))
        controller.view.addSubview(acceptButton)
        window.defaultButtonCell = acceptButton.cell as? NSButtonCell
        key(36)
        checks["selection-grid-return-activates-native-default-button-once-without-playing"] = defaultProbe.count == 1 && played.count == 2
        acceptButton.isEnabled = false
        key(36)
        checks["selection-grid-return-does-not-activate-disabled-default-button"] = defaultProbe.count == 1 && played.count == 2
        window.defaultButtonCell = nil
        acceptButton.removeFromSuperview()
        collection.selectAll(nil)
        checks["native-responder-select-all-publishes-canonical-multiselection"] = controller.selection.references == Set(values.map(\.reference))
        key(0, text: "a", flags: .command)
        key(51)
        checks["selection-mode-command-a-and-delete-target-current-filtered-values"] = controller.selection.references.count == values.count
            && deleted.last == values.map(\.reference)
        var menuTargets: [WallpaperReference] = []
        controller.menuProvider = { targets in menuTargets = targets.map(\.reference); return NSMenu() }
        func context(_ index: Int) {
            let frame = flow.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame
            let point = collection.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 8, clickCount: 1, pressure: 1)!
            _ = collection.menu(for: event)
        }
        let inspectionsBeforeMenu = inspected.count
        context(0)
        checks["right-click-inside-selection-preserves-the-entire-group-without-inspecting"] = menuTargets == values.map(\.reference)
            && inspected.count == inspectionsBeforeMenu
        var smallSelection = controller.selection
        smallSelection.references = [values[0].reference]
        update(.favorites, selection: smallSelection)
        context(2)
        checks["right-click-outside-selection-captures-only-the-target-without-opening-details"] = menuTargets == [values[2].reference]
            && controller.selection.references == [values[2].reference] && inspected.count == inspectionsBeforeMenu
        controller.collection.onBoxSelection?(IndexPath(item: 0, section: 0), firstFrame, false)
        let selectionBeforeReorder = controller.selection
        update(.favorites, selection: selectionBeforeReorder, items: [values[1], values[0]] + values.dropFirst(2))
        controller.collection.onBoxSelection?(IndexPath(item: 0, section: 0), firstFrame, true)
        checks["same-session-order-change-revokes-old-pan-without-changing-accepted-selection"] = collection.cancelSelectionTracking
            && controller.selection == selectionBeforeReorder
        update(.favorites, selection: selectionBeforeReorder)
        click(2) // Start a fresh real gesture after the old one was revoked.
        let receipt = controller.selection.sessionID
        controller.collection.onBoxSelection?(IndexPath(item: 0, section: 0), firstFrame, false)
        var reset = WallpaperLibrarySelectionState()
        reset.isSelecting = true
        update(.favorites, selection: reset, items: Array(values.suffix(4)))
        checks["foreign-session-revokes-box-tracking-before-a-late-drag-can-write-new-page"] = receipt != reset.sessionID
            && collection.cancelSelectionTracking && controller.selection.references.isEmpty
        let newFrame = flow.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        controller.collection.onBoxSelection?(IndexPath(item: 0, section: 0), newFrame, true)
        checks["cancelled-tracking-does-not-select-the-new-item-at-an-old-index"] = controller.selection.references.isEmpty
        controller.onSelection = { _, _ in nil }
        update(.videos, selection: WallpaperLibrarySelectionState(), items: Array(values.prefix(4)))
        let beforeRejected = controller.selection
        let inspectionsBeforeRejected = inspected.count
        key(124)
        click(1)
        context(2)
        checks["rejected-selection-command-preserves-the-prior-session"] = controller.selection == beforeRejected
            && inspected.count == inspectionsBeforeRejected && collection.selectionIndexPaths.isEmpty
        let foreignReset = WallpaperLibrarySelectionState()
        controller.onSelection = { _, _ in
            controller.update(page: .images, items: Array(values.suffix(4)), selection: foreignReset,
                preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
            return nil
        }
        key(124)
        checks["rejected-old-selection-cannot-roll-back-a-synchronous-foreign-reset"] = controller.selection == foreignReset
            && controller.items == Array(values.suffix(4)) && collection.selectionIndexPaths.isEmpty
            && inspected.count == inspectionsBeforeRejected
        controller.onSelection = { _, _ in UUID() }
        let dragPage = WallpaperLibraryPage.playlist(UUID())
        update(dragPage, selection: WallpaperLibrarySelectionState(), items: Array(values.prefix(4)))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let writer = controller.collectionView(collection, pasteboardWriterForItemAt: IndexPath(item: 0, section: 0))!
        board.writeObjects([writer])
        let drag = GridDropInfo(source: collection, board: board)
        func validate(_ info: GridDropInfo) -> NSDragOperation {
            var proposed = NSIndexPath(forItem: 3, inSection: 0)
            var operation = NSCollectionView.DropOperation.on
            return withUnsafeMutablePointer(to: &proposed) { proposed in
                withUnsafeMutablePointer(to: &operation) { operation in
                    controller.collectionView(collection, validateDrop: info, proposedIndexPath: AutoreleasingUnsafeMutablePointer(proposed), dropOperation: operation)
                }
            }
        }
        let beforeInternalDrop = controller.items
        checks["media-grid-never-advertises-or-accepts-an-internal-reorder"] = validate(drag).isEmpty
            && !controller.collectionView(collection, acceptDrop: drag, indexPath: IndexPath(item: 3, section: 0), dropOperation: .before)
            && controller.items == beforeInternalDrop
        checks["local-card-drag-exposes-only-its-current-reference-for-sidebar-quick-add"] = controller.referencesForPlaylistDrop(from: drag) == [values[0].reference]
        update(dragPage, dragging: false)
        checks["readonly-dragging-has-no-source-payload-and-revokes-a-held-sidebar-drop"] =
            controller.collectionView(collection, pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)) == nil
            && controller.referencesForPlaylistDrop(from: drag) == nil
        update(.videos, items: Array(values[1..<4]))
        checks["removed-reference-is-rejected-for-sidebar-and-internal-drop"] = controller.referencesForPlaylistDrop(from: drag) == nil
            && validate(drag).isEmpty
            && !controller.collectionView(collection, acceptDrop: drag, indexPath: IndexPath(item: 3, section: 0), dropOperation: .before)
        let external = GridDropInfo(source: NSView(), board: board)
        checks["external-reference-cannot-forge-sidebar-capability-or-implicit-import"] = controller.referencesForPlaylistDrop(from: external) == nil
            && validate(external).isEmpty
            && !controller.collectionView(collection, acceptDrop: external, indexPath: IndexPath(item: 0, section: 0), dropOperation: .on)
        let quickAddBoard = NSPasteboard.withUniqueName()
        defer { quickAddBoard.releaseGlobally() }
        var localPagesAcceptEveryProvider = true
        for localPage in [WallpaperLibraryPage.videos, .images, .downloads, .recent, .favorites, dragPage] {
            update(localPage, selection: WallpaperLibrarySelectionState(), items: Array(values.prefix(WallpaperProvider.allCases.count)))
            for index in WallpaperProvider.allCases.indices {
                quickAddBoard.clearContents()
                guard let source = controller.collectionView(collection, pasteboardWriterForItemAt: IndexPath(item: index, section: 0)) else {
                    localPagesAcceptEveryProvider = false; continue
                }
                quickAddBoard.writeObjects([source])
                let current = GridDropInfo(source: collection, board: quickAddBoard)
                localPagesAcceptEveryProvider = localPagesAcceptEveryProvider
                    && controller.referencesForPlaylistDrop(from: current) == [values[index].reference]
            }
        }
        checks["every-local-page-publishes-all-current-provider-references-for-sidebar-add"] = localPagesAcceptEveryProvider
        var remotePagesRejectDrag = true
        for nonLibraryPage in [WallpaperLibraryPage.workshop, .pixabay, .wallhaven, .pixiv, .playlists] {
            update(nonLibraryPage, selection: WallpaperLibrarySelectionState(), items: Array(values.prefix(4)))
            remotePagesRejectDrag = remotePagesRejectDrag
                && controller.collectionView(collection, pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)) == nil
        }
        checks["remote-browse-and-directory-values-cannot-masquerade-as-a-local-media-drag"] = remotePagesRejectDrag
        update(.downloads, selection: WallpaperLibrarySelectionState(), items: Array(values.prefix(2)))
        let oldSessionWriter = controller.collectionView(collection, pasteboardWriterForItemAt: IndexPath(item: 1, section: 0))!
        quickAddBoard.clearContents(); quickAddBoard.writeObjects([oldSessionWriter])
        let filteredDrag = GridDropInfo(source: collection, board: quickAddBoard)
        checks["filtered-local-results-retain-sidebar-quick-add-capability"] = controller.referencesForPlaylistDrop(from: filteredDrag) == [values[1].reference]
        update(.images, selection: WallpaperLibrarySelectionState(), items: Array(values.prefix(2)))
        checks["a-new-page-session-rejects-the-old-local-drag-receipt"] = controller.referencesForPlaylistDrop(from: filteredDrag) == nil
        let fileBoard = NSPasteboard.withUniqueName()
        defer { fileBoard.releaseGlobally() }
        let file = URL(fileURLWithPath: "/fixture/import.mp4")
        fileBoard.writeObjects([file as NSURL])
        let fileDrag = GridDropInfo(source: nil, board: fileBoard)
        checks["unbound-import-does-not-advertise-file-copy"] = validate(fileDrag).isEmpty
        var imports: [[URL]] = []
        controller.onImportFiles = { imports.append($0); return true }
        checks["bound-file-import-only-forwards-local-file-urls-to-the-original-owner"] = validate(fileDrag) == .copy
            && controller.collectionView(collection, acceptDrop: fileDrag, indexPath: IndexPath(item: 0, section: 0), dropOperation: .on)
            && imports == [[file]]
        update(.videos, selection: WallpaperLibrarySelectionState(), items: Array(values.prefix(4)))
        window.setFrameOrigin(NSPoint(x: 160, y: 160))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        let activationDeadline = Date().addingTimeInterval(5)
        while (!NSApp.isActive || !window.isKeyWindow), Date() < activationDeadline { pump() }
        let card = collection.item(at: IndexPath(item: 0, section: 0))!.view
        let origin = card.convert(NSPoint(x: card.bounds.midX, y: card.bounds.midY), to: nil)
        let moved = NSPoint(x: origin.x + 70, y: origin.y + 25)
        let inspectionsBeforeDrag = inspected.count
        func dragEvent(_ type: NSEvent.EventType, _ point: NSPoint, _ time: TimeInterval) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 13, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1)!
        }
        let time = ProcessInfo.processInfo.systemUptime
        NSApp.postEvent(dragEvent(.leftMouseUp, moved, time + 0.03), atStart: true)
        NSApp.postEvent(dragEvent(.leftMouseDragged, moved, time + 0.02), atStart: true)
        window.sendEvent(dragEvent(.leftMouseDown, origin, time))
        pump()
        checks["real-cover-drag-enters-native-collection-session-without-inspecting-or-playing"] = GridNativeDragProbe.started
            && inspected.count == inspectionsBeforeDrag && played.count == 2

        // AX activation uses the same accepted selection owner, with no
        // coordinate synthesis, provider dispatch or playback side effect.
        update(.downloads, selection: WallpaperLibrarySelectionState(), items: Array(values.prefix(WallpaperProvider.allCases.count)))
        func accessibilityRoot(_ index: Int = 0) -> WallpaperCardInteractionView {
            collection.item(at: IndexPath(item: index, section: 0))!.view as! WallpaperCardInteractionView
        }
        checks["all-provider-cards-expose-their-current-native-accessibility-group-and-title"] = WallpaperProvider.allCases.indices.allSatisfy {
            let root = accessibilityRoot($0)
            return root.isAccessibilityElement() && root.accessibilityRole() == .group && root.accessibilityLabel() == values[$0].title
        }
        let beforeAXInspections = inspected.count, beforeAXPlays = played.count
        let beforeAXSession = accessibilityRoot().onAccessibilityActivate!
        let singleAccepted = accessibilityRoot().accessibilityPerformPress()
        checks["accessibility-cover-press-selects-and-inspects-once-without-playing"] = singleAccepted
            && controller.selection.references == [values[0].reference]
            && inspected.count == beforeAXInspections + 1 && inspected.last == values[0].reference && played.count == beforeAXPlays
        let selectedByAX = controller.selection
        checks["old-accessibility-selection-session-cannot-replay-an-accepted-action"] = !beforeAXSession()
            && controller.selection == selectedByAX && inspected.count == beforeAXInspections + 1

        var axMulti = WallpaperLibrarySelectionState(); axMulti.isSelecting = true
        update(.downloads, selection: axMulti, items: Array(values.prefix(4)))
        let firstToggle = accessibilityRoot().accessibilityPerformPress()
        let selectedOnce = controller.selection.references == [values[0].reference]
        let secondToggle = accessibilityRoot().accessibilityPerformPress()
        checks["accessibility-explicit-multiselect-toggles-the-same-card-twice-without-details-or-play"] = firstToggle && selectedOnce
            && secondToggle && controller.selection.references.isEmpty && controller.selection.isSelecting
            && inspected.count == beforeAXInspections + 1 && played.count == beforeAXPlays

        let beforeReplacement = accessibilityRoot().onAccessibilityActivate!
        missingFirstSource = true
        update(.downloads)
        let isMissingRoot = collection.item(at: IndexPath(item: 0, section: 0)) is GridUnavailableProbeCell
        let oldProviderRejected = !beforeReplacement()
        let missingAccepted = accessibilityRoot().accessibilityPerformPress()
        checks["missing-source-card-keeps-the-same-accessibility-selection-entry"] = isMissingRoot && missingAccepted
            && controller.selection.references == [values[0].reference] && oldProviderRejected
            && inspected.count == beforeAXInspections + 1 && played.count == beforeAXPlays
        let beforeRestoration = accessibilityRoot().onAccessibilityActivate!
        missingFirstSource = false
        update(.downloads)
        checks["replaced-placeholder-accessibility-callback-cannot-act-on-its-reused-provider-cell"] = !beforeRestoration()
            && controller.selection.references == [values[0].reference]
        let beforeNewItems = accessibilityRoot().onAccessibilityActivate!
        let preservedSession = controller.selection
        update(.downloads, selection: preservedSession, items: Array(values.suffix(4)))
        checks["same-page-native-cell-reuse-rejects-the-old-fixed-reference"] = !beforeNewItems()
            && controller.selection == preservedSession && inspected.count == beforeAXInspections + 1
        checks["native-card-reuse-exposes-the-new-source-title-instead-of-the-old-label"] = accessibilityRoot().isAccessibilityElement()
            && accessibilityRoot().accessibilityRole() == .group && accessibilityRoot().accessibilityLabel() == values[76].title
        let beforePageChange = accessibilityRoot().onAccessibilityActivate!
        update(.images, selection: WallpaperLibrarySelectionState(), items: Array(values.suffix(4)))
        checks["old-accessibility-page-callback-cannot-select-the-new-page"] = !beforePageChange()
            && controller.selection.references.isEmpty && inspected.count == beforeAXInspections + 1
        let beforeHide = accessibilityRoot().onAccessibilityActivate!
        controller.viewWillDisappear()
        checks["hidden-grid-revokes-both-current-and-held-accessibility-actions"] = !beforeHide()
            && accessibilityRoot().onAccessibilityActivate?() == false && controller.selection.references.isEmpty
        controller.viewDidAppear(); pump()
        controller.onSelection = { _, _ in nil }
        let beforeAXRejection = controller.selection
        checks["rejected-accessibility-selection-reports-false-without-inspecting"] = !accessibilityRoot().accessibilityPerformPress()
            && controller.selection == beforeAXRejection && inspected.count == beforeAXInspections + 1 && played.count == beforeAXPlays

        // The first catalogue publication can arrive before its native view is
        // mounted. Neither zero width nor that initial empty snapshot may eat
        // the saved row/offset before the actual clip geometry exists.
        let delayed = WallpaperLibraryGridController { collection, path, _, _ in
            collection.makeItem(withIdentifier: unavailableReuse, for: path)
        }
        delayed.loadViewIfNeeded()
        delayed.collection.register(GridUnavailableProbeCell.self, forItemWithIdentifier: unavailableReuse)
        delayed.view.frame = .zero
        delayed.view.layoutSubtreeIfNeeded()
        let playlistPage = WallpaperLibraryPage.playlist(UUID())
        let playlistHeader = NSView()
        delayed.update(page: playlistPage, items: [], selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: values[20].reference, scrollOffset: -13, scrollAtTop: false,
            header: (playlistHeader, { _ in 168 }))
        checks["deferred-scroll-test-starts-with-real-zero-width"] = delayed.scrollView.contentView.bounds.width == 0
        delayed.update(page: playlistPage, items: values, selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil, header: (playlistHeader, { _ in 168 }))
        checks["source-arrives-while-grid-is-still-unmounted-and-zero-width"] = delayed.scrollView.contentView.bounds.width == 0
        let delayedWindow = NSWindow(contentViewController: delayed)
        delayedWindow.isReleasedWhenClosed = false
        delayedWindow.setContentSize(NSSize(width: 1000, height: 650))
        delayedWindow.setFrameOrigin(NSPoint(x: 14000, y: 14000))
        delayedWindow.orderFrontRegardless()
        defer { delayedWindow.orderOut(nil); delayedWindow.close() }
        delayedWindow.contentView?.layoutSubtreeIfNeeded()
        delayedWindow.contentView?.layoutSubtreeIfNeeded(); pump()
        let delayedFlow = delayed.collection.collectionViewLayout as! NSCollectionViewFlowLayout
        let delayedFrame = delayedFlow.layoutAttributesForItem(at: IndexPath(item: 20, section: 0))!.frame
        checks["zero-width-and-initial-empty-publication-preserve-pending-row-offset"] = abs(delayedFrame.minY - delayed.scrollView.contentView.bounds.minY + 13) < 1
        var leaving: (WallpaperReference?, Double, Bool)?
        delayed.onScrollAnchor = { page, ref, offset, top in if page == playlistPage { leaving = (ref, offset, top) } }
        delayed.update(page: .videos, items: values, selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil)
        checks["leaving-playlist-captures-geometry-before-removing-header"] = leaving?.0 == values[20].reference
            && abs((leaving?.1 ?? 0) + 13) < 1 && leaving?.2 == false
        delayed.update(page: playlistPage, items: values, selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: leaving?.0, scrollOffset: leaving?.1, scrollAtTop: leaving?.2,
            header: (playlistHeader, { _ in 168 }))
        checks["playlist-header-roundtrip-restores-original-reference-and-offset"] = abs(delayedFrame.minY - delayed.scrollView.contentView.bounds.minY + 13) < 1
        delayed.update(page: .images, items: values, selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: values[1].reference, header: (playlistHeader, { _ in 168 }))
        checks["legacy-nonfirst-reference-in-first-row-does-not-invent-true-top"] = delayed.scrollView.contentView.bounds.minY == 176
        delayed.update(page: playlistPage, items: values, selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: values[20].reference, scrollOffset: -13, scrollAtTop: false,
            header: (playlistHeader, { _ in 168 }))
        var gestureReceipts = 0
        delayed.onScrollAnchor = { _, _, _, _ in gestureReceipts += 1 }
        var delayedSelection = WallpaperLibrarySelectionState(); delayedSelection.isSelecting = true
        delayed.update(page: playlistPage, items: values, selection: delayedSelection, preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil, header: (playlistHeader, { _ in 168 }))
        delayed.collection.onBoxSelection?(IndexPath(item: 20, section: 0), delayedFrame, false)
        for step in 1...20 { delayed.scrollView.contentView.scroll(to: NSPoint(x: 0, y: delayedFrame.minY + CGFloat(step))) }
        checks["box-autoscroll-does-not-persist-per-pixel-scroll-receipts"] = gestureReceipts == 0
        delayed.collection.onBoxSelection?(IndexPath(item: 20, section: 0), delayedFrame, true)
        checks["box-autoscroll-persists-one-final-scroll-receipt"] = gestureReceipts == 1
        delayed.invalidateScrollReceipt()
        delayed.scrollView.contentView.scroll(to: NSPoint(x: 0, y: delayedFrame.minY + 100))
        checks["revoked-grid-scroll-cannot-recreate-reset-state"] = gestureReceipts == 1
        delayed.update(page: playlistPage, items: values, selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil, header: (playlistHeader, { _ in 168 }))
        checks["hidden-reset-regrant-on-the-same-page-and-items-discards-old-scroll-geometry"] = delayed.scrollView.contentView.bounds.minY == 0
            && gestureReceipts == 1
        // Match MainWindowController's real titlebar/toolbar composition. The
        // earlier plain-window checks stay independent and retain their y=0
        // contract; here the actual window's uncovered content is the oracle.
        FileHandle.standardError.write(Data("grid-stage unified-start checks=\(checks.count)\n".utf8))
        let unified = WallpaperLibraryGridController { collection, path, _, _ in
            collection.makeItem(withIdentifier: unavailableReuse, for: path)
        }
        unified.loadViewIfNeeded()
        unified.collection.register(GridUnavailableProbeCell.self, forItemWithIdentifier: unavailableReuse)
        unified.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 650)
        unified.view.layoutSubtreeIfNeeded()
        unified.update(page: .videos, items: values, selection: .init(), preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil)
        unified.view.layoutSubtreeIfNeeded()
        checks["unified-toolbar-prepublication-starts-without-a-window-or-native-insets"] = unified.view.window == nil
            && unified.scrollView.contentInsets.top == 0
        let unifiedWindow = NSWindow(contentViewController: unified)
        unifiedWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        unifiedWindow.titleVisibility = .hidden
        unifiedWindow.titlebarAppearsTransparent = false
        unifiedWindow.titlebarSeparatorStyle = .shadow
        unifiedWindow.toolbarStyle = .unified
        unifiedWindow.isReleasedWhenClosed = false
        unifiedWindow.setContentSize(NSSize(width: 1000, height: 650))
        unifiedWindow.setFrameOrigin(NSPoint(x: 15000, y: 15000))
        let unifiedToolbarDelegate = GridUnifiedToolbarProbe()
        let unifiedToolbar = NSToolbar(identifier: "grid-native-insets-toolbar")
        unifiedToolbar.delegate = unifiedToolbarDelegate
        unifiedWindow.toolbar = unifiedToolbar
        unifiedWindow.orderFrontRegardless()
        defer {
            withExtendedLifetime(unifiedToolbarDelegate) {}
            unifiedWindow.orderOut(nil); unifiedWindow.close()
        }
        func settleUnified() {
            for _ in 0..<3 {
                unifiedWindow.contentView?.layoutSubtreeIfNeeded()
                unified.view.layoutSubtreeIfNeeded()
                unified.collection.layoutSubtreeIfNeeded()
                pump()
            }
        }
        func updateUnified(_ page: WallpaperLibraryPage, columns: Int = 5, anchor: WallpaperReference? = nil,
                           offset: Double? = nil, top: Bool? = nil, header: NSView? = nil, height: CGFloat = 0) {
            unified.update(page: page, items: values, selection: .init(), preferredColumns: columns,
                permitsDragging: false, scrollAnchor: anchor, scrollOffset: offset, scrollAtTop: top,
                header: header.map { ($0, { _ in height }) })
            settleUnified()
        }
        func itemTopInWindow(_ index: Int) -> CGFloat? {
            guard let item = unified.collection.item(at: IndexPath(item: index, section: 0)) else { return nil }
            return item.view.convert(item.view.bounds, to: nil).maxY
        }
        func firstCardHasNativeSafeSpacing() -> Bool {
            guard let top = itemTopInWindow(0) else { return false }
            return abs(top - (unifiedWindow.contentLayoutRect.maxY - 8)) < 1
        }
        settleUnified()
        checks["unified-toolbar-mount-after-t0-publication-preserves-uncovered-top-spacing"] = firstCardHasNativeSafeSpacing()
        updateUnified(.videos)
        checks["unified-toolbar-fixture-produces-real-native-top-inset"] = unified.scrollView.contentInsets.top > 0
            && unifiedWindow.contentLayoutRect.maxY < unifiedWindow.contentView!.bounds.maxY
        checks["unified-toolbar-first-entry-keeps-first-card-eight-points-below-uncovered-window"] = firstCardHasNativeSafeSpacing()
        FileHandle.standardError.write(Data("unified-grid-insets top=\(unified.scrollView.contentInsets.top) clipY=\(unified.scrollView.contentView.bounds.minY) cardTop=\(itemTopInWindow(0) ?? -1) layoutTop=\(unifiedWindow.contentLayoutRect.maxY)\n".utf8))
        updateUnified(.images)
        checks["unified-toolbar-page-switch-keeps-native-top-safe-spacing"] = firstCardHasNativeSafeSpacing()
        updateUnified(.images, columns: 3)
        let largeTop = firstCardHasNativeSafeSpacing()
        updateUnified(.images, columns: 6)
        checks["unified-toolbar-density-changes-preserve-uncovered-top-spacing"] = largeTop && firstCardHasNativeSafeSpacing()
        let unifiedFlow = unified.collection.collectionViewLayout as! NSCollectionViewFlowLayout
        let middleFrame = unifiedFlow.layoutAttributesForItem(at: IndexPath(item: 24, section: 0))!.frame
        unified.scrollView.contentView.scroll(to: NSPoint(x: 0, y: middleFrame.minY + 9))
        unified.scrollView.reflectScrolledClipView(unified.scrollView.contentView)
        settleUnified()
        checks["unified-toolbar-return-top-test-starts-below-initial-row"] = unified.scrollView.contentView.bounds.minY > 0
        unified.scrollToTop(animated: false)
        settleUnified()
        checks["unified-toolbar-explicit-scroll-to-top-keeps-native-safe-spacing"] = firstCardHasNativeSafeSpacing()
        let realHeader = NSView()
        updateUnified(playlistPage, top: true, header: realHeader, height: 168)
        checks["unified-toolbar-playlist-header-is-fully-below-titlebar"] = realHeader.window === unifiedWindow
            && abs(realHeader.convert(realHeader.bounds, to: nil).maxY - unifiedWindow.contentLayoutRect.maxY) < 1
        updateUnified(.videos, anchor: values[1].reference, header: realHeader, height: 168)
        checks["unified-toolbar-legacy-nonfirst-reference-aligns-with-uncovered-viewport"] = itemTopInWindow(1).map {
            abs($0 - unifiedWindow.contentLayoutRect.maxY) < 1
        } ?? false
        updateUnified(.images, top: true)
        let nativeInset = unified.scrollView.contentInsets.top
        let partialNativeY = -nativeInset * 0.5
        var partialReceipt: (WallpaperReference?, Double, Bool)?
        unified.onScrollAnchor = { page, reference, offset, atTop in
            if page == .images { partialReceipt = (reference, offset, atTop) }
        }
        unified.scrollView.contentView.scroll(to: NSPoint(x: 0, y: partialNativeY))
        unified.scrollView.reflectScrolledClipView(unified.scrollView.contentView)
        settleUnified()
        let partialCardTop = itemTopInWindow(0)
        let expectedSafeOffset = partialCardTop.map { Double(unifiedWindow.contentLayoutRect.maxY - $0) }
        checks["unified-toolbar-partial-negative-origin-is-a-real-intermediate-scroll"] = nativeInset > 0
            && unified.scrollView.contentView.bounds.minY < 0 && unified.scrollView.contentView.bounds.minY > -nativeInset
        checks["unified-toolbar-partial-negative-origin-receipt-is-not-true-top"] = partialReceipt?.0 == values[0].reference
            && partialReceipt?.2 == false
        checks["unified-toolbar-scroll-offset-measures-the-uncovered-window-edge"] = expectedSafeOffset.map {
            abs((partialReceipt?.1 ?? .infinity) - $0) < 1
        } ?? false
        let capturedPartial = partialReceipt
        updateUnified(.favorites, top: true)
        updateUnified(.images, anchor: capturedPartial?.0, offset: capturedPartial?.1, top: capturedPartial?.2)
        checks["unified-toolbar-partial-negative-origin-and-card-offset-survive-page-roundtrip"] = capturedPartial != nil
            && abs(unified.scrollView.contentView.bounds.minY - partialNativeY) < 1
            && partialCardTop.map { abs((itemTopInWindow(0) ?? .infinity) - $0) < 1 } == true
        updateUnified(.favorites, top: true)
        updateUnified(.images, anchor: values[20].reference, offset: -13, top: false)
        let middleSafeOffset = itemTopInWindow(20).map { unifiedWindow.contentLayoutRect.maxY - $0 }
        let shownInset = unified.scrollView.contentInsets.top
        let shownOrigin = unified.scrollView.contentView.bounds.minY
        unifiedToolbar.isVisible = false
        settleUnified()
        let hiddenInset = unified.scrollView.contentInsets.top
        let hiddenOrigin = unified.scrollView.contentView.bounds.minY
        let hiddenSafeOffset = itemTopInWindow(20).map { unifiedWindow.contentLayoutRect.maxY - $0 }
        checks["unified-toolbar-visibility-test-has-real-inset-change-and-middle-anchor"] = middleSafeOffset.map { abs($0 + 13) < 1 } == true
            && shownOrigin > 0 && hiddenInset < shownInset
        checks["unified-toolbar-hiding-preserves-fixed-middle-card-relative-to-uncovered-top"] = middleSafeOffset != nil
            && hiddenSafeOffset.map { abs($0 - middleSafeOffset!) < 1 } == true
        unifiedToolbar.isVisible = true
        settleUnified()
        let reshownSafeOffset = itemTopInWindow(20).map { unifiedWindow.contentLayoutRect.maxY - $0 }
        checks["unified-toolbar-showing-preserves-fixed-middle-card-relative-to-uncovered-top"] = middleSafeOffset != nil
            && reshownSafeOffset.map { abs($0 - middleSafeOffset!) < 1 } == true
        FileHandle.standardError.write(Data("unified-grid-toolbar-toggle shownInset=\(shownInset) hiddenInset=\(hiddenInset) shownOrigin=\(shownOrigin) hiddenOrigin=\(hiddenOrigin) initialOffset=\(middleSafeOffset ?? .infinity) hiddenOffset=\(hiddenSafeOffset ?? .infinity) reshownOffset=\(reshownSafeOffset ?? .infinity)\n".utf8))

        // Exercise the production keyboard path, rather than restoring an
        // anchor or directly asking AppKit to reveal the expected target.
        FileHandle.standardError.write(Data("grid-stage unified-keyboard-start checks=\(checks.count)\n".utf8))
        var keyboardSelections: [(Set<WallpaperReference>, WallpaperReference?)] = []
        var keyboardInspections: [WallpaperReference] = [], keyboardPlays: [WallpaperReference] = []
        unified.onSelection = { refs, focus in keyboardSelections.append((refs, focus)); return UUID() }
        unified.onInspect = { keyboardInspections.append($0.reference) }
        unified.onPrimaryAction = { keyboardPlays.append($0.reference) }
        func keyboardReveal(_ name: String, target: Int, up: Bool, header: NSView? = nil) {
            let columns = 6
            let source = up ? target + columns : target - columns
            let state = WallpaperLibrarySelectionState(references: [values[source].reference], focusedReference: values[source].reference)
            unified.update(page: header == nil ? .videos : playlistPage, items: values, selection: state,
                preferredColumns: columns, permitsDragging: false, scrollAnchor: nil,
                header: header.map { ($0, { _ in 168 }) })
            settleUnified()
            let path = IndexPath(item: target, section: 0)
            let frame = unifiedFlow.layoutAttributesForItem(at: path)!.frame
            let inset = unified.scrollView.contentInsets.top
            let y = up ? frame.minY - inset * 0.5
                : frame.maxY - unified.scrollView.contentView.bounds.height - 20
            unifiedWindow.makeFirstResponder(unified.collection)
            unified.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            unified.scrollView.reflectScrolledClipView(unified.scrollView.contentView)
            settleUnified()
            let before = unified.collection.item(at: path)!.view
            let beforeRect = before.convert(before.bounds, to: nil)
            let layoutRect = unifiedWindow.contentLayoutRect
            checks["unified-keyboard-\(name)-starts-with-real-occlusion"] = inset > 0
                && frame.height < layoutRect.height && unifiedWindow.firstResponder === unified.collection
                && (up ? beforeRect.maxY > layoutRect.maxY + 1 : beforeRect.minY < layoutRect.minY - 1)
                && (!up || unified.scrollView.contentView.bounds.contains(frame))
            let priorSelection = keyboardSelections.count, priorInspect = keyboardInspections.count, priorPlay = keyboardPlays.count
            let text = String(UnicodeScalar(up ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)!)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: unifiedWindow.windowNumber,
                context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false,
                keyCode: up ? 126 : 125)!
            unifiedWindow.sendEvent(event)
            settleUnified()
            let after = unified.collection.item(at: path)!.view
            let afterRect = after.convert(after.bounds, to: nil)
            checks["unified-keyboard-\(name)-moves-to-exact-reference-once-without-play"] = unified.selection.references == [values[target].reference]
                && unified.selection.focusedReference == values[target].reference
                && keyboardSelections.count == priorSelection + 1 && keyboardSelections.last?.0 == [values[target].reference]
                && keyboardSelections.last?.1 == values[target].reference
                && keyboardInspections.count == priorInspect + 1 && keyboardInspections.last == values[target].reference
                && keyboardPlays.count == priorPlay
            checks["unified-keyboard-\(name)-reveals-whole-card-in-window-content-layout"] = afterRect.maxY <= layoutRect.maxY + 1
                && afterRect.minY >= layoutRect.minY - 1
            FileHandle.standardError.write(Data("unified-grid-keyboard \(name) before=\(beforeRect) after=\(afterRect) contentLayout=\(layoutRect) clipY=\(unified.scrollView.contentView.bounds.minY)\n".utf8))
        }
        keyboardReveal("up-middle", target: 24, up: true)
        keyboardReveal("down-middle", target: 36, up: false)
        keyboardReveal("up-first-row", target: 0, up: true)
        keyboardReveal("up-first-row-with-header", target: 0, up: true, header: NSView())
        FileHandle.standardError.write(Data("grid-stage real-header-start checks=\(checks.count)\n".utf8))
        WallpaperPlaylistHeaderChecks.run(grid: unified, window: unifiedWindow, values: values, settle: settleUnified, checks: &checks)
        FileHandle.standardError.write(Data("grid-stage checks-complete count=\(checks.count)\n".utf8))
        let output = try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys])
        print(String(data: output, encoding: .utf8)!)
    }
}

enum GridNativeDragProbe {
    static var started = false
    static var onBegin: ((NSDraggingSession, Set<IndexPath>) -> Void)?
}
