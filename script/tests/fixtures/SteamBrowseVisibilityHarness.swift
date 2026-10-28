import AppKit
import Combine

// Only source preparation and the other idle gates are leaves. Native window
// events, the view's demand pairing, service count and idle policy stay real.
@MainActor private final class VisibilityService {
    // ACTUAL_DEMAND_STATE
    // ACTUAL_DEMAND_METHODS
    var selectedBrowserItem: String?
    enum State { case idle, loading, loaded }
    var browserState = State.idle
    var preparations = 0
    func prepareForBrowserEntry() { preparations += 1; browserState = .loaded }
    func dismissItemDetail() {}
}
private enum VisibilityModule { case steamWorkshop }
@MainActor private enum InspectorHostActions { static func postClose(module: VisibilityModule) {} }
@MainActor private final class VisibilityGrid { var opensDetailsOnSingleClick: () -> Bool = { false } }
@MainActor private final class VisibilityView: NSView {
    let service: VisibilityService
    private let gridView = VisibilityGrid()
    var opensDetailsOnSingleClick: () -> Bool = { false }
    // ACTUAL_VISIBILITY_STATE
    init(service: VisibilityService) { self.service = service; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    func syncContent(force: Bool) {}
    func presentPendingDownloadErrorIfNeeded() {}
    func syncSelectedInspectorItem(_ item: String?) {}
    // ACTUAL_VISIBILITY_METHODS
}
@MainActor private final class VisibilityTiming: SteamIdleReapTiming {
    var next: (@MainActor () -> Void)?
    func schedule(after delay: TimeInterval, _ handler: @escaping @MainActor () -> Void) { next = handler }
    func cancelScheduled() { next = nil }
    func fire() { let handler = next; next = nil; handler?() }
}

@main private enum SteamBrowseVisibilityChecks {
    @MainActor static func main() {
        initializeNativeAppHarness()
        Task { @MainActor in
            await run()
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: false) }
        }
        NSApp.run()
    }
    @MainActor static func run() async {
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ value: Bool) { precondition(value, name); checks[name] = value }
        func settle(_ delay: Double = 0.08) async { try? await Task.sleep(for: .seconds(delay)) }
        let service = VisibilityService(), timing = VisibilityTiming()
        var reaps = 0
        let reaper = SteamHelperIdleReaper(now: { Date(timeIntervalSince1970: 1_000) }, timing: timing,
            gates: .init(helperQuiet: { true }, accountDormant: { true }, downloadsDormant: { true },
                browseDormant: { !service.isBrowsePanelOpen }),
            lastActivity: { Date(timeIntervalSince1970: 0) }, reap: { reaps += 1 })
        reaper.begin()
        defer { reaper.end() }
        func window(_ x: CGFloat) -> NSWindow {
            let value = NSWindow(contentRect: .init(x: x, y: 160, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            value.isReleasedWhenClosed = false
            return value
        }
        let first = window(180), second = window(710)
        let firstView = VisibilityView(service: service), secondView = VisibilityView(service: service)
        first.contentView = firstView; second.contentView = secondView
        check("mounted-but-unshown-browsers-hold-no-visible-demand", service.browsePanelAttachmentCount == 0)
        first.makeKeyAndOrderFront(nil); second.orderFront(nil); await settle()
        check("two-visible-browsers-hold-two-independent-demands", service.browsePanelAttachmentCount == 2)
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: first)
        check("repeated-visible-events-do-not-double-count", service.browsePanelAttachmentCount == 2)
        let preparationsBeforeRestoration = service.preparations
        first.miniaturize(nil); await settle(0.4)
        timing.fire(); await settle()
        check("one-minimized-browser-releases-only-its-own-demand", first.isMiniaturized
            && service.browsePanelAttachmentCount == 1 && reaps == 0)
        second.orderOut(nil); await settle()
        timing.fire(); await settle()
        check("all-hidden-browsers-allow-the-existing-idle-policy-to-reap", service.browsePanelAttachmentCount == 0 && reaps == 1)
        second.orderFront(nil); first.deminiaturize(nil); await settle(0.4)
        check("restoration-reacquires-each-demand-once-without-refreshing-an-old-query", service.browsePanelAttachmentCount == 2
            && service.preparations == preparationsBeforeRestoration)
        NSApp.hide(nil); await settle()
        check("hiding-the-app-releases-both-window-demands", NSApp.isHidden && service.browsePanelAttachmentCount == 0)
        NSApp.unhide(nil); await settle()
        check("unhiding-the-app-restores-two-demands-without-another-clock", !NSApp.isHidden && service.browsePanelAttachmentCount == 2)
        firstView.isHidden = true; await settle()
        check("hidden-browser-view-releases-only-its-demand", service.browsePanelAttachmentCount == 1)
        firstView.removeFromSuperview(); firstView.removeFromSuperview(); await settle()
        check("detaching-an-already-hidden-view-never-consumes-another-window-demand", service.browsePanelAttachmentCount == 1)
        second.close(); first.close(); await settle()
        check("closing-the-last-window-leaves-no-browse-demand", service.browsePanelAttachmentCount == 0)
        print(String(data: try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
