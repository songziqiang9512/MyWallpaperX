import AppKit

@MainActor private final class CardReflowWindow: NSWindow {
    // Controlled fixture input, not evidence about delivery of OS mouse events.
    var testPointer = NSPoint(x: -10_000, y: -10_000)
    override var mouseLocationOutsideOfEventStream: NSPoint { testPointer }
}

@MainActor private final class CardReflowToolbar: NSObject, NSToolbarDelegate {
    let titleID = NSToolbarItem.Identifier("card-reflow-title")
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [titleID, .flexibleSpace] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [titleID, .flexibleSpace] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = NSTextField(labelWithString: "Controlled reflow pointer")
        return item
    }
}

/// Whole production GridController and provider cards. Only source records,
/// thumbnail delivery and window pointer are fixture inputs. No exit/refresh is
/// sent during the 3→4→5 reflow; AppKit owns the collection frames and layout.
/// A separate cold responder-exit control runs before any mouseMoved input.
@MainActor func wallpaperGridCardReflowChecks(
    label: String, provider: WallpaperProvider, itemClass: NSCollectionViewItem.Type,
    reuseIdentifier: NSUserInterfaceItemIdentifier,
    resetColdTracking: () -> Void,
    makeCard: @escaping (NSCollectionView, IndexPath, WallpaperLibraryGridController.CellState, Bool) -> NSCollectionViewItem,
    updateState: @escaping (NSCollectionViewItem, WallpaperLibraryGridController.CellState, Bool) -> Void,
    isHovering: (NSCollectionViewItem) -> Bool,
    bar: (NSCollectionViewItem) -> NSView?
) -> [String: Bool] {
    let page: WallpaperLibraryPage = provider == .videoLibrary ? .videos : provider == .staticImageLibrary ? .images : .downloads
    let kind: WallpaperMediaKind = provider == .staticImageLibrary ? .image : .video
    let values = (0..<12).map { index -> WallpaperContentItem in
        let reference = WallpaperReference(provider: provider, sourceID: "reflow-\(index)")
        return WallpaperContentItem(reference: reference, providerReference: reference,
            locator: .init(mediaKind: kind), title: "Reflow \(index)", kind: kind,
            publishedAvailability: .available, capabilities: [.play, .inspect, .organize],
            metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
    }
    var playing: WallpaperReference?
    var selection = WallpaperLibrarySelectionState()
    let controller = WallpaperLibraryGridController { collection, path, content, state in
        makeCard(collection, path, state, playing == content.reference)
    }
    controller.loadViewIfNeeded()
    controller.collection.register(itemClass, forItemWithIdentifier: reuseIdentifier)
    controller.updateCell = { cell, content, state in updateState(cell, state, playing == content.reference) }
    let window = CardReflowWindow(contentRect: NSRect(x: 14_000, y: 14_000, width: 1150, height: 820),
        styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = false
    window.toolbarStyle = .unified
    let toolbarDelegate = CardReflowToolbar()
    let toolbar = NSToolbar(identifier: "card-reflow")
    toolbar.delegate = toolbarDelegate
    window.toolbar = toolbar
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 1150, height: 820))
    window.orderFrontRegardless()
    window.makeKey()
    NSApp.activate()
    defer { window.orderOut(nil); window.close(); withExtendedLifetime(toolbarDelegate) {} }
    func settle(_ duration: TimeInterval = 0.06) {
        controller.view.layoutSubtreeIfNeeded()
        controller.collection.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(duration)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) } while Date() < deadline
        controller.view.layoutSubtreeIfNeeded()
        controller.collection.layoutSubtreeIfNeeded()
    }
    func update(_ columns: Int) {
        controller.update(page: page, items: values, selection: selection, preferredColumns: columns,
            permitsDragging: false, scrollAnchor: nil)
        settle()
    }
    func cards() -> [NSCollectionViewItem] { controller.collection.visibleItems() }
    func visibleBars() -> Int {
        cards().filter { item in
            guard let value = bar(item) else { return false }
            return value.superview != nil && !value.isHidden && value.alphaValue > 0.99
        }.count
    }
    func first(_ index: Int) -> NSCollectionViewItem? {
        controller.collection.item(at: IndexPath(item: index, section: 0))
    }
    func toolbarPointer() {
        window.testPointer = NSPoint(x: 250, y: window.contentLayoutRect.maxY + 12)
    }
    func movedInside(_ item: NSCollectionViewItem) {
        let point = item.view.convert(NSPoint(x: item.view.bounds.midX, y: item.view.bounds.midY), to: nil)
        window.testPointer = point
        item.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!)
    }
    func diagnose(_ phase: String) {
        let rows = cards().compactMap { item -> [String: Any]? in
            guard let path = controller.collection.indexPath(for: item) else { return nil }
            let value = bar(item)
            return ["index": path.item, "frame": NSStringFromRect(item.view.frame),
                "pointerInside": item.view.isGridPointerInside, "hover": isHovering(item),
                "playing": playing == values[path.item].reference,
                "selected": selection.references.contains(values[path.item].reference),
                "focused": selection.focusedReference == values[path.item].reference,
                "barVisible": value.map { $0.superview != nil && !$0.isHidden && $0.alphaValue > 0.99 } ?? false]
        }
        let value: [String: Any] = ["phase": phase, "provider": label, "controlledPointer": NSStringFromPoint(window.testPointer),
            "nativeTopInset": controller.scrollView.contentInsets.top, "cards": rows]
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardError.write(data + Data("\n".utf8))
    }
    var checks: [String: Bool] = [:]
    func check(_ name: String, _ value: Bool) { checks[label + "." + name] = value }
    toolbarPointer()
    resetColdTracking()
    update(3)
    guard let initial = first(0) else { return [label + ".real-grid-mounts-provider": false] }
    check("native-toolbar-is-outside-all-cards", NSApp.isActive && controller.scrollView.contentInsets.top > 0
        && !cards().isEmpty && cards().allSatisfy { !$0.view.isGridPointerInside })
    check("cold-outside-layout-has-no-bars", visibleBars() == 0)
    // Cold admission is deliberately layout-only: there has been no mouseMoved
    // to activate the provider's existing process-wide event admission flag.
    window.testPointer = initial.view.convert(NSPoint(x: initial.view.bounds.midX, y: initial.view.bounds.midY), to: nil)
    initial.view.needsLayout = true
    settle(0.4)
    check("cold-inside-layout-reveals-current-card", initial.view.isGridPointerInside && isHovering(initial)
        && visibleBars() == 1)
    toolbarPointer()
    initial.mouseExited(with: NSEvent.enterExitEvent(with: .mouseExited, location: window.testPointer,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 2, trackingNumber: 0, userData: nil)!)
    // Capture the responder's result before AppKit can perform a later layout.
    // Only let the existing exit animation finish; do not refresh/layout here.
    let coldExitClearedSynchronously = !isHovering(initial)
    let coldExitDeadline = Date().addingTimeInterval(0.4)
    repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) } while Date() < coldExitDeadline
    diagnose("cold-responder-exit-before-first-move")
    check("cold-native-exit-clears-hover-before-any-move", coldExitClearedSynchronously
        && !isHovering(initial) && !initial.view.isGridPointerInside && visibleBars() == 0)
    window.testPointer = initial.view.convert(NSPoint(x: initial.view.bounds.midX, y: initial.view.bounds.midY), to: nil)
    initial.view.needsLayout = true
    settle(0.4)
    check("cold-layout-can-reenter-after-native-exit", initial.view.isGridPointerInside
        && isHovering(initial) && visibleBars() == 1)
    let frameAtThree = initial.view.frame
    toolbarPointer()
    update(4)
    settle(0.4)
    check("three-to-four-uses-native-new-frame", first(0) === initial && initial.view.frame.width < frameAtThree.width)
    check("cold-reflow-clears-hover-without-exit", !isHovering(initial) && visibleBars() == 0
        && cards().allSatisfy { !$0.view.isGridPointerInside })
    // Establish three actual responder hover inputs. Their absent exit events
    // model the reported reflow boundary; no stored hover/bar state is injected.
    let warm = (0..<3).compactMap(first)
    var warmInputsPassed = warm.count == 3
    for item in warm { movedInside(item); warmInputsPassed = warmInputsPassed && isHovering(item) }
    check("warm-inputs-established-three-real-hovers", warmInputsPassed)
    let framesAtFour = warm.map { $0.view.frame }
    toolbarPointer()
    update(5)
    settle(0.4)
    diagnose("after-3-4-5-no-exit")
    check("four-to-five-changes-native-card-frames", zip(warm, framesAtFour).allSatisfy { $0.0.view.frame.width < $0.1.width })
    check("warm-reflow-clears-all-nonplaying-bars", cards().allSatisfy { !isHovering($0) && !$0.view.isGridPointerInside }
        && visibleBars() == 0)
    // Existing scroll-phase protocol is a separate control, after the reflow
    // assertions. It must still clear hover even on the unpatched source.
    for case let item as WallpaperGridHoverItem in cards() { item.refreshGridHover(isScrolling: true) }
    for case let item as WallpaperGridHoverItem in cards() { item.refreshGridHover(isScrolling: false) }
    settle(0.4)
    check("scroll-refresh-still-clears-outside-hover", visibleBars() == 0 && cards().allSatisfy { !isHovering($0) })
    selection.references = [values[0].reference]
    selection.focusedReference = values[0].reference
    update(5)
    check("selection-and-focus-do-not-persist-bars", visibleBars() == 0)
    playing = values[1].reference
    update(5)
    diagnose("one-playing-selected-other")
    check("one-playing-keeps-exactly-one-bar", visibleBars() == 1
        && first(1).flatMap(bar).map { !$0.isHidden && $0.superview != nil } == true)
    selection.isSelecting = true
    update(5)
    check("multiselect-still-hides-playing-bar", visibleBars() == 0)
    selection.isSelecting = false
    update(5)
    check("leaving-multiselect-restores-only-playing-bar", visibleBars() == 1)
    playing = nil
    update(5)
    check("stopping-last-playing-card-hides-all-bars", visibleBars() == 0)
    initial.prepareForReuse()
    check("reuse-still-clears-hover-and-bar", !isHovering(initial)
        && bar(initial).map { $0.isHidden || $0.superview == nil } != false)
    return checks
}
