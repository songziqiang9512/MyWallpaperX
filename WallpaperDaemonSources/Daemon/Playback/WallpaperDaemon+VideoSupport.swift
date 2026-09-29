import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore

extension WallpaperDaemon {
    func updateLayerFrames() {
        guard let contentBounds = window.contentView?.bounds else { return }
        fallbackLayer.frame = contentBounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        inactiveLayer.frame = contentBounds
        inactiveLayer.opacity = 0
        CATransaction.commit()
        updateSpectrumLayout()
    }

    func layerFrameForFillMode(_ fillMode: String, in bounds: CGRect, sourceLayer: AVPlayerLayer? = nil) -> CGRect {
        let layerForSize = sourceLayer ?? activeLayer
        guard fillMode == "aspectFit",
              let videoSize = naturalVideoSize(from: layerForSize),
              videoSize.width > 0, videoSize.height > 0 else {
            return bounds
        }
        let boundsAspect = bounds.width / bounds.height
        let videoAspect = videoSize.width / videoSize.height
        let w: CGFloat
        let h: CGFloat
        if videoAspect > boundsAspect {
            w = bounds.width
            h = bounds.width / videoAspect
        } else {
            h = bounds.height
            w = bounds.height * videoAspect
        }
        let screen = NSScreen.screens.first { $0.frame.origin == window.frame.origin && $0.frame.size == window.frame.size }
                  ?? NSScreen.screens.first { NSMouseInRect(window.frame.origin, $0.frame, false) }
                  ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? bounds

        let centerY: CGFloat
        if h <= visibleFrame.height {
            let visibleMinY = visibleFrame.minY - window.frame.minY
            let visibleMaxY = visibleFrame.maxY - window.frame.minY
            centerY = (visibleMinY + visibleMaxY) / 2
        } else {
            centerY = bounds.height / 2
        }

        let x = (bounds.width - w) / 2
        let y = centerY - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    func showFallback(framePath: String?, gravity: CALayerContentsGravity, fillMode: String? = nil) {
        fallbackLayer.contentsGravity = gravity
        guard let framePath,
              FileManager.default.fileExists(atPath: framePath),
              let image = NSImage(contentsOfFile: framePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fallbackLayer.contents = nil
            fallbackLayer.opacity = 0
            return
        }

        if fillMode == "aspectFit",
           let contentBounds = window.contentView?.bounds {
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            if imageSize.width > 0, imageSize.height > 0 {
                let imageAspect = imageSize.width / imageSize.height
                let boundsAspect = contentBounds.width / contentBounds.height
                let w: CGFloat
                let h: CGFloat
                if imageAspect > boundsAspect {
                    w = contentBounds.width
                    h = contentBounds.width / imageAspect
                } else {
                    h = contentBounds.height
                    w = contentBounds.height * imageAspect
                }
                let screen = NSScreen.screens.first { $0.frame.origin == window.frame.origin && $0.frame.size == window.frame.size }
                    ?? NSScreen.main
                let visibleFrame = screen?.visibleFrame ?? contentBounds
                let visibleMinY = visibleFrame.minY - window.frame.minY
                let visibleMaxY = visibleFrame.maxY - window.frame.minY
                let centerY = (visibleMinY + visibleMaxY) / 2
                let fallbackFrame = CGRect(x: (contentBounds.width - w) / 2, y: centerY - h / 2, width: w, height: h)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                fallbackLayer.frame = fallbackFrame
                fallbackLayer.contents = cgImage
                fallbackLayer.opacity = 1
                CATransaction.commit()
                return
            }
        }

        if let contentBounds = window.contentView?.bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fallbackLayer.frame = contentBounds
            CATransaction.commit()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.contents = cgImage
        fallbackLayer.opacity = 1
        CATransaction.commit()
    }

    func waitUntilPlayerReady(_ player: AVQueuePlayer, token: Int, requestID: Int?, videoPath: String, attempt: Int = 0) {
        guard switchToken == token else { return }

        guard let currentItem = player.currentItem else {
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    self?.waitUntilPlayerReady(player, token: token, requestID: requestID, videoPath: videoPath, attempt: attempt + 1)
                }
            } else {
                daemonLog("fallback activate without currentItem token=\(token)")
                activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
            }
            return
        }

        switch currentItem.status {
        case .readyToPlay:
            activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
        case .failed:
            daemonLog("current item failed token=\(token) error=\(currentItem.error?.localizedDescription ?? "unknown")")
            emit(type: "failed", requestID: requestID, message: "item_failed", videoPath: videoPath, contentKind: "video")
        case .unknown:
            pendingStatusObservation = currentItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self else { return }
                guard self.switchToken == token else { return }
                switch item.status {
                case .readyToPlay:
                    self.pendingStatusObservation = nil
                    DispatchQueue.main.async {
                        guard self.switchToken == token else { return }
                        self.activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
                    }
                case .failed:
                    self.pendingStatusObservation = nil
                    daemonLog("observed item failed token=\(token) error=\(item.error?.localizedDescription ?? "unknown")")
                    self.emit(type: "failed", requestID: requestID, message: "item_failed", videoPath: videoPath, contentKind: "video")
                default:
                    break
                }
            }
        @unknown default:
            daemonLog("unknown player item status token=\(token)")
            activatePreparedPlayer(requestID: requestID, videoPath: videoPath)
        }
    }

    @objc func handleScreenParametersChanged() {
        guard let screen = WallpaperDaemon.screen(for: displayID) else { return }
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
}
