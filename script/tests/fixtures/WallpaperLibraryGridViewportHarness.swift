import AppKit

private final class ViewportCell: NSCollectionViewItem {
    static let reuse = NSUserInterfaceItemIdentifier("viewport-cell")
    var visible = false
    override func loadView() { view = WallpaperCardInteractionView() }
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
        let items = (0..<200).map { index -> WallpaperContentItem in
            let reference = WallpaperReference(provider: WallpaperProvider.allCases[index % WallpaperProvider.allCases.count], sourceID: "\(index)")
            return .init(reference: reference, providerReference: reference, locator: .init(mediaKind: .video),
                title: "\(index)", kind: .video, publishedAvailability: .available, capabilities: [.inspect, .play],
                metadata: .init(), acquisition: .idle, update: .idle, aliases: [])
        }
        let controller = WallpaperLibraryGridController { collection, path, _, _ in
            collection.makeItem(withIdentifier: ViewportCell.reuse, for: path)
        }
        controller.loadViewIfNeeded()
        controller.collection.register(ViewportCell.self, forItemWithIdentifier: ViewportCell.reuse)
        controller.setCellVisible = { cell, visible in (cell as? ViewportCell)?.visible = visible }
        var emissions: [([WallpaperReference], [WallpaperReference])] = []
        controller.onViewport = { visible, nearby in emissions.append((visible.map(\.providerReference), nearby.map(\.providerReference))) }
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
        let layout = controller.collection.collectionViewLayout!
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
        var resizeAndZoom = true
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
                }
            }
        }
        checks["shared-native-grid-resize-zoom-and-both-scroller-styles-fit-real-clip"] = resizeAndZoom
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
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
