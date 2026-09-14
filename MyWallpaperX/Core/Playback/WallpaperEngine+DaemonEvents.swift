//
//  WallpaperEngine+DaemonEvents.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import CoreGraphics

extension WallpaperEngine {
    func dispatchWebRuntimeCommand(_ command: WebWallpaperRuntimeCommand) {
        switch currentWebHostStrategy {
        case .daemonDiagnosticsHarness:
            dispatchWebRuntimeCommandViaDaemonHarness(command)
        case .dedicatedHostPlaceholder:
            dedicatedWebHostAdapter.handle(command)
        }
    }

    private func dispatchWebRuntimeCommandViaDaemonHarness(_ command: WebWallpaperRuntimeCommand) {
        if case .stop = command {
            let displayIDs = displaySessions.values
                .filter { $0.process.isRunning }
                .map(\.displayID)
            for displayID in displayIDs {
                terminateSession(for: displayID)
            }
            return
        }

        for session in displaySessions.values where session.process.isRunning {
            switch command {
            case .pause:
                send(DaemonCommand(action: "pause", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            case let .resume(playbackRate):
                send(DaemonCommand(action: "resume", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: playbackRate, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            case .stop:
                break
            case let .setVolume(volume):
                send(DaemonCommand(action: "setVolume", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: volume, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            case let .setPlaybackRate(playbackRate):
                send(DaemonCommand(action: "setPlaybackRate", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: playbackRate, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            case let .applyProperties(propertiesJSON):
                send(DaemonCommand(action: "applyWebProperties", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: propertiesJSON, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            case let .pushAudioSpectrum(levels):
                send(DaemonCommand(action: "setSpectrumLevels", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: levels, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            }
        }
    }

    func send(_ command: DaemonCommand, to session: DisplayDaemonSession) {
        guard let data = try? DaemonNewlineJSON.encode(command) else { return }
        session.transport.send(data)
    }

    func resizedSpectrumLevels(_ levels: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !levels.isEmpty else { return Array(repeating: 0, count: count) }
        if levels.count == count {
            return levels.map { min(max($0, 0), 1) }
        }

        var output = Array(repeating: Float(0), count: count)
        let scale = Double(levels.count) / Double(count)
        for index in 0..<count {
            let sourceIndex = min(levels.count - 1, Int((Double(index) * scale).rounded(.down)))
            output[index] = min(max(levels[sourceIndex], 0), 1)
        }
        return output
    }

    func consumeDaemonEvents(from data: Data, for session: DisplayDaemonSession) {
        guard displaySessions[session.displayID] === session else { return }
        for line in session.outputFrames.append(data) {
            do {
                let event = try JSONDecoder().decode(DaemonEvent.self, from: line)
                handleDaemonEvent(event, for: session)
            } catch {
            }
        }
    }

    private func handleDaemonEvent(_ event: DaemonEvent, for session: DisplayDaemonSession) {
        switch event.type {
        case "launched":
            session.launched = true
        case "accepted":
            guard event.requestID == nil
                    || event.requestID == session.latestRequestedPlayRequestID else { return }
            session.latestAcceptedPlayRequestID = event.requestID
        case "ready":
            guard event.requestID == nil
                    || event.requestID == session.latestRequestedPlayRequestID else { return }
            session.latestReadyPlayRequestID = event.requestID
            if event.videoPath == currentContentPath {
                lastFailureVideoPath = nil
                lastFailureAt = 0
                displayCrashCounts[session.displayID] = 0
            }
        case "failed":
            handlePlaybackFailureEvent(event, for: session)
        case "ended":
            handlePlaybackEndedEvent(event, for: session)
        case "stopped":
            break
        default:
            break
        }
    }

    private func handlePlaybackFailureEvent(_ event: DaemonEvent, for session: DisplayDaemonSession) {
        guard let failedPath = event.videoPath,
              failedPath == currentContentPath,
              event.requestID == nil || event.requestID == session.latestRequestedPlayRequestID else {
            return
        }

        let now = CACurrentMediaTime()
        if lastFailureVideoPath == failedPath && now - lastFailureAt < 1.0 {
            return
        }

        lastFailureVideoPath = failedPath
        lastFailureAt = now

        NotificationCenter.default.post(
            name: Self.playbackFailedNotification,
            object: self,
            userInfo: [
                "videoPath": failedPath,
                "message": event.message ?? "unknown",
                "contentKind": event.contentKind ?? currentPlaybackContentKind?.rawValue as Any
            ]
        )
    }

    private func handlePlaybackEndedEvent(_ event: DaemonEvent, for session: DisplayDaemonSession) {
        guard let endedPath = event.videoPath,
              endedPath == currentContentPath,
              event.requestID == nil || event.requestID == session.latestRequestedPlayRequestID else {
            return
        }

        let now = CACurrentMediaTime()
        if lastEndedVideoPath == endedPath && now - lastEndedAt < 1.0 {
            return
        }

        lastEndedVideoPath = endedPath
        lastEndedAt = now

        NotificationCenter.default.post(
            name: Self.playbackEndedNotification,
            object: self,
            userInfo: [
                "videoPath": endedPath,
                "contentKind": event.contentKind ?? currentPlaybackContentKind?.rawValue as Any
            ]
        )
    }

    func shouldMaintainSession(for displayID: CGDirectDisplayID) -> Bool {
        scanDisplays()
        guard displayIDs.contains(displayID) else { return false }
        if currentMultiDisplayEnabled {
            return true
        }
        return displayID == displayIDs.first
    }

    func scanDisplays() {
        displayIDs = NSScreen.screens.compactMap {
            guard let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return CGDirectDisplayID(screenNumber.uint32Value)
        }
    }
}
