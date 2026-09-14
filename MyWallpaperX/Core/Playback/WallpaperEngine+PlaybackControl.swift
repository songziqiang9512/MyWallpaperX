//
//  WallpaperEngine+PlaybackControl.swift
//  MyWallpaperX
//

import Foundation

extension WallpaperEngine {
    func setPlaybackPausedState(_ paused: Bool) {
        playbackPaused = paused
        refreshSystemAudioSpectrumCapture()
    }

    public func pauseAllPlayers() {
        assert(Thread.isMainThread, "pauseAllPlayers must be called on main thread")
        if playbackPaused { return }

        if currentPlaybackContentKind == .web {
            dispatchWebRuntimeCommand(.pause)
        } else {
            for session in displaySessions.values where session.process.isRunning {
                send(
                    DaemonCommand(
                        action: "pause",
                        videoPath: nil,
                        framePath: nil,
                        webRootPath: nil,
                        propertiesJSON: nil,
                        fillMode: nil,
                        shouldLoopCurrentItem: nil,
                        volume: nil,
                        playbackRate: nil,
                        spectrumEnabled: nil,
                        spectrumLevels: nil,
                        spectrumBarCount: nil,
                        spectrumColorHex: nil,
                        spectrumOffsetX: nil,
                        spectrumOffsetY: nil,
                        spectrumPeakCapsEnabled: nil,
                        requestID: nil
                    ),
                    to: session
                )
            }
        }
        setPlaybackPausedState(true)
    }

    public func resumeAllPlayers() {
        assert(Thread.isMainThread, "resumeAllPlayers must be called on main thread")
        if !playbackPaused { return }

        if currentPlaybackContentKind == .web {
            dispatchWebRuntimeCommand(.resume(playbackRate: targetPlaybackRate))
        } else {
            for session in displaySessions.values where session.process.isRunning {
                send(
                    DaemonCommand(
                        action: "resume",
                        videoPath: nil,
                        framePath: nil,
                        webRootPath: nil,
                        propertiesJSON: nil,
                        fillMode: nil,
                        shouldLoopCurrentItem: nil,
                        volume: nil,
                        playbackRate: targetPlaybackRate,
                        spectrumEnabled: nil,
                        spectrumLevels: nil,
                        spectrumBarCount: nil,
                        spectrumColorHex: nil,
                        spectrumOffsetX: nil,
                        spectrumOffsetY: nil,
                        spectrumPeakCapsEnabled: nil,
                        requestID: nil
                    ),
                    to: session
                )
            }
        }
        setPlaybackPausedState(false)
    }
}
