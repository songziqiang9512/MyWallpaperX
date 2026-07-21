//
//  DebugSceneWindowCapture.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
enum DebugSceneWindowCapture {
    static func capture(
        windowNumber: Int,
        reason: String,
        outputDirectory: URL
    ) {
        let windowID = CGWindowID(windowNumber)
        SCShareableContent.getCurrentProcessShareableContent { content, error in
            DispatchQueue.main.async {
                if let error {
                    reportFailure(reason: reason, stage: "shareable-content", error: error)
                    return
                }
                let processID = ProcessInfo.processInfo.processIdentifier
                let processWindows = content?.windows.filter {
                    $0.owningApplication?.processID == processID
                } ?? []
                let exactWindow = processWindows.first(where: { $0.windowID == windowID })
                let fallbackWindow = processWindows.max {
                    ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
                }
                guard let window = exactWindow ?? fallbackWindow else {
                    let available = content?.windows.map { String($0.windowID) }.joined(separator: ",") ?? "-"
                    reportFailure(
                        reason: reason,
                        stage: "window-lookup-available-\(available)",
                        error: nil
                    )
                    return
                }
                if exactWindow == nil {
                    NSLog(
                        "MWX DEBUG SCENE: phase=snapshot-window-fallback reason=%@ expected=%u resolved=%u",
                        reason,
                        windowID,
                        window.windowID
                    )
                }
                capture(window: window, reason: reason, outputDirectory: outputDirectory)
            }
        }
    }

    private static func capture(
        window: SCWindow,
        reason: String,
        outputDirectory: URL
    ) {
        let maximumDimension = 1280.0
        let scale = min(1, maximumDimension / max(window.frame.width, window.frame.height))
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)

        SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) { image, error in
            DispatchQueue.main.async {
                guard let image else {
                    reportFailure(reason: reason, stage: "capture-image", error: error)
                    return
                }
                let outputURL = outputDirectory.appendingPathComponent("scene-\(reason)-window.png")
                let representation = NSBitmapImageRep(cgImage: image)
                guard let data = representation.representation(using: .png, properties: [:]) else {
                    reportFailure(reason: reason, stage: "png-encode", error: nil)
                    return
                }
                do {
                    try data.write(to: outputURL, options: [.atomic])
                    NSLog(
                        "MWX DEBUG SCENE: phase=snapshot reason=%@ window=%u path=%@",
                        reason,
                        window.windowID,
                        outputURL.path
                    )
                } catch {
                    reportFailure(reason: reason, stage: "write", error: error)
                }
            }
        }
    }

    private static func reportFailure(reason: String, stage: String, error: Error?) {
        NSLog(
            "MWX DEBUG SCENE: phase=snapshot-failed reason=%@ stage=%@ error=%@",
            reason,
            stage,
            error?.localizedDescription ?? "unknown"
        )
    }
}
#endif
