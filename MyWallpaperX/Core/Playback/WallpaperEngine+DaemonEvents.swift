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
        let restoresCommittedVideo = pendingVideoIsRetainedRecovery
            && videoPreparationIntentEpoch == playbackIntentEpoch
            && activeVideoPlayback?.path == currentContentPath
        switch event.type {
        case "launched":
            session.launched = true
        case "accepted":
            guard event.requestID == nil
                    || event.requestID == session.latestRequestedPlayRequestID else { return }
            session.latestAcceptedPlayRequestID = event.requestID
        case "prepared":
            guard let requestID = event.requestID,
                  requestID == session.latestRequestedPlayRequestID,
                  pendingVideoDisplayIDs.contains(session.displayID),
                  currentPlaybackContentKind == .video,
                  event.videoPath.map(normalizedPath) == currentContentPath,
                  runtimeCommitAdmission?(.video) != false || restoresCommittedVideo else { return }
            session.latestPreparedPlayRequestID = requestID
            let targets = pendingVideoDisplayIDs.compactMap { displaySessions[$0] }
            guard targets.count == pendingVideoDisplayIDs.count,
                  targets.allSatisfy({ $0.latestRequestedPlayRequestID != nil
                      && $0.latestPreparedPlayRequestID == $0.latestRequestedPlayRequestID }),
                  targets.contains(where: { $0.latestCommittedPlayRequestID != $0.latestRequestedPlayRequestID }) else { return }
            for target in targets {
                guard let id = target.latestRequestedPlayRequestID else { continue }
                target.latestCommittedPlayRequestID = id
                sendVideoPreparationCommand("commitVideo", requestID: id, to: target)
            }
        case "ready":
            guard let requestID = event.requestID,
                  requestID == session.latestRequestedPlayRequestID,
                  requestID == session.latestCommittedPlayRequestID,
                  pendingVideoDisplayIDs.contains(session.displayID) else { return }
            session.latestReadyPlayRequestID = requestID
            let targets = pendingVideoDisplayIDs.compactMap { displaySessions[$0] }
            if currentPlaybackContentKind == .video,
               event.videoPath.map(normalizedPath) == currentContentPath,
               targets.count == pendingVideoDisplayIDs.count,
               targets.allSatisfy({
                   $0.latestRequestedPlayRequestID != nil
                       && $0.latestReadyPlayRequestID == $0.latestRequestedPlayRequestID
               }), runtimeCommitAdmission?(.video) != false || restoresCommittedVideo {
                for target in targets {
                    guard let id = target.latestRequestedPlayRequestID else { continue }
                    target.latestFinalizedPlayRequestID = id
                    sendVideoPreparationCommand("finalizeVideo", requestID: id, to: target)
                }
                if let wallpaper = currentWallpaper, let path = currentContentPath {
                    activeVideoPlayback = .init(wallpaper: wallpaper, path: path,
                        multiDisplayEnabled: currentMultiDisplayEnabled)
                }
                let obsolete = Set(displaySessions.keys).subtracting(pendingVideoDisplayIDs)
                pendingVideoDisplayIDs.removeAll()
                pendingVideoIsRetainedRecovery = false
                for displayID in obsolete { terminateSession(for: displayID) }
                if restoresCommittedVideo {
                    for target in targets { displayCrashCounts[target.displayID] = 0 }
                    return
                }
                postWallpaperRuntimeWillSwitch(to: .video)
                if pendingWebRetirementOnVideoReady {
                    pendingWebRetirementOnVideoReady = false
                    currentWebRequestID = nil
                    dispatchWebRuntimeCommand(.stop)
                    setWebAudioSpectrumRequested(false)
                    currentWebRecordID = nil
                    currentWebPropertiesJSON = nil
                }
                lastFailureVideoPath = nil
                lastFailureAt = 0
                displayCrashCounts[session.displayID] = 0
                // E2a-3: the committed selection may land now — the daemon
                // confirmed this exact content is playing.
                NotificationCenter.default.post(
                    name: Self.playbackReadyNotification,
                    object: self,
                    userInfo: [
                        "videoPath": currentContentPath as Any
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
        guard let reportedPath = event.videoPath else { return }
        let failedPath = normalizedPath(reportedPath)
        guard
              failedPath == currentContentPath,
              event.requestID == nil || event.requestID == session.latestRequestedPlayRequestID else {
            return
        }

        reportVideoPlaybackFailure(path: failedPath, message: event.message ?? "unknown")
    }

    func reportVideoPlaybackFailure(path failedPath: String, message: String) {
        let now = CACurrentMediaTime()
        if lastFailureVideoPath == failedPath && now - lastFailureAt < 1.0 {
            return
        }

        lastFailureVideoPath = failedPath
        lastFailureAt = now
        if pendingVideoIsRetainedRecovery { activeVideoPlayback = nil }
        if !rollbackVideoPreparationToWeb() {
            cancelVideoPreparationRetainingActivePlayback()
        }

        NotificationCenter.default.post(
            name: Self.playbackFailedNotification,
            object: self,
            userInfo: [
                "videoPath": failedPath,
                "message": message,
                "contentKind": PlaybackContentKind.video.rawValue
            ]
        )
    }

    private func handlePlaybackEndedEvent(_ event: DaemonEvent, for session: DisplayDaemonSession) {
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
                  self.pendingVideoDisplayIDs.isEmpty,
                  self.runtimeCommitAdmission?(.video) != false else { return }
            self.videoEndState = (active.id, true)
            NotificationCenter.default.post(name: Self.playbackEndedNotification,
                object: self, userInfo: ["videoPath": active.path, "contentKind": "video"])
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
