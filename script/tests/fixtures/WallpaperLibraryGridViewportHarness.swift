import AppKit

private final class ViewportCell: NSCollectionViewItem {
    static let reuse = NSUserInterfaceItemIdentifier("viewport-cell")
    var visible = false
    override func loadView() { view = WallpaperCardInteractionView() }
}

private final class GridViewportToolbarProbe: NSObject, NSToolbarDelegate {
    private let itemID = NSToolbarItem.Identifier("GridViewportSearch")
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [itemID] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [itemID] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Search"
        item.view = NSSearchField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        return item
    }
}

@main enum WallpaperLibraryGridViewportHarness {
    static func spin(_ seconds: TimeInterval = 0.06) {
        let deadline = Date().addingTimeInterval(seconds)
        repeat { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) } while Date() < deadline
    }
    static func wait(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { spin(0.01) }
        return condition()
    }
    static func main() throws {
        initializeNativeAppHarness()
        var checks: [String: Bool] = [:]
        let items = (0..<1_000).map { index -> WallpaperContentItem in
            let reference = WallpaperReference(provider: WallpaperProvider.allCases[index % WallpaperProvider.allCases.count], sourceID: "\(index)")
            return .init(reference: reference, providerReference: reference, locator: .init(mediaKind: .video),
                title: "\(index)", kind: .video, publishedAvailability: .available, capabilities: [.inspect, .play],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        var firstFactoryPixels: (Int, CGFloat)?
        let controller = WallpaperLibraryGridController { collection, path, _, state in
            if firstFactoryPixels == nil {
                let side = WallpaperLibraryGridMetrics(clipWidth: collection.enclosingScrollView!.contentView.bounds.width, preferredColumns: 5).coverSide
                firstFactoryPixels = (state.thumbnailRequest.width, collection.convertToBacking(NSSize(width: side, height: side)).width)
            }
            return collection.makeItem(withIdentifier: ViewportCell.reuse, for: path)
        }
        controller.loadViewIfNeeded()
        controller.collection.register(ViewportCell.self, forItemWithIdentifier: ViewportCell.reuse)
        controller.setCellVisible = { cell, state in (cell as? ViewportCell)?.visible = state != nil }
        var emissions: [([WallpaperReference], [WallpaperReference])] = []
        var emittedPixels: [Int] = [], configuredPixels: [Int] = []
        controller.updateCell = { _, _, state in configuredPixels.append(state.thumbnailRequest.width) }
        controller.onViewport = { visible, nearby, request in
            emittedPixels.append(request.width); emissions.append((visible.map(\.providerReference), nearby.map(\.providerReference)))
        }
        func update(page: WallpaperLibraryPage = .images) {
            controller.update(page: page, items: items, selection: controller.selection, preferredColumns: 5,
                permitsDragging: false, scrollAnchor: nil)
        }
        update(); spin()
        checks["unattached-grid-never-acquires-viewport-or-card-leases"] = emissions.isEmpty
        let window = NSWindow(contentRect: NSRect(x: 14000, y: 14000, width: 900, height: 600),
            styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let replacement = NSWindow(contentRect: NSRect(x: 15000, y: 15000, width: 900, height: 600),
            styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        replacement.isReleasedWhenClosed = false
        let ancestor = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        window.contentView = ancestor
        controller.view.frame = ancestor.bounds
        controller.view.autoresizingMask = [.width, .height]
        ancestor.addSubview(controller.view)
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        controller.collection.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil); replacement.orderOut(nil); window.close(); replacement.close() }
        checks["order-in-acquires-shared-visible-and-nearby-leases"] = wait { emissions.last?.0.isEmpty == false && emissions.last?.1.isEmpty == false }
        let layout = controller.collection.collectionViewLayout as! NSCollectionViewFlowLayout
        func expectedVisible() -> [WallpaperReference] {
            layout.layoutAttributesForElements(in: controller.collection.visibleRect).compactMap { attribute -> Int? in
                guard attribute.representedElementCategory == .item, attribute.frame.intersects(controller.collection.visibleRect),
                      let path = attribute.indexPath else { return nil }
                return path.item
            }.sorted().map { items[$0].providerReference }
        }
        checks["visible-demand-comes-from-native-layout-geometry"] = emissions.last?.0 == expectedVisible()
        let columns = WallpaperLibraryGridMetrics(clipWidth: controller.scrollView.contentView.bounds.width, preferredColumns: 5).columns
        let first = emissions.last!
        checks["local-nearby-demand-is-bounded-and-never-visible"] = first.1.count <= 96
            && Set(first.0).isDisjoint(with: first.1) && Set(first.1).count == first.1.count
        let index = columns * 10
        let y = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame.minY + 10
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        let geometry = expectedVisible()
        checks["single-large-scroll-refreshes-real-viewport-before-stale-cell-list"] = wait { emissions.last?.0 == geometry }
        let last = emissions.last!
        let nativeIndices = last.0.compactMap { ref in items.firstIndex { $0.providerReference == ref } }
        let localNearby = Set(last.1)
        let localBefore = localNearby.filter { Int($0.sourceID)! < nativeIndices.first! }.count
        let localAfter = localNearby.filter { Int($0.sourceID)! > nativeIndices.last! }.count
        checks["images-large-jump-prefetch-reaches-local-cap-with-forward-bias"] =
            nativeIndices.count == 20 && localNearby.count == 96 && localNearby.count == last.1.count
            && localAfter >= localBefore * 2 && localAfter <= localBefore * 2 + 2
            && (nativeIndices.first! - localBefore..<nativeIndices.first!).allSatisfy { localNearby.contains(items[$0].providerReference) }
            && (nativeIndices.last! + 1...nativeIndices.last! + localAfter).allSatisfy { localNearby.contains(items[$0].providerReference) }
            && Set(last.0).isDisjoint(with: localNearby)
        checks["downward-scroll-starts-with-nearest-forward-neighbor"] = last.1.first == items[nativeIndices.last! + 1].providerReference
        let beforeReverse = emissions.count
        let reverseY = layout.layoutAttributesForItem(at: IndexPath(item: index - columns, section: 0))!.frame.minY + 10
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: reverseY))
        let reverseGeometry = expectedVisible()
        checks["reverse-scroll-refreshes-actual-local-viewport"] = wait { emissions.count > beforeReverse && emissions.last?.0 == reverseGeometry }
        let reverse = emissions.last!
        let reverseIndices = reverse.0.compactMap { ref in items.firstIndex { $0.providerReference == ref } }
        let reverseNearby = Set(reverse.1)
        let reverseBefore = reverseNearby.filter { Int($0.sourceID)! < reverseIndices.first! }.count
        let reverseAfter = reverseNearby.filter { Int($0.sourceID)! > reverseIndices.last! }.count
        checks["upward-scroll-restores-two-screen-budget-and-reverses-leading-share"] =
            reverseIndices.count == 20 && reverseNearby.count == 40 && reverseNearby.count == reverse.1.count
            && reverseBefore >= reverseAfter * 2 && reverseBefore <= reverseAfter * 2 + 2
            && (reverseIndices.first! - reverseBefore..<reverseIndices.first!).allSatisfy { reverseNearby.contains(items[$0].providerReference) }
            && (reverseIndices.last! + 1...reverseIndices.last! + reverseAfter).allSatisfy { reverseNearby.contains(items[$0].providerReference) }
            && Set(reverse.0).isDisjoint(with: reverseNearby)
            && reverse.1.first == items[reverseIndices.first! - 1].providerReference
        func scrollReceipt(_ y: CGFloat) -> (visible: [WallpaperReference], nearby: [WallpaperReference])? {
            let previous = emissions.count
            let clip = controller.scrollView.contentView
            let proposed = NSRect(origin: NSPoint(x: clip.bounds.minX, y: y), size: clip.bounds.size)
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
            controller.scrollView.reflectScrolledClipView(clip)
            let expected = expectedVisible()
            guard wait({ emissions.dropFirst(previous).contains { $0.0 == expected } }) else { return nil }
            return emissions.dropFirst(previous).first { $0.0 == expected }
        }
        func shares(_ receipt: (visible: [WallpaperReference], nearby: [WallpaperReference])) -> (before: Int, after: Int) {
            let first = Int(receipt.visible.first!.sourceID)!, last = Int(receipt.visible.last!.sourceID)!
            return (receipt.nearby.filter { Int($0.sourceID)! < first }.count,
                receipt.nearby.filter { Int($0.sourceID)! > last }.count)
        }
        let fineY = layout.layoutAttributesForItem(at: IndexPath(item: columns * 20, section: 0))!.frame.minY + 20
        let fineBase = scrollReceipt(fineY), fineDown = scrollReceipt(fineY + 2), fineDownAgain = scrollReceipt(fineY + 4)
        if let base = fineBase, let down = fineDown, let again = fineDownAgain {
            let counts = shares(down)
            checks["two-within-row-downward-moves-keep-forward-share-and-identical-neighbors"] = base.visible == down.visible
                && down.visible == again.visible && down.nearby == again.nearby
                && counts.after >= counts.before * 2 && counts.after <= counts.before * 2 + 2
        } else { checks["two-within-row-downward-moves-keep-forward-share-and-identical-neighbors"] = false }
        let fineUp = scrollReceipt(fineY + 2), fineUpAgain = scrollReceipt(fineY)
        if let up = fineUp, let again = fineUpAgain {
            let counts = shares(up)
            checks["two-within-row-upward-moves-keep-reverse-share-and-identical-neighbors"] = up.visible == again.visible
                && up.nearby == again.nearby && counts.before >= counts.after * 2 && counts.before <= counts.after * 2 + 2
        } else { checks["two-within-row-upward-moves-keep-reverse-share-and-identical-neighbors"] = false }
        let beforeStill = emissions.count
        controller.view.needsLayout = true; window.contentView?.layoutSubtreeIfNeeded()
        let stillReceived = wait { emissions.count > beforeStill }
        if stillReceived, let still = emissions.dropFirst(beforeStill).first, !still.0.isEmpty {
            let counts = shares(still)
            checks["stationary-native-layout-restores-the-original-neutral-neighbors"] = abs(counts.before - counts.after) <= 1
        } else { checks["stationary-native-layout-restores-the-original-neutral-neighbors"] = false }
        let stride = layout.itemSize.height + layout.minimumLineSpacing
        let middleY = layout.layoutAttributesForItem(at: IndexPath(item: columns * 100, section: 0))!.frame.minY
        let sixPages = controller.scrollView.contentView.bounds.height * 6
        for (phaseIndex, phase) in [CGFloat(0.1), 0.4, 0.8].enumerated() {
            for direction in [CGFloat(-1), 1] {
                let name = "six-page-native-landing-phase-\(phaseIndex)-direction-\(Int(direction))"
                let origin = middleY + stride * phase
                _ = scrollReceipt(origin)
                let approach = scrollReceipt(origin + sixPages * direction)
                let landed = scrollReceipt(origin + sixPages * direction * 2)
                checks[name] = approach.map { before in landed.map { next in
                    let required = Set(next.visible).subtracting(before.visible)
                    return !required.isEmpty && required.isSubset(of: Set(before.nearby)) && before.nearby.count <= 96
                } ?? false } ?? false
            }
        }
        let beforeRemote = emissions.count
        update(page: .wallhaven); spin()
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        let remoteGeometry = expectedVisible()
        checks["wallhaven-publishes-its-real-page-viewport"] = wait { emissions.count > beforeRemote && emissions.last?.0 == remoteGeometry }
        let remote = emissions.last!
        let remoteIndices = remote.0.compactMap { ref in items.firstIndex { $0.providerReference == ref } }
        let remoteNearby = Set(remote.1)
        checks["wallhaven-keeps-one-row-before-and-after-with-original-cap"] = remoteNearby.count == columns * 2 && remoteNearby.count <= 24
            && (remoteIndices.first! - columns..<remoteIndices.first!).allSatisfy { remoteNearby.contains(items[$0].providerReference) }
            && (remoteIndices.last! + 1...remoteIndices.last! + columns).allSatisfy { remoteNearby.contains(items[$0].providerReference) }
            && remoteNearby.count == remote.1.count && Set(remote.0).isDisjoint(with: remoteNearby)
        checks["wallhaven-downward-demand-starts-at-first-forward-row"] = remote.1.first == items[remoteIndices.last! + 1].providerReference
        let beforeLocalReturn = emissions.count
        update(); spin()
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        checks["images-reentry-restores-current-page-demand"] = wait { emissions.count > beforeLocalReturn && emissions.last?.0 == expectedVisible() }
        // Repeated inputs stay below the original 30ms cadence. If every input
        // postpones a trailing debounce, nothing can publish during this loop.
        let prior = emissions.count
        for offset in 0..<16 {
            controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y + CGFloat(offset + 1)))
            spin(0.007)
        }
        checks["continued-scroll-uses-leading-coalescing-instead-of-postponing-until-idle"] = emissions.count > prior
        window.orderOut(nil)
        checks["order-out-revokes-visible-and-prefetch-consumers"] = wait { emissions.last.map { $0.0.isEmpty && $0.1.isEmpty } == true }
        let hiddenCount = emissions.count
        update(); spin(0.09)
        checks["hidden-layout-and-data-updates-cannot-restart-consumers"] = emissions.count == hiddenCount
            && controller.collection.visibleItems().allSatisfy { ($0 as? ViewportCell)?.visible != true }
        window.orderFrontRegardless()
        checks["order-in-resumes-latest-demand"] = wait { emissions.last?.0.isEmpty == false }
        ancestor.isHidden = true
        checks["ancestor-hide-revokes-leases"] = wait { emissions.last?.0.isEmpty == true && emissions.last?.1.isEmpty == true }
        window.miniaturize(nil)
        let mini = wait { window.isMiniaturized }
        window.deminiaturize(nil)
        let restored = wait { !window.isMiniaturized && window.isVisible }
        spin(0.09)
        checks["hidden-ancestor-cannot-resume-after-deminiaturize"] = mini && restored
            && emissions.last?.0.isEmpty == true && emissions.last?.1.isEmpty == true
        ancestor.isHidden = false
        checks["ancestor-unhide-resumes-both-consumers"] = wait { emissions.last?.0.isEmpty == false && emissions.last?.1.isEmpty == false }
        controller.viewWillDisappear(); spin()
        let offPageCount = emissions.count
        update(); spin()
        checks["off-page-update-cannot-revive-demand"] = emissions.count == offPageCount && emissions.last?.0.isEmpty == true
        controller.viewDidAppear()
        checks["returning-to-page-resumes-current-value-demand"] = wait { emissions.last?.0.isEmpty == false }
        controller.view.removeFromSuperview()
        checks["detach-revokes-old-window-lease"] = wait { emissions.last?.0.isEmpty == true }
        replacement.contentView?.addSubview(controller.view)
        replacement.orderFrontRegardless()
        checks["reparent-uses-replacement-window"] = wait { emissions.last?.0.isEmpty == false }
        spin()
        let reparentCount = emissions.count
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        window.orderOut(nil); spin()
        checks["old-window-events-cannot-cancel-or-wake-new-lease"] = emissions.count == reparentCount && emissions.last?.0.isEmpty == false
        let selection = controller.selection
        controller.scrollToTop(animated: false); spin()
        checks["reselected-sidebar-scroll-to-top-preserves-selection-and-page-items"] = controller.scrollView.contentView.bounds.origin == .zero
            && controller.selection == selection && controller.items == items && emissions.last?.0 == expectedVisible()
        var resizeAndZoom = true, pixelGeometryMatches = true
        for style: NSScroller.Style in [.legacy, .overlay] {
            controller.scrollView.scrollerStyle = style
            for width: CGFloat in [620, 1000, 2800, 1000] {
                for zoom in [3, 4, 5, 6] {
                    replacement.setContentSize(NSSize(width: width, height: 600))
                    controller.update(page: .images, items: items, selection: controller.selection,
                        preferredColumns: zoom, permitsDragging: false, scrollAnchor: nil)
                    replacement.contentView?.layoutSubtreeIfNeeded(); controller.collection.layoutSubtreeIfNeeded(); spin(0.012)
                    let metric = WallpaperLibraryGridMetrics(clipWidth: controller.scrollView.contentView.bounds.width, preferredColumns: zoom)
                    let frames = (0..<min(items.count, metric.columns * 2)).compactMap {
                        layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame
                    }
                    let rowCount = frames.filter { abs($0.minY - (frames.first?.minY ?? 0)) < 1 }.count
                    resizeAndZoom = resizeAndZoom && rowCount == metric.columns
                        && frames.allSatisfy { abs($0.width - metric.coverSide) < 0.5 && $0.width == $0.height
                            && $0.maxX <= controller.scrollView.contentView.bounds.width + 0.5 }
                    if let frame = frames.first, let pixels = configuredPixels.last {
                        let required = controller.collection.convertToBacking(frame.size).width
                        pixelGeometryMatches = pixelGeometryMatches && pixels % 64 == 0
                            && CGFloat(pixels) >= required && CGFloat(pixels) < required + 64
                            && pixels <= 4096
                    } else { pixelGeometryMatches = false }
                }
            }
        }
        checks["shared-native-grid-resize-zoom-and-both-scroller-styles-fit-real-clip"] = resizeAndZoom
        checks["shared-native-grid-configures-covering-pixel-target-across-resize-and-zoom"] = pixelGeometryMatches
        checks["settled-native-viewport-shares-the-configured-pixel-target"] = wait {
            emittedPixels.last != nil && emittedPixels.last == configuredPixels.last
        }
        checks["first-cell-target-does-not-use-its-unprepared-frame"] = firstFactoryPixels.map {
            $0.0 % 64 == 0 && CGFloat($0.0) >= $0.1 && CGFloat($0.0) < $0.1 + 64
        } == true
        let beforeEmpty = emissions.count
        controller.update(page: .images, items: [], selection: controller.selection, preferredColumns: 6,
            permitsDragging: false, scrollAnchor: nil)
        replacement.contentView?.layoutSubtreeIfNeeded(); controller.collection.layoutSubtreeIfNeeded()
        checks["attached-empty-grid-revokes-all-visible-and-nearby-demand"] = wait {
            emissions.count > beforeEmpty && emissions.last?.0.isEmpty == true && emissions.last?.1.isEmpty == true
        } && controller.view.window === replacement && controller.collection.visibleItems().allSatisfy { ($0 as? ViewportCell)?.visible != true }
        let emptyRect = controller.collection.gridVisibleRect
        FileHandle.standardError.write(Data("ADAPTIVE EMPTY rectIsNull=\(emptyRect.isNull) rectIsEmpty=\(emptyRect.isEmpty) clipY=\(controller.scrollView.gridViewportRect.minY)\n".utf8))
        let beforeShort = emissions.count
        controller.update(page: .images, items: Array(items.prefix(1)), selection: controller.selection, preferredColumns: 6,
            permitsDragging: false, scrollAnchor: nil)
        replacement.contentView?.layoutSubtreeIfNeeded(); controller.collection.layoutSubtreeIfNeeded()
        checks["attached-single-item-restarts-without-old-neighbor-leases"] = wait {
            emissions.count > beforeShort && emissions.last?.0 == [items[0].providerReference] && emissions.last?.1.isEmpty == true
        } && controller.collection.visibleItems().allSatisfy {
            ($0 as? ViewportCell)?.visible != true || ($0.representedObject as? WallpaperReference) == items[0].reference
        }
        let beforeFull = emissions.count
        controller.update(page: .images, items: items, selection: controller.selection, preferredColumns: 6,
            permitsDragging: false, scrollAnchor: nil)
        replacement.contentView?.layoutSubtreeIfNeeded(); controller.collection.layoutSubtreeIfNeeded()
        checks["attached-full-list-restores-only-current-valid-demand"] = wait {
            controller.items == items && emissions.count > beforeFull && (emissions.last?.0.count ?? 0) > 1
        } && emissions.last?.0 == expectedVisible() && emissions.last.map {
            Set($0.0 + $0.1).isSubset(of: Set(items.map(\.providerReference)))
                && Set($0.0).isDisjoint(with: $0.1) && Set($0.1).count == $0.1.count && $0.1.count <= 96
        } == true
        // Native automatic toolbar inset, separate from all zero-inset checks.
        let toolbarController = WallpaperLibraryGridController { collection, path, _, _ in
            collection.makeItem(withIdentifier: ViewportCell.reuse, for: path)
        }
        toolbarController.loadViewIfNeeded()
        toolbarController.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        toolbarController.collection.register(ViewportCell.self, forItemWithIdentifier: ViewportCell.reuse)
        toolbarController.setCellVisible = { cell, state in (cell as? ViewportCell)?.visible = state != nil }
        var toolbarEmissions: [([WallpaperReference], [WallpaperReference])] = []
        toolbarController.onViewport = { visible, nearby, _ in
            toolbarEmissions.append((visible.map(\.providerReference), nearby.map(\.providerReference)))
        }
        toolbarController.update(page: .images, items: items, selection: toolbarController.selection, preferredColumns: 5,
            permitsDragging: false, scrollAnchor: nil)
        let toolbarWindow = NSWindow(contentViewController: toolbarController)
        toolbarWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        toolbarWindow.titleVisibility = .hidden
        toolbarWindow.titlebarAppearsTransparent = false
        toolbarWindow.toolbarStyle = .unified
        toolbarWindow.isReleasedWhenClosed = false
        toolbarWindow.setContentSize(NSSize(width: 800, height: 600))
        toolbarWindow.center()
        let toolbarItems = GridViewportToolbarProbe()
        let toolbar = NSToolbar(identifier: "grid-viewport-native-toolbar")
        toolbar.delegate = toolbarItems; toolbar.displayMode = .iconOnly
        toolbarWindow.toolbar = toolbar
        toolbarWindow.makeKeyAndOrderFront(nil)
        defer { withExtendedLifetime(toolbarItems) {}; toolbarWindow.orderOut(nil); toolbarWindow.close() }
        spin(0.12)
        checks["toolbar-fixture-uses-native-automatic-top-inset"] = wait {
            toolbarController.scrollView.contentInsets.top > 0 && toolbarController.collection.visibleRect.height > 0
                && toolbarWindow.contentLayoutRect.maxY < toolbarWindow.contentView!.bounds.maxY
        }
        let toolbarColumns = WallpaperLibraryGridMetrics(clipWidth: toolbarController.scrollView.contentView.bounds.width, preferredColumns: 5).columns
        let bandPath = IndexPath(item: toolbarColumns * 20, section: 0)
        let bandFrame = toolbarController.collection.collectionViewLayout!.layoutAttributesForItem(at: bandPath)!.frame
        toolbarController.scrollView.contentView.scroll(to: NSPoint(x: 0, y: bandFrame.maxY - toolbarController.scrollView.contentInsets.top / 2))
        toolbarController.scrollView.reflectScrolledClipView(toolbarController.scrollView.contentView)
        checks["toolbar-band-cell-is-native-visible-and-outside-safe-interaction-area"] = wait {
            toolbarController.collection.item(at: bandPath) != nil && bandFrame.intersects(toolbarController.collection.visibleRect)
                && !bandFrame.intersects(toolbarController.collection.gridVisibleRect)
        }
        FileHandle.standardError.write(Data("R109 GRID clip=\(toolbarController.scrollView.contentView.bounds) visible=\(toolbarController.collection.visibleRect) safe=\(toolbarController.collection.gridVisibleRect) band=\(bandFrame) cell=\(toolbarController.collection.item(at: bandPath) != nil) window=\(toolbarWindow.frame)\n".utf8))
        checks["toolbar-band-is-in-display-viewport-demand"] = wait {
            toolbarEmissions.last?.0.contains(items[bandPath.item].providerReference) == true
        }
        let bandCell = toolbarController.collection.item(at: bandPath) as? ViewportCell
        checks["toolbar-band-native-cell-has-display-demand"] = bandCell?.visible == true
        let bandActivation = (bandCell?.view as? WallpaperCardInteractionView)?.onAccessibilityActivate
        checks["toolbar-band-does-not-expand-safe-accessibility-activation"] = bandActivation != nil && bandActivation?() == false
        toolbarWindow.orderOut(nil)
        checks["toolbar-window-hide-still-revokes-display-and-nearby-demand"] = wait {
            toolbarEmissions.last?.0.isEmpty == true && toolbarEmissions.last?.1.isEmpty == true
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
