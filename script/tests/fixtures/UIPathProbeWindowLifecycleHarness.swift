import AppKit
import Foundation

private final class ProbeFiles: @unchecked Sendable {
    static let shared = ProbeFiles()
    private let lock = NSLock()
    private var barrier: DispatchSemaphore?
    private var calls = 0
    private var active = 0
    private var maximumActive = 0
    func reset() {
        lock.lock(); defer { lock.unlock() }
        precondition(active == 0)
        calls = 0; maximumActive = 0
    }
    func blockNext() -> DispatchSemaphore {
        lock.lock(); defer { lock.unlock() }
        let pending = DispatchSemaphore(value: 0)
        barrier = pending
        return pending
    }
    var observation: (calls: Int, active: Int, maximumActive: Int) {
        lock.lock(); defer { lock.unlock() }
        return (calls, active, maximumActive)
    }
    func fileExists(atPath path: String) -> Bool {
        lock.lock()
        calls += 1; active += 1; maximumActive = max(maximumActive, active)
        let pending = barrier; barrier = nil
        lock.unlock()
        pending?.wait()
        lock.lock(); active -= 1; lock.unlock()
        return false
    }
}
private struct Record { let id: String; let path: String; var thumbnailPath: String? = nil }
private typealias VideoWallpaper = Record
private final class ProbeManager: @unchecked Sendable {
    func normalizedSourcePathExists(_ path: String) -> Bool { ProbeFiles.shared.fileExists(atPath: path) }
    func resolvedThumbnailPath(for wallpaper: Record) -> String? { "/fixture/preview" }
    func ensurePreviewAssetsForWallpaper(_ wallpaper: Record) {}
}
@MainActor private final class Collection {
    var reloadCount = 0
    func indexPathsForVisibleItems() -> Set<IndexPath> { [IndexPath(item: 0, section: 0)] }
    func reloadItems(at paths: Set<IndexPath>) { if !paths.isEmpty { reloadCount += 1 } }
}
@MainActor private protocol ProbeAudit: AnyObject {
    var view: NSView { get }
    var timerIdentity: ObjectIdentifier? { get }
    var observerCount: Int { get }
    var lifecycleUpdates: Int { get }
    var inFlight: Bool { get }
    var pendingResume: Bool { get }
    var reloadCount: Int { get }
    func fire()
    func synchronize()
}

// PRODUCTION_GRIDS

@main private enum Checks {
    @MainActor static func wait(_ reason: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            precondition(Date() < deadline, reason)
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }
    @MainActor static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    @MainActor static func makeWindow(shown: Bool = true) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 120, height: 100),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if shown { window.orderFront(nil) }
        return window
    }
    @MainActor static func audit(_ name: String, make: () -> any ProbeAudit) -> [String: Bool] {
        var checks: [String: Bool] = [:]
        func record(_ key: String, _ passed: Bool) { checks[name + ":" + key] = passed }
        let files = ProbeFiles.shared
        files.reset()
        let window = makeWindow(shown: false)
        let replacement = makeWindow()
        let grid = make()
        record("unattachedViewHasNoTimerOrWindowObservers", grid.timerIdentity == nil && grid.observerCount == 0)
        grid.fire()
        record("unattachedDirectProbeDoesNoIO", files.observation.calls == 0)
        window.contentView!.addSubview(grid.view)
        record("attachmentBeforeOrderFrontKeepsCadenceWithoutIO", grid.timerIdentity != nil && files.observation.calls == 0)
        window.orderFront(nil)
        wait("visible attachment did not probe") { files.observation.calls == 1 && !grid.inFlight }
        record("initialOrderFrontReachesProbeOnExistingCadence", grid.timerIdentity != nil && grid.observerCount == 2)
        let timer = grid.timerIdentity
        for _ in 0..<20 { grid.synchronize() }
        record("visibleSynchronizationIsIdempotent", grid.timerIdentity == timer && files.observation.calls == 1)
        window.orderOut(nil)
        wait("orderOut did not hide window") { !window.isVisible }
        let hiddenCalls = files.observation.calls
        grid.fire()
        spin(2.4)
        record("orderOutKeepsTimerButStopsStatAndDirectProbe", grid.timerIdentity == timer && files.observation.calls == hiddenCalls)
        window.orderFront(nil)
        wait("orderFront did not restore probe on existing cadence") { grid.timerIdentity != nil && files.observation.calls > hiddenCalls && !grid.inFlight }
        let shownCalls = files.observation.calls
        window.miniaturize(nil)
        wait("miniaturize did not stop timer") { window.isMiniaturized && grid.timerIdentity == nil }
        let miniCalls = files.observation.calls
        grid.fire()
        spin(2.4)
        record("miniaturizedWindowStopsTicksAndDirectProbe", files.observation.calls == miniCalls)
        window.deminiaturize(nil)
        wait("same-window deminiaturize did not immediately probe") { !window.isMiniaturized && grid.timerIdentity != nil && files.observation.calls > miniCalls && !grid.inFlight }
        record("sameWindowRestoresImmediateProbe", shownCalls > hiddenCalls && files.observation.calls > miniCalls)

        grid.view.removeFromSuperview()
        record("detachDropsTimerAndObserverLease", grid.timerIdentity == nil && grid.observerCount == 0)
        replacement.contentView!.addSubview(grid.view)
        wait("replacement attachment did not complete") { !grid.inFlight }
        let newTimer = grid.timerIdentity
        let updates = grid.lifecycleUpdates
        for notification in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.post(name: notification, object: window)
        }
        record("oldWindowCannotWakeOrStopNewLease", grid.timerIdentity == newTimer && grid.lifecycleUpdates == updates && grid.observerCount == 2)

        files.reset()
        let pending = files.blockNext()
        grid.fire()
        wait("blocked probe did not start") { files.observation.active == 1 }
        grid.view.removeFromSuperview()
        record("detachKeepsOldFlightButClearsPendingResume", grid.inFlight && !grid.pendingResume && grid.timerIdentity == nil)
        replacement.contentView!.addSubview(grid.view)
        let resumedTimer = grid.timerIdentity
        for _ in 0..<20 { grid.synchronize() }
        record("busyResumeHasOnePendingAndOneFlight", grid.pendingResume && grid.inFlight && files.observation.calls == 1
            && grid.timerIdentity == resumedTimer && files.observation.maximumActive == 1)
        pending.signal()
        wait("resume catch-up did not finish") { files.observation.calls == 2 && !grid.inFlight }
        spin(0.05)
        record("completionRunsExactlyOneResumeCatchUp", !grid.pendingResume && files.observation.calls == 2
            && files.observation.maximumActive == 1 && grid.timerIdentity == resumedTimer)

        files.reset()
        let abandoned = files.blockNext()
        grid.fire()
        wait("second blocked probe did not start") { files.observation.active == 1 }
        grid.view.removeFromSuperview()
        replacement.contentView!.addSubview(grid.view)
        record("secondBusyResumeRecordsPending", grid.pendingResume)
        replacement.orderOut(nil)
        wait("orderOut after resume did not hide window") { !replacement.isVisible }
        let priorReloads = grid.reloadCount
        abandoned.signal()
        wait("hidden old completion did not release flight") { !grid.inFlight }
        spin(0.05)
        record("hiddenCompletionClearsPendingWithoutSelfSustainingWork", !grid.pendingResume && files.observation.calls == 1 && grid.reloadCount == priorReloads)
        replacement.orderFront(nil)
        wait("later visible restore did not probe") { files.observation.calls == 2 && !grid.inFlight }
        grid.view.removeFromSuperview()
        window.close(); replacement.close()

        files.reset()
        let releaseWindow = makeWindow()
        let releaseBarrier = files.blockNext()
        weak var weakRetired: NSView?
        // AppKit may autorelease a view removed from its hierarchy; drain that
        // ownership separately from our observer/worker lifetime assertion.
        autoreleasepool {
            var retired: (any ProbeAudit)? = make()
            weakRetired = retired?.view
            releaseWindow.contentView!.addSubview(retired!.view)
            wait("retiring probe did not start") { files.observation.active == 1 }
            retired!.view.removeFromSuperview()
            retired = nil
        }
        record("windowObserverAndWorkerDoNotRetainDetachedView", weakRetired == nil)
        releaseBarrier.signal()
        wait("retiring stat did not finish") { files.observation.active == 0 }
        spin(0.05)
        record("lateCompletionCannotReviveDetachedView", weakRetired == nil)
        releaseWindow.close()
        return checks
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        var checks = audit("Video", make: { VideoGrid() })
        checks.merge(audit("SIL", make: { SILGrid() })) { _, next in next }
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
