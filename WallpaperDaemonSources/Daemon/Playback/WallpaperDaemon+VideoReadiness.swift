import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func commitVisualSwitchWhenReady(incomingLayer: AVPlayerLayer, targetFrame: CGRect, requestID: Int?, videoPath: String?) {
        pendingDisplayObservation = nil
        pendingDisplayFallbackWorkItem?.cancel()

        let performSwitch = { [weak self] in
            guard let self else { return }
            self.pendingDisplayObservation = nil
            self.pendingDisplayFallbackWorkItem?.cancel()
            self.pendingDisplayFallbackWorkItem = nil
            self.finishVisualSwitch(targetFrame: targetFrame, requestID: requestID, videoPath: videoPath)
        }

        if incomingLayer.isReadyForDisplay {
            performSwitch()
            return
        }

        pendingDisplayObservation = incomingLayer.observe(\.isReadyForDisplay, options: [.new]) { _, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async { performSwitch() }
        }

        let fallbackWorkItem = DispatchWorkItem(block: performSwitch)
        pendingDisplayFallbackWorkItem = fallbackWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: fallbackWorkItem)
    }
}
