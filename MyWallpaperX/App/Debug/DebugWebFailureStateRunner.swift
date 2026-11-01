//
//  DebugWebFailureStateRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation
import WebKit

@MainActor
enum DebugWebFailureStateRunner {
    private static let reportFlag = "--mwx-debug-web-failure-state-report"
    private static var reportURL: URL?
    private static let failureCapture = DebugPlaybackFailureCapture()
    private static var failureObserver: NSObjectProtocol?

    static func scheduleIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: reportFlag),
              arguments.indices.contains(flagIndex + 1) else { return false }
        reportURL = URL(fileURLWithPath: arguments[flagIndex + 1])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: start)
        return true
    }

    private static func start() {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyWallpaperXWebFailureState", isDirectory: true)
        let entryURL = fixtureRoot.appendingPathComponent("index.html")
        do {
            try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
            try "<html><body style='background:#246'>failure state</body></html>"
                .write(to: entryURL, atomically: true, encoding: .utf8)
        } catch {
            finish(preconditionFailure: "fixture-write-failed: \(error.localizedDescription)")
            return
        }

        var settings = WallpaperManager.shared.settings
        settings.pauseWhenOtherAppFocused = false
        settings.pauseWhenOtherAppFullscreen = false
        settings.pauseWhenUnplugged = false
        settings.pauseWhenIdle = false
        WallpaperManager.shared.settings = settings
        PlaybackPolicyController.shared.updateSettings(settings)
        PlaybackCommandMultiplexer.shared.dispatch(.resume)
        NSLog("MWX DEBUG FAILURE: prepared pause=%@", String(describing: PlaybackCommandMultiplexer.shared.pauseSnapshot))
        installFailureObserver()
        postWebLaunch(entryURL: entryURL, rootURL: fixtureRoot, recordID: "debug-terminal-failure")
        waitForFirstWebReady(entryURL: entryURL, attempt: 0)
    }

    private static func postWebLaunch(entryURL: URL, rootURL: URL, recordID: String) {
        WallpaperLibraryPlaybackRouting.postDiagnosticWeb(entryURL: entryURL, rootURL: rootURL, recordID: recordID)
    }

    private static var navigationChecks: [String: Bool] = [:]

    private static func waitForFirstWebReady(entryURL: URL, attempt: Int) {
        let engine = WallpaperEngine.shared
        guard let host = engine.dedicatedWebHostAdapter as? WebDaemonHostAdapter else {
            finish(preconditionFailure: "web-process-host-unavailable"); return
        }
        if let session = host.active, session.request.id == engine.currentWebRequestID {
            let webStarted = engine.isPlaying()
                && wallpaperStateMatchesWeb()
                && host.liveProcessIdentifiers.allSatisfy { $0 != ProcessInfo.processInfo.processIdentifier }
            postWebLaunch(entryURL: entryURL, rootURL: entryURL.deletingLastPathComponent(),
                recordID: "debug-terminal-failure")
            waitForSecondWebReady(staleSession: session,
                webStarted: webStarted, attempt: 0)
            return
        }
        guard attempt < 100 else { finish(preconditionFailure: "first-web-ready-timeout"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForFirstWebReady(entryURL: entryURL, attempt: attempt + 1)
        }
    }

    private static func wallpaperStateMatchesWeb() -> Bool {
        WallpaperManager.shared.activeWallpaperRuntime == .web && WallpaperManager.shared.isPlaying
    }

    private static func waitForSecondWebReady(staleSession: WebDaemonHostAdapter.Session, webStarted: Bool, attempt: Int) {
        let engine = WallpaperEngine.shared
        guard let host = engine.dedicatedWebHostAdapter as? WebDaemonHostAdapter else { return }
        let staleRequestID = staleSession.request.id
        if let current = host.active, current.request.id != staleRequestID,
           current.request.id == engine.currentWebRequestID {
            guard let output = staleSession.transport.onOutput,
                  let frame = try? DaemonNewlineJSON.encode(WebDaemonEnvelope(requestID: staleRequestID,
                    payload: WebDaemonEvent.host(.failed(message: "debug-stale-a-failure", requestID: staleRequestID)))) else {
                finish(preconditionFailure: "stale-web-frame-unavailable"); return
            }
            withExtendedLifetime(staleSession) { output(frame) }
            let checks = ["webStarted": webStarted,
                "staleFailureIgnored": engine.currentWebRequestID == current.request.id
                    && host.activeRequest?.id == current.request.id && engine.isPlaying()
                    && failureCapture.snapshot().isEmpty]
            host.debugNavigationChecksHandler = { navigationChecks = $0 }
            host.debugExerciseFailure()
            waitForTerminalFailure(requestID: current.request.id, lastTerminatedExecutionID: current.executionID,
                checks: checks, attempt: 0)
            return
        }
        guard attempt < 100 else { finish(preconditionFailure: "second-web-ready-timeout"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForSecondWebReady(staleSession: staleSession,
                webStarted: webStarted, attempt: attempt + 1)
        }
    }

    private static func waitForTerminalFailure(requestID: UUID, lastTerminatedExecutionID: UUID, checks: [String: Bool], attempt: Int) {
        let engine = WallpaperEngine.shared
        let manager = WallpaperManager.shared
        guard let host = engine.dedicatedWebHostAdapter as? WebDaemonHostAdapter else { return }
        let failures = failureCapture.snapshot()
        guard failures.count <= 1 else { finish(preconditionFailure: "duplicate-failure-notification"); return }
        guard failures.count == 1, engine.currentWebRequestID == nil, host.liveProcessIdentifiers.isEmpty else {
            guard attempt < 150 else { finish(preconditionFailure: "terminal-failure-timeout"); return }
            let activeExecutionID = host.active.flatMap { $0.request.id == requestID ? $0.executionID : nil }
            let nextTerminatedExecutionID = activeExecutionID ?? lastTerminatedExecutionID
            if nextTerminatedExecutionID != lastTerminatedExecutionID { host.debugTerminateActiveProcess() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                waitForTerminalFailure(requestID: requestID, lastTerminatedExecutionID: nextTerminatedExecutionID,
                    checks: checks, attempt: attempt + 1)
            }
            return
        }
        let payload = failures.first
        let terminalCleared = engine.currentWallpaper == nil && engine.currentContentPath == nil
            && engine.currentPlaybackContentKind == nil && engine.currentWebPropertiesJSON == nil
            && engine.currentWebRecordID == nil && !engine.isPlaying()
        let managerStopped = manager.activeWallpaperRuntime == .web && manager.currentWallpaper == nil
            && !manager.isPlaying && manager.autoSwitchTimer == nil
        let payloadPreserved = payload?["message"] as? String == "Web 宿主反复退出"
            && payload?["contentKind"] as? String == "web"
            && payload?["requestID"] as? String == requestID.uuidString
            && payload?["videoPath"] == nil
        guard let videoURL = BundledVideoLibrary.videoURL(named: "Video2") else {
            finish(preconditionFailure: "bundled-video-missing"); return
        }
        manager.requestDiagnosticVideo(VideoWallpaper(title: "Failure Gate Video", path: videoURL.path))
        let allChecks = checks.merging(navigationChecks) { _, new in new }.merging([
            "terminalCleared": terminalCleared,
            "hostCleared": host.activeRequest == nil && host.liveProcessIdentifiers.isEmpty,
            "managerStopped": managerStopped, "payloadPreserved": payloadPreserved
        ]) { _, new in new }
        waitForVideoReady(attempt: 0, checks: allChecks)
    }

    private static func waitForVideoReady(
        attempt: Int,
        checks: [String: Bool]
    ) {
        let engine = WallpaperEngine.shared
        let manager = WallpaperManager.shared
        let sessionsReady = !engine.displaySessions.isEmpty && engine.displaySessions.values.allSatisfy {
            $0.latestRequestedPlayRequestID != nil
                && $0.latestAcceptedPlayRequestID == $0.latestRequestedPlayRequestID
                && $0.latestReadyPlayRequestID == $0.latestRequestedPlayRequestID
        }
        if sessionsReady {
            let videoRecovered = engine.currentPlaybackContentKind == .video
                && engine.currentWallpaper != nil
                && engine.isPlaying()
                && manager.activeWallpaperRuntime == .video
                && manager.currentWallpaper != nil
                && manager.isPlaying
            engine.stopPlayback()
            let stopCleared = engine.currentWallpaper == nil
                && engine.currentContentPath == nil
                && engine.currentPlaybackContentKind == nil
                && engine.displaySessions.isEmpty
            finish(checks: checks.merging([
                "videoRecovered": videoRecovered,
                "stopCleared": stopCleared
            ]) { _, latest in latest })
            return
        }
        guard attempt < 50 else {
            finish(preconditionFailure: "video-ready-timeout")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForVideoReady(
                attempt: attempt + 1,
                checks: checks
            )
        }
    }

    private static func installFailureObserver() {
        failureCapture.reset()
        let capture = failureCapture
        failureObserver = NotificationCenter.default.addObserver(
            forName: WallpaperEngine.playbackFailedNotification,
            object: nil,
            queue: .main
        ) { notification in
            capture.append(notification.userInfo ?? [:])
        }
    }

    private static func finish(checks: [String: Bool] = [:], preconditionFailure: String? = nil) {
        (WallpaperEngine.shared.dedicatedWebHostAdapter as? WebDaemonHostAdapter)?.debugNavigationChecksHandler = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        let failureCount = failureCapture.snapshot().count
        let payload: [String: Any] = [
            "checks": checks,
            "failureCount": failureCount,
            "passed": preconditionFailure == nil && checks.count == 12 && checks.values.allSatisfy { $0 },
            "preconditionFailure": preconditionFailure.map { $0 as Any } ?? NSNull()
        ]
        guard let reportURL,
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: reportURL, options: .atomic)
    }
}
#endif
