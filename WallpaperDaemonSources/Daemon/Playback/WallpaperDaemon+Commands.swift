import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import WebKit
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func handle(_ command: DaemonCommand) {
        switch command.action {
        case "play":
            guard let videoPath = command.videoPath else { return }
            currentContentKind = "video"
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
                requestID: command.requestID
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
            activePlayer.rate = playbackRate
        case "setVolume":
            if let volume = command.volume {
                currentVolume = min(max(volume, 0), 1)
                for player in players {
                    player.volume = currentVolume
                }
            }
        case "setPlaybackRate":
            if let playbackRate = command.playbackRate {
                self.playbackRate = max(playbackRate, 0.1)
                if !paused {
                    activePlayer.rate = self.playbackRate
                }
            }
        case "setFillMode":
            if let fillMode = command.fillMode, fillMode != currentFillMode {
                currentFillMode = fillMode
                animateLayerFrameForFillMode(fillMode)
                let fallbackGravity: CALayerContentsGravity = fillMode == "aspectFit" ? .resizeAspect : .resizeAspectFill
                fallbackLayer.contentsGravity = fallbackGravity
            }
        case "setLoop":
            if let shouldLoop = command.shouldLoopCurrentItem {
                if shouldLoop {
                    if loopEndObservation == nil, let item = activePlayer.currentItem {
                        loopEndObservation = NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: item,
                            queue: .main
                        ) { [weak self] _ in
                            guard let self else { return }
                            self.activePlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                            self.activePlayer.rate = self.playbackRate
                        }
                        if let obs = pendingEndObservation {
                            NotificationCenter.default.removeObserver(obs)
                            pendingEndObservation = nil
                        }
                    }
                } else {
                    if let obs = loopEndObservation {
                        NotificationCenter.default.removeObserver(obs)
                        loopEndObservation = nil
                    }
                    if pendingEndObservation == nil,
                       let item = activePlayer.currentItem,
                       let videoPath = currentVideoPath {
                        observePlaybackEnd(for: item, requestID: currentRequestID, videoPath: videoPath)
                    }
                    activePlayer.actionAtItemEnd = .pause
                }
            }
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
        pendingStatusObservation = nil
        pendingEndObservation = nil
        pendingDisplayObservation = nil
        loopEndObservation = nil
        pendingDisplayFallbackWorkItem?.cancel()
        pendingDisplayFallbackWorkItem = nil
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
