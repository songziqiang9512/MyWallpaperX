//
//  WallpaperEngine+DaemonSessionLifecycle.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import CoreGraphics

extension WallpaperEngine {
    func refreshVideoSpectrumTargets() {
        spectrumDelivery.setVideoTargets(displaySessions.values.map(\.transport))
        refreshSystemAudioSpectrumCapture()
    }

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
                    self.refreshVideoSpectrumTargets()
                }
                self.cleanupSessionIO(session)

                // Keep the finalized identity across a helper crash. A failed
                // Web preparation can restore that identity and rebuild its
                // missing helper; an uncommitted Video request is not a fallback.
                if self.pendingVideoRetirementOnWebReady, self.displaySessions.isEmpty,
                   self.activeVideoPlayback == nil {
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
                        shouldLoopCurrentItem: self.currentShouldLoopCurrentItem,
                        retainedVideoRecovery: self.activeVideoPlayback?.path == recoveryPath
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
            refreshVideoSpectrumTargets()
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
        refreshVideoSpectrumTargets()
        if displaySessions.isEmpty, currentPlaybackContentKind != .video,
           !pendingVideoRetirementOnWebReady { activeVideoPlayback = nil }

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
        session.latestPreparedPlayRequestID = nil
        session.latestCommittedPlayRequestID = nil
        session.latestReadyPlayRequestID = nil
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
                spectrumLevels: spectrumDelivery.currentOverlayLevels,
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

    func sendVideoPreparationCommand(_ action: String, requestID: Int, to session: DisplayDaemonSession) {
        send(DaemonCommand(action: action, videoPath: nil, framePath: nil,
            propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil,
            volume: nil, playbackRate: nil, spectrumEnabled: nil,
            spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil,
            spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil,
            requestID: requestID), to: session)
    }

    /// Revoke the candidate without destroying a helper's finalized active slot.
    /// Cancellation is ordered after a possibly in-flight commit in the same pipe.
    func cancelVideoPreparationRetainingActivePlayback() {
        defer { scheduleRetainedVideoRecoveryIfNeeded() }
        let hadPreparation = !pendingVideoDisplayIDs.isEmpty
        pendingVideoDisplayIDs.removeAll()
        pendingVideoIsRetainedRecovery = false
        if hadPreparation { pendingWebRetirementOnVideoReady = false }
        for session in Array(displaySessions.values) {
            guard session.process.isRunning else {
                terminateSession(for: session.displayID)
                continue
            }
            guard let requested = session.latestRequestedPlayRequestID,
                  requested != session.latestFinalizedPlayRequestID else { continue }
            if let finalized = session.latestFinalizedPlayRequestID {
                sendVideoPreparationCommand("cancelVideoPreparation", requestID: requested, to: session)
                session.latestRequestedPlayRequestID = finalized
                session.latestReadyPlayRequestID = finalized
                session.latestPreparedPlayRequestID = nil
                session.latestCommittedPlayRequestID = nil
            } else {
                terminateSession(for: session.displayID)
            }
        }
        guard hadPreparation, currentPlaybackContentKind == .video else { return }
        if let active = activeVideoPlayback {
            currentWallpaper = active.wallpaper
            currentContentPath = active.path
            currentMultiDisplayEnabled = active.multiDisplayEnabled
        } else {
            currentWallpaper = nil
            currentContentPath = nil
            currentPlaybackContentKind = nil
        }
    }

    private func scheduleRetainedVideoRecoveryIfNeeded() {
        guard let active = activeVideoPlayback else { return }
        let epoch = playbackIntentEpoch
        DispatchQueue.main.async { [weak self] in
            guard let self, self.playbackIntentEpoch == epoch,
                  self.currentPlaybackContentKind == .video,
                  self.currentContentPath == active.path,
                  self.activeVideoPlayback?.path == active.path,
                  self.pendingVideoDisplayIDs.isEmpty else { return }
            self.scanDisplays()
            let targets = active.multiDisplayEnabled ? self.displayIDs : Array(self.displayIDs.prefix(1))
            guard targets.contains(where: {
                guard let session = self.displaySessions[$0] else { return true }
                return !session.process.isRunning || session.latestFinalizedPlayRequestID == nil
            }) else { return }
            self.applyWallpaper(active.wallpaper, multiDisplayEnabled: active.multiDisplayEnabled,
                videoFillMode: self.currentVideoFillMode,
                shouldLoopCurrentItem: self.currentShouldLoopCurrentItem, retainedVideoRecovery: true)
        }
    }

}
