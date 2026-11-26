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
        currentFillMode = fillMode
        updateLayerFrames()
        if currentVideoPath == nil {
            showFallback(framePath: framePath, gravity: .resizeAspectFill, fillMode: fillMode)
        } else {
            window.level = WallpaperDaemon.desktopWindowLevel
            window.orderFrontRegardless()
        }

        let incomingPlayer = inactivePlayer
        clearLooper(for: inactiveSlot)
        incomingPlayer.pause()
        incomingPlayer.removeAllItems()
        incomingPlayer.actionAtItemEnd = shouldLoopCurrentItem ? .advance : .none
        clearPlaybackObservers(for: inactiveSlot)

        let item = AVPlayerItem(url: URL(fileURLWithPath: videoPath))
        item.preferredForwardBufferDuration = 1.5

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
        let incoming = activeLayer
        let retained = inactiveLayer
        let incomingFrame = layerFrameForFillMode(fillMode, in: contentBounds, sourceLayer: incoming)
        var retainedFrame = layerFrameForFillMode(fillMode, in: contentBounds, sourceLayer: retained)
        var duration: CFTimeInterval = 0.42
        if let preparation = videoPreparation, preparation.isCommitted, !preparation.transitionComplete,
           retained.opacity > 0, !incomingFrame.isEmpty, !retainedFrame.isEmpty {
            retainedFrame = AVMakeRect(aspectRatio: retainedFrame.size, insideRect: incomingFrame)
            let animation = incoming.animation(forKey: "opacity")
            let end = animation.map { $0.beginTime + $0.duration } ?? CACurrentMediaTime()
            duration = min(duration, max(0, end - CACurrentMediaTime()))
        }
        let layouts = [(incoming, incoming.presentation()?.frame ?? incoming.frame, incomingFrame),
                       (retained, retained.presentation()?.frame ?? retained.frame, retainedFrame)]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.frame = contentBounds
        for (layer, from, target) in layouts {
            layer.removeAnimation(forKey: "position")
            layer.removeAnimation(forKey: "bounds")
            layer.frame = layer.opacity > 0 ? from : target
        }
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0))
        for (layer, _, target) in layouts where layer.opacity > 0 {
            layer.frame = target
        }
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
        if targetFrame != .zero { incomingLayer.frame = targetFrame }
        incomingLayer.opacity = 0
        fallbackLayer.contents = nil
        fallbackLayer.opacity = 0
        CATransaction.commit()

        commitVisualSwitchWhenReady(incomingLayer: incomingLayer, targetFrame: targetFrame, requestID: requestID, videoPath: videoPath)
    }
}
