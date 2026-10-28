import AppKit
import QuartzCore

// Native batch execution remains intact; only its completed delivery and the
// existing Reduce Motion preference are controlled in the compiled test copy.
@MainActor enum WallpaperLibraryGridAnimationProbe {
    static var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    static var holding = false
    static var arrivals = 0
    private(set) static var inFlight = 0
    static var pending: [() -> Void] = []
    static func wrap(_ completion: @escaping (Bool) -> Void) -> (Bool) -> Void {
        inFlight += 1
        return { finished in
            arrivals += 1
            let deliver = { completion(finished); inFlight -= 1 }
            if holding { pending.append(deliver) }
            else { deliver() }
        }
    }
    static func release() {
        holding = false
        let callbacks = pending
        pending = []
        callbacks.forEach { $0() }
    }
}

private final class GridAnimationCell: NSCollectionViewItem {
    let label = NSTextField(labelWithString: "")
    override func loadView() {
        view = WallpaperCardInteractionView()
        view.wantsLayer = true
        view.addSubview(label)
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        label.frame = view.bounds.insetBy(dx: 12, dy: 12)
    }
}
private final class GridAnimationUnavailableCell: NSCollectionViewItem {
    override func loadView() { view = WallpaperCardInteractionView() }
}

@MainActor enum WallpaperLibraryGridAnimationChecks {
    static func settleNativeChanges(_ grid: WallpaperLibraryGridController) {
        CATransaction.flush()
        let deadline = Date().addingTimeInterval(3)
        while WallpaperLibraryGridAnimationProbe.inFlight > 0, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        precondition(WallpaperLibraryGridAnimationProbe.inFlight == 0, "native collection batch did not finish")
        grid.view.layoutSubtreeIfNeeded(); grid.collection.layoutSubtreeIfNeeded()
    }
    static func run(values: [WallpaperContentItem]) -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let systemMotion = WallpaperLibraryGridAnimationProbe.reduceMotion
        defer { WallpaperLibraryGridAnimationProbe.reduceMotion = systemMotion }
        WallpaperLibraryGridAnimationProbe.reduceMotion = false
        let initial = Array(values.prefix(9)), reuse = NSUserInterfaceItemIdentifier("grid-reflow-proof")
        let unavailable = NSUserInterfaceItemIdentifier("grid-reflow-unavailable")
        var leases: [ObjectIdentifier: WallpaperReference] = [:]
        var demand: [WallpaperReference] = []
        let grid = WallpaperLibraryGridController { collection, path, item, _ in
            if item.publishedAvailability == .unavailable { return collection.makeItem(withIdentifier: unavailable, for: path) }
            let cell = collection.makeItem(withIdentifier: reuse, for: path) as! GridAnimationCell
            cell.label.stringValue = item.title
            return cell
        }
        grid.loadViewIfNeeded()
        grid.collection.register(GridAnimationCell.self, forItemWithIdentifier: reuse)
        grid.collection.register(GridAnimationUnavailableCell.self, forItemWithIdentifier: unavailable)
        grid.needsCellReplacement = { cell, item in (cell is GridAnimationUnavailableCell) != (item.publishedAvailability == .unavailable) }
        grid.updateCell = { cell, item, _ in (cell as? GridAnimationCell)?.label.stringValue = item.title }
        grid.setCellVisible = { cell, visible in
            if visible, let ref = cell.representedObject as? WallpaperReference { leases[ObjectIdentifier(cell)] = ref }
            else { leases.removeValue(forKey: ObjectIdentifier(cell)) }
        }
        grid.onViewport = { visible, nearby in demand = (visible + nearby).map(\.reference) }
        let window = NSWindow(contentViewController: grid)
        window.isReleasedWhenClosed = false
        window.setContentSize(.init(width: 900, height: 700))
        window.contentView?.wantsLayer = true
        window.makeKeyAndOrderFront(nil)
        defer { WallpaperLibraryGridAnimationProbe.release(); window.orderOut(nil); window.close() }
        func settle(_ seconds: TimeInterval = 0.3) {
            CATransaction.flush()
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
            grid.collection.layoutSubtreeIfNeeded()
        }
        var selection = WallpaperLibrarySelectionState(references: [initial[2].reference], focusedReference: initial[2].reference)
        selection.isSelecting = true
        func publish(_ items: [WallpaperContentItem], page: WallpaperLibraryPage = .recent) {
            grid.update(page: page, items: items, selection: selection, preferredColumns: 5,
                permitsDragging: true, scrollAnchor: nil)
        }
        func cells() -> [WallpaperReference: NSCollectionViewItem] {
            Dictionary(uniqueKeysWithValues: grid.collection.visibleItems().compactMap { cell in
                (cell.representedObject as? WallpaperReference).map { ($0, cell) }
            })
        }
        func frames(_ cells: [WallpaperReference: NSCollectionViewItem]) -> [WallpaperReference: NSRect] {
            cells.mapValues { cell in
                if let frame = cell.view.layer?.presentation()?.frame { return grid.collection.convert(frame, from: cell.view.superview) }
                return grid.collection.convert(cell.view.bounds, from: cell.view)
            }
        }
        func identitiesMatch(_ expected: [WallpaperContentItem]) -> Bool {
            grid.collection.numberOfItems(inSection: 0) == expected.count && grid.items == expected
                && grid.collection.visibleItems().allSatisfy { cell in
                    guard let path = grid.collection.indexPath(for: cell), expected.indices.contains(path.item) else { return false }
                    return cell.representedObject as? WallpaperReference == expected[path.item].reference
                }
        }
        publish(initial); settle(0.05)
        let mounted = cells(), startFrames = frames(mounted), initialArrivals = WallpaperLibraryGridAnimationProbe.arrivals
        checks["reflow-first-publication-does-not-animate-or-create-another-state-owner"] = mounted.count == initial.count && initialArrivals == 0
        let reordered = [initial.last!] + Array(initial.dropLast())
        WallpaperLibraryGridAnimationProbe.holding = true
        publish(reordered)
        let updated = reordered.map { item in
            WallpaperContentItem(reference: item.reference, providerReference: item.providerReference, locator: item.locator,
                title: "切换中 " + item.title, kind: item.kind, publishedAvailability: item.publishedAvailability,
                capabilities: item.capabilities, metadata: item.metadata, acquisition: item.acquisition, update: item.update, aliases: item.aliases)
        }
        publish(updated)
        checks["reflow-pending-action-feedback-is-immediate-while-native-move-is-running"] = cells().count == mounted.count && cells().allSatisfy { ref, cell in
            cell === mounted[ref] && (cell as? GridAnimationCell)?.label.stringValue.hasPrefix("切换中 ") == true
        }
        var intermediate = false
        CATransaction.flush()
        for _ in 0..<12 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            for (ref, cell) in mounted {
                guard let before = startFrames[ref], let current = frames([ref: cell])[ref],
                      let path = grid.collection.indexPath(for: cell),
                      let final = grid.collection.collectionViewLayout?.layoutAttributesForItem(at: path)?.frame else { continue }
                let dx = final.midX - before.midX, dy = final.midY - before.midY
                let distance = dx * dx + dy * dy
                let progress = distance > 1 ? ((current.midX - before.midX) * dx + (current.midY - before.midY) * dy) / distance : 0
                if progress > 0.01, progress < 0.99 { intermediate = true }
            }
        }
        checks["reflow-recent-success-has-a-real-intermediate-native-frame"] = intermediate
        settle(0.2)
        checks["reflow-native-completion-can-be-held-after-appkit-finishes"] = WallpaperLibraryGridAnimationProbe.pending.count == 1
        grid.collection.cancelSelectionTracking = false
        let panFrame = grid.collection.collectionViewLayout!.layoutAttributesForItem(at: .init(item: 0, section: 0))!.frame
        grid.collection.onBoxSelection?(.init(item: 0, section: 0), panFrame, false)
        selection = .init(); selection.isSelecting = true
        publish(Array(updated.dropFirst()))
        grid.collection.onBoxSelection?(.init(item: 0, section: 0), panFrame, true)
        checks["reflow-foreign-session-retires-live-pan-before-queued-topology-finishes"] = grid.collection.cancelSelectionTracking
            && grid.selection == selection && WallpaperLibraryGridAnimationProbe.pending.count == 1
        publish(updated) // Undo before completion must supersede the queued deletion.
        WallpaperLibraryGridAnimationProbe.release(); settle()
        checks["reflow-delete-undo-during-move-keeps-latest-model-and-surviving-cells"] = identitiesMatch(updated)
            && cells().allSatisfy { $0.value === mounted[$0.key] }
            && grid.selection.references == selection.references
        let reverse = Array(updated.reversed())
        let replaceReference = updated[0].reference
        let replacement = reverse.map { item in
            WallpaperContentItem(reference: item.reference, providerReference: item.providerReference, locator: item.locator,
                title: item.title, kind: item.kind, publishedAvailability: item.reference == replaceReference ? .unavailable : item.publishedAvailability,
                capabilities: item.capabilities, metadata: item.metadata, acquisition: item.acquisition, update: item.update, aliases: item.aliases)
        }
        WallpaperLibraryGridAnimationProbe.holding = true
        publish(reverse); settle()
        publish(replacement)
        checks["reflow-real-cell-replacement-does-not-nest-reload-inside-running-batch"] = cells()[replaceReference] is GridAnimationCell
            && WallpaperLibraryGridAnimationProbe.pending.count == 1
        WallpaperLibraryGridAnimationProbe.release(); settle()
        checks["reflow-queued-real-cell-replacement-installs-the-current-provider-view"] = identitiesMatch(replacement)
            && cells()[replaceReference] is GridAnimationUnavailableCell
        publish(updated); settle()
        let beforeMutation = cells()
        let inserted = values[9]
        let changed = Array(updated.dropFirst(2)) + [inserted]
        WallpaperLibraryGridAnimationProbe.holding = true
        publish(changed); settle()
        checks["reflow-add-remove-uses-native-batch-without-reloading-survivors"] = identitiesMatch(changed)
            && changed.dropLast().allSatisfy { cells()[$0.reference] === beforeMutation[$0.reference] }
        let final = Array(values[20..<24])
        selection = .init(references: [final[1].reference], focusedReference: final[1].reference)
        let staleActivation = (grid.collection.item(at: .init(item: 0, section: 0))!.view as! WallpaperCardInteractionView).onAccessibilityActivate!
        publish([], page: .favorites)
        checks["reflow-queued-foreign-page-immediately-revokes-old-input-and-thumbnail-lease"] = !staleActivation()
            && !grid.select([changed[0].reference], focus: changed[0].reference)
            && grid.collectionView(grid.collection, pasteboardWriterForItemAt: .init(item: 0, section: 0)) == nil
            && leases.isEmpty && demand.isEmpty
        publish(final, page: .images)
        WallpaperLibraryGridAnimationProbe.release(); settle()
        checks["reflow-old-completion-never-overwrites-latest-page-selection-count-or-leases"] = identitiesMatch(final)
            && grid.collection.selectionIndexPaths == [IndexPath(item: 1, section: 0)]
            && Set(leases.values).isSubset(of: Set(final.map(\.reference)))
            && Set(demand).isSubset(of: Set(final.map(\.reference)))
        WallpaperLibraryGridAnimationProbe.reduceMotion = true
        grid.update(page: .images, items: Array(final.reversed()), selection: selection, preferredColumns: 5,
            permitsDragging: true, scrollAnchor: nil)
        settle(0.04)
        checks["reflow-reduce-motion-settles-native-order-without-delayed-callback"] = identitiesMatch(Array(final.reversed()))
            && WallpaperLibraryGridAnimationProbe.pending.isEmpty
        grid.update(page: .images, items: [], selection: .init(), preferredColumns: 5, permitsDragging: true, scrollAnchor: nil)
        settle(0.04)
        checks["reflow-empty-deletion-retires-all-native-cells-and-thumbnail-demand"] = identitiesMatch([])
            && leases.isEmpty && demand.isEmpty
        return checks
    }
}
