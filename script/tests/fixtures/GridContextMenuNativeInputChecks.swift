import AppKit

/// Test-copy observations only. The production scroll/tracker and collection
/// execute their original bodies; this trace neither ends nor starts tracking.
enum GridContextMenuInputTrace {
    static weak var scroll: WallpaperGridScrollView?
    static weak var sourceMenu: NSMenu?
    static var events: [[String: Any]] = []

    static func record(_ name: String, event: NSEvent? = nil, menu: NSMenu? = nil) {
        guard let scroll else { return }
        var value: [String: Any] = ["name": name, "time": ProcessInfo.processInfo.systemUptime,
            "tracking": scroll.isTrackingContextMenu,
            "scrolling": scroll.isGridScrolling, "mounted": scroll.window != nil,
            "pressedButtons": NSEvent.pressedMouseButtons,
            "acceptsMouseMovedEvents": scroll.window?.acceptsMouseMovedEvents ?? false,
            "firstResponder": scroll.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "none"]
        if let event {
            value["eventType"] = event.type.rawValue
            value["eventTime"] = event.timestamp
            if [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .pressure].contains(event.type) {
                value["pressure"] = event.pressure
            }
            if event.type == .pressure { value["stage"] = event.stage }
        }
        if let menu {
            value["menuID"] = String(describing: ObjectIdentifier(menu))
            value["sourceMenu"] = menu === sourceMenu
            value["isSubmenu"] = menu.supermenu != nil
        }
        value["cards"] = ((scroll.documentView as? NSCollectionView)?.visibleItems() ?? []).compactMap {
            guard let item = $0 as? HoverItem else { return nil as [String: Any]? }
            return ["id": item.identity, "hovered": item.hovered, "barVisible": !item.button.isHidden,
                "scale": item.view.layer?.transform.m11 ?? 0, "areas": item.view.trackingAreas.count]
        }
        events.append(value)
    }
}

private final class ContextInputMenuObserver: NSObject, NSMenuDelegate {
    var openedSubmenu = false
    func menuWillOpen(_ menu: NSMenu) {
        openedSubmenu = openedSubmenu || menu.supermenu != nil
        GridContextMenuInputTrace.record("delegate.willOpen", menu: menu)
    }
    func menuDidClose(_ menu: NSMenu) { GridContextMenuInputTrace.record("delegate.didClose", menu: menu) }
}

private extension Checks {
    mutating func nativeContextMenuInput() throws {
        observations["contextMenuNativeScope"] = [
            "route": "NSApplication.sendEvent → shared WallpaperCardInteractionView → production WallpaperLibraryCollectionView.menu(for:) → native contextual menu",
            "input": "public NSEvent right-down/up packets with immediate or delayed release; no physical trackpad validation",
            "hardwareAcceptance": "not-verified",
            "leaf": "fixed NSMenu replaces Commands/SQLite only; the menu route never invokes popUp directly",
            "hoverInput": "the current actual trackingArea.owner receives the same public mouseExited/mouseMoved entry before and after the native menu; no WindowServer tracking-event generation claim",
        ]
        for (name, delay, submenu, detach, staleScroll) in [
            ("immediate-release-cancel", 0.005, false, false, false),
            ("held-release-cancel", 0.18, false, false, false),
            ("held-release-submenu-cancel", 0.18, true, false, false),
            ("held-release-action-detach", 0.18, false, true, false),
            ("live-scroll-without-end-then-held-menu", 0.18, false, false, true),
        ] {
            let collection = WallpaperLibraryCollectionView(frame: NSRect(x: 0, y: 0, width: 340, height: 1_200))
            let fixture = try GridFixture(collection: collection)
            defer { fixture.cleanup() }
            fixture.window.acceptsMouseMovedEvents = true
            let cards = fixture.visible.sorted { $0.identity < $1.identity }
            guard cards.count > 1 else { throw FixtureFailure.unavailable("native menu input cards") }
            let original = cards[0], neighbor = cards[1]
            original.usesHoverActionVisibility = true; neighbor.usesHoverActionVisibility = true
            func point(_ item: HoverItem) -> NSPoint { item.view.convert(NSPoint(x: 160, y: 55), to: nil) }
            let sourcePoint = point(original)
            fixture.window.testPointer = sourcePoint
            original.refreshGridHover(isScrolling: false)
            let scale = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1.0 : 1.025
            let probe = ContextMenuActionProbe(), observer = ContextInputMenuObserver()
            let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = observer
            let leaf = NSMenuItem(title: "固定命令", action: #selector(ContextMenuActionProbe.activate(_:)), keyEquivalent: "")
            leaf.target = probe
            if submenu {
                let parent = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
                let child = NSMenu(); child.autoenablesItems = false; child.delegate = observer
                child.addItem(leaf); parent.submenu = child; menu.addItem(parent)
            } else { menu.addItem(leaf) }
            var paths: [IndexPath?] = [], clearedOnActionDetach = false, scrollSettlements = 0
            fixture.scroll.onScrollSettled = { scrollSettlements += 1 }
            collection.contextMenuProvider = { path in
                paths.append(path); GridContextMenuInputTrace.record("provider", menu: menu)
                return menu
            }
            probe.invoke = {
                GridContextMenuInputTrace.record("action", menu: menu)
                if detach {
                    fixture.scroll.removeFromSuperview()
                    clearedOnActionDetach = !fixture.scroll.isTrackingContextMenu && fixture.scroll.contextMenuPointerLocation == nil
                }
            }
            GridContextMenuInputTrace.scroll = fixture.scroll
            GridContextMenuInputTrace.sourceMenu = menu
            GridContextMenuInputTrace.events = []
            defer { GridContextMenuInputTrace.scroll = nil; GridContextMenuInputTrace.sourceMenu = nil }
            let notices = [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification,
                           NSMenu.willSendActionNotification, NSMenu.didSendActionNotification].map { notification in
                NotificationCenter.default.addObserver(forName: notification, object: nil, queue: nil) { value in
                    MainActor.assumeIsolated {
                        GridContextMenuInputTrace.record("native." + value.name.rawValue, menu: value.object as? NSMenu)
                    }
                }
            }
            defer { notices.forEach { NotificationCenter.default.removeObserver($0) } }
            let monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp, .rightMouseDragged, .pressure, .mouseMoved]) { event in
                MainActor.assumeIsolated { GridContextMenuInputTrace.record("local-monitor", event: event) }
                return event
            }
            defer { if let monitor { NSEvent.removeMonitor(monitor) } }
            func mouse(_ type: NSEvent.EventType, at point: NSPoint, pressure: Float) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: pressure)!
            }
            func trackingOwner(_ item: HoverItem) throws -> NSResponder {
                guard let area = item.view.trackingAreas.first(where: { $0.options.contains(.mouseMoved) }),
                      let owner = area.owner as? NSResponder, owner === item else {
                    throw FixtureFailure.unavailable("the current native tracking area must retain its original item owner")
                }
                return owner
            }
            func trackingMove(to item: HoverItem, exiting previous: HoverItem) throws {
                let target = point(item)
                fixture.window.testPointer = target
                let exit = NSEvent.enterExitEvent(with: .mouseExited, location: target, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: fixture.window.windowNumber,
                    context: nil, eventNumber: 2, trackingNumber: 0, userData: nil)!
                GridContextMenuInputTrace.record("trackingOwner.exit.dispatch", event: exit)
                try trackingOwner(previous).mouseExited(with: exit)
                let move = mouse(.mouseMoved, at: target, pressure: 0)
                GridContextMenuInputTrace.record("trackingOwner.move.dispatch", event: move)
                try trackingOwner(item).mouseMoved(with: move)
            }
            func key(_ code: UInt16, _ text: String) {
                let event = NSEvent.keyEvent(with: .keyDown, location: sourcePoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: fixture.window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
                    isARepeat: false, keyCode: code)!
                GridContextMenuInputTrace.record("key.enqueued", event: event)
                NSApp.postEvent(event, atStart: false)
            }
            let nativeMovesBefore = original.moves
            NSApp.sendEvent(mouse(.mouseMoved, at: sourcePoint, pressure: 0)); pump(0.02)
            // Ordinary synthetic mouseMoved dispatch is a first-responder path.
            // Observe it separately; do not equate it with OS tracking delivery.
            let syntheticMovesDelivered = original.moves - nativeMovesBefore
            let ownerMovesBefore = original.moves
            try trackingMove(to: original, exiting: neighbor)
            expect(name + "-the-same-tracking-owner-input-reaches-the-card-before-the-menu", original.moves == ownerMovesBefore + 1
                && original.hovered && !original.button.isHidden && !neighbor.hovered)
            if staleScroll {
                fixture.begin()
                expect(name + "-starts-with-the-real-live-scroll-suppression-owner", fixture.scroll.isGridScrolling && original.view.trackingAreas.isEmpty)
            }
            var timers: [Timer] = [], releaseEnqueued = false, observedOpen = false, keptDuringTracking = false, timedOut = false
            func schedule(_ interval: TimeInterval, _ action: @escaping @MainActor () -> Void) {
                let timer = Timer(timeInterval: interval, repeats: false) { _ in MainActor.assumeIsolated { action() } }
                timers.append(timer); RunLoop.main.add(timer, forMode: .eventTracking)
            }
            schedule(delay) {
                observedOpen = fixture.scroll.isTrackingContextMenu
                keptDuringTracking = abs((original.view.layer?.transform.m11 ?? 0) - scale) < 0.0001
                let up = mouse(.rightMouseUp, at: sourcePoint, pressure: 0)
                GridContextMenuInputTrace.record("rightUp.enqueued", event: up)
                releaseEnqueued = true; NSApp.postEvent(up, atStart: false)
            }
            if detach {
                schedule(delay + 0.06) { key(125, "\u{F701}"); key(36, "\r") }
            } else if submenu {
                schedule(delay + 0.06) { key(125, "\u{F701}"); key(124, "\u{F703}") }
                schedule(delay + 0.16) { key(53, "\u{1b}") }
                schedule(delay + 0.20) { key(53, "\u{1b}") }
            } else { schedule(delay + 0.06) { key(53, "\u{1b}") } }
            schedule(2) { timedOut = true; GridContextMenuInputTrace.record("timeout.cancel", menu: menu); menu.cancelTracking() }
            defer { timers.forEach { $0.invalidate() } }
            let down = mouse(.rightMouseDown, at: sourcePoint, pressure: 1)
            GridContextMenuInputTrace.record("rightDown.dispatch.begin", event: down)
            NSApp.sendEvent(down)
            GridContextMenuInputTrace.record("rightDown.dispatch.return", event: down)
            timers.forEach { $0.invalidate() }
            pump(0.04)
            let rows = GridContextMenuInputTrace.events
            let detail = String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self)
            expect(name + "-uses-the-production-collection-menu-route-for-the-pressed-card", !paths.isEmpty
                && paths.allSatisfy { $0?.item == original.identity } && rows.contains { $0["name"] as? String == "collection.menu" }, detail)
            expect(name + "-opens-and-closes-natively-with-a-real-right-up-packet", releaseEnqueued && observedOpen && !timedOut
                && rows.contains { ($0["name"] as? String) == "delegate.didClose" && $0["sourceMenu"] as? Bool == true }
                && !fixture.scroll.isTrackingContextMenu, detail)
            expect(name + "-keeps-the-source-thumbnail-scale-through-native-tracking", keptDuringTracking, detail)
            expect(name + "-native-return-releases-the-pointer-and-any-prior-scroll-without-a-wheel-end", !fixture.scroll.isGridScrolling
                && fixture.scroll.contextMenuPointerLocation == nil && (!staleScroll || scrollSettlements == 1), detail)
            if detach {
                expect(name + "-an-action-view-removal-clears-the-same-owner-before-native-return", probe.actions == 1
                    && clearedOnActionDetach && fixture.scroll.window == nil, detail)
            } else {
                expect(name + "-cancel-does-not-run-a-command", probe.actions == 0, detail)
                if submenu { expect(name + "-actually-opens-the-native-submenu", observer.openedSubmenu, detail) }
                let beforeMoves = (original.moves, neighbor.moves)
                var previous = original, repeatedResponses = true
                for target in [neighbor, original, neighbor, original, neighbor, original] {
                    let moves = target.moves
                    try trackingMove(to: target, exiting: previous)
                    repeatedResponses = repeatedResponses && target.moves == moves + 1 && target.hovered && !target.button.isHidden
                        && !previous.hovered && previous.button.isHidden
                        && abs((target.view.layer?.transform.m11 ?? 0) - scale) < 0.0001
                        && abs((previous.view.layer?.transform.m11 ?? 0) - 1) < 0.0001
                    previous = target
                }
                expect(name + "-the-same-actual-tracking-owner-input-repeatedly-restores-both-cards-bars-and-scales-without-scrolling",
                    repeatedResponses && original.moves == beforeMoves.0 + 3 && neighbor.moves == beforeMoves.1 + 3, detail)
            }
            let endIndex = rows.firstIndex { ($0["name"] as? String) == "scroll.end.after" }
            let upIndex = rows.firstIndex { ($0["name"] as? String) == "rightUp.enqueued" }
            let order = endIndex.flatMap { end in upIndex.map { end < $0 ? "end-before-up-enqueued" : "up-enqueued-before-end" } }
            observations[name] = ["releaseDelay": delay, "events": GridContextMenuInputTrace.events,
                "ordinarySyntheticMoveOwnerDeliveriesBeforeMenu": syntheticMovesDelivered,
                "endRelativeToReleasePacket": order ?? "end-or-up-not-observed"]
        }
    }
}
