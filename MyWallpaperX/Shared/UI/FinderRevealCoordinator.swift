import AppKit
import CoreGraphics

/// Owns only the return trip from an explicit “Show in Finder” action.
/// Window metadata is observed while that Finder window is in front; changing
/// application, Space or choosing another Finder window retires the return trip.
/// Finder retains closed window IDs; only the ordered visible list represents
/// the window that the user is actually leaving.
@MainActor final class FinderRevealCoordinator {
    static let shared = FinderRevealCoordinator()
    private weak var returnWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var finderPID: pid_t?
    private var revealedWindowID: CGWindowID?
    private var acquisitionDeadline = Date.distantPast

    isolated deinit { cancel() }

    func reveal(_ urls: [URL], returningTo window: NSWindow? = nil) {
        guard !urls.isEmpty else { return }
        cancel()
        returnWindow = window ?? NSApp.mainWindow ?? NSApp.keyWindow
        if returnWindow != nil {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated {
                    self?.applicationActivated(bundleID: app.bundleIdentifier, pid: app.processIdentifier)
                }
            })
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } })
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        if returnWindow != nil, let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.apple.finder" {
            applicationActivated(bundleID: app.bundleIdentifier, pid: app.processIdentifier)
        }
    }

    private func applicationActivated(bundleID: String?, pid: pid_t) {
        if bundleID == "com.apple.finder" {
            guard timer == nil else { return }
            finderPID = pid
            acquisitionDeadline = Date().addingTimeInterval(5)
            timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            poll()
        } else if finderPID != nil || bundleID != Bundle.main.bundleIdentifier {
            cancel()
        }
    }

    private func poll() {
        guard let window = returnWindow, window.isVisible, !NSApp.isHidden,
              let finderPID, NSWorkspace.shared.frontmostApplication?.processIdentifier == finderPID else {
            cancel(); return
        }
        guard let windows = Self.finderWindowIDs(pid: finderPID) else { cancel(); return }
        guard let revealedWindowID else {
            self.revealedWindowID = windows.first
            if windows.isEmpty, Date() >= acquisitionDeadline { cancel() }
            return
        }
        if !windows.contains(revealedWindowID) {
            cancel()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else if windows.first != revealedWindowID {
            cancel()
        }
    }

    private func cancel() {
        timer?.invalidate(); timer = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        finderPID = nil; revealedWindowID = nil; returnWindow = nil
    }

    private static func finderWindowIDs(pid: pid_t) -> [CGWindowID]? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
    }
}
