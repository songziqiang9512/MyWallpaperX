import AppKit
import AVFoundation
import QuartzCore

extension WallpaperDaemon {
    /// The previous slot remains recoverable until the parent acknowledges
    /// this exact visual commit. A newer intent can cancel even after ready.
    func commitVideoPreparation(requestID: Int?, activationID: UUID? = nil,
                                generation: UInt64? = nil, cohortID: UUID? = nil) {
        guard let preparation = videoPreparation,
              preparation.requestID == requestID, preparation.isPrepared,
              !preparation.isCommitted,
              generation == nil || generation == UInt64(preparation.token),
              cohortID == nil || cohortID == preparation.cohortID else { return }
        if cohortID != nil {
            guard generation == UInt64(preparation.token), activationID != nil,
                  cohortID == preparation.cohortID else { return }
        }
        videoPreparation?.activationID = activationID ?? UUID()
        outputActivityAllowed = true
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
        guard preparation.visibilityConfirmed else { return }
        videoPreparation?.isFinalized = true
        window.level = Self.desktopWindowLevel
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
        stopActivationVisibilityCheck()
        switchToken += 1
        pendingStatusObservation = nil
        pendingDisplayObservation = nil
        pendingDisplayFallbackWorkItem?.cancel()
        pendingDisplayFallbackWorkItem = nil
        rememberCancelledPreparation(preparation)
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
            currentVideoCohortID = preparation.previousCohortID
        }
        currentFillMode = preparation.previousFillMode
        window.alphaValue = 1
        if let screen = Self.screen(for: displayID) { window.setFrame(screen.frame, display: true) }
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
        activePlayer.volume = outputActivityAllowed ? currentVolume : 0
        if paused || !outputActivityAllowed { activePlayer.pause() }
        else { activePlayer.rate = playbackRate }
        window.level = currentVideoPath == nil
            ? NSWindow.Level(rawValue: Self.desktopWindowLevel.rawValue - 2)
            : Self.desktopWindowLevel
    }

    func clearVideoSlot(_ slot: Slot) {
        let player = slot == .primary ? primaryPlayer : secondaryPlayer
        let layer = slot == .primary ? primaryLayer : secondaryLayer
        clearLooper(for: slot)
        player.pause()
        player.removeAllItems()
        player.volume = 0
        layer.removeAllAnimations()
        layer.opacity = 0
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
