import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func commitVisualSwitchWhenReady(incomingLayer: AVPlayerLayer, targetFrame: CGRect, requestID: Int?, videoPath: String?) {
        let token = switchToken
        pendingDisplayObservation = nil
        pendingDisplayFallbackWorkItem?.cancel()

        let performSwitch = { [weak self] in
            guard let self, self.switchToken == token,
                  self.videoPreparation?.requestID == requestID,
                  self.videoPreparation?.isPrepared == false,
                  self.videoPreparation?.isSeekingToStart == false else { return }
            self.pendingDisplayObservation = nil
            guard incomingLayer.isReadyForDisplay, let player = incomingLayer.player else { return }
            // Decode just enough to obtain a real frame, then freeze at the
            // author's start. Waiting for another display/parent must not run
            // a short candidate to its end before the visual commit.
            self.videoPreparation?.isSeekingToStart = true
            player.pause()
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                DispatchQueue.main.async {
                    guard let self, self.switchToken == token,
                          self.videoPreparation?.requestID == requestID else { return }
                    self.pendingDisplayFallbackWorkItem?.cancel()
                    self.pendingDisplayFallbackWorkItem = nil
                    guard finished else {
                        self.cancelVideoPreparation(requestID: requestID)
                        self.emit(type: "failed", requestID: requestID, message: "video_seek_failed", videoPath: videoPath, contentKind: "video")
                        return
                    }
                    self.videoPreparation?.targetFrame = targetFrame
                    self.videoPreparation?.isSeekingToStart = false
                    self.videoPreparation?.isPrepared = true
                    self.emit(type: "prepared", requestID: requestID, message: nil, videoPath: videoPath, contentKind: "video")
                }
            }
        }

        let fallbackWorkItem = DispatchWorkItem { [weak self] in
            guard let self, self.switchToken == token,
                  self.videoPreparation?.isPrepared == false else { return }
            self.cancelVideoPreparation(requestID: requestID)
            self.emit(type: "failed", requestID: requestID, message: "video_frame_timeout", videoPath: videoPath, contentKind: "video")
        }
        pendingDisplayFallbackWorkItem = fallbackWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: fallbackWorkItem)

        if incomingLayer.isReadyForDisplay {
            performSwitch()
            return
        }

        pendingDisplayObservation = incomingLayer.observe(\.isReadyForDisplay, options: [.new]) { _, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async { performSwitch() }
        }

    }
}
