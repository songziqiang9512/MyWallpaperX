import CoreFoundation
import Darwin
import Foundation

/// Installed before AppKit/content initialization in renderer entries. Parent
/// loss and stdin EOF share one deadline, independent of the renderer main loop.
nonisolated final class DaemonParentLifetime: @unchecked Sendable {
    static let shared = DaemonParentLifetime()
    static let parentEnvironmentKey = "MWX_PLAYBACK_PARENT_PID"

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.mywallpaperx.renderer-parent-lifetime")
    private var parentSource: DispatchSourceProcess?
    private var shutdownHandler: (@MainActor @Sendable () -> Void)?
    private var shutdownRequested = false
    private var handlerScheduled = false
    private let hardExitDelay: TimeInterval

    init(hardExitDelay: TimeInterval = 3) {
        self.hardExitDelay = hardExitDelay
        let inherited = ProcessInfo.processInfo.environment[Self.parentEnvironmentKey].flatMap(Int32.init)
        let parent = inherited ?? getppid()
        // Cover a parent already lost before entry or before registration.
        guard parent > 1, getppid() == parent else {
            requestShutdown()
            return
        }
        let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in self?.requestShutdown() }
        // resume registers the kevent asynchronously. Check again after
        // registration so a parent lost during installation cannot be missed.
        source.setRegistrationHandler { [weak self] in
            if getppid() != parent { self?.requestShutdown() }
        }
        parentSource = source
        source.resume()
    }

    deinit { parentSource?.cancel() }

    func setShutdownHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        lock.lock()
        shutdownHandler = handler
        scheduleHandlerLocked()
        lock.unlock()
    }

    func requestShutdown() {
        lock.lock()
        if !shutdownRequested {
            shutdownRequested = true
            // _exit avoids atexit/AppKit/VM work that may itself be blocked.
            queue.asyncAfter(deadline: .now() + hardExitDelay) { Darwin._exit(70) }
        }
        scheduleHandlerLocked()
        lock.unlock()
    }

    private func scheduleHandlerLocked() {
        guard shutdownRequested, !handlerScheduled, let shutdownHandler else { return }
        handlerScheduled = true
        RunLoop.main.perform(inModes: [.common, .init("NSModalPanelRunLoopMode")]) {
            MainActor.assumeIsolated { shutdownHandler() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
