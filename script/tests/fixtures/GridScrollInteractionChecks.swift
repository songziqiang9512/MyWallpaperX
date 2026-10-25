import AppKit
import CoreGraphics

private enum FixtureFailure: Error {
    case unavailable(String)
}

/// The former observer-only override is a negative control for AppKit's default
/// compatibility heuristic. It forwards input but has no explicit opt-in.
private final class LegacyWheelScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
    }
}

/// A deterministic native window input, without warping the user's pointer.
private final class PointerWindow: NSWindow {
    var testPointer = NSPoint(x: -10_000, y: -10_000)
    override var canBecomeKey: Bool { true }
    override var mouseLocationOutsideOfEventStream: NSPoint { testPointer }
}

private final class ClickSurface: NSView {
    var downs = 0
    var ups = 0
    override func mouseDown(with event: NSEvent) { downs += 1 }
    override func mouseUp(with event: NSEvent) { ups += 1 }
}

private final class HoverItem: NSCollectionViewItem, WallpaperGridHoverItem {
    private let tracking = WallpaperGridHoverTracking()
    var identity = -1
    var refreshCalls: [Bool] = []
    var hovered = false
    var actions = 0
    let button = NSButton(title: "Action", target: nil, action: nil)
    var surface: ClickSurface { view as! ClickSurface }

    override func loadView() {
        view = ClickSurface(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
        button.frame = NSRect(x: 12, y: 12, width: 72, height: 28)
        button.target = self
        button.action = #selector(action)
        view.addSubview(button)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        tracking.update(in: view, owner: self)
    }

    @objc private func action() { actions += 1 }

    func refreshGridHover(isScrolling: Bool) {
        tracking.update(in: view, owner: self, isScrolling: isScrolling)
        refreshCalls.append(isScrolling)
        hovered = !isScrolling && view.isGridPointerInside
    }
}

private final class Items: NSObject, NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { 12 }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("hover"), for: indexPath) as! HoverItem
        item.identity = indexPath.item
        item.refreshCalls = []
        item.hovered = false
        return item
    }
}

private final class GridFixture {
    let window = PointerWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
                               styleMask: [.borderless], backing: .buffered, defer: false)
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 180))
    let scroll = WallpaperGridScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 180))
    let collection = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 340, height: 1_200))
    let source = Items()

    init() throws {
        window.isReleasedWhenClosed = false
        // Responsive scrolling creates a display-synchronized monitor, so the
        // native window must belong to a real screen even in this input fixture.
        guard let screen = NSScreen.main else { throw FixtureFailure.unavailable("native display") }
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 10, y: screen.visibleFrame.minY + 10))
        window.contentView = host
        host.addSubview(scroll)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 280, height: 100)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.register(HoverItem.self, forItemWithIdentifier: .init("hover"))
        collection.dataSource = source
        scroll.documentView = collection
        showAndActivate()
        guard window.screen != nil else { throw FixtureFailure.unavailable("scroll window has no display") }
        collection.reloadData()
        settle()
        guard !visible.isEmpty else { throw FixtureFailure.unavailable("native collection has no visible items") }
    }

    var visible: [HoverItem] { collection.visibleItems().compactMap { $0 as? HoverItem } }

    func showAndActivate() {
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
        let deadline = Date().addingTimeInterval(1)
        repeat { pump(0.01) } while !NSApp.isActive && Date() < deadline
    }

    func settle() {
        host.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        collection.layoutSubtreeIfNeeded()
        pump(0.03)
    }

    func move(to y: CGFloat) {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle()
    }

    func begin() {
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    }

    func end() {
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
    }

    func cleanup() {
        scroll.removeFromSuperview()
        window.orderOut(nil)
        window.close()
    }
}

private func pump(_ interval: TimeInterval) {
    let deadline = Date().addingTimeInterval(interval)
    while Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.005)))
        // A standalone harness must also dispatch AppKit's queued activation
        // and window events; running Foundation timers alone leaves isActive
        // at the previous state even though WindowServer changed focus.
        for _ in 0..<100 {
            guard let event = NSApp.nextEvent(matching: .any, until: .distantPast,
                inMode: .default, dequeue: true) else { break }
            NSApp.sendEvent(event)
        }
    }
}

private func wheel(phase: Int64 = 0, momentum: Int64 = 0,
                   expectedPhase: NSEvent.Phase = [], expectedMomentum: NSEvent.Phase = []) throws -> NSEvent {
    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                              wheelCount: 1, wheel1: 8, wheel2: 0, wheel3: 0) else {
        throw FixtureFailure.unavailable("CGEvent wheel construction")
    }
    // CGScrollPhase uses 1/2/4/8 for began/changed/ended/cancelled;
    // CGMomentumScrollPhase uses 1/2/3 for begin/continue/end.
    // These differ from NSEvent.Phase raw values, so verify the native decode.
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
    guard let native = NSEvent(cgEvent: event), native.type == .scrollWheel,
          native.phase == expectedPhase, native.momentumPhase == expectedMomentum else {
        throw FixtureFailure.unavailable("native scroll phase decode \(phase)/\(momentum)")
    }
    return native
}

private final class PullCountDocument: NSView {
    override var isFlipped: Bool { true }
}

/// Only the controlled geometry mode selects this before the original product
/// observers attach. Native input and every older mode use AppKit's normal clip.
enum GridScrollClipProbe { static var usesControlledGeometry = false }
final class GridScrollGeometryClip: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect { proposedBounds }
}

private final class PullCountToolbar: NSObject, NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("count")] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("count")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = NSButton(title: "Native toolbar", target: nil, action: nil)
        return item
    }
}

private final class PullCountFixture {
    let window = PointerWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 320),
        styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    let scroll = WallpaperGridScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
    let document: PullCountDocument
    let toolbarDelegate = PullCountToolbar()
    var permitsInput = true

    init(height: CGFloat) throws {
        document = PullCountDocument(frame: NSRect(x: 0, y: 0, width: 400, height: height))
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "pull-count-native")
        toolbar.delegate = toolbarDelegate
        window.toolbar = toolbar
        window.contentView = scroll
        window.setContentSize(NSSize(width: 420, height: 320))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.documentView = document
        scroll.permitsPullCountInput = { [weak self] in self?.permitsInput == true }
        scroll.pullCountText = "共 42 张壁纸"
        window.orderFrontRegardless(); window.makeKey(); NSApp.activate()
        pump(0.1)
        scroll.layoutSubtreeIfNeeded()
        guard window.screen != nil, label != nil else { throw FixtureFailure.unavailable("native pull-count surface") }
    }

    var label: NSTextField? { scroll.subviews.compactMap { $0 as? NSTextField }.first }
    func cleanup() { scroll.removeFromSuperview(); window.orderOut(nil); window.close() }
}

private struct Checks {
    var values: [String: Bool] = [:]
    var details: [String: String] = [:]
    var observations: [String: Any] = [:]

    mutating func expect(_ name: String, _ condition: @autoclosure () -> Bool, _ detail: String = "") {
        values[name] = condition()
        if values[name] == false { details[name] = detail }
    }

    mutating func responsiveScrolling() {
        expect("native scroll view supports responsive scrolling", NSScrollView.isCompatibleWithResponsiveScrolling)
        expect("old wheel override opts out without explicit compatibility", !LegacyWheelScrollView.isCompatibleWithResponsiveScrolling)
        expect("production scroll observer retains native responsive scrolling", WallpaperGridScrollView.isCompatibleWithResponsiveScrolling)
        expect("native clip view remains compatible", NSClipView.isCompatibleWithResponsiveScrolling)
        expect("native collection document remains compatible", NSCollectionView.isCompatibleWithResponsiveScrolling)
    }

    mutating func notifications() throws {
        let first = try GridFixture(), second = try GridFixture()
        defer { first.cleanup(); second.cleanup() }
        let visible = first.visible
        expect("idle cards have one native hover area", visible.allSatisfy { $0.view.trackingAreas.count == 1 })
        first.begin()
        expect("scroll removes native hover tracking areas", visible.allSatisfy { $0.view.trackingAreas.isEmpty })
        expect("begin changes its own scroll state", first.scroll.isGridScrolling)
        expect("begin refreshes every native visible item once", visible.allSatisfy { $0.refreshCalls == [true] })
        expect("other grid stays interactive", !second.scroll.isGridScrolling && second.visible.allSatisfy { !$0.view.isGridHoverSuppressed && $0.refreshCalls.isEmpty })
        first.begin()
        expect("duplicate begin does not redispatch", visible.allSatisfy { $0.refreshCalls == [true] })
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: second.scroll)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: nil)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: NSScrollView())
        expect("unrelated and unscoped end do not clear owner", first.scroll.isGridScrolling)
        second.begin()
        first.end()
        first.end()
        expect("native end keeps short momentum handoff suppressed", first.scroll.isGridScrolling)
        pump(0.16)
        expect("end restores one area without accumulating duplicates", visible.allSatisfy { $0.view.trackingAreas.count == 1 })
        expect("end refreshes once", visible.allSatisfy { $0.refreshCalls == [true, false] })
        expect("second grid owns its independent session", second.scroll.isGridScrolling)
        second.end()
        pump(0.16)
        expect("both native sessions end independently", !first.scroll.isGridScrolling && !second.scroll.isGridScrolling)
    }

    mutating func newItems() throws {
        let fixture = try GridFixture()
        defer { fixture.cleanup() }
        fixture.move(to: 120)
        expect("programmatic bounds do not begin scrolling", !fixture.scroll.isGridScrolling)
        expect("programmatic bounds do not refresh hover", fixture.visible.allSatisfy { $0.refreshCalls.isEmpty })
        let before = Set(fixture.visible.map(\.identity))
        fixture.begin()
        fixture.move(to: 800)
        let incoming = fixture.visible.filter { !before.contains($0.identity) }
        expect("native virtualization reaches different cards", !incoming.isEmpty)
        expect("newly visible cards do not install tracking during scrolling", incoming.allSatisfy { $0.view.trackingAreas.isEmpty })
        expect("newly visible cards read suppression immediately", incoming.allSatisfy { $0.view.isGridHoverSuppressed })
        let nested = NSView(frame: .zero)
        if let item = incoming.first { item.view.addSubview(nested) }
        expect("descendant controls read the same scroll owner", nested.isGridHoverSuppressed)
        fixture.end()
        pump(0.16)
        expect("new cards restore their native tracking area", incoming.allSatisfy { $0.view.trackingAreas.count == 1 })
        expect("new cards release suppression at end", incoming.allSatisfy { !$0.view.isGridHoverSuppressed })
        fixture.move(to: 200)
        expect("later programmatic bounds stay outside the gate", !fixture.scroll.isGridScrolling)
    }

    mutating func clippedHover() throws {
        let fixture = try GridFixture()
        defer { fixture.cleanup() }
        fixture.move(to: 45)
        guard let item = fixture.visible.first(where: {
            let clipped = $0.view.bounds.intersection($0.view.visibleRect)
            return !clipped.isEmpty && clipped.height < $0.view.bounds.height - 2
        }) else {
            let items = fixture.visible.map { "id=\($0.identity), frame=\($0.view.frame), bounds=\($0.view.bounds), visible=\($0.view.visibleRect)" }
            throw FixtureFailure.unavailable("native clip must partially intersect an item; clip=\(fixture.scroll.contentView.bounds), document=\(fixture.collection.frame); \(items)")
        }
        let bounds = item.view.bounds, visible = bounds.intersection(item.view.visibleRect)
        let candidates = [NSPoint(x: bounds.midX, y: bounds.minY + 1),
                          NSPoint(x: bounds.midX, y: bounds.maxY - 1)]
        guard let clipped = candidates.first(where: { bounds.contains($0) && !visible.contains($0) }) else {
            throw FixtureFailure.unavailable("point inside item but outside clip")
        }
        fixture.window.testPointer = item.view.convert(clipped, to: nil)
        fixture.begin(); fixture.end()
        pump(0.16)
        expect("clipped-away card area cannot regain hover", !item.hovered && !item.view.isGridPointerInside,
               "bounds=\(bounds), visible=\(visible), point=\(clipped)")
        let inside = NSPoint(x: visible.midX, y: visible.midY)
        fixture.window.testPointer = item.view.convert(inside, to: nil)
        fixture.begin(); fixture.end()
        pump(0.16)
        expect("positive hover has real active visible window", NSApp.isActive && fixture.window.isVisible && !fixture.window.isMiniaturized,
               "active=\(NSApp.isActive), visible=\(fixture.window.isVisible)")
        expect("visible card area regains hover", item.hovered && item.view.isGridPointerInside)
        let rawVisible = item.view.visibleRect
        let gutterCandidates = [NSPoint(x: rawVisible.minX + 1, y: visible.midY),
                                NSPoint(x: rawVisible.maxX - 1, y: visible.midY)]
        guard let gutter = gutterCandidates.first(where: { rawVisible.contains($0) && !bounds.contains($0) }) else {
            throw FixtureFailure.unavailable("native visibleRect must expose the collection gutter for outside-card negative")
        }
        fixture.window.testPointer = item.view.convert(gutter, to: nil)
        fixture.begin(); fixture.end()
        pump(0.16)
        expect("visible viewport gutter outside card cannot regain hover", !item.hovered && !item.view.isGridPointerInside,
               "bounds=\(bounds), raw visible=\(rawVisible), pointer=\(gutter)")
        item.view.isHidden = true
        expect("hidden card cannot report pointer inside", !item.view.isGridPointerInside)
    }

    mutating func inactiveAndHidden() throws {
        let fixture = try GridFixture()
        defer { fixture.cleanup() }
        guard let item = fixture.visible.first,
              !item.view.bounds.intersection(item.view.visibleRect).isEmpty else {
            throw FixtureFailure.unavailable("native visible item for inactivity")
        }
        let visible = item.view.bounds.intersection(item.view.visibleRect)
        fixture.window.testPointer = item.view.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
        expect("positive pointer state uses real App activation", NSApp.isActive && fixture.window.isVisible && item.view.isGridPointerInside,
               "activation could not be established: \(NSApp.isActive)")
        fixture.begin()
        fixture.window.orderOut(nil)
        fixture.end()
        pump(0.16)
        expect("hidden window ends the scroll gate", !fixture.scroll.isGridScrolling)
        expect("hidden window cannot restore hover", !fixture.window.isVisible && !item.hovered && !item.view.isGridPointerInside)
        fixture.showAndActivate()
        fixture.begin()
        // Exercise a real inactive-but-visible App state. A bare deactivate()
        // can be followed by the pending LaunchServices activation request.
        // Hide finishes that transition; unhideWithoutActivation keeps the
        // visible window separate from the activation eligibility condition.
        NSApp.hide(nil)
        pump(0.08)
        NSApp.unhideWithoutActivation()
        fixture.window.orderFrontRegardless()
        pump(0.08)
        // No overridden NSApplication status: failure to deactivate remains a
        // fixture capability failure and the negative assertion still executes.
        expect("native deactivation really happened", !NSApp.isActive && fixture.window.isVisible,
               "actual active=\(NSApp.isActive), visible=\(fixture.window.isVisible)")
        fixture.end()
        pump(0.16)
        expect("inactive App ends gate without hover restore", !fixture.scroll.isGridScrolling
            && !item.hovered && !item.view.isGridPointerInside,
            "actual active=\(NSApp.isActive), hovered=\(item.hovered)")
    }

    mutating func momentumHandoff() throws {
        let fixture = try GridFixture()
        defer { fixture.cleanup() }
        fixture.scroll.scrollWheel(with: try wheel(phase: 1, expectedPhase: .began))
        fixture.scroll.scrollWheel(with: try wheel(phase: 2, expectedPhase: .changed))
        fixture.scroll.scrollWheel(with: try wheel(phase: 4, expectedPhase: .ended))
        expect("finger end keeps hover suppressed during handoff", fixture.scroll.isGridScrolling)
        pump(0.06)
        fixture.scroll.scrollWheel(with: try wheel(momentum: 1, expectedMomentum: .began))
        fixture.scroll.scrollWheel(with: try wheel(momentum: 2, expectedMomentum: .changed))
        let visible = fixture.visible
        pump(0.10)
        expect("momentum begins before old finger deadline without restore", fixture.scroll.isGridScrolling
            && visible.allSatisfy { !$0.refreshCalls.contains(false) })
        fixture.scroll.scrollWheel(with: try wheel(momentum: 3, expectedMomentum: .ended))
        let endReturned = ProcessInfo.processInfo.systemUptime
        pump(0.06)
        expect("momentum end keeps its own quiet interval", fixture.scroll.isGridScrolling,
               "elapsed since scrollWheel returned=\(ProcessInfo.processInfo.systemUptime - endReturned), refreshes=\(visible.map(\.refreshCalls))")
        pump(0.10)
        expect("momentum end eventually restores once", !fixture.scroll.isGridScrolling
            && visible.allSatisfy { $0.refreshCalls.filter { !$0 }.count == 1 })
        fixture.scroll.scrollWheel(with: try wheel(phase: 1, expectedPhase: .began))
        fixture.scroll.scrollWheel(with: try wheel(phase: 8, expectedPhase: .cancelled))
        pump(0.16)
        expect("cancelled finger sequence also closes", !fixture.scroll.isGridScrolling)
    }

    mutating func phaseLessWheel() throws {
        let fixture = try GridFixture()
        defer { fixture.cleanup() }
        let event = try wheel()
        fixture.scroll.scrollWheel(with: event)
        expect("phase-less native wheel begins gate", fixture.scroll.isGridScrolling)
        pump(0.07)
        fixture.scroll.scrollWheel(with: event)
        let visible = fixture.visible
        pump(0.075)
        expect("second wheel keeps gate past first deadline", fixture.scroll.isGridScrolling)
        expect("old deadline cannot dispatch a restore", visible.allSatisfy { !$0.refreshCalls.contains(false) })
        pump(0.16)
        expect("quiet wheel sequence closes", !fixture.scroll.isGridScrolling)
        expect("quiet close dispatches once", visible.allSatisfy { $0.refreshCalls.filter { !$0 }.count == 1 })
        let histories = visible.map(\.refreshCalls)
        pump(0.17)
        expect("no second completion arrives", visible.map(\.refreshCalls) == histories)
    }

    mutating func cancellation() throws {
        let fixture = try GridFixture()
        defer { fixture.cleanup() }
        let event = try wheel()
        fixture.scroll.scrollWheel(with: event)
        pump(0.035)
        fixture.begin()
        pump(0.18)
        expect("native begin cancels old wheel end", fixture.scroll.isGridScrolling)
        expect("cancelled wheel does not restore live cards", fixture.visible.allSatisfy { !$0.refreshCalls.contains(false) })
        fixture.end()
        pump(0.16)
        expect("native end still closes session", !fixture.scroll.isGridScrolling)
        fixture.scroll.scrollWheel(with: event)
        fixture.scroll.removeFromSuperview()
        expect("leaving a window clears scroll state", !fixture.scroll.isGridScrolling)
        fixture.host.addSubview(fixture.scroll)
        fixture.settle()
        fixture.begin()
        let visible = fixture.visible
        let counts = visible.map { $0.refreshCalls.filter { !$0 }.count }
        pump(0.2)
        expect("detached wheel cannot end a new native session", fixture.scroll.isGridScrolling)
        expect("detached completion cannot dispatch late restore", visible.map { $0.refreshCalls.filter { !$0 }.count } == counts)
        fixture.end()
        pump(0.16)
    }

    mutating func interaction() throws {
        let fixture = try GridFixture()
        defer { fixture.cleanup() }
        guard let item = fixture.visible.first else { throw FixtureFailure.unavailable("click item") }
        fixture.begin()
        let point = item.view.convert(NSPoint(x: 220, y: 70), to: nil)
        let parentPoint = fixture.host.convert(point, from: nil)
        let target = fixture.scroll.hitTest(parentPoint)
        expect("suppression keeps the card hit target", target === item.surface)
        if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 1, windowNumber: fixture.window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
           let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: 2, windowNumber: fixture.window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0) {
            target?.mouseDown(with: down)
            target?.mouseUp(with: up)
        }
        expect("card click delivery remains available", item.surface.downs == 1 && item.surface.ups == 1)
        let buttonPoint = item.button.convert(NSPoint(x: 25, y: 14), to: nil)
        expect("embedded native action keeps its hit target", fixture.scroll.hitTest(fixture.host.convert(buttonPoint, from: nil)) === item.button)
        item.button.performClick(nil)
        expect("embedded native action remains enabled", item.actions == 1 && item.button.isEnabled)
        fixture.collection.selectItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: [])
        expect("native selection remains available", fixture.collection.selectionIndexPaths == [IndexPath(item: 0, section: 0)])
        expect("collection still accepts native keyboard focus", fixture.window.makeFirstResponder(fixture.collection))
        guard let down = NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 3, windowNumber: fixture.window.windowNumber,
            context: nil, characters: "\u{f701}", charactersIgnoringModifiers: "\u{f701}",
            isARepeat: false, keyCode: 125) else {
            throw FixtureFailure.unavailable("native down-arrow event")
        }
        fixture.collection.keyDown(with: down)
        expect("native keyboard navigation remains available", fixture.collection.selectionIndexPaths == [IndexPath(item: 1, section: 0)])
        fixture.collection.selectItems(at: [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)], scrollPosition: [])
        expect("multiple selection remains available", fixture.collection.allowsMultipleSelection && fixture.collection.selectionIndexPaths.count == 2)
        expect("click and selection do not end the scroll session", fixture.scroll.isGridScrolling)
        fixture.end()
        pump(0.16)
        fixture.collection.deselectAll(nil)
        expect("selection clearing does not begin the gate", !fixture.scroll.isGridScrolling && fixture.collection.selectionIndexPaths.isEmpty)
        item.button.performClick(nil)
        fixture.collection.selectItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: [])
        fixture.collection.keyDown(with: down)
        fixture.collection.selectItems(at: [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)], scrollPosition: [])
        expect("idle click keyboard and multi-selection do not begin suppression", !fixture.scroll.isGridScrolling
            && item.actions == 2 && fixture.collection.selectionIndexPaths.count == 2)
    }

    mutating func pullCountGeometry() throws {
        GridScrollClipProbe.usesControlledGeometry = true
        defer { GridScrollClipProbe.usesControlledGeometry = false }
        for height: CGFloat in [0, 64, 1_200] {
            let fixture = try PullCountFixture(height: height)
            defer { fixture.cleanup() }
            let scroll = fixture.scroll
            guard let label = fixture.label else { throw FixtureFailure.unavailable("count label") }
            for inset: CGFloat in [0, 56] {
                let name = "height\(Int(height))-inset\(Int(inset))"
                // Controlled bounds are a geometry/notification oracle only.
                // The separate input case never sets overscrolled bounds.
                scroll.automaticallyAdjustsContentInsets = false
                scroll.contentInsets = NSEdgeInsets(top: inset, left: 3, bottom: 7, right: 5)
                scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: scroll.gridDocumentTopY))
                let frame = fixture.document.frame, insets = scroll.contentInsets
                expect(name + "-idle-label-hidden-and-count-accessible", label.isHidden
                    && scroll.accessibilityHelp() == "共 42 张壁纸" && !label.isAccessibilityElement())
                NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: scroll.gridDocumentTopY - 64))
                expect(name + "-bounds-notification-shows-nonhit-count-in-native-gap", !label.isHidden
                    && scroll.contentView is GridScrollGeometryClip
                    && abs(scroll.gridDocumentTopY - scroll.contentView.bounds.minY - 64) < 0.5
                    && label.stringValue == "共 42 张壁纸" && label.hitTest(label.frame.origin) == nil
                    && label.frame.minY >= scroll.bounds.minY && label.frame.maxY <= scroll.bounds.maxY,
                    "clip=\(scroll.contentView.bounds) label=\(label.frame) root=\(scroll.bounds)")
                expect(name + "-pull-does-not-change-document-or-insets", fixture.document.frame == frame
                    && scroll.contentInsets.top == insets.top && scroll.contentInsets.bottom == insets.bottom
                    && scroll.contentInsets.left == insets.left && scroll.contentInsets.right == insets.right)
                fixture.permitsInput = false
                NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: fixture.window)
                let deniedOrigin = scroll.contentView.bounds.origin
                scroll.scrollWheel(with: try wheel())
                expect(name + "-modal-admission-hides-count-and-rejects-new-wheel", label.isHidden
                    && scroll.contentView.bounds.origin == deniedOrigin)
                fixture.permitsInput = true
                NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: fixture.window)
                expect(name + "-admission-return-can-reveal-existing-native-gap", !label.isHidden)
                NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
                pump(0.16)
                expect(name + "-settlement-hides-count-without-moving-native-anchor", label.isHidden
                    && scroll.contentView.bounds.origin == deniedOrigin && !scroll.isGridScrolling)
                scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: scroll.gridDocumentTopY))
                expect(name + "-programmatic-return-does-not-show-count", label.isHidden && !scroll.isGridScrolling)
            }
            scroll.pullCountText = nil
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: scroll.gridDocumentTopY - 64))
            expect("height\(Int(height))-unknown-count-is-not-fabricated-zero", label.isHidden
                && scroll.accessibilityHelp() == nil)
        }
    }

    mutating func pullCountNativeInput() throws {
        // Constructed public NSEvents, not identities of physical devices.
        // In particular CUA's observed continuous wheel had no phase at all.
        let packets: [(name: String, continuous: Bool, phased: Bool)] = [
            ("continuous-phased", true, true), ("discrete-phaseless", false, false),
            ("continuous-phaseless", true, false),
        ]
        for height: CGFloat in [0, 64, 1_200] {
            for packet in packets {
                let fixture = try PullCountFixture(height: height)
                defer { fixture.cleanup() }
                let scroll = fixture.scroll
                guard let label = fixture.label else { throw FixtureFailure.unavailable("native count label") }
                let name = "height\(Int(height))-" + packet.name
                let frame = fixture.document.frame, insets = scroll.contentInsets, originalClip = scroll.contentView
                let origin = scroll.contentView.bounds.origin
                expect(name + "-native-input-keeps-unmodified-AppKit-clip", !(scroll.contentView is GridScrollGeometryClip))
                var minimumY = origin.y, countWasVisible = false
                var eligibleSamples = 0, correctEligibleSamples = 0
                var allSamplesRespectGap = true, originalGeometryPreserved = true
                var eventFacts: [[String: Any]] = []
                func deliver(_ delta: Int32, phase: Int64, expectedPhase: NSEvent.Phase) throws {
                    guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: packet.continuous ? .pixel : .line,
                        wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else {
                        throw FixtureFailure.unavailable("pull wheel")
                    }
                    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: packet.continuous ? 1 : 0)
                    cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                    guard let event = NSEvent(cgEvent: cg), event.phase == expectedPhase,
                          event.momentumPhase.isEmpty, event.hasPreciseScrollingDeltas == packet.continuous else {
                        throw FixtureFailure.unavailable("pull wheel native precision/phase decode")
                    }
                    scroll.scrollWheel(with: event)
                    pump(0.015)
                    minimumY = min(minimumY, scroll.contentView.bounds.minY)
                    countWasVisible = countWasVisible || !label.isHidden
                    let gap = scroll.gridDocumentTopY - scroll.contentView.bounds.minY
                    let clip = scroll.convert(scroll.contentView.bounds, from: scroll.contentView)
                    let top = scroll.isFlipped ? clip.minY + insets.top : clip.maxY - insets.top
                    let lower = scroll.isFlipped ? top : top - gap
                    let upper = scroll.isFlipped ? top + gap : top
                    if gap >= 24 {
                        eligibleSamples += 1
                        let correct = scroll.isGridScrolling && !label.isHidden && label.stringValue == "共 42 张壁纸"
                            && label.bounds.width > 0 && label.bounds.height > 0 && label.hitTest(label.frame.origin) == nil
                            && label.frame.minY >= lower && label.frame.maxY <= upper
                        if correct { correctEligibleSamples += 1 }
                        allSamplesRespectGap = allSamplesRespectGap && correct
                    } else {
                        allSamplesRespectGap = allSamplesRespectGap && label.isHidden
                    }
                    originalGeometryPreserved = originalGeometryPreserved && scroll.contentView === originalClip
                        && fixture.document.frame == frame && scroll.contentInsets.top == insets.top
                        && scroll.contentInsets.left == insets.left && scroll.contentInsets.bottom == insets.bottom
                        && scroll.contentInsets.right == insets.right
                    eventFacts.append(["delta": event.scrollingDeltaY, "phase": event.phase.rawValue,
                        "momentum": event.momentumPhase.rawValue, "gap": gap,
                        "precise": event.hasPreciseScrollingDeltas, "clipY": scroll.contentView.bounds.minY,
                        "labelVisible": !label.isHidden, "labelFrame": NSStringFromRect(label.frame),
                        "labelText": label.stringValue])
                }
                try deliver(32, phase: packet.phased ? 1 : 0, expectedPhase: packet.phased ? .began : [])
                for _ in 0..<6 { try deliver(32, phase: packet.phased ? 2 : 0, expectedPhase: packet.phased ? .changed : []) }
                try deliver(0, phase: packet.phased ? 4 : 0, expectedPhase: packet.phased ? .ended : [])
                pump(0.6)
                let gap = scroll.gridDocumentTopY - minimumY
                observations[name] = ["events": eventFacts, "nativeInset": insets.top, "startY": origin.y,
                    "maximumNativeGap": gap, "countWasVisible": countWasVisible,
                    "settledY": scroll.contentView.bounds.minY, "settledHidden": label.isHidden,
                    "settledAtNativeTopObserved": abs(scroll.contentView.bounds.minY - scroll.gridDocumentTopY) < 0.5,
                    "eligibleRenderSamples": eligibleSamples, "correctEligibleRenderSamples": correctEligibleSamples,
                    "scope": "constructed event packet; elastic gap and exact native return are framework observations, not physical-device validation"]
                expect(name + "-uses-real-native-toolbar-inset-and-elasticity", insets.top > 0
                    && scroll.automaticallyAdjustsContentInsets && scroll.verticalScrollElasticity == .allowed)
                expect(name + "-all-event-turns-preserve-original-clip-document-and-insets", originalGeometryPreserved
                    && scroll.contentView === originalClip && fixture.document.frame == frame && scroll.contentInsets.top == insets.top)
                expect(name + "-packet-quiet-completion-hides-count-and-ends-scroll-owner", label.isHidden && !scroll.isGridScrolling,
                    "start=\(origin.y) maxGap=\(gap) settled=\(scroll.contentView.bounds.minY) top=\(scroll.gridDocumentTopY)")
                // Positive rendering coverage is independently mandatory in
                // all six controlled-geometry cases, even if this OS packet
                // never creates a usable gap. Never call zero samples parity.
                expect(name + "-every-observed-gap-sample-obeys-the-rendering-contract", eventFacts.count == 8 && allSamplesRespectGap,
                    "maxGap=\(gap) eligible=\(eligibleSamples) correct=\(correctEligibleSamples)")
            }
        }
    }
}

@main
private enum GridScrollChecks {
    static func main() throws {
        if let pidPath = ProcessInfo.processInfo.environment["MWX_GRID_NATIVE_PID_PATH"] {
            try String(ProcessInfo.processInfo.processIdentifier).write(toFile: pidPath, atomically: true, encoding: .utf8)
        }
        let mode = CommandLine.arguments.dropFirst().first
        // The class-property regression needs neither a window nor activation.
        if mode != "responsive" {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.finishLaunching()
        }
        var checks = Checks()
        switch mode {
        case "responsive": checks.responsiveScrolling()
        case "notifications": try checks.notifications()
        case "new-items": try checks.newItems()
        case "clipped-hover": try checks.clippedHover()
        case "inactive-hidden": try checks.inactiveAndHidden()
        case "momentum": try checks.momentumHandoff()
        case "wheel": try checks.phaseLessWheel()
        case "cancellation": try checks.cancellation()
        case "interaction": try checks.interaction()
        case "pull-count-geometry": try checks.pullCountGeometry()
        case "pull-count-native-input": try checks.pullCountNativeInput()
        default: throw FixtureFailure.unavailable("unknown native test case")
        }
        var result: [String: Any] = ["checks": checks.values, "details": checks.details, "observations": checks.observations,
            "scope": "isolated native AppKit events and hit testing; no frame-rate claim"]
        if mode == "pull-count-native-input" {
            result["scope"] = "constructed public NSEvent packets; no physical mouse or trackpad validation"
            result["hardwareAcceptance"] = "not-verified"
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
