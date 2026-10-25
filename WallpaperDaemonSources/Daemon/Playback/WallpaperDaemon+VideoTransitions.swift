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
        let timing = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)

        activeSlot = activeSlot == .primary ? .secondary : .primary
        currentVideoPath = videoPath
        currentRequestID = requestID
        currentVideoCohortID = preparation.cohortID
        window.level = PlaybackSurfaceVisibility.activationLevel(normal: Self.desktopWindowLevel)
        window.orderFrontRegardless()

        let cleanupOutgoing: () -> Void = { [weak self] in
            self?.completeVideoTransition(token: token)
        }

        guard !isFirstPlay else {
            currentVideoPath = videoPath
            currentRequestID = requestID
            window.level = PlaybackSurfaceVisibility.activationLevel(normal: Self.desktopWindowLevel)
            window.orderFrontRegardless()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            incomingLayer.opacity = 1
            outgoingLayer.opacity = 0
            fallbackLayer.opacity = 0
            CATransaction.commit()
            cleanupOutgoing()
            confirmVideoActivationWhenVisible(requestID: requestID)
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.opacity = 0
        CATransaction.commit()

        let outFrame = outgoingLayer.presentation()?.frame ?? outgoingLayer.frame
        let needsFrameAnim = targetFrame != .zero
            && (abs(outFrame.width - targetFrame.width) > 0.5
                || abs(outFrame.height - targetFrame.height) > 0.5
                || abs(outFrame.midX - targetFrame.midX) > 0.5
                || abs(outFrame.midY - targetFrame.midY) > 0.5)

        let doCrossfade = { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            incomingLayer.opacity = 0
            outgoingLayer.opacity = 1
            CATransaction.commit()

            CATransaction.begin()
            CATransaction.setAnimationDuration(self.crossfadeDuration)
            CATransaction.setAnimationTimingFunction(timing)
            incomingLayer.opacity = 1
            outgoingLayer.opacity = 0
            CATransaction.commit()

            self.confirmVideoActivationWhenVisible(requestID: requestID)
            DispatchQueue.main.asyncAfter(deadline: .now() + self.crossfadeDuration, execute: cleanupOutgoing)
        }

        guard needsFrameAnim else {
            doCrossfade()
            return
        }

        let scaleX = targetFrame.width / outFrame.width
        let scaleY = targetFrame.height / outFrame.height
        let animDuration: CFTimeInterval = 0.55
        let transformTiming = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
        let opacityTiming = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.6, 1.0)
        let outMid = CGPoint(x: outFrame.midX, y: outFrame.midY)
        let targetMid = CGPoint(x: targetFrame.midX, y: targetFrame.midY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outgoingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        outgoingLayer.frame = outFrame
        outgoingLayer.transform = CATransform3DIdentity
        outgoingLayer.opacity = 0
        incomingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        incomingLayer.frame = targetFrame
        incomingLayer.transform = CATransform3DIdentity
        incomingLayer.opacity = 1
        CATransaction.commit()

        let now = CACurrentMediaTime()

        let outPosAnim = CABasicAnimation(keyPath: "position")
        outPosAnim.fromValue = outMid
        outPosAnim.toValue = targetMid
        outPosAnim.duration = animDuration
        outPosAnim.timingFunction = transformTiming
        outPosAnim.fillMode = .backwards
        outPosAnim.isRemovedOnCompletion = true
        outPosAnim.beginTime = now

        let outScaleAnim = CABasicAnimation(keyPath: "transform")
        outScaleAnim.fromValue = CATransform3DIdentity
        outScaleAnim.toValue = CATransform3DMakeScale(scaleX, scaleY, 1)
        outScaleAnim.duration = animDuration
        outScaleAnim.timingFunction = transformTiming
        outScaleAnim.fillMode = .backwards
        outScaleAnim.isRemovedOnCompletion = true
        outScaleAnim.beginTime = now

        let outOpacityAnim = CABasicAnimation(keyPath: "opacity")
        outOpacityAnim.fromValue = 1
        outOpacityAnim.toValue = 0
        outOpacityAnim.duration = animDuration
        outOpacityAnim.timingFunction = opacityTiming
        outOpacityAnim.fillMode = .backwards
        outOpacityAnim.isRemovedOnCompletion = true
        outOpacityAnim.beginTime = now

        let inPosAnim = CABasicAnimation(keyPath: "position")
        inPosAnim.fromValue = outMid
        inPosAnim.toValue = targetMid
        inPosAnim.duration = animDuration
        inPosAnim.timingFunction = transformTiming
        inPosAnim.fillMode = .backwards
        inPosAnim.isRemovedOnCompletion = true
        inPosAnim.beginTime = now

        let inStartScaleX = outFrame.width / targetFrame.width
        let inStartScaleY = outFrame.height / targetFrame.height
        let inScaleAnim = CABasicAnimation(keyPath: "transform")
        inScaleAnim.fromValue = CATransform3DMakeScale(inStartScaleX, inStartScaleY, 1)
        inScaleAnim.toValue = CATransform3DIdentity
        inScaleAnim.duration = animDuration
        inScaleAnim.timingFunction = transformTiming
        inScaleAnim.fillMode = .backwards
        inScaleAnim.isRemovedOnCompletion = true
        inScaleAnim.beginTime = now

        let inOpacityAnim = CABasicAnimation(keyPath: "opacity")
        inOpacityAnim.fromValue = 0
        inOpacityAnim.toValue = 1
        inOpacityAnim.duration = animDuration
        inOpacityAnim.timingFunction = opacityTiming
        inOpacityAnim.fillMode = .backwards
        inOpacityAnim.isRemovedOnCompletion = true
        inOpacityAnim.beginTime = now

        outgoingLayer.add(outPosAnim, forKey: "switchOutPosition")
        outgoingLayer.add(outScaleAnim, forKey: "switchOutTransform")
        outgoingLayer.add(outOpacityAnim, forKey: "switchOutOpacity")
        incomingLayer.add(inPosAnim, forKey: "switchInPosition")
        incomingLayer.add(inScaleAnim, forKey: "switchInTransform")
        incomingLayer.add(inOpacityAnim, forKey: "switchInOpacity")

        currentVideoPath = videoPath
        currentRequestID = requestID
        confirmVideoActivationWhenVisible(requestID: requestID)
        DispatchQueue.main.asyncAfter(deadline: .now() + animDuration) { [weak self] in
            guard let self, self.switchToken == token,
                  self.videoPreparation?.token == token else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            incomingLayer.transform = CATransform3DIdentity
            outgoingLayer.transform = CATransform3DIdentity
            outgoingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            incomingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            CATransaction.commit()
            cleanupOutgoing()
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

    func observePlaybackEnd(for item: AVPlayerItem, requestID: Int?, videoPath: String, slot: Slot? = nil) {
        let slot = slot ?? activeSlot
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
