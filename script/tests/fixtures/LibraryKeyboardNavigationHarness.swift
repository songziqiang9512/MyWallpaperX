import AppKit

private final class KeyboardCell: NSCollectionViewItem {
    static let reuse = NSUserInterfaceItemIdentifier("keyboard-cell")
    override func loadView() { view = WallpaperCardInteractionView() }
}

@main enum LibraryKeyboardNavigationHarness {
    @MainActor static func spin(_ duration: TimeInterval = 0.06) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
    @MainActor static func event(_ code: UInt16, in window: NSWindow, text: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }
    @MainActor static func makeGrid() -> WallpaperLibraryGridController {
        let grid = WallpaperLibraryGridController { collection, path, _, _ in
            collection.makeItem(withIdentifier: KeyboardCell.reuse, for: path)
        }
        grid.loadViewIfNeeded()
        grid.collection.register(KeyboardCell.self, forItemWithIdentifier: KeyboardCell.reuse)
        return grid
    }
    @MainActor static func main() throws {
        initializeNativeAppHarness()
        var checks: [String: Bool] = [:]
        // Opaque provider identities share their numeric component deliberately.
        // The accepted display order is the navigation input; Query owns sorting.
        let values = (0..<40).map { index -> WallpaperContentItem in
            let ref = WallpaperReference(provider: WallpaperProvider.allCases[index % 4], sourceID: String(index / 4))
            return .init(reference: ref, providerReference: ref, locator: .init(mediaKind: .video),
                title: "Item \(index)", kind: .video, publishedAvailability: .available,
                capabilities: [.inspect, .play], metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        let original = values
        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 900, height: 550),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 550))
        window.contentView = root
        let grid = makeGrid()
        grid.view.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        root.addSubview(grid.view)
        let search = NSSearchField(frame: NSRect(x: 20, y: 510, width: 220, height: 24))
        root.addSubview(search)
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        var selections: [(Set<WallpaperReference>, WallpaperReference?)] = []
        var inspections: [WallpaperReference] = [], plays: [WallpaperReference] = [], previews: [WallpaperReference] = []
        grid.onSelection = { refs, focus in selections.append((refs, focus)); return UUID() }
        grid.onInspect = { inspections.append($0.reference) }
        grid.onPrimaryAction = { plays.append($0.reference) }
        grid.onQuickLook = { previews.append($0.reference) }
        func update(_ state: WallpaperLibrarySelectionState, _ items: [WallpaperContentItem] = values, zoom: Int = 5) {
            grid.update(page: .downloads, items: items, selection: state, preferredColumns: zoom,
                permitsDragging: false, scrollAnchor: nil)
        }
        var matrix = true, writes = true, inputs = true, steps = 0
        for width in [CGFloat(100), 480, 900] {
            window.setContentSize(NSSize(width: width, height: 550))
            grid.view.frame.size = NSSize(width: width, height: 500)
            for zoom in [3, 4, 5, 6] {
                update(.init(), zoom: zoom)
                root.layoutSubtreeIfNeeded(); grid.view.layoutSubtreeIfNeeded()
                let columns = WallpaperLibraryGridMetrics(clipWidth: grid.scrollView.contentView.bounds.width, preferredColumns: zoom).columns
                let starts: [Int?] = [nil, 0, 1, min(columns, values.count - 1), 20, values.count - 1]
                for start in starts {
                    for code in [UInt16(123), 124, 125, 126] {
                        var state = WallpaperLibrarySelectionState()
                        if let start { state.references = [values[start].reference]; state.focusedReference = values[start].reference }
                        update(state, zoom: zoom)
                        let priorWrites = selections.count, priorInspect = inspections.count, priorPlays = plays.count
                        let delta = code == 123 ? -1 : code == 124 ? 1 : code == 125 ? columns : -columns
                        let target = start.map { min(values.count - 1, max(0, $0 + delta)) } ?? 0
                        grid.collection.keyDown(with: event(code, in: window))
                        matrix = matrix && grid.selection.references == [values[target].reference]
                            && grid.selection.focusedReference == values[target].reference
                        writes = writes && selections.count == priorWrites + 1 && selections.last?.0 == [values[target].reference]
                            && inspections.count == priorInspect + 1 && inspections.last == values[target].reference && plays.count == priorPlays
                        inputs = inputs && values == original && grid.items == values
                        steps += 1
                    }
                }
            }
        }
        checks["allFourArrowsUseAcceptedDisplayOrderAndActualVisualColumnsAtBounds"] = matrix && steps == 288
        checks["eachHandledArrowEmitsOneCanonicalSelectionAndInspectorReceiptWithoutPlaying"] = writes
        checks["navigationNeverSortsOrMutatesAcceptedSourceValues"] = inputs
        var absent = WallpaperLibrarySelectionState()
        absent.focusedReference = .init(provider: .videoLibrary, sourceID: "not-in-this-projection")
        update(absent)
        grid.collection.keyDown(with: event(124, in: window))
        checks["missingFocusStartsAtFirstActualVisibleValue"] = grid.selection.focusedReference == values[0].reference
        let beforeEmpty = selections.count, inspectEmpty = inspections.count
        update(.init(), [])
        for code in [UInt16(123), 124, 125, 126] { grid.collection.keyDown(with: event(code, in: window)) }
        checks["emptyOrNoMatchProjectionNeverWritesSelectionOrInspector"] = grid.selection.references.isEmpty
            && selections.count == beforeEmpty && inspections.count == inspectEmpty
        var single = WallpaperLibrarySelectionState()
        single.references = [values[1].reference]; single.focusedReference = values[1].reference
        update(single)
        window.makeFirstResponder(search)
        search.stringValue = "needle"
        let beforeSearch = grid.selection, writesBeforeSearch = selections.count
        window.sendEvent(event(123, in: window))
        checks["nativeSearchFieldConsumesArrowWithoutGridSelectionWrite"] = window.firstResponder is NSTextView
            && grid.selection == beforeSearch && selections.count == writesBeforeSearch
        window.makeFirstResponder(grid.collection)
        window.sendEvent(event(124, in: window))
        checks["returningNativeFirstResponderToGridResumesNavigation"] = grid.selection.focusedReference == values[2].reference
        checks["equalNumericIDsFromDifferentProvidersNavigateAsDistinctCards"] = values[1].reference.sourceID == values[2].reference.sourceID
            && values[1].reference != values[2].reference && grid.selection.references == [values[2].reference]
        let beforeUnsupported = grid.selection, beforeUnsupportedWrites = selections.count
        let handledUnsupported = grid.collection.onKey?(event(7, in: window, text: "x"))
        let handledModified = grid.collection.onKey?(event(124, in: window, flags: .option))
        checks["unsupportedAndModifiedProductKeysDoNotClaimOrWriteSelection"] = handledUnsupported == false && handledModified == false
            && grid.selection == beforeUnsupported && selections.count == beforeUnsupportedWrites
        var multi = WallpaperLibrarySelectionState()
        multi.isSelecting = true; multi.references = [values[1].reference, values[4].reference]; multi.focusedReference = values[4].reference
        update(multi)
        let beforeMultiInspect = inspections.count, beforeMultiPlay = plays.count
        grid.collection.keyDown(with: event(124, in: window))
        let afterRight = grid.selection.focusedReference
        grid.collection.keyDown(with: event(125, in: window))
        let columns = WallpaperLibraryGridMetrics(clipWidth: grid.scrollView.contentView.bounds.width, preferredColumns: 5).columns
        checks["explicitMultiselectArrowsMoveFocusWithoutChangingGroupOrOpeningInspector"] = afterRight == values[5].reference
            && grid.selection.focusedReference == values[min(values.count - 1, 5 + columns)].reference
            && grid.selection.references == multi.references && inspections.count == beforeMultiInspect && plays.count == beforeMultiPlay
        grid.collection.keyDown(with: event(36, in: window))
        checks["explicitMultiselectReturnNeverStartsBatchPlayback"] = plays.count == beforeMultiPlay
        update(single)
        grid.collection.keyDown(with: event(36, in: window)); grid.collection.keyDown(with: event(49, in: window))
        checks["returnAndSpaceUseCurrentCanonicalProviderIdentity"] = plays.last == values[1].reference && previews.last == values[1].reference

        var retiredEmissions = 0
        weak var weakGrid: WallpaperLibraryGridController?
        weak var weakView: NSView?
        weak var weakWindow: NSWindow?
        autoreleasepool {
            var temporaryWindow: NSWindow? = NSWindow(contentRect: NSRect(x: 15000, y: 15000, width: 500, height: 400),
                styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
            temporaryWindow!.isReleasedWhenClosed = false
            weakWindow = temporaryWindow
            var temporary: WallpaperLibraryGridController? = makeGrid()
            weakGrid = temporary; weakView = temporary?.view
            temporary!.view.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
            temporaryWindow!.contentView!.addSubview(temporary!.view)
            temporary!.onViewport = { _, _ in retiredEmissions += 1 }
            temporary!.update(page: .images, items: values, selection: .init(), preferredColumns: 5, permitsDragging: false, scrollAnchor: nil)
            temporaryWindow!.orderFrontRegardless(); spin()
            temporary!.view.removeFromSuperview()
            temporary = nil
            temporaryWindow!.orderOut(nil); temporaryWindow!.close(); temporaryWindow = nil
        }
        spin()
        checks["detachedNativeGridAndRootAreNotRetainedByViewportOrWindowObservers"] = weakGrid == nil && weakView == nil
        checks["retiredNativeWindowIsNotRetainedByDetachedGridLease"] = weakWindow == nil
        let countAfterRetirement = retiredEmissions
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        spin()
        checks["lateWindowEventsCannotReviveRetiredGridDemand"] = weakGrid == nil && retiredEmissions == countAfterRetirement
        print(String(decoding: try JSONEncoder().encode(checks), as: UTF8.self))
    }
}
