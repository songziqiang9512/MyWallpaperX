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
            let reference = WallpaperReference(provider: WallpaperProvider.allCases[index % 4], sourceID: "\(index)")
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
        func update() {
            controller.update(page: .downloads, items: items, selection: controller.selection, preferredColumns: 5,
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
        checks["nearby-demand-is-bounded-one-row-each-side-and-never-visible"] = first.1.count <= min(24, columns * 2)
            && Set(first.0).isDisjoint(with: first.1) && Set(first.1).count == first.1.count
        let index = columns * 10
        let y = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!.frame.minY + 10
        controller.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        let geometry = expectedVisible()
        checks["single-large-scroll-refreshes-real-viewport-before-stale-cell-list"] = wait { emissions.last?.0 == geometry }
        let last = emissions.last!
        let nativeIndices = last.0.compactMap { ref in items.firstIndex { $0.providerReference == ref } }
        let expectedNearby = GridThumbnailPrefetchDemand.indices(visibleIndices: nativeIndices,
            itemCount: items.count, neighborLimit: min(24, columns * 2), direction: 1).map { items[$0].providerReference }
        checks["downward-scroll-prioritizes-forward-neighbors-with-original-algorithm"] = last.1 == expectedNearby
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
                    controller.update(page: .downloads, items: items, selection: controller.selection,
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
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
