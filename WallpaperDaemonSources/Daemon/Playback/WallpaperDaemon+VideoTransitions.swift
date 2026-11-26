import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func finishVisualSwitch(targetFrame: CGRect, requestID: Int?, videoPath: String?) {
        guard let preparation = videoPreparation, preparation.isCommitted,
              preparation.requestID == requestID else { return }
        let token = preparation.token
        let incomingLayer = inactiveLayer
        let outgoingLayer = activeLayer
        let isFirstPlay = outgoingLayer.opacity == 0

        activeSlot = activeSlot == .primary ? .secondary : .primary
        currentVideoPath = videoPath
        currentRequestID = requestID
        currentVideoCohortID = preparation.cohortID
        window.level = PlaybackSurfaceVisibility.activationLevel(normal: Self.desktopWindowLevel)
        window.orderFrontRegardless()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The outgoing picture stays opaque beneath the incoming fade.
        outgoingLayer.zPosition = 1
        incomingLayer.zPosition = 2
        incomingLayer.frame = targetFrame
        incomingLayer.opacity = 1
        guard !isFirstPlay else {
            CATransaction.commit()
            completeVideoTransition(token: token)
            confirmVideoActivationWhenVisible(requestID: requestID)
            return
        }

        let outFrame = outgoingLayer.presentation()?.frame ?? outgoingLayer.frame
        let needsFrameAnim = !targetFrame.isEmpty && !outFrame.isEmpty
            && (abs(outFrame.width - targetFrame.width) > 0.5
                || abs(outFrame.height - targetFrame.height) > 0.5
                || abs(outFrame.midX - targetFrame.midX) > 0.5
                || abs(outFrame.midY - targetFrame.midY) > 0.5)

        let duration = needsFrameAnim ? 0.55 : crossfadeDuration
        let beginTime = CACurrentMediaTime()
        let opacityTiming = needsFrameAnim
            ? CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.6, 1.0)
            : CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
        func animate(_ layer: CALayer, _ keyPath: String, from: Any, to: Any, timing: CAMediaTimingFunction) {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = timing
            animation.beginTime = beginTime
            animation.fillMode = .backwards
            layer.add(animation, forKey: keyPath)
        }

        if needsFrameAnim {
            let timing = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            let incomingStart = AVMakeRect(aspectRatio: targetFrame.size, insideRect: outFrame)
            // Any retained picture must be inside the incoming picture when it is hidden.
            outgoingLayer.frame = AVMakeRect(aspectRatio: outFrame.size, insideRect: targetFrame)
            for (layer, from) in [(outgoingLayer, outFrame), (incomingLayer, incomingStart)] {
                let fromCenter = CGPoint(x: from.midX, y: from.midY)
                animate(layer, "position", from: fromCenter, to: layer.position, timing: timing)
                let fromBounds = CGRect(origin: layer.bounds.origin, size: from.size)
                animate(layer, "bounds", from: fromBounds, to: layer.bounds, timing: timing)
            }
        }
        animate(incomingLayer, "opacity", from: 0, to: 1, timing: opacityTiming)
        CATransaction.commit()

        confirmVideoActivationWhenVisible(requestID: requestID)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.completeVideoTransition(token: token)
        }
    }

    func clearLooper(for slot: Slot) {
        switch slot {
        case .primary:
            primaryLooper?.disableLooping()
            primaryLooper = nil
        case .secondary:
            secondaryLooper?.disableLooping()
            secondaryLooper = nil
        }
    }

    func observePlaybackEnd(for item: AVPlayerItem, requestID: Int?, videoPath: String, slot: Slot) {
        let observation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.activeSlot == slot,
                  self.currentRequestID == requestID,
                  self.currentVideoPath == videoPath else { return }
            daemonLog("playbackEnded fired for \(videoPath)")
            self.clearPlaybackObservers(for: slot)
            self.emit(type: "ended", requestID: requestID, message: nil, videoPath: videoPath, contentKind: "video")
        }
        if slot == .primary { primaryEndObservation = observation }
        else { secondaryEndObservation = observation }
    }
}
