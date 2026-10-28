import CoreGraphics
import Darwin
import Foundation

// System I/O leaves only. NotificationCenter and Timer below are the native
// Foundation implementations; no production return/cancel algorithm is copied.
@MainActor final class FinderWindow {
    var isVisible = true
    private(set) var raises = 0
    func makeKeyAndOrderFront(_ sender: Any?) { raises += 1 }
}
@MainActor final class FinderApplication {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    init(bundleID: String?, pid: pid_t) { bundleIdentifier = bundleID; processIdentifier = pid }
}
@MainActor final class FinderWorkspace {
    static let shared = FinderWorkspace()
    nonisolated static let didActivateApplicationNotification = Notification.Name("fixture.finder.didActivate")
    nonisolated static let activeSpaceDidChangeNotification = Notification.Name("fixture.finder.spaceChanged")
    nonisolated static let applicationUserInfoKey = "application"
    let notificationCenter = NotificationCenter()
    var frontmostApplication: FinderApplication?
    var reveals: [[URL]] = []
    var onReveal: (() -> Void)?
    func activateFileViewerSelecting(_ urls: [URL]) { reveals.append(urls); onReveal?() }
    func activate(_ app: FinderApplication) {
        frontmostApplication = app
        notificationCenter.post(name: Self.didActivateApplicationNotification, object: nil,
                                userInfo: [Self.applicationUserInfoKey: app])
    }
}
@MainActor final class FinderApp {
    var mainWindow: FinderWindow?
    var keyWindow: FinderWindow?
    var isHidden = false
    var activations = 0
    func activate(ignoringOtherApps: Bool) {
        precondition(ignoringOtherApps, "Finder does not yield cooperative activation")
        activations += 1
        FinderWorkspace.shared.activate(.init(bundleID: Bundle.main.bundleIdentifier, pid: 9))
    }
}
@MainActor let NSApp = FinderApp()
@MainActor enum FinderIO {
    static var now = Date(timeIntervalSince1970: 100)
    static var rows: [[String: Any]]? = []
    static var queries = 0
    static func windowList(_ options: CGWindowListOption, _ relativeTo: CGWindowID) -> CFArray? {
        precondition(options == [.optionOnScreenOnly, .excludeDesktopElements])
        precondition(relativeTo == kCGNullWindowID)
        queries += 1
        return rows.map { $0.filter { ($0[kCGWindowIsOnscreen as String] as? Bool) != false } as CFArray }
    }
    static func window(_ id: CGWindowID, pid: pid_t = 42, layer: Int = 0, onscreen: Bool = true) -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowNumber as String: NSNumber(value: id),
         kCGWindowLayer as String: NSNumber(value: layer), kCGWindowIsOnscreen as String: onscreen]
    }
}

// ACTUAL_FINDER_COORDINATOR

// Read-only observations and an explicit native-tick driver. The production
// Timer still fires in the dedicated cadence check, and every tick executes poll.
extension FinderRevealCoordinator {
    var observingForFixture: Bool { !observers.isEmpty }
    var timingForFixture: Bool { timer?.isValid == true }
    func tickForFixture() { poll() }
}

@main enum FinderRevealChecks {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ value: Bool) { precondition(value, name); checks[name] = value }
        let workspace = FinderWorkspace.shared
        let coordinator = FinderRevealCoordinator()
        let file = URL(fileURLWithPath: "/fixture/wallpaper.mp4")
        let otherFile = URL(fileURLWithPath: "/fixture/other.jpg")
        let finder = FinderApplication(bundleID: "com.apple.finder", pid: 42)
        let editor = FinderApplication(bundleID: "fixture.editor", pid: 77)
        func prepare(main: FinderWindow? = nil, key: FinderWindow? = nil) {
            workspace.activate(editor) // A real app-activation event retires the preceding scenario.
            workspace.frontmostApplication = .init(bundleID: Bundle.main.bundleIdentifier, pid: 9)
            workspace.reveals = []; workspace.onReveal = nil
            FinderIO.rows = [FinderIO.window(101)]; FinderIO.queries = 0
            FinderIO.now = Date(timeIntervalSince1970: 100)
            NSApp.mainWindow = main; NSApp.keyWindow = key; NSApp.isHidden = false; NSApp.activations = 0
        }
        func activateFinder() { workspace.activate(finder) }
        func pumpUntil(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(1.5)
            while !condition() && Date() < deadline {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            precondition(condition(), "native Finder observation timer did not fire")
        }

        prepare()
        coordinator.reveal([])
        check("empty-input-does-not-open-finder-or-start-observation", workspace.reveals.isEmpty
            && !coordinator.observingForFixture && !coordinator.timingForFixture)
        coordinator.reveal([file])
        activateFinder()
        check("no-return-window-still-reveals-without-claiming-focus", workspace.reveals == [[file]]
            && NSApp.activations == 0 && !coordinator.observingForFixture && !coordinator.timingForFixture)

        let main = FinderWindow(), transientKey = FinderWindow()
        prepare(main: main, key: transientKey)
        coordinator.reveal([file])
        check("reveal-subscribes-before-finder-activation", coordinator.observingForFixture && !coordinator.timingForFixture)
        activateFinder()
        transientKey.isVisible = false
        FinderIO.rows = []
        coordinator.tickForFixture()
        check("closing-revealed-window-returns-to-persistent-main-not-transient-key", main.raises == 1
            && transientKey.raises == 0 && NSApp.activations == 1 && !coordinator.observingForFixture && !coordinator.timingForFixture)

        let cachedClosed = FinderWindow()
        prepare(main: cachedClosed)
        FinderIO.rows = [FinderIO.window(500, onscreen: false), FinderIO.window(101)]
        coordinator.reveal([file]); activateFinder()
        FinderIO.rows = [FinderIO.window(101, onscreen: false), FinderIO.window(500, onscreen: false)]
        coordinator.tickForFixture()
        check("finder-cached-closed-ids-do-not-prevent-return-from-the-visible-window", cachedClosed.raises == 1
            && NSApp.activations == 1 && !coordinator.timingForFixture)

        let changedSpace = FinderWindow()
        prepare(main: changedSpace)
        coordinator.reveal([file]); activateFinder()
        workspace.notificationCenter.post(name: FinderWorkspace.activeSpaceDidChangeNotification, object: nil)
        FinderIO.rows = [FinderIO.window(101, onscreen: false)]
        coordinator.tickForFixture()
        check("changing-space-retires-the-trip-before-a-window-leaves-the-visible-list", changedSpace.raises == 0
            && NSApp.activations == 0 && !coordinator.observingForFixture && !coordinator.timingForFixture)

        let explicit = FinderWindow(), unusedMain = FinderWindow()
        prepare(main: unusedMain)
        coordinator.reveal([file], returningTo: explicit)
        activateFinder()
        FinderIO.rows = [FinderIO.window(202)] // The tracked window closed; another Finder window remains.
        coordinator.tickForFixture()
        check("explicit-visible-host-is-restored-on-exact-target-close", explicit.raises == 1
            && unusedMain.raises == 0 && NSApp.activations == 1)
        FinderIO.rows = []
        coordinator.tickForFixture()
        check("return-trip-only-activates-once", explicit.raises == 1 && NSApp.activations == 1)

        let outside = FinderWindow()
        prepare(main: outside)
        coordinator.reveal([file]); activateFinder()
        workspace.activate(editor)
        FinderIO.rows = []
        coordinator.tickForFixture()
        check("choosing-third-party-application-retires-return-without-focus-theft", NSApp.activations == 0
            && outside.raises == 0 && !coordinator.observingForFixture && !coordinator.timingForFixture)

        let alternate = FinderWindow()
        prepare(main: alternate)
        coordinator.reveal([file]); activateFinder()
        FinderIO.rows = [FinderIO.window(202), FinderIO.window(101)]
        coordinator.tickForFixture()
        FinderIO.rows = []
        coordinator.tickForFixture()
        check("choosing-another-finder-window-retires-return-without-focus-theft", NSApp.activations == 0
            && alternate.raises == 0 && !coordinator.observingForFixture && !coordinator.timingForFixture)

        let closedHost = FinderWindow()
        prepare(main: closedHost)
        coordinator.reveal([file]); activateFinder()
        closedHost.isVisible = false
        FinderIO.rows = []
        coordinator.tickForFixture()
        check("closed-original-window-is-never-reopened", NSApp.activations == 0 && closedHost.raises == 0
            && !coordinator.observingForFixture && !coordinator.timingForFixture)

        let hiddenHost = FinderWindow()
        prepare(main: hiddenHost)
        coordinator.reveal([file]); activateFinder()
        NSApp.isHidden = true; FinderIO.rows = []
        coordinator.tickForFixture()
        check("hidden-application-is-never-unhidden-by-a-return-trip", NSApp.activations == 0 && hiddenHost.raises == 0
            && !coordinator.observingForFixture && !coordinator.timingForFixture)

        let unavailable = FinderWindow()
        prepare(main: unavailable)
        coordinator.reveal([file]); activateFinder()
        FinderIO.rows = nil
        coordinator.tickForFixture()
        let failedQueries = FinderIO.queries
        FinderIO.rows = []
        coordinator.tickForFixture()
        check("unavailable-window-query-cancels-and-cannot-be-mistaken-for-window-close", NSApp.activations == 0
            && unavailable.raises == 0 && FinderIO.queries == failedQueries
            && !coordinator.observingForFixture && !coordinator.timingForFixture)
        prepare(main: unavailable)
        FinderIO.rows = nil
        coordinator.reveal([file]); activateFinder()
        check("unavailable-first-query-does-not-poll-forever", !coordinator.observingForFixture
            && !coordinator.timingForFixture && NSApp.activations == 0)

        let noFinderWindow = FinderWindow()
        prepare(main: noFinderWindow)
        FinderIO.rows = []
        coordinator.reveal([file]); activateFinder()
        check("window-acquisition-does-not-invent-a-closed-target", coordinator.timingForFixture && NSApp.activations == 0)
        FinderIO.now = FinderIO.now.addingTimeInterval(6)
        coordinator.tickForFixture()
        check("missing-finder-window-expires-the-acquisition", !coordinator.observingForFixture
            && !coordinator.timingForFixture && NSApp.activations == 0)

        let firstHost = FinderWindow(), secondHost = FinderWindow()
        prepare(main: firstHost)
        coordinator.reveal([file]); activateFinder()
        workspace.onReveal = { FinderIO.rows = [FinderIO.window(202)] }
        coordinator.reveal([otherFile], returningTo: secondHost)
        check("second-reveal-replaces-first-observation", workspace.reveals == [[file], [otherFile]]
            && coordinator.observingForFixture && coordinator.timingForFixture)
        coordinator.tickForFixture()
        check("old-target-removal-cannot-return-to-first-host", firstHost.raises == 0
            && secondHost.raises == 0 && NSApp.activations == 0)
        FinderIO.rows = []
        coordinator.tickForFixture()
        check("only-second-target-close-restores-second-host", firstHost.raises == 0 && secondHost.raises == 1
            && NSApp.activations == 1 && !coordinator.timingForFixture)

        let nativeTickHost = FinderWindow()
        prepare(main: nativeTickHost)
        FinderIO.rows = [FinderIO.window(999, pid: 50), FinderIO.window(998, layer: 3), FinderIO.window(101)]
        coordinator.reveal([file]); activateFinder()
        FinderIO.rows = []
        pumpUntil { nativeTickHost.raises == 1 }
        check("actual-native-timer-drives-the-same-filtered-window-decision", nativeTickHost.raises == 1
            && NSApp.activations == 1 && !coordinator.observingForFixture && !coordinator.timingForFixture)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
