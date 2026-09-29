import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func finishVisualSwitch(targetFrame: CGRect, requestID: Int?, videoPath: String?) {
        let incomingLayer = inactiveLayer
        let outgoingLayer = activeLayer
        let isFirstPlay = outgoingLayer.opacity == 0
        let timing = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)

        let previousSlot = activeSlot
        activeSlot = activeSlot == .primary ? .secondary : .primary

        let cleanupOutgoing = { [weak self] in
            guard let self else { return }
            switch previousSlot {
            case .primary:
                self.primaryPlayer.pause()
                self.primaryPlayer.removeAllItems()
            case .secondary:
                self.secondaryPlayer.pause()
                self.secondaryPlayer.removeAllItems()
            }
            self.clearLooper(for: previousSlot)
        }

        guard !isFirstPlay else {
            currentVideoPath = videoPath
            currentRequestID = requestID
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            incomingLayer.opacity = 1
            outgoingLayer.opacity = 0
            fallbackLayer.opacity = 0
            CATransaction.commit()
            emit(type: "ready", requestID: requestID, message: nil, videoPath: videoPath, contentKind: "video")
            DispatchQueue.main.asyncAfter(deadline: .now() + crossfadeDuration, execute: cleanupOutgoing)
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

            self.emit(type: "ready", requestID: requestID, message: nil, videoPath: videoPath, contentKind: "video")
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
        emit(type: "ready", requestID: requestID, message: nil, videoPath: videoPath, contentKind: "video")
        DispatchQueue.main.asyncAfter(deadline: .now() + animDuration) { [weak self] in
            guard self != nil else { return }
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
            primaryLooper = nil
        case .secondary:
            secondaryLooper = nil
        }
    }

    func observePlaybackEnd(for item: AVPlayerItem, requestID: Int?, videoPath: String) {
        pendingEndObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            daemonLog("playbackEnded fired for \(videoPath)")
            self.pendingEndObservation = nil
            self.emit(type: "ended", requestID: requestID, message: nil, videoPath: videoPath, contentKind: "video")
        }
    }
}
