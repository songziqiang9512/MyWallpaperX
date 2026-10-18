import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func handle(_ command: DaemonCommand) {
        switch command.action {
        case "commitVideo":
            commitVideoPreparation(requestID: command.requestID, activationID: command.activationID,
                generation: command.preparationGeneration, cohortID: command.cohortID)
        case "finalizeVideo":
            guard matchesVideoPreparation(command) else { return }
            finalizeVideoPreparation(requestID: command.requestID)
        case "cancelVideoPreparation": cancelVideoPreparationCommand(command)
        case "setOutputActivity": setOutputActivity(command)
        case "play":
            guard let videoPath = command.videoPath else { return }
            emit(type: "accepted", requestID: command.requestID, message: nil, videoPath: videoPath, contentKind: "video")
            if let playbackRate = command.playbackRate {
                self.playbackRate = max(playbackRate, 0.1)
            }
            if let volume = command.volume {
                currentVolume = min(max(volume, 0), 1)
            }
            applySpectrumConfiguration(from: command)
            if let spectrumEnabled = command.spectrumEnabled {
                setSpectrumEnabled(spectrumEnabled)
            }
            if let spectrumLevels = command.spectrumLevels {
                updateSpectrumLevels(spectrumLevels)
            }
            play(
                videoPath: videoPath,
                framePath: command.framePath,
                fillMode: command.fillMode ?? "aspectFill",
                shouldLoopCurrentItem: command.shouldLoopCurrentItem ?? false,
                requestID: command.requestID,
                cohortID: command.cohortID
            )
        case "pause":
            paused = true
            for player in players {
                player.pause()
            }
        case "resume":
            paused = false
            if let playbackRate = command.playbackRate {
                self.playbackRate = max(playbackRate, 0.1)
            }
            if outputActivityAllowed { activePlayer.rate = playbackRate }
        case "setVolume":
            if let volume = command.volume {
                currentVolume = min(max(volume, 0), 1)
                activePlayer.volume = outputActivityAllowed ? currentVolume : 0
                inactivePlayer.volume = 0
            }
        case "setPlaybackRate":
            if let playbackRate = command.playbackRate {
                self.playbackRate = max(playbackRate, 0.1)
                if !paused && outputActivityAllowed {
                    activePlayer.rate = self.playbackRate
                }
            }
        case "setFillMode":
            if let fillMode = command.fillMode, fillMode != currentFillMode {
                videoPreparation?.previousFillMode = fillMode
                currentFillMode = fillMode
                animateLayerFrameForFillMode(fillMode)
                let fallbackGravity: CALayerContentsGravity = fillMode == "aspectFit" ? .resizeAspect : .resizeAspectFill
                fallbackLayer.contentsGravity = fallbackGravity
            }
        case "setLoop":
            if let shouldLoop = command.shouldLoopCurrentItem { updateVideoLoopPolicy(shouldLoop) }
        case "setSpectrumEnabled":
            applySpectrumConfiguration(from: command)
            if let spectrumEnabled = command.spectrumEnabled {
                setSpectrumEnabled(spectrumEnabled)
            }
            if let spectrumLevels = command.spectrumLevels {
                updateSpectrumLevels(spectrumLevels)
            } else if command.spectrumEnabled == false {
                updateSpectrumLevels(Array(repeating: 0, count: spectrumBarCount))
            }
        case "setSpectrumConfig":
            applySpectrumConfiguration(from: command)
            if let spectrumEnabled = command.spectrumEnabled {
                setSpectrumEnabled(spectrumEnabled)
            }
            if let spectrumLevels = command.spectrumLevels {
                updateSpectrumLevels(spectrumLevels)
            }
        case "setSpectrumLevels":
            if let spectrumLevels = command.spectrumLevels {
                updateSpectrumLevels(spectrumLevels)
            }
        case "stop":
            daemonLog("received stop")
            shutdown()
        default:
            break
        }
    }

    func shutdown() {
        stopActivationVisibilityCheck()
        pendingStatusObservation = nil
        clearPlaybackObservers(for: .primary)
        clearPlaybackObservers(for: .secondary)
        pendingDisplayObservation = nil
        pendingDisplayFallbackWorkItem?.cancel()
        pendingDisplayFallbackWorkItem = nil
        clearLooper(for: .primary)
        clearLooper(for: .secondary)
        for player in players {
            player.pause()
            player.removeAllItems()
        }
        primaryLooper = nil
        secondaryLooper = nil
        window.orderOut(nil)
        fallbackLayer.contents = nil
        emit(type: "stopped", requestID: nil, message: nil, videoPath: nil)
        daemonLog("shutdown")
        NSApp.terminate(nil)
    }

    var players: [AVQueuePlayer] {
        [primaryPlayer, secondaryPlayer]
    }

    var activePlayer: AVQueuePlayer {
        activeSlot == .primary ? primaryPlayer : secondaryPlayer
    }

    var inactivePlayer: AVQueuePlayer {
        activeSlot == .primary ? secondaryPlayer : primaryPlayer
    }

    var inactiveSlot: Slot { activeSlot == .primary ? .secondary : .primary }

    var pendingEndObservation: NSObjectProtocol? {
        get { activeSlot == .primary ? primaryEndObservation : secondaryEndObservation }
        set {
            if activeSlot == .primary { primaryEndObservation = newValue }
            else { secondaryEndObservation = newValue }
        }
    }

    var loopEndObservation: NSObjectProtocol? {
        get { activeSlot == .primary ? primaryLoopEndObservation : secondaryLoopEndObservation }
        set {
            if activeSlot == .primary { primaryLoopEndObservation = newValue }
            else { secondaryLoopEndObservation = newValue }
        }
    }

    var activeLayer: AVPlayerLayer {
        activeSlot == .primary ? primaryLayer : secondaryLayer
    }

    var inactiveLayer: AVPlayerLayer {
        activeSlot == .primary ? secondaryLayer : primaryLayer
    }

    func setInactiveLooper(_ looper: AVPlayerLooper?) {
        switch activeSlot {
        case .primary:
            secondaryLooper = looper
        case .secondary:
            primaryLooper = looper
        }
    }

    func clearActiveLooper() {
        switch activeSlot {
        case .primary:
            primaryLooper = nil
        case .secondary:
            secondaryLooper = nil
        }
    }

    func configureWindowForVideoRendering() {
        window.backgroundColor = .black
        window.isOpaque = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.black.cgColor
    }
}
