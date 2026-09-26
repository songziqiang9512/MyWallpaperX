//
//  WallpaperEngine+PlaybackControl.swift
//  MyWallpaperX
//

import Foundation

extension WallpaperEngine {
    func applySystemPlaybackPausedState(_ paused: Bool) {
        if paused {
            pauseAllPlayers()
        } else {
            resumeAllPlayers()
        }
        // E2b: 系统暂停评估结果以通知上报——跨 runtime 命令下发归控制层
        // （引擎不再自发 mux 命令，owner 兼 handler 倒置移除）。
        NotificationCenter.default.post(
            name: WallpaperEngine.playbackSystemPauseDidChangeNotification,
            object: self,
            userInfo: ["paused": paused]
        )
    }

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
