//
//  DebugWebSpaceLifecycleRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation

@MainActor
enum DebugWebSpaceLifecycleRunner {
    private static let sequenceFlag = "--mwx-debug-web-space-lifecycle-sequence"

    static func scheduleIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: sequenceFlag),
              arguments.indices.contains(flagIndex + 1) else {
            return false
        }
        schedule(itemID: arguments[flagIndex + 1])
        return true
    }

    private static func schedule(itemID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard DebugWebPlaybackRunner.hasUsableWorkshopRoot else {
                NSLog("MWX DEBUG SPACE LIFECYCLE: precondition=isolated-root-required")
                return
            }
            let service = SteamWorkshopService.shared
            NSLog("MWX DEBUG PLAY: using workshop root %@", service.libraryRootURL.path)
            service.reloadInstalledItems()
            DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)

            schedule(after: 6.0, action: "default-space") {
                NotificationCenter.default.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            }
            schedule(after: 6.5, action: "workspace-space") {
                NSWorkspace.shared.notificationCenter.post(
                    name: NSWorkspace.activeSpaceDidChangeNotification,
                    object: nil
                )
            }
            schedule(after: 7.0, action: "screen-burst") {
                for _ in 0..<3 {
                    NotificationCenter.default.post(
                        name: NSApplication.didChangeScreenParametersNotification,
                        object: nil
                    )
                }
            }
            schedule(after: 8.0, action: "relaunch") {
                DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)
            }
            schedule(after: 13.5, action: "workspace-space-after-relaunch") {
                NSWorkspace.shared.notificationCenter.post(
                    name: NSWorkspace.activeSpaceDidChangeNotification,
                    object: nil
                )
            }
            schedule(after: 14.0, action: "stop") {
                WallpaperEngine.shared.stopPlayback()
            }
            schedule(after: 15.2, action: "post-stop-notifications") {
                NotificationCenter.default.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
                NSWorkspace.shared.notificationCenter.post(
                    name: NSWorkspace.activeSpaceDidChangeNotification,
                    object: nil
                )
                NotificationCenter.default.post(
                    name: NSApplication.didChangeScreenParametersNotification,
                    object: nil
                )
            }
            schedule(after: 16.2, action: "completed") {}
        }
    }

    private static func schedule(
        after delay: TimeInterval,
        action: String,
        operation: @escaping @MainActor () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSLog("MWX DEBUG SPACE LIFECYCLE: action=%@", action)
            operation()
        }
    }
}
#endif
