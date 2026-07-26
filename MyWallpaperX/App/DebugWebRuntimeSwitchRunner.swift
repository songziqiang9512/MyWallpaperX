//
//  DebugWebRuntimeSwitchRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Darwin
import Foundation

@MainActor
enum DebugWebRuntimeSwitchRunner {
    private static let sequenceFlag = "--mwx-debug-web-runtime-switch-sequence"
    private static var sequenceStartedAt: CFTimeInterval?
    private static var video1PIDs: [Int] = []
    private static var video2PIDs: [Int] = []
    private static var recoveredPIDs: [Int] = []
    private static var staleVideo1ReadabilityHandler: ((FileHandle) -> Void)?
    private static var staleHandlerCaptured = false
    private static var staleFailureInjected = false
    private static var playbackFailureCount = 0
    private static var playbackFailureObserver: NSObjectProtocol?

    static func scheduleIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: sequenceFlag),
              arguments.indices.contains(flagIndex + 1) else {
            return false
        }
        schedule(itemID: arguments[flagIndex + 1])
        return true
    }

    private static func schedule(itemID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard DebugWebPlaybackRunner.hasUsableWorkshopRoot else {
                logPreconditionFailure("isolated-root-required")
                return
            }
            guard let video1URL = bundledVideoURL(named: "Video1"),
                  let video2URL = bundledVideoURL(named: "Video2") else {
                logPreconditionFailure("bundled-videos-missing")
                return
            }

            let service = SteamWorkshopService.shared
            NSLog("MWX DEBUG PLAY: using workshop root %@", service.libraryRootURL.path)
            service.reloadInstalledItems()
            guard let record = service.latestDownloadRecord(for: itemID),
                  record.contentType == .web,
                  service.canLaunchDownloadRecord(record),
                  let context = service.resolvedWebPlaybackContext(for: record) else {
                logPreconditionFailure("web-sample-not-launchable")
                return
            }

            let engine = WallpaperEngine.shared
            guard engine.currentPlaybackContentKind == nil,
                  engine.displaySessions.isEmpty,
                  webHostIsIdle(engine) else {
                logPreconditionFailure("engine-not-idle")
                return
            }

            logAction("preflight", elapsedMilliseconds: 0)
            logCheckpoint("preflight")
            installPlaybackFailureObserver()
            sequenceStartedAt = CACurrentMediaTime()

            logAction("video1")
            setVideo(video1URL, title: "Debug Video 1", on: engine)
            video1PIDs = sessionPIDs(engine)
            staleVideo1ReadabilityHandler = engine.displaySessions.values.first?
                .outputPipe.fileHandleForReading.readabilityHandler
            staleHandlerCaptured = staleVideo1ReadabilityHandler != nil
            logCheckpoint("video1-requested")

            logAction("web")
            engine.setSystemAudioSpectrumEnabled(false)
            engine.setWebWallpaper(
                entryURL: context.effectiveEntryURL,
                rootURL: context.effectiveRootURL,
                propertiesJSON: context.propertyPayloadJSON,
                recordID: record.id,
                language: context.language,
                runtimeProfile: service.recommendedWebRuntimeProfile(for: record),
                multiDisplayEnabled: false
            )
            logCheckpoint("web-requested")

            logAction("video2")
            setVideo(video2URL, title: "Debug Video 2", on: engine)
            video2PIDs = sessionPIDs(engine)
            logCheckpoint("video2-requested")
            logAction("inject-stale-failure")
            injectStaleVideo1Failure(displayID: engine.displayIDs.first, video2URL: video2URL)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                logCheckpoint("stale-event-filtered")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                logCheckpoint("video2-stable")
                logAction("crash-video2")
                guard let session = engine.displaySessions.values.first else {
                    logPreconditionFailure("video2-session-missing-before-crash")
                    return
                }
                session.process.terminate()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                recoveredPIDs = sessionPIDs(engine)
                logCheckpoint("video2-recovered")
                guard let session = engine.displaySessions.values.first else {
                    logPreconditionFailure("recovered-session-missing-before-delayed-crash")
                    return
                }
                engine.displayCrashCounts[session.displayID] = 1
                logAction("crash-video2-delayed")
                session.process.terminate()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.3) {
                logCheckpoint("recovery-pending")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
                logAction("stop")
                engine.stopPlayback()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.8) {
                logCheckpoint("stopped")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                logCheckpoint("post-stop")
                logAction("completed")
                removePlaybackFailureObserver()
            }
        }
    }

    private static func bundledVideoURL(named name: String) -> URL? {
        BundledVideoLibrary.videoURL(named: name)
    }

    private static func setVideo(_ url: URL, title: String, on engine: WallpaperEngine) {
        postWallpaperRuntimeWillSwitch(to: .video)
        engine.setWallpaper(
            VideoWallpaper(title: title, path: url.path),
            multiDisplayEnabled: false,
            videoFillMode: VideoFillMode.aspectFill.ipcValue,
            shouldLoopCurrentItem: true,
            pauseWhenOtherAppFocused: false,
            pauseWhenOtherAppFullscreen: false,
            pauseWhenUnplugged: false,
            pauseWhenIdle: false,
            idleTimeoutMinutes: 10
        )
    }

    private static func logPreconditionFailure(_ reason: String) {
        NSLog("MWX DEBUG RUNTIME SWITCH: precondition=%@", reason)
    }

    private static func installPlaybackFailureObserver() {
        playbackFailureCount = 0
        playbackFailureObserver = NotificationCenter.default.addObserver(
            forName: WallpaperEngine.playbackFailedNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                playbackFailureCount += 1
            }
        }
    }

    private static func removePlaybackFailureObserver() {
        if let playbackFailureObserver {
            NotificationCenter.default.removeObserver(playbackFailureObserver)
        }
        playbackFailureObserver = nil
    }

    private static func injectStaleVideo1Failure(
        displayID: CGDirectDisplayID?,
        video2URL: URL
    ) {
        guard let staleVideo1ReadabilityHandler, let displayID else {
            logPreconditionFailure("stale-video1-handler-missing")
            return
        }
        let event = DaemonEvent(
            type: "failed",
            displayID: displayID,
            requestID: 1,
            message: "debug_stale_session_injection",
            videoPath: video2URL.path,
            contentKind: "video"
        )
        guard let data = try? JSONEncoder().encode(event) + Data([0x0A]) else {
            logPreconditionFailure("stale-event-encoding-failed")
            return
        }
        let pipe = Pipe()
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
            try pipe.fileHandleForWriting.close()
            staleFailureInjected = true
            staleVideo1ReadabilityHandler(pipe.fileHandleForReading)
            try? pipe.fileHandleForReading.close()
        } catch {
            logPreconditionFailure("stale-event-injection-failed")
        }
    }

    private static func logAction(_ action: String, elapsedMilliseconds: Int? = nil) {
        let elapsed = elapsedMilliseconds ?? currentElapsedMilliseconds()
        NSLog("MWX DEBUG RUNTIME SWITCH: action=%@ elapsedMs=%ld", action, elapsed)
    }

    private static func logCheckpoint(_ checkpoint: String) {
        let engine = WallpaperEngine.shared
        let host = engine.dedicatedWebHostAdapter as? DedicatedWebWallpaperHostPlaceholderAdapter
        let sessions = engine.displaySessions.values
            .sorted { $0.displayID < $1.displayID }
            .map { session -> [String: Any] in
                [
                    "accepted": session.latestAcceptedPlayRequestID.map { $0 as Any } ?? NSNull(),
                    "display": Int(session.displayID),
                    "launched": session.launched,
                    "pid": Int(session.process.processIdentifier),
                    "ready": session.latestReadyPlayRequestID.map { $0 as Any } ?? NSNull(),
                    "requested": session.latestRequestedPlayRequestID.map { $0 as Any } ?? NSNull(),
                    "running": session.process.isRunning
                ]
            }
        let path = engine.currentContentPath.map {
            URL(fileURLWithPath: $0).lastPathComponent
        } ?? "-"
        let payload: [String: Any] = [
            "elapsedMs": currentElapsedMilliseconds(),
            "crashCount": engine.displayCrashCounts.values.max() ?? 0,
            "kind": engine.currentPlaybackContentKind?.rawValue ?? "-",
            "path": path,
            "playbackFailures": playbackFailureCount,
            "playing": engine.isPlaying(),
            "recoveredAlive": recoveredPIDs.filter(processIsAlive),
            "recoveredPids": recoveredPIDs,
            "sessions": sessions,
            "staleFailureInjected": staleFailureInjected,
            "staleHandlerCaptured": staleHandlerCaptured,
            "video1Alive": video1PIDs.filter(processIsAlive),
            "video1Pids": video1PIDs,
            "video2Alive": video2PIDs.filter(processIsAlive),
            "video2Pids": video2PIDs,
            "web": [
                "currentRequest": host?.currentRequest == nil ? 0 : 1,
                "loopbacks": host?.loopbackServers.count ?? 0,
                "monitors": (host?.localMouseMonitor == nil ? 0 : 1)
                    + (host?.globalMouseMonitor == nil ? 0 : 1),
                "observers": host?.lifecycleObservers.count ?? 0,
                "phase": host?.phase.rawValue ?? "unavailable",
                "pointerTimer": host?.pointerPollingTimer == nil ? 0 : 1,
                "surfaces": host?.surfaces.count ?? 0,
                "watchTimer": host?.directoryWatchTimer == nil ? 0 : 1,
                "watchers": host?.directoryWatchersByProperty.count ?? 0
            ]
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            NSLog("MWX DEBUG RUNTIME SWITCH: checkpoint=%@ state=serialization-error", checkpoint)
            return
        }
        NSLog("MWX DEBUG RUNTIME SWITCH: checkpoint=%@ state=%@", checkpoint, json)
    }

    private static func currentElapsedMilliseconds() -> Int {
        guard let sequenceStartedAt else { return 0 }
        return Int(((CACurrentMediaTime() - sequenceStartedAt) * 1_000).rounded())
    }

    private static func sessionPIDs(_ engine: WallpaperEngine) -> [Int] {
        engine.displaySessions.values
            .map { Int($0.process.processIdentifier) }
            .sorted()
    }

    private static func processIsAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        return Darwin.kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    private static func webHostIsIdle(_ engine: WallpaperEngine) -> Bool {
        guard let host = engine.dedicatedWebHostAdapter as? DedicatedWebWallpaperHostPlaceholderAdapter else {
            return false
        }
        return host.phase == .idle
            && host.currentRequest == nil
            && host.surfaces.isEmpty
            && host.loopbackServers.isEmpty
            && host.lifecycleObservers.isEmpty
    }
}
#endif
