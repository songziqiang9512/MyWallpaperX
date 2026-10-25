import AppKit

/// The real native source callback always reaches the production owner before
/// its session/selection is observed by the continuous and legacy checks.
@MainActor final class GridNativeDragDelegate: NSObject, NSCollectionViewDelegate {
    let owner: WallpaperLibraryGridController
    init(_ owner: WallpaperLibraryGridController) { self.owner = owner }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || owner.responds(to: selector)
    }
    override func forwardingTarget(for selector: Selector!) -> Any? { owner }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        willBeginAt point: NSPoint, forItemsAt paths: Set<IndexPath>) {
        (owner as NSCollectionViewDelegate).collectionView?(collectionView, draggingSession: session,
            willBeginAt: point, forItemsAt: paths)
        GridNativeDragProbe.started = true
        GridNativeDragProbe.onBegin?(session, paths)
    }
}

private final class SelectionDragCard: NSCollectionViewItem {
    private let image = NSImageView()
    override func loadView() {
        view = WallpaperCardInteractionView()
        image.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        view.addSubview(image)
    }
    override func viewDidLayout() { super.viewDidLayout(); image.frame = view.bounds }
}

/// Constructed NSEvents enter the real mounted window/card/native drag loop.
/// This verifies AppKit selection and pasteboard callbacks, not OS pointer input.
@MainActor enum WallpaperLibraryGridDragChecks {
    static func run(values: [WallpaperContentItem]) -> [String: Bool] {
        let controller = WallpaperLibraryGridController { collection, path, _, _ in
            collection.makeItem(withIdentifier: .init("selection-drag-card"), for: path)
        }
        controller.loadViewIfNeeded()
        let dragDelegate = GridNativeDragDelegate(controller)
        controller.collection.delegate = dragDelegate
        defer { withExtendedLifetime(dragDelegate) {} }
        controller.collection.register(SelectionDragCard.self, forItemWithIdentifier: .init("selection-drag-card"))
        var inspections = 0, plays = 0, selectionEvents: [[String]] = []
        controller.onSelection = { refs, _ in selectionEvents.append(refs.map(\.storageKey).sorted()); return UUID() }
        controller.onInspect = { _ in inspections += 1 }
        controller.onPrimaryAction = { _ in plays += 1 }
        let window = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 1000, height: 650),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1000, height: 650))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let deadline = Date().addingTimeInterval(5)
        while !NSApp.isActive || !window.isKeyWindow {
            precondition(Date() < deadline, "native continuous drag window never became active")
            WallpaperLibraryGridHarness.pump()
        }
        defer { GridNativeDragProbe.onBegin = nil; window.orderOut(nil); window.close() }
        let collection = controller.collection
        func update(_ state: WallpaperLibrarySelectionState, page: WallpaperLibraryPage = .videos) {
            controller.update(page: page, items: values, selection: state, preferredColumns: 5,
                permitsDragging: true, scrollAnchor: nil)
            window.contentView?.layoutSubtreeIfNeeded()
            collection.layoutSubtreeIfNeeded()
            WallpaperLibraryGridHarness.pump()
        }
        update(WallpaperLibrarySelectionState())
        precondition(collection.indexPathsForVisibleItems().count == values.count,
            "continuous drag requires all four real native cards")
        struct Receipt {
            let paths: Set<IndexPath>
            let nativeSelection: Set<IndexPath>
            let references: Set<WallpaperReference>
            let payload: [String]
        }
        var receipts: [Receipt] = []
        var onBegin: (() -> Void)?
        GridNativeDragProbe.onBegin = { session, paths in
            receipts.append(Receipt(paths: paths, nativeSelection: collection.selectionIndexPaths,
                references: controller.selection.references,
                payload: session.draggingPasteboard.pasteboardItems?.compactMap {
                    $0.string(forType: WallpaperLibraryGridController.referencesType)
                } ?? []))
            onBegin?()
        }
        func event(_ type: NSEvent.EventType, point: NSPoint, time: TimeInterval,
                   flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 31, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1)!
        }
        func input(_ index: Int, drag: Bool, flags: NSEvent.ModifierFlags = []) {
            let card = collection.item(at: IndexPath(item: index, section: 0))!.view
            let start = card.convert(NSPoint(x: card.bounds.midX, y: card.bounds.midY), to: nil)
            let end = drag ? NSPoint(x: start.x + 70, y: start.y + 25) : start
            let time = ProcessInfo.processInfo.systemUptime
            NSApp.postEvent(event(.leftMouseUp, point: end, time: time + 0.04, flags: flags), atStart: true)
            if drag { NSApp.postEvent(event(.leftMouseDragged, point: end, time: time + 0.02, flags: flags), atStart: true) }
            window.sendEvent(event(.leftMouseDown, point: start, time: time, flags: flags))
            WallpaperLibraryGridHarness.pump()
        }
        var checks: [String: Bool] = [:]
        func checkDrag(_ name: String, index: Int, flags: NSEvent.ModifierFlags = []) {
            let count = receipts.count, beforeInspect = inspections, beforePlay = plays
            input(index, drag: true, flags: flags)
            let path = IndexPath(item: index, section: 0), ref = values[index].reference
            checks[name + "-begins-a-real-native-session"] = receipts.count == count + 1
            checks[name + "-selection-and-payload-are-only-the-dragged-reference"] = receipts.count == count + 1
                && receipts.last?.paths == [path] && receipts.last?.nativeSelection == [path]
                && receipts.last?.references == [ref] && receipts.last?.payload == [ref.storageKey]
                && controller.selection.references == [ref] && collection.selectionIndexPaths == [path]
            checks[name + "-does-not-inspect-or-play"] = inspections == beforeInspect && plays == beforePlay
            FileHandle.standardError.write(Data("continuous-drag \(name) events=\(selectionEvents) native=\(collection.selectionIndexPaths) owner=\(controller.selection.references.map(\.storageKey)) payload=\(receipts.last?.payload ?? [])\n".utf8))
        }
        checkDrag("empty-to-A", index: 0)
        checkDrag("A-then-unselected-B", index: 1)
        checkDrag("selected-B-again", index: 1)
        checkDrag("command-drag-C-is-still-ordinary-mode", index: 2, flags: .command)
        checkDrag("shift-drag-D-is-still-ordinary-mode", index: 3, flags: .shift)
        func stage(_ name: String) { FileHandle.standardError.write(Data("continuous-drag-tail \(name)\n".utf8)) }
        stage("before-ordinary-click")
        let beforeClick = inspections, beforeClickSelection = selectionEvents.count
        input(0, drag: false)
        stage("after-ordinary-click")
        checks["ordinary-click-still-selects-and-inspects-once"] = controller.selection.references == [values[0].reference]
            && inspections == beforeClick + 1 && plays == 0
        checks["one-ordinary-click-has-one-selection-receipt-across-native-mousedown-and-completion"] = selectionEvents.count == beforeClickSelection + 1
        input(0, drag: false)
        checks["a-new-click-on-the-selected-card-still-requests-a-new-receipt-and-inspects-once"] = selectionEvents.count == beforeClickSelection + 2
            && inspections == beforeClick + 2 && plays == 0
        let beforeRejection = controller.selection
        controller.onSelection = { _, _ in nil }
        input(0, drag: false)
        checks["selected-card-cannot-reuse-the-previous-click-receipt-after-current-admission-rejects"] = controller.selection == beforeRejection
            && selectionEvents.count == beforeClickSelection + 2 && inspections == beforeClick + 2 && plays == 0
        controller.onSelection = { refs, _ in selectionEvents.append(refs.map(\.storageKey).sorted()); return UUID() }
        var multi = WallpaperLibrarySelectionState()
        multi.isSelecting = true; multi.references = [values[0].reference, values[1].reference]
        stage("before-explicit-mode-update")
        update(multi)
        stage("after-explicit-mode-update")
        let beforeMultiInspect = inspections, beforeMultiSessions = receipts.count
        input(2, drag: false)
        stage("after-first-explicit-toggle")
        checks["explicit-selection-mode-still-toggles-without-opening-an-inspector"] = controller.selection.references == Set(values.prefix(3).map(\.reference))
            && controller.selection.isSelecting && inspections == beforeMultiInspect && receipts.count == beforeMultiSessions
            && controller.collectionView(collection, pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)) == nil
        input(2, drag: false)
        stage("after-second-explicit-toggle")
        checks["explicit-second-toggle-retains-the-other-selected-targets"] = controller.selection.references == [values[0].reference, values[1].reference]
            && inspections == beforeMultiInspect && plays == 0
        update(WallpaperLibrarySelectionState())
        stage("after-return-to-ordinary-mode")
        let foreign = WallpaperLibrarySelectionState(references: [values[3].reference], focusedReference: values[3].reference)
        onBegin = {
            stage("foreign-willBegin-enter")
            controller.update(page: .images, items: values, selection: foreign, preferredColumns: 5,
                permitsDragging: true, scrollAnchor: nil)
            window.contentView?.layoutSubtreeIfNeeded()
            collection.layoutSubtreeIfNeeded()
            // Do not pump events inside willBegin: the queued mouse-up belongs
            // to the native drag tracker that takes control after this returns.
            stage("foreign-willBegin-return")
        }
        let beforeForeign = inspections
        stage("before-foreign-page-drag")
        input(0, drag: true)
        stage("after-foreign-page-drag")
        checks["old-native-drag-completion-does-not-overwrite-a-new-page-session"] = controller.selection == foreign
            && inspections == beforeForeign && plays == 0
        return checks
    }
}
