import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import WebKit
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func play(videoPath: String, framePath: String?, fillMode: String, shouldLoopCurrentItem: Bool, requestID: Int?) {
        guard FileManager.default.fileExists(atPath: videoPath) else {
            daemonLog("video not found \(videoPath)")
            emit(type: "failed", requestID: requestID, message: "video_not_found", videoPath: videoPath, contentKind: "video")
            return
        }

        guard let screen = WallpaperDaemon.screen(for: displayID) else {
            daemonLog("screen disappeared \(displayID)")
            emit(type: "failed", requestID: requestID, message: "screen_not_found", videoPath: videoPath, contentKind: "video")
            shutdown()
            return
        }


        switchToken += 1
        let token = switchToken
        pendingStatusObservation = nil

        configureWindowForVideoRendering()
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        window.level = WallpaperDaemon.desktopWindowLevel
        currentFillMode = fillMode
        updateLayerFrames()

        let fallbackGravity: CALayerContentsGravity = .resizeAspectFill
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryLayer.videoGravity = .resizeAspectFill
        secondaryLayer.videoGravity = .resizeAspectFill
        CATransaction.commit()

        showFallback(framePath: framePath, gravity: fallbackGravity, fillMode: fillMode)

        let incomingPlayer = inactivePlayer
        incomingPlayer.pause()
        incomingPlayer.removeAllItems()
        incomingPlayer.actionAtItemEnd = shouldLoopCurrentItem ? .advance : .none
        setInactiveLooper(nil)
        if let pendingEndObservation {
            NotificationCenter.default.removeObserver(pendingEndObservation)
            self.pendingEndObservation = nil
        }
        if let loopEndObservation {
            NotificationCenter.default.removeObserver(loopEndObservation)
            self.loopEndObservation = nil
        }

        let item = AVPlayerItem(url: URL(fileURLWithPath: videoPath))
        item.preferredForwardBufferDuration = 1.5
        item.preferredMaximumResolution = CGSize(width: screen.frame.width, height: screen.frame.height)

        incomingPlayer.volume = currentVolume
        if shouldLoopCurrentItem {
            let looper = AVPlayerLooper(player: incomingPlayer, templateItem: item)
            setInactiveLooper(looper)
        } else {
            incomingPlayer.insert(item, after: nil)
            observePlaybackEnd(for: item, requestID: requestID, videoPath: videoPath)
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

    func animateFillModeTransitionIfNeeded(to newGravity: AVLayerVideoGravity, bounds: CGRect) {
        let layer = activeLayer
        guard layer.opacity > 0,
              layer.videoGravity != newGravity,
              let videoSize = naturalVideoSize(from: layer),
              videoSize.width > 0, videoSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }

        let fromRect = renderedRect(for: layer.videoGravity, videoSize: videoSize, bounds: bounds)
        let toRect = renderedRect(for: newGravity, videoSize: videoSize, bounds: bounds)
        guard fromRect.width > 0, toRect.width > 0 else { return }

        let scaleX = fromRect.width / toRect.width
        let scaleY = fromRect.height / toRect.height
        let tx = fromRect.midX - toRect.midX
        let ty = fromRect.midY - toRect.midY
        let startTransform = CATransform3DTranslate(CATransform3DMakeScale(scaleX, scaleY, 1), tx / scaleX, ty / scaleY, 0)

        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = startTransform
        anim.toValue = CATransform3DIdentity
        anim.duration = 0.32
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
        anim.fillMode = .backwards
        anim.isRemovedOnCompletion = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        layer.add(anim, forKey: "fillModeTransition")
    }

    func renderedRect(for gravity: AVLayerVideoGravity, videoSize: CGSize, bounds: CGRect) -> CGRect {
        let boundsAspect = bounds.width / bounds.height
        let videoAspect = videoSize.width / videoSize.height

        switch gravity {
        case .resizeAspect:
            if videoAspect > boundsAspect {
                let h = bounds.width / videoAspect
                return CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
            } else {
                let w = bounds.height * videoAspect
                return CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
            }
        case .resizeAspectFill:
            if videoAspect > boundsAspect {
                let w = bounds.height * videoAspect
                return CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
            } else {
                let h = bounds.width / videoAspect
                return CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
            }
        default:
            return bounds
        }
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

        if let vp = videoPath {
            currentVideoPath = vp
            currentRequestID = requestID
        }

        incomingPlayer.volume = currentVolume
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
