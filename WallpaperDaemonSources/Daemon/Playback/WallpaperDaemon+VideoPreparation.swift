import AppKit
import AVFoundation
import QuartzCore

extension WallpaperDaemon {
    /// The previous slot remains recoverable until the parent acknowledges
    /// this exact visual commit. A newer intent can cancel even after ready.
    func commitVideoPreparation(requestID: Int?) {
        guard let preparation = videoPreparation,
              preparation.requestID == requestID, preparation.isPrepared,
              !preparation.isCommitted else { return }
        videoPreparation?.isCommitted = true
        activePlayer.volume = 0
        inactivePlayer.volume = currentVolume
        if paused { inactivePlayer.pause() }
        else { inactivePlayer.rate = playbackRate }
        let targetFrame = window.contentView.map {
            layerFrameForFillMode(currentFillMode, in: $0.bounds, sourceLayer: inactiveLayer)
        } ?? preparation.targetFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        inactiveLayer.frame = targetFrame
        CATransaction.commit()
        finishVisualSwitch(targetFrame: targetFrame,
            requestID: requestID, videoPath: preparation.videoPath)
    }

    func finalizeVideoPreparation(requestID: Int?) {
        guard let preparation = videoPreparation,
              preparation.requestID == requestID, preparation.isCommitted,
              !preparation.isFinalized else { return }
        videoPreparation?.isFinalized = true
        if preparation.transitionComplete { completeVideoTransition(token: preparation.token) }
    }

    func completeVideoTransition(token: Int) {
        guard let preparation = videoPreparation, preparation.token == token,
              switchToken == token else { return }
        videoPreparation?.transitionComplete = true
        guard preparation.isFinalized else { return }
        clearVideoSlot(preparation.previousSlot)
        videoPreparation = nil
    }

    func cancelVideoPreparation(requestID: Int? = nil) {
        guard let preparation = videoPreparation,
              requestID == nil || preparation.requestID == requestID else { return }
        switchToken += 1
        pendingStatusObservation = nil
        pendingDisplayObservation = nil
        pendingDisplayFallbackWorkItem?.cancel()
        pendingDisplayFallbackWorkItem = nil
        videoPreparation = nil
        if preparation.isFinalized {
            clearVideoSlot(preparation.previousSlot)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            activeLayer.removeAllAnimations()
            activeLayer.transform = CATransform3DIdentity
            activeLayer.opacity = 1
            CATransaction.commit()
            return
        }
        if preparation.isCommitted {
            activeSlot = preparation.previousSlot
            currentVideoPath = preparation.previousVideoPath
            currentRequestID = preparation.previousRequestID
        }
        currentFillMode = preparation.previousFillMode
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [primaryLayer, secondaryLayer] {
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.opacity = layer === activeLayer && currentVideoPath != nil ? 1 : 0
        }
        if let bounds = window.contentView?.bounds {
            activeLayer.frame = layerFrameForFillMode(currentFillMode, in: bounds)
        }
        fallbackLayer.opacity = 0
        CATransaction.commit()
        clearVideoSlot(preparation.incomingSlot)
        activePlayer.volume = currentVolume
        if paused { activePlayer.pause() }
        else { activePlayer.rate = playbackRate }
        window.level = currentVideoPath == nil
            ? NSWindow.Level(rawValue: Self.desktopWindowLevel.rawValue - 2)
            : Self.desktopWindowLevel
    }

    func clearVideoSlot(_ slot: Slot) {
        let player = slot == .primary ? primaryPlayer : secondaryPlayer
        let layer = slot == .primary ? primaryLayer : secondaryLayer
        player.pause()
        player.removeAllItems()
        player.volume = 0
        layer.removeAllAnimations()
        layer.opacity = 0
        clearLooper(for: slot)
        clearPlaybackObservers(for: slot)
    }

    func clearPlaybackObservers(for slot: Slot) {
        let end = slot == .primary ? primaryEndObservation : secondaryEndObservation
        let loop = slot == .primary ? primaryLoopEndObservation : secondaryLoopEndObservation
        if let end { NotificationCenter.default.removeObserver(end) }
        if let loop { NotificationCenter.default.removeObserver(loop) }
        if slot == .primary { primaryEndObservation = nil; primaryLoopEndObservation = nil }
        else { secondaryEndObservation = nil; secondaryLoopEndObservation = nil }
    }
}
