import Foundation
import AppKit
import CoreGraphics
import Darwin

func parseDisplayID() -> CGDirectDisplayID? {
    let args = CommandLine.arguments
    guard let flagIndex = args.firstIndex(of: "--display-id"),
          args.indices.contains(flagIndex + 1),
          let value = UInt32(args[flagIndex + 1]) else {
        return nil
    }
    return CGDirectDisplayID(value)
}

let parentLifetime = DaemonParentLifetime.shared
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

guard let displayID = parseDisplayID() else {
    daemonLog("missing --display-id")
    exit(1)
}

guard let daemon = WallpaperDaemon(displayID: displayID) else {
    exit(2)
}

parentLifetime.setShutdownHandler { daemon.shutdown() }
let reader = CommandReader(daemon: daemon)
reader.start()
RunLoop.main.run()
