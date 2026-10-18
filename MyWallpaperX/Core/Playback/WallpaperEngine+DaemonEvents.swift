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
        case "launched": session.launched = true
        case "accepted":
            if event.requestID == session.latestRequestedPlayRequestID {
                session.latestAcceptedPlayRequestID = event.requestID
            }
        case "prepared": videoDidPrepare(event, session: session)
        case "ready": videoDidBecomeVisible(event, session: session)
        case "cancelled": videoDidCancel(event, session: session)
        case "outputActivityChanged": videoDidChangeOutputActivity(event, session: session)
        case "failed":
            guard let execution = videoExecution(for: event, session: session),
                  !execution.cancelling, !execution.retired else { return }
            if execution.finalized {
                switchLost?(execution.ticket, event.message ?? "Video playback failed")
            } else { switchFailed?(execution.ticket, event.message ?? "Video playback failed") }
            if !execution.finalized { cancelVideoExecution(execution, completion: {}) }
        case "ended": handlePlaybackEndedEvent(event, for: session)
        default: break
        }
    }

    func reportVideoPlaybackFailure(path failedPath: String, message: String) {
        if let execution = videoCandidate, execution.path == failedPath {
            switchFailed?(execution.ticket, message)
            cancelVideoExecution(execution, completion: {})
        }
        NotificationCenter.default.post(name: Self.playbackFailedNotification,
            object: self, userInfo: ["videoPath": failedPath, "message": message,
                                    "contentKind": PlaybackContentKind.video.rawValue])
    }

    private func handlePlaybackEndedEvent(_ event: DaemonEvent, for session: DisplayDaemonSession) {
        if let candidate = videoCandidate, candidate.activated, !candidate.cancelling,
           candidate.sessions[session.displayID] === session,
           candidate.requests[session.displayID] == event.requestID,
           event.videoPath.map(normalizedPath) == candidate.path {
            candidate.ended = true
            return
        }
        guard let active = activeVideoPlayback, let path = event.videoPath,
              normalizedPath(path) == active.path,
              let requestID = event.requestID,
              requestID == session.latestFinalizedPlayRequestID,
              videoEndState?.playbackID != active.id else { return }
        // A retained video can end while another intent is still preparing.
        // Preserve that terminal for rollback without letting it steal selection.
        videoEndState = (active.id, false)
        replayDeferredVideoEndIfNeeded()
    }

    func replayDeferredVideoEndIfNeeded() {
        guard let end = videoEndState, !end.delivered else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let active = self.activeVideoPlayback,
                  self.videoEndState?.playbackID == end.playbackID,
                  self.videoEndState?.delivered == false,
                  active.id == end.playbackID,
                  self.currentPlaybackContentKind == .video,
                  self.currentContentPath == active.path,
                  self.videoEndDeliveryAdmission?() != false,
                  self.videoCandidate == nil,
                  (self.dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.hasPendingRequest != true else { return }
            self.videoEndState = (active.id, true)
            NotificationCenter.default.post(name: Self.playbackEndedNotification,
                object: self, userInfo: ["videoPath": active.path, "contentKind": "video",
                    "executionID": self.activeVideoExecution?.id as Any,
                    "ticket": self.activeVideoExecution?.ticket as Any])
        }
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
