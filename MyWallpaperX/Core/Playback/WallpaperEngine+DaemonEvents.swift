//
//  WallpaperEngine+DaemonEvents.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import CoreGraphics

extension WallpaperEngine {
    func dispatchWebRuntimeCommand(_ command: WebWallpaperRuntimeCommand) {
        dedicatedWebHostAdapter.handle(command)
    }

    func send(_ command: DaemonCommand, to session: DisplayDaemonSession) {
        guard let data = try? DaemonNewlineJSON.encode(command) else { return }
        if command.action == "setSpectrumLevels" {
            session.transport.sendLatest(data)
        } else {
            session.transport.sendRequired(data)
        }
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
                // E2a-3: the committed selection may land now — the daemon
                // confirmed this exact content is playing.
                NotificationCenter.default.post(
                    name: Self.playbackReadyNotification,
                    object: self,
                    userInfo: [
                        "videoPath": event.videoPath ?? currentContentPath as Any
                    ]
                )
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
