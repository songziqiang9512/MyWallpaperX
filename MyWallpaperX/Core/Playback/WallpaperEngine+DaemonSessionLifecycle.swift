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
        guard DaemonPlaybackProcessRegistry.shared.acceptsNewProcesses else { return nil }
        if let session = displaySessions[displayID], session.process.isRunning {
            return session
        }

        terminateSession(for: displayID)

        guard let helperURL = helperExecutableURL() else {
            return nil
        }

        let transport = DaemonProcessTransport(
            executableURL: helperURL,
            arguments: ["--display-id", String(displayID)],
            playbackRenderer: true
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

                self.videoSessionDidExit(session, wasCurrent: wasCurrentSession)
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

        if session.process.isRunning {
            send(DaemonCommand(action: "stop", videoPath: nil, framePath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
        }
        // EOF follows the ordered stop command; the shared physical registry
        // retains this helper after removal from the display session table.
        session.transport.requestGracefulStop()
    }

    func cancelVideoPreparationRetainingActivePlayback() {
        if let videoCandidate,
           videoCandidate.visibleDisplays.count != videoCandidate.sessions.count {
            cancelVideoExecution(videoCandidate, completion: {})
        }
    }
}
