//
//  WallpaperEngine+DaemonSessionLifecycle.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import CoreGraphics

extension WallpaperEngine {
    func ensureSession(for displayID: CGDirectDisplayID) -> DisplayDaemonSession? {
        if let session = displaySessions[displayID], session.process.isRunning {
            return session
        }

        terminateSession(for: displayID)

        guard let helperURL = helperExecutableURL() else {
            return nil
        }

        let transport = DaemonProcessTransport(
            executableURL: helperURL,
            arguments: ["--display-id", String(displayID)]
        )
        let session = DisplayDaemonSession(
            displayID: displayID,
            transport: transport
        )
        attachReaders(for: session)

        transport.onTermination = { [weak self, weak session] _ in
            guard let session else { return }
                guard let self else { return }
                let wasCurrentSession = self.displaySessions[displayID] === session
                if wasCurrentSession {
                    self.displaySessions.removeValue(forKey: displayID)
                }
                self.cleanupSessionIO(session)

                // web 准备窗内被保留的 video runtime 全灭（多屏全部会话崩溃/
                // 单屏唯一会话崩溃）时清空保留：E2a-4 失败回滚假设被保留的
                // runtime 还活着——否则回滚会把引擎真值复活成已死的 video
                // （isPlaying 为真、屏幕无输出、无自愈路径）。全灭后走 else
                // 清空分支，引擎如实报告未在播。
                if self.pendingVideoRetirementOnWebReady, self.displaySessions.isEmpty {
                    self.pendingVideoRetirementOnWebReady = false
                    self.retainedVideoWallpaper = nil
                    self.retainedVideoContentPath = nil
                    self.retainedVideoMultiDisplayEnabled = nil
                }

                guard wasCurrentSession,
                      self.currentPlaybackContentKind == .video,
                      self.shouldMaintainSession(for: displayID),
                      let currentWallpaper = self.currentWallpaper,
                      let currentContentPath = self.currentContentPath else {
                    return
                }
                let recoveryEpoch = self.playbackIntentEpoch
                let recoveryPath = URL(fileURLWithPath: currentWallpaper.path)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL.path
                guard recoveryPath == currentContentPath else { return }

                let crashCount = self.displayCrashCounts[displayID, default: 0]
                self.displayCrashCounts[displayID] = crashCount + 1
                let delay = DaemonRestartBackoff.delay(
                    forConsecutiveFailureCount: crashCount
                )

                let rebuild = { [weak self] in
                    guard let self,
                          self.playbackIntentEpoch == recoveryEpoch,
                          self.currentPlaybackContentKind == .video,
                          self.currentContentPath == recoveryPath,
                          self.displaySessions[displayID] == nil,
                          self.shouldMaintainSession(for: displayID) else {
                        return
                    }
                    self.applyWallpaper(
                        currentWallpaper,
                        multiDisplayEnabled: self.currentMultiDisplayEnabled,
                        videoFillMode: self.currentVideoFillMode,
                        shouldLoopCurrentItem: self.currentShouldLoopCurrentItem
                    )
                }

                if delay <= 0 {
                    rebuild()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: rebuild)
                }
        }

        do {
            try transport.start()
            displaySessions[displayID] = session
            return session
        } catch {
            cleanupSessionIO(session)
            return nil
        }
    }

    private func helperExecutableURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        let helperURL = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("MyWallpaperXWallpaperDaemon")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            return nil
        }
        return helperURL
    }

    private func attachReaders(for session: DisplayDaemonSession) {
        let displayID = session.displayID
        session.transport.onOutput = { [weak self, weak session] data in
            guard let self,
                  let session,
                  self.displaySessions[displayID] === session else { return }
            self.consumeDaemonEvents(from: data, for: session)
        }
        session.transport.onError = { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            print(trimmed)
        }
    }

    private func cleanupSessionIO(_ session: DisplayDaemonSession) {
        session.transport.closeIO()
    }

    func terminateSession(for displayID: CGDirectDisplayID) {
        guard let session = displaySessions.removeValue(forKey: displayID) else { return }

        if session.process.isRunning {
            send(DaemonCommand(action: "stop", videoPath: nil, framePath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            session.transport.terminate()
        }
        session.transport.closeIO()
    }

    func sendPlayCommand(
        for videoPath: String,
        framePath: String?,
        fillMode: String,
        shouldLoopCurrentItem: Bool,
        to session: DisplayDaemonSession
    ) {
        session.nextRequestID += 1
        let requestID = session.nextRequestID
        session.latestRequestedPlayRequestID = requestID
        send(
            DaemonCommand(
                action: "play",
                videoPath: videoPath,
                framePath: framePath,
                propertiesJSON: nil,
                fillMode: fillMode,
                shouldLoopCurrentItem: shouldLoopCurrentItem,
                volume: effectiveVolumeNormalized,
                playbackRate: targetPlaybackRate,
                spectrumEnabled: currentSystemAudioSpectrumEnabled,
                spectrumLevels: currentSpectrumLevels,
                spectrumBarCount: currentSystemAudioSpectrumBarCount,
                spectrumColorHex: currentSystemAudioSpectrumColorHex,
                spectrumOffsetX: currentSystemAudioSpectrumOffsetX,
                spectrumOffsetY: currentSystemAudioSpectrumOffsetY,
                spectrumPeakCapsEnabled: currentSystemAudioSpectrumPeakCapsEnabled,
                requestID: requestID
            ),
            to: session
        )
        sendPlaybackPaused(PlaybackCommandMultiplexer.shared.isPlaybackPaused, to: session)
    }

}
