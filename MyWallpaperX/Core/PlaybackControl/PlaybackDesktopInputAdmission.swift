import AppKit
import CoreGraphics
import Foundation

/// Shared WindowServer desktop-input qualification. Engine input owners keep
/// their own surfaces/caches; content-sharing permissions never grant clicks.
nonisolated enum PlaybackDesktopInputAdmission {
    static func allowsDesktopWindow(windowNumber: Int) -> Bool {
        guard windowNumber > 0,
              let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow,
                CGWindowID(windowNumber)) as? [[String: Any]],
              let info = windows.first(where: {
                ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == windowNumber
              }) else { return false }
        let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        return allowsDesktopWindow(ownerPID: pid,
            ownerBundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
            ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
            layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? Int.max,
            currentPID: getpid(), desktopIconLevel: Int(CGWindowLevelForKey(.desktopIconWindow)))
    }

    static func allowsDesktopWindow(
        ownerPID: pid_t, ownerBundleIdentifier: String?, ownerName: String,
        layer: Int, currentPID: pid_t, desktopIconLevel: Int
    ) -> Bool {
        guard ownerPID != currentPID, layer <= desktopIconLevel else { return false }
        return ownerBundleIdentifier == "com.apple.finder" || ownerName == "Finder" || ownerName == "访达"
    }
}
