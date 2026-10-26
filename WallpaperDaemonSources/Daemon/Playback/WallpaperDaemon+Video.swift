import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func play(videoPath: String, framePath: String?, fillMode: String, shouldLoopCurrentItem: Bool, requestID: Int?, cohortID: UUID? = nil) {
        cancelVideoPreparation()
        switchToken += 1
        let token = switchToken
        // Even a request rejected before AVFoundation work has a preparation
        // identity, so its failure and later cancellation remain correlated.
        videoPreparation = VideoPreparation(token: token, requestID: requestID,
            videoPath: videoPath, incomingSlot: inactiveSlot, previousSlot: activeSlot,
            previousVideoPath: currentVideoPath, previousRequestID: currentRequestID,
            previousFillMode: currentFillMode)
        videoPreparation?.cohortID = cohortID
        videoPreparation?.previousCohortID = currentVideoCohortID
        pendingStatusObservation = nil
        guard FileManager.default.fileExists(atPath: videoPath) else {
            daemonLog("video not found \(videoPath)")
            failVideoPreparation(token: token, requestID: requestID, message: "video_not_found")
            return
        }

        guard let screen = WallpaperDaemon.screen(for: displayID) else {
            daemonLog("screen disappeared \(displayID)")
            failVideoPreparation(token: token, requestID: requestID, message: "screen_not_found")
            shutdown()
            return
        }


        videoPreparation?.targetScreenFrame = screen.frame

        window.setFrame(screen.frame, display: true)
        if currentVideoPath != nil {
            window.level = WallpaperDaemon.desktopWindowLevel
            window.orderFrontRegardless()
        }
        currentFillMode = fillMode
        updateLayerFrames()

        let fallbackGravity: CALayerContentsGravity = .resizeAspectFill
        showFallback(framePath: framePath, gravity: fallbackGravity, fillMode: fillMode)

        let incomingPlayer = inactivePlayer
        clearLooper(for: inactiveSlot)
        incomingPlayer.pause()
        incomingPlayer.removeAllItems()
        incomingPlayer.actionAtItemEnd = shouldLoopCurrentItem ? .advance : .none
        clearPlaybackObservers(for: inactiveSlot)

        let item = AVPlayerItem(url: URL(fileURLWithPath: videoPath))
        item.preferredForwardBufferDuration = 1.5
        item.preferredMaximumResolution = CGSize(width: screen.frame.width, height: screen.frame.height)

        incomingPlayer.volume = 0
        if shouldLoopCurrentItem {
            let looper = AVPlayerLooper(player: incomingPlayer, templateItem: item)
            setInactiveLooper(looper)
        } else {
            incomingPlayer.insert(item, after: nil)
            observePlaybackEnd(for: item, requestID: requestID, videoPath: videoPath, slot: inactiveSlot)
        }
        waitUntilPlayerReady(incomingPlayer, token: token, requestID: requestID, videoPath: videoPath)
    }

    func animateLayerFrameForFillMode(_ fillMode: String) {
        guard let contentBounds = window.contentView?.bounds else { return }
        let targetFrame = layerFrameForFillMode(fillMode, in: contentBounds)

        let layer = activeLayer
        guard layer.opacity > 0,
              targetFrame.width > 0, targetFrame.height > 0 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for l in [primaryLayer, secondaryLayer] { l.frame = targetFrame }
            fallbackLayer.frame = contentBounds
            CATransaction.commit()
            return
        }

        let fromFrame = layer.presentation()?.frame ?? layer.frame

        guard abs(fromFrame.width - targetFrame.width) > 0.5 ||
              abs(fromFrame.height - targetFrame.height) > 0.5 ||
              abs(fromFrame.midX - targetFrame.midX) > 0.5 ||
              abs(fromFrame.midY - targetFrame.midY) > 0.5 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for l in [primaryLayer, secondaryLayer] { l.frame = targetFrame }
            fallbackLayer.frame = contentBounds
            CATransaction.commit()
            return
        }

        let duration: CFTimeInterval = 0.42
        let timing = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)

        let inactive = inactiveLayer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        inactive.frame = targetFrame
        fallbackLayer.frame = contentBounds
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = fromFrame
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(timing)
        layer.frame = targetFrame
        CATransaction.commit()
    }

    func naturalVideoSize(from layer: AVPlayerLayer) -> CGSize? {
        guard let item = layer.player?.currentItem else { return nil }
        let size = item.presentationSize
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    func activatePreparedPlayer(requestID: Int?, videoPath: String?) {
        let incomingPlayer = inactivePlayer
        let incomingLayer = inactiveLayer

        incomingPlayer.volume = 0
        if paused {
            incomingPlayer.pause()
        } else {
            incomingPlayer.rate = playbackRate
        }

        let targetFrame: CGRect
        if let contentBounds = window.contentView?.bounds {
            targetFrame = layerFrameForFillMode(currentFillMode, in: contentBounds, sourceLayer: incomingLayer)
        } else {
            targetFrame = .zero
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        incomingLayer.transform = CATransform3DIdentity
        if targetFrame != .zero { incomingLayer.frame = targetFrame }
        incomingLayer.opacity = 0
        fallbackLayer.opacity = 0
        CATransaction.commit()

        commitVisualSwitchWhenReady(incomingLayer: incomingLayer, targetFrame: targetFrame, requestID: requestID, videoPath: videoPath)
    }
}
