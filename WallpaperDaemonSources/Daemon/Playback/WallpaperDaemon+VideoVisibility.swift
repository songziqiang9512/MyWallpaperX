import AppKit
import AVFoundation
import Foundation
import QuartzCore

extension WallpaperDaemon {
    func matchesVideoPreparation(_ command: DaemonCommand) -> Bool {
        guard let preparation = videoPreparation, preparation.requestID == command.requestID,
              command.cohortID == nil || preparation.cohortID == command.cohortID,
              command.preparationGeneration == nil || command.preparationGeneration == UInt64(preparation.token),
              command.activationID == nil || preparation.activationID == nil
                || command.activationID == preparation.activationID else { return false }
        if preparation.isCommitted, preparation.cohortID != nil {
            return command.cohortID == preparation.cohortID
                && command.preparationGeneration == UInt64(preparation.token)
                && command.activationID == preparation.activationID
        }
        return true
    }

    func emitVideoPreparation(type: String, message: String? = nil,
                              preparation: VideoPreparation? = nil,
                              visibility: [PlaybackSurfaceVisibility.Evidence]? = nil) {
        guard let preparation = preparation ?? videoPreparation else { return }
        var event = DaemonEvent(type: type, displayID: displayID, requestID: preparation.requestID,
            message: message, videoPath: preparation.videoPath, contentKind: "video")
        event.activationID = preparation.activationID
        event.preparationGeneration = UInt64(preparation.token)
        event.cohortID = preparation.cohortID
        event.visibility = visibility
        write(event)
    }

    func confirmVideoActivationWhenVisible(requestID: Int?) {
        guard let preparation = videoPreparation, preparation.requestID == requestID,
              preparation.isCommitted, !preparation.visibilityConfirmed else { return }
        stopActivationVisibilityCheck()
        let token = preparation.token
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.videoPreparation?.token == token else { return }
            self.failVideoActivation(reason: "video_activation_timeout")
        }
        activationVisibilityDeadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        checkVideoActivationVisibility(token: token)
    }

    private func checkVideoActivationVisibility(token: Int) {
        guard let preparation = videoPreparation, preparation.token == token,
              switchToken == token, preparation.isCommitted, !preparation.visibilityConfirmed else { return }
        activationVisibilityWorkItem?.cancel(); activationVisibilityWorkItem = nil
        if let targetFrame = preparation.targetScreenFrame,
           Self.screen(for: displayID)?.frame != targetFrame {
            failVideoActivation(reason: "video_activation_topology_changed"); return
        }
        let expected = PlaybackSurfaceVisibility.activationLevel(normal: Self.desktopWindowLevel)
        let evidence = MainActor.assumeIsolated {
            PlaybackSurfaceVisibility.observe(window: window, displayID: displayID,
                                              expectedLevel: expected.rawValue)
        }
        let decision = PlaybackSurfaceVisibility.evaluate(evidence)
        if decision == .deferredOffSpace {
            failVideoActivation(reason: "video_activation_deferred_inactive_space", deferred: true)
            return
        }
        // Window registration does not prove that the incoming layer has
        // completed the existing crossfade or still owns its decoded frame.
        if decision == .confirmed, preparation.transitionComplete,
           activeLayer.isReadyForDisplay, activeLayer.opacity >= 0.99,
           (activeLayer.presentation()?.opacity ?? activeLayer.opacity) >= 0.99 {
            videoPreparation?.visibilityConfirmed = true
            stopActivationVisibilityCheck()
            emitVideoPreparation(type: "ready", visibility: [evidence])
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.checkVideoActivationVisibility(token: token) }
        activationVisibilityWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func failVideoActivation(reason: String, deferred: Bool = false) {
        guard let preparation = videoPreparation else { return }
        outputActivityAllowed = false
        cancelVideoPreparation(requestID: preparation.requestID)
        emitVideoPreparation(type: deferred ? "activationDeferred" : "failed", message: reason,
                             preparation: preparation)
    }

    func stopActivationVisibilityCheck() {
        activationVisibilityWorkItem?.cancel(); activationVisibilityWorkItem = nil
        activationVisibilityDeadline?.cancel(); activationVisibilityDeadline = nil
    }

    func cancelVideoPreparationCommand(_ command: DaemonCommand) {
        if matchesVideoPreparation(command), videoPreparation?.isFinalized == false {
            // Typed cancellation withdraws the candidate's audio grant before
            // restoring the old picture. The parent separately restores old activity.
            if command.cohortID != nil || command.activationID != nil { outputActivityAllowed = false }
            cancelVideoPreparation(requestID: command.requestID)
            lastVideoCancellation = command
        } else if lastVideoCancellation?.requestID != command.requestID
                    || lastVideoCancellation?.cohortID != command.cohortID
                    || (command.preparationGeneration != nil
                        && lastVideoCancellation?.preparationGeneration != command.preparationGeneration)
                    || (lastVideoCancellation?.activationID != nil
                        && lastVideoCancellation?.activationID != command.activationID) {
            return
        }
        emitVideoCommandAcknowledgement(type: "cancelled", command: command)
    }

    func rememberCancelledPreparation(_ preparation: VideoPreparation) {
        var command = DaemonCommand(action: "cancelVideoPreparation", videoPath: nil,
            framePath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil,
            volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil,
            spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil,
            spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: preparation.requestID)
        command.cohortID = preparation.cohortID
        command.activationID = preparation.activationID
        command.preparationGeneration = UInt64(preparation.token)
        lastVideoCancellation = command
    }

    func setOutputActivity(_ command: DaemonCommand) {
        guard let active = command.outputActive, let id = command.activityID else { return }
        let ownsActive = (command.requestID == nil || command.requestID == currentRequestID)
            && (command.cohortID == nil || command.cohortID == currentVideoCohortID)
        let ownsRetained = !active && command.requestID == videoPreparation?.previousRequestID
            && (command.cohortID == nil || command.cohortID == videoPreparation?.previousCohortID)
        guard ownsActive || ownsRetained else { return }
        currentActivityID = id
        if ownsActive {
            outputActivityAllowed = active
            for player in players { player.volume = 0; player.pause() }
            if active {
                activePlayer.volume = currentVolume
                if !paused { activePlayer.rate = playbackRate }
            }
            window.ignoresMouseEvents = true
        }
        emitVideoCommandAcknowledgement(type: "outputActivityChanged", command: command)
    }

    private func emitVideoCommandAcknowledgement(type: String, command: DaemonCommand) {
        var event = DaemonEvent(type: type, displayID: displayID, requestID: command.requestID,
            message: nil, videoPath: nil, contentKind: "video")
        event.activationID = command.activationID
        event.preparationGeneration = command.preparationGeneration
        event.cohortID = command.cohortID
        event.outputActive = command.outputActive
        event.activityID = command.activityID
        write(event)
    }
}
