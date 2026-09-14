import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import WebKit
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func emit(type: String, requestID: Int?, message: String?, videoPath: String?, contentKind: String? = nil) {
        let event = DaemonEvent(
            type: type,
            displayID: displayID,
            requestID: requestID,
            message: message,
            videoPath: videoPath,
            contentKind: contentKind ?? currentContentKind
        )

        do {
            let data = try DaemonNewlineJSON.encode(event)
            FileHandle.standardOutput.write(data)
        } catch {
            daemonLog("failed to emit event \(type): \(error.localizedDescription)")
        }
    }
}
