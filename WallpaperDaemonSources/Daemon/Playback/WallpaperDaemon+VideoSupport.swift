import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore

extension WallpaperDaemon {
    func updateLayerFrames() {
        guard let contentBounds = window.contentView?.bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutFallbackLayer(fillMode: currentFillMode, in: contentBounds)
        inactiveLayer.frame = contentBounds
        inactiveLayer.opacity = 0
        CATransaction.commit()
        updateSpectrumLayout()
    }

    func layerFrameForFillMode(_ fillMode: String, in bounds: CGRect, sourceLayer: AVPlayerLayer? = nil) -> CGRect {
        guard fillMode == "aspectFit",
              let size = naturalVideoSize(from: sourceLayer ?? activeLayer) else { return bounds }
        return aspectFitFrame(for: size, in: bounds)
    }

    private func aspectFitFrame(for size: CGSize, in bounds: CGRect) -> CGRect {
        let fit = AVMakeRect(aspectRatio: size, insideRect: bounds)
        let windowFrame = window.frame
        guard let visible = Self.screen(for: displayID)?.visibleFrame.intersection(windowFrame),
              fit.height <= visible.height else { return fit }
        let centerY = bounds.minY + visible.midY - windowFrame.minY
        return fit.offsetBy(dx: 0, dy: centerY - fit.midY)
    }

    func showFallback(framePath: String?, fillMode: String) {
        let image = framePath.flatMap {
            NSImage(contentsOfFile: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.contents = image
        fallbackLayer.opacity = image == nil ? 0 : 1
        if let bounds = window.contentView?.bounds {
            layoutFallbackLayer(fillMode: fillMode, in: bounds)
        }
        CATransaction.commit()
    }

    func layoutFallbackLayer(fillMode: String, in bounds: CGRect) {
        guard let contents = fallbackLayer.contents else { return }
        if fillMode == "aspectFit" {
            // showFallback stores a decoded CGImage, which survives fill changes.
            let image = contents as! CGImage
            fallbackLayer.contentsGravity = .resizeAspect
            fallbackLayer.frame = aspectFitFrame(for: CGSize(width: image.width, height: image.height), in: bounds)
        } else {
            fallbackLayer.contentsGravity = .resizeAspectFill
            fallbackLayer.frame = bounds
        }
    }

    func waitUntilPlayerReady(_ player: AVQueuePlayer, token: Int, requestID: Int?, videoPath: String, attempt: Int = 0) {
        guard switchToken == token else { return }

        if attempt == 0 {
            pendingDisplayFallbackWorkItem?.cancel()
            let timeout = DispatchWorkItem { [weak self] in
                self?.failVideoPreparation(token: token, requestID: requestID, message: "video_item_timeout")
            }
            pendingDisplayFallbackWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        }

        guard let currentItem = player.currentItem else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.waitUntilPlayerReady(player, token: token, requestID: requestID, videoPath: videoPath, attempt: attempt + 1)
            }
            return
        }

        switch currentItem.status {
        case .readyToPlay:
            activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
        case .failed:
            daemonLog("current item failed token=\(token) error=\(currentItem.error?.localizedDescription ?? "unknown")")
            failVideoPreparation(token: token, requestID: requestID, message: "item_failed")
        case .unknown:
            pendingStatusObservation = currentItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    guard let self, self.switchToken == token,
                          self.pendingStatusObservation != nil else { return }
                    switch item.status {
                    case .readyToPlay:
                        self.pendingStatusObservation = nil
                        self.activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
                    case .failed:
                        self.pendingStatusObservation = nil
                        daemonLog("observed item failed token=\(token) error=\(item.error?.localizedDescription ?? "unknown")")
                        self.failVideoPreparation(token: token, requestID: requestID, message: "item_failed")
                    default:
                        break
                    }
                }
            }
        @unknown default:
            daemonLog("unknown player item status token=\(token)")
            failVideoPreparation(token: token, requestID: requestID, message: "video_item_status_unsupported")
        }
    }

    func failVideoPreparation(token: Int, requestID: Int?, message: String) {
        guard switchToken == token, let preparation = videoPreparation,
              preparation.token == token, preparation.requestID == requestID else { return }
        cancelVideoPreparation(requestID: requestID)
        emitVideoPreparation(type: "failed", message: message, preparation: preparation)
    }

    @objc func handleScreenParametersChanged() {
        guard let screen = WallpaperDaemon.screen(for: displayID), window.frame != screen.frame else { return }
        window.setFrame(screen.frame, display: true)
        updateLayerFrames()
    }

    static func makeQueuePlayer() -> AVQueuePlayer {
        let player = AVQueuePlayer()
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.isMuted = false
        return player
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            guard let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenNumber.uint32Value == displayID
        }
    }

    static var desktopWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    }
    /// Policy changes apply to both the candidate and the retained slot. A
    /// rollback must keep the latest user policy, rather than its load snapshot.
    func updateVideoLoopPolicy(_ shouldLoop: Bool) {
        for slot in [Slot.primary, .secondary] {
            let player = slot == .primary ? primaryPlayer : secondaryPlayer
            guard let item = player.currentItem else { continue }
            let path: String?
            let request: Int?
            if let preparation = videoPreparation {
                let incoming = slot == preparation.incomingSlot
                path = incoming ? preparation.videoPath : preparation.previousVideoPath
                request = incoming ? preparation.requestID : preparation.previousRequestID
            } else {
                path = slot == activeSlot ? currentVideoPath : nil
                request = slot == activeSlot ? currentRequestID : nil
            }
            guard let path else { continue }
            let looper = slot == .primary ? primaryLooper : secondaryLooper
            if shouldLoop, looper != nil { continue }
            clearPlaybackObservers(for: slot)
            if !shouldLoop {
                clearLooper(for: slot)
                // disableLooping stops replenishment; queued replicas must also
                // leave so a newly disabled loop ends at the current item.
                for queued in player.items() where queued !== item { player.remove(queued) }
                player.actionAtItemEnd = .pause
                observePlaybackEnd(for: item, requestID: request, videoPath: path, slot: slot)
            } else {
                player.actionAtItemEnd = .pause
                let observation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                    object: item, queue: .main) { [weak self, weak player, weak item] _ in
                    guard let self, let player, let item, player.currentItem === item else { return }
                    player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    if self.activeSlot == slot && !self.paused && self.outputActivityAllowed {
                        player.rate = self.playbackRate
                    }
                }
                if slot == .primary { primaryLoopEndObservation = observation }
                else { secondaryLoopEndObservation = observation }
            }
        }
    }

}
