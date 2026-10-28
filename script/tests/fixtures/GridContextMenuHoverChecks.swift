// Explicit native popup boundaries supplement the production rightDown/up
// route in GridContextMenuNativeInputChecks; they do not claim hardware input.
private final class ContextMenuActionProbe: NSObject {
    var actions = 0
    var invoke: (() -> Void)?
    @objc func activate(_ sender: Any?) { actions += 1; invoke?() }
}

private extension Checks {
    mutating func contextMenus() throws {
        let collection = WallpaperLibraryCollectionView(frame: NSRect(x: 0, y: 0, width: 340, height: 1_200))
        let fixture = try GridFixture(collection: collection), otherGrid = try GridFixture()
        defer { fixture.cleanup(); otherGrid.cleanup() }
        fixture.showAndActivate(); fixture.settle()
        let cards = fixture.visible.sorted { $0.identity < $1.identity }
        guard cards.count > 1 else { throw FixtureFailure.unavailable("two visible menu cards") }
        let original = cards[0], neighbor = cards[1]
        original.usesHoverActionVisibility = true; neighbor.usesHoverActionVisibility = true
        func point(_ card: HoverItem) -> NSPoint { card.view.convert(NSPoint(x: 90, y: 45), to: nil) }
        let sourcePoint = point(original), nextPoint = point(neighbor)
        fixture.window.testPointer = sourcePoint
        original.refreshGridHover(isScrolling: false)
        let scale = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1.0 : 1.025
        let probe = ContextMenuActionProbe()
        func makeMenu() -> NSMenu {
            let menu = NSMenu(); menu.autoenablesItems = false
            let item = NSMenuItem(title: "固定命令", action: #selector(ContextMenuActionProbe.activate(_:)), keyEquivalent: "")
            item.target = probe; menu.addItem(item)
            return menu
        }
        let prepared = makeMenu()
        collection.contextMenuProvider = { _ in prepared }
        let request = NSEvent.mouseEvent(with: .rightMouseDown, location: sourcePoint, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let queried = collection.menu(for: request)
        fixture.window.testPointer = nextPoint
        original.refreshGridHover(isScrolling: false); neighbor.refreshGridHover(isScrolling: false)
        expect("requesting-a-menu-without-native-tracking-does-not-freeze-pointer-sampling", queried === prepared
            && !fixture.scroll.isTrackingContextMenu && !original.hovered && neighbor.hovered)

        fixture.window.testPointer = sourcePoint
        let unrelatedRefreshes = otherGrid.visible.reduce(0) { $0 + $1.refreshCalls.count }
        fixture.scroll.beginContextMenu(at: sourcePoint)
        expect("actual-popup-begin-restores-a-source-card-that-already-received-exit", original.hovered && !original.button.isHidden
            && abs((original.view.layer?.transform.m11 ?? 0) - scale) < 0.0001)
        let menu = makeMenu(), area = original.view.trackingAreas.first!
        var preserved = false
        let duringMenu = Timer(timeInterval: 0.035, repeats: false) { _ in
            MainActor.assumeIsolated {
                fixture.window.testPointer = nextPoint
                let event = NSEvent.enterExitEvent(with: .mouseExited, location: nextPoint, modifierFlags: [],
                    timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0,
                    trackingNumber: 0, userData: nil)!
                (area.owner as? NSResponder)?.mouseExited(with: event)
                preserved = abs((original.view.layer?.transform.m11 ?? 0) - scale) < 0.0001
                menu.cancelTracking()
            }
        }
        RunLoop.main.add(duringMenu, forMode: .eventTracking)
        _ = menu.popUp(positioning: nil, at: collection.convert(sourcePoint, from: nil), in: collection)
        fixture.scroll.endContextMenu(); duringMenu.invalidate()
        expect("native-context-menu-keeps-original-thumbnail-scale-with-its-real-tracking-owner", preserved && area.owner as AnyObject? === original)
        expect("native-menu-cancel-resamples-current-visible-cards-without-touching-another-grid", !fixture.scroll.isTrackingContextMenu
            && fixture.scroll.contextMenuPointerLocation == nil && !original.hovered && neighbor.hovered && !neighbor.button.isHidden
            && otherGrid.visible.reduce(0, { $0 + $1.refreshCalls.count }) == unrelatedRefreshes)
        let restored = fixture.visible.reduce(0) { $0 + $1.refreshCalls.count }
        fixture.scroll.endContextMenu()
        expect("one-native-close-has-only-one-pointer-restore", fixture.visible.reduce(0) { $0 + $1.refreshCalls.count } == restored)

        let detachedMenu = makeMenu()
        fixture.scroll.beginContextMenu(at: sourcePoint)
        var clearedOnDetach = false
        let detach = Timer(timeInterval: 0.025, repeats: false) { _ in
            MainActor.assumeIsolated {
                fixture.scroll.removeFromSuperview()
                clearedOnDetach = !fixture.scroll.isTrackingContextMenu && fixture.scroll.contextMenuPointerLocation == nil
                detachedMenu.cancelTracking()
            }
        }
        RunLoop.main.add(detach, forMode: .eventTracking)
        _ = detachedMenu.popUp(positioning: nil, at: collection.convert(sourcePoint, from: nil), in: collection)
        fixture.scroll.endContextMenu(); detach.invalidate()
        expect("a-popup-view-detach-retires-its-pointer-before-return", clearedOnDetach && fixture.scroll.window == nil)

        fixture.host.addSubview(fixture.scroll); fixture.settle()
        guard let scrollItem = fixture.visible.first(where: { $0.identity == original.identity }),
              !scrollItem.view.trackingAreas.isEmpty else { throw FixtureFailure.unavailable("reattached menu card") }
        scrollItem.usesHoverActionVisibility = true
        fixture.window.testPointer = point(scrollItem)
        let move = NSEvent.mouseEvent(with: .mouseMoved, location: sourcePoint, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        let scrollingMenu = makeMenu()
        fixture.scroll.beginContextMenu(at: point(scrollItem))
        var scrollCalls = 0
        let duringScroll = Timer(timeInterval: 0.025, repeats: false) { _ in
            MainActor.assumeIsolated {
                fixture.begin()
                scrollCalls = scrollItem.refreshCalls.count
                for _ in 0..<12 { NSApp.sendEvent(move) }
                scrollingMenu.cancelTracking()
            }
        }
        RunLoop.main.add(duringScroll, forMode: .eventTracking)
        _ = scrollingMenu.popUp(positioning: nil, at: collection.convert(sourcePoint, from: nil), in: collection)
        fixture.scroll.endContextMenu(); duringScroll.invalidate()
        expect("menu-close-during-scroll-does-not-restore-or-continuously-sample-hover", fixture.scroll.isGridScrolling
            && !scrollItem.hovered && scrollItem.refreshCalls.count == scrollCalls && scrollItem.view.trackingAreas.isEmpty)
        fixture.end(); pump(0.2)
        expect("original-scroll-settlement-restores-pointer-after-menu-exit", !fixture.scroll.isGridScrolling
            && scrollItem.hovered && !scrollItem.button.isHidden && !scrollItem.view.trackingAreas.isEmpty)
    }
}
