#if DEBUG
import AppKit
import Foundation
import Darwin

/// Runs the product IPC path with real WKWebView, real system audio and an
/// intentionally blocked parent main thread. Fixtures live beside the report.
@MainActor
enum DebugWebProcessIsolationRunner {
    private static var observationTimer: Timer?
    private static let observationQueue = DispatchQueue(label: "MWX.WebContinuityEvidence")

    static func startObservingIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--mwx-debug-web-continuity-log"),
              args.indices.contains(index + 1) else { return }
        if args.contains("--mwx-debug-web-disable-policy-pauses") {
            var settings = WallpaperManager.shared.settings
            settings.pauseWhenOtherAppFocused = false
            settings.pauseWhenOtherAppFullscreen = false
            settings.pauseWhenUnplugged = false
            settings.pauseWhenIdle = false
            PlaybackPolicyController.shared.updateSettings(settings)
        }
        let output = URL(fileURLWithPath: args[index + 1])
        let host = WallpaperEngine.shared.dedicatedWebHostAdapter as? WebDaemonHostAdapter
        host?.debugContinuityHandler = { [weak host] metrics in
            guard let metrics else { return }
            let row: [String: Any] = ["uptime": ProcessInfo.processInfo.systemUptime,
                "requestID": host?.activeRequest?.id.uuidString ?? "-",
                "processPids": host?.liveProcessIdentifiers ?? [], "metrics": metrics]
            guard var data = try? JSONSerialization.data(withJSONObject: row, options: .sortedKeys) else { return }
            data.append(0x0A)
            let framed = data
            observationQueue.async {
                if !FileManager.default.fileExists(atPath: output.path) {
                    FileManager.default.createFile(atPath: output.path, contents: nil)
                }
                guard let handle = try? FileHandle(forWritingTo: output) else { return }
                defer { try? handle.close() }
                do { try handle.seekToEnd(); try handle.write(contentsOf: framed) }
                catch { NSLog("MWX continuity evidence write failed: %@", error.localizedDescription) }
            }
        }
        let timer = Timer(timeInterval: 4, repeats: true) { _ in
            guard host?.activeRequest != nil, host?.hasPendingRequest == false else { return }
            host?.debugMeasureContinuity()
        }
        observationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    static func scheduleIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--mwx-debug-web-startup-report"),
           args.indices.contains(index + 2) {
            let report = URL(fileURLWithPath: args[index + 1])
            let itemID = args[index + 2]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                Task { await measureStartup(reportURL: report, itemID: itemID) }
            }
            return true
        }
        guard let index = args.firstIndex(of: "--mwx-debug-web-process-isolation-report"),
              args.indices.contains(index + 1) else { return false }
        let reportURL = URL(fileURLWithPath: args[index + 1])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { await run(reportURL: reportURL) }
        }
        return true
    }

    /// Real Steam selection path, rather than the shorter direct host launch.
    /// Alternating forced-cold and ordinary selections separate cache warmth
    /// from an already-running empty renderer. Polling contributes up to 20ms.
    private static func measureStartup(reportURL: URL, itemID: String) async {
        let engine = WallpaperEngine.shared
        guard DebugWebPlaybackRunner.hasUsableWorkshopRoot,
              let host = engine.dedicatedWebHostAdapter as? WebDaemonHostAdapter else { return }
        var settings = WallpaperSettings()
        settings.pauseWhenOtherAppFocused = false
        settings.pauseWhenOtherAppFullscreen = false
        settings.pauseWhenUnplugged = false
        settings.pauseWhenIdle = false
        PlaybackPolicyController.shared.updateSettings(settings)
        let service = SteamWorkshopService.shared
        service.reloadInstalledItems()
        guard let record = await DebugWebPlaybackRunner.awaitInstalledRecord(itemID, using: service),
              record.contentType == .web else { return }
        var rows: [[String: Any]] = []
        for index in 0..<7 {
            let cold = index == 0 || index.isMultiple(of: 2)
            if cold { host.cancelPreparation() }
            let before = host.liveProcessIdentifiers
            let preparationFacts = host.debugPreparationFacts
            let previous = host.activeRequest?.id
            let started = ProcessInfo.processInfo.systemUptime
            service.setAsWallpaper(record)
            var completed = false
            for _ in 0..<1_000 {
                if let request = host.activeRequest, request.id != previous,
                   request.recordID == itemID, engine.currentWebRequestID == request.id,
                   !host.hasPendingRequest {
                    let pid = host.debugActiveProcessIdentifier
                    rows.append(["index": index, "forcedCold": cold,
                        "entryToCommitMs": (ProcessInfo.processInfo.systemUptime - started) * 1_000,
                        "requestID": request.id.uuidString, "beforePIDs": before, "activePID": pid ?? 0,
                        "preparationFacts": preparationFacts,
                        "adoptedExistingProcess": pid.map { before.contains($0) } ?? false])
                    completed = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            if !completed {
                rows.append(["index": index, "failed": true]); break
            }
            try? await Task.sleep(for: .seconds(3))
        }
        engine.stopPlayback()
        let result: [String: Any] = ["rows": rows, "itemID": itemID,
            "passed": rows.count == 7 && rows.allSatisfy { $0["failed"] == nil },
            "timingBoundary": "Steam selection entry to matching committed Web request; up to 20ms polling"]
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: .atomic)
        } catch { NSLog("MWX Web startup report failed: %@", error.localizedDescription) }
    }

    private static func waitUntil(_ test: () -> Bool, attempts: Int = 150) async -> Bool {
        for _ in 0..<attempts {
            if test() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private static func postWeb(root: URL, entry: String = "index.html", recordID: String = "debug-process-isolation", requestID: UUID = UUID()) {
        NotificationCenter.default.post(name: .steamWorkshopWebWallpaperReadyToPlay, object: nil,
            userInfo: ["requestID": requestID, "entryURL": root.appendingPathComponent(entry), "rootURL": root,
                "propertiesJSON": "{}", "recordID": recordID, "language": "en-us",
                "runtimeProfile": WallpaperEngine.WebRuntimeProfile.diagnostic])
    }

    private static func run(reportURL: URL) async {
        // Long waits with no windows/audio are intentional. Keep this bounded
        // harness awake; App Nap must not turn an expiry check into a timer test.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Bounded playback lifecycle validation")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let engine = WallpaperEngine.shared
        guard let host = engine.dedicatedWebHostAdapter as? WebDaemonHostAdapter else { return }
        let root = reportURL.deletingLastPathComponent().appendingPathComponent("fixture")
        var checks: [String: Bool] = [:]
        var metrics: [String: Double] = [:]
        var failureFacts: [String: String] = [:]
        var notCovered: [String: String] = [:]
        var pids: [Int32] = []
        var expectedChecks = 23
        defer {
            engine.stopPlayback()
            let complete = checks.count + notCovered.count == expectedChecks
            let outcome = !complete || checks.values.contains(false) ? "failed"
                : notCovered.isEmpty ? "passed" : "incomplete"
            let report: [String: Any] = ["checks": checks, "metrics": metrics, "failureFacts": failureFacts,
                "notCovered": notCovered, "outcome": outcome,
                "processes": pids, "parentPID": ProcessInfo.processInfo.processIdentifier,
                "passed": outcome == "passed"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: reportURL, options: .atomic)
            }
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try """
            <html><body style="background:#123;color:white"><h1>Web process isolation</h1>
            <script>wallpaperRegisterAudioListener(x=>{window.lastSpectrum=x;});</script></body></html>
            """.write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        } catch { return }
        var settings = WallpaperSettings()
        settings.pauseWhenOtherAppFocused = false
        settings.pauseWhenOtherAppFullscreen = false
        settings.pauseWhenUnplugged = false
        settings.pauseWhenIdle = false
        PlaybackPolicyController.shared.updateSettings(settings)
        host.prepareIdleProcess()
        let idleID = host.availablePreparedRequestID
        let idlePIDs = host.liveProcessIdentifiers
        if let idleID {
            checks["idlePrewarmHasNoUserRequest"] = idlePIDs.count == 1
                && !host.hasPendingRequest && host.activeRequest == nil && host.activeRecordIDs.isEmpty
                && host.inUsePersistentDataStoreIdentifiers.isEmpty
            let adoptedIdle = SteamWorkshopService.shared.prepareWebPlaybackProcess?()
            checks["idlePrewarmAdoptedOriginalIdentity"] = adoptedIdle?.requestID == idleID
                && host.liveProcessIdentifiers == idlePIDs && host.hasPendingRequest
            postWeb(root: root, requestID: idleID)
            guard await waitUntil({ host.activeRequest?.id == idleID }) else { return }
            // Cross the original idle deadline after full launch. A cancelled old
            // prewarm timeout must never retire the now-active content process.
            try? await Task.sleep(for: .seconds(31))
            checks["adoptedIdleSurvivesOriginalDeadline"] = host.activeRequest?.id == idleID
                && host.debugActiveProcessIdentifier == idlePIDs.first
                && idlePIDs.allSatisfy { kill($0, 0) == 0 }
            adoptedIdle?.cancel()
        } else {
            for name in ["idlePrewarmHasNoUserRequest", "idlePrewarmAdoptedOriginalIdentity",
                         "adoptedIdleSurvivesOriginalDeadline"] {
                notCovered[name] = "precondition-idle-process-not-created: \(host.debugPreparationFacts)"
            }
        }
        engine.stopPlayback()
        guard await waitUntil({ host.liveProcessIdentifiers.isEmpty }) else { return }
        NSLog("MWX DEBUG IDLE: before-expiry-test %@", host.debugPreparationFacts)
        host.prepareIdleProcess()
        let expiringPID = host.liveProcessIdentifiers.first
        checks["noRendererDemandDoesNotCaptureAudio"] = await waitUntil {
            !engine.systemAudioSpectrumService.debugHasCaptureResources
        }
        failureFacts["idleExpiryInitial"] = host.debugPreparationFacts
        NSLog("MWX DEBUG IDLE: expiry-start %@", host.debugPreparationFacts)
        if let expiringPID {
            checks["unusedIdlePrewarmExpires"] = await waitUntil({
                host.availablePreparedRequestID == nil && host.liveProcessIdentifiers.isEmpty
                    && kill(expiringPID, 0) != 0 && errno == ESRCH
            }, attempts: 350)
        } else {
            notCovered["unusedIdlePrewarmExpires"] =
                "precondition-idle-process-not-created: \(host.debugPreparationFacts)"
        }
        failureFacts["idleExpiryFinal"] = host.debugPreparationFacts
        NSLog("MWX DEBUG IDLE: expiry-finished %@", host.debugPreparationFacts)
        let cancelledID = UUID()
        host.prepareProcess(requestID: cancelledID)
        let cancelledPID = host.liveProcessIdentifiers.first
        host.cancelPreparedProcess(requestID: cancelledID)
        checks["preparedCancellation"] = await waitUntil {
            host.liveProcessIdentifiers.isEmpty && cancelledPID.map { kill($0, 0) != 0 && errno == ESRCH } == true
        }
        let stopPreparation = SteamWorkshopService.shared.prepareWebPlaybackProcess?()
        let stoppedPreparedPID = host.liveProcessIdentifiers.first
        WallpaperManager.shared.stopCurrentPlayback()
        checks["preparedStopInvalidation"] = await waitUntil {
            stopPreparation?.isCurrent() == false && host.liveProcessIdentifiers.isEmpty
                && stoppedPreparedPID.map { kill($0, 0) != 0 && errno == ESRCH } == true
        }
        let firstID = UUID()
        host.prepareProcess(requestID: firstID)
        let preparedPIDs = host.liveProcessIdentifiers
        // Adopt before hello, exercising partial framing/callback transfer.
        postWeb(root: root, requestID: firstID)
        guard await waitUntil({ host.activeRequest?.id == engine.currentWebRequestID && host.activeRequest != nil }),
              let first = host.activeRequest else { checks["started"] = false; return }
        pids = host.liveProcessIdentifiers
        checks["started"] = pids.count == 1 && pids == preparedPIDs
            && pids[0] != ProcessInfo.processInfo.processIdentifier
        // Device/tap initialization is a separate cold-start stage. Measure
        // continuity only after the real producer has actually supplied music.
        guard await waitUntil({ engine.spectrumDelivery.currentWebLevels.contains { $0 > 0.001 } }) else {
            checks["realMusicContinued"] = false
            return
        }
        host.debugContinuityStartedHandler = { Thread.sleep(forTimeInterval: 1.25) }
        var result: [String: Double]?
        host.debugContinuityHandler = { result = $0 }
        host.debugMeasureContinuity()
        guard await waitUntil({ result != nil }), let result else { return }
        metrics = result
        metrics["parentMainBlockedMs"] = 1_250
        checks["pageContinued"] = (result["frames"] ?? 0) > 60 && (result["maxGapMs"] ?? .infinity) < 250
        checks["childMainContinued"] = (result["nativeMaxGapMs"] ?? .infinity) < 200
        checks["realMusicContinued"] = (result["spectrumFrames"] ?? 0) > 35
            && (result["nonSilentSpectrumFrames"] ?? 0) > 25
            && (result["pageSpectrumFrames"] ?? 0) > 35
            && (result["changedSpectrumFrames"] ?? 0) > 25

        // Invalid candidate must not retire an already committed Web process.
        postWeb(root: root, entry: "missing.html", recordID: "debug-invalid-candidate")
        checks["failedCandidateKeptActive"] = await waitUntil {
            !host.hasPendingRequest && host.activeRequest?.id == first.id && engine.currentWebRequestID == first.id
        }
        host.debugTerminateActiveProcess()
        checks["crashRecovered"] = await waitUntil {
            host.activeRequest?.id == first.id
                && !host.liveProcessIdentifiers.isEmpty
                && Set(host.liveProcessIdentifiers).isDisjoint(with: pids)
        }
        pids += host.liveProcessIdentifiers
        let retainedWebID = host.activeRequest?.id
        // Preparing another Web may cancel a published candidate, but an early
        // validation return must restore the actual active request projection.
        postWeb(root: root, requestID: UUID())
        let staleAutoplay = ImportedVideoAutoplayGate.shared.claim()
        let unusedPreparation = SteamWorkshopService.shared.prepareWebPlaybackProcess?()
        checks["newIntentRevokedAutoplay"] = !ImportedVideoAutoplayGate.shared.isCurrent(staleAutoplay)
        unusedPreparation?.cancel()
        checks["cancelledCandidateRestoredProjection"] = await waitUntil {
            !host.hasPendingRequest && host.activeRequest?.id == retainedWebID
                && engine.currentWebRequestID == retainedWebID
                && engine.currentPlaybackContentKind == .web
        }
        let badVideoURL = root.appendingPathComponent("corrupt.mp4")
        try? Data("not a playable media asset".utf8).write(to: badVideoURL)
        let badVideo = VideoWallpaper(title: "Invalid video candidate", path: badVideoURL.path)
        WallpaperManager.shared.setAsWallpaper(badVideo, userInitiated: true)
        checks["badVideoRestoredWeb"] = await waitUntil {
            WallpaperManager.shared.pendingWallpaper == nil
                && WallpaperManager.shared.activeWallpaperRuntime == .web
                && WallpaperManager.shared.requestedRuntime == .web
                && engine.currentPlaybackContentKind == .web
                && engine.currentWebRequestID == retainedWebID && engine.currentWallpaper == nil
                && engine.displaySessions.isEmpty && host.activeRequest?.id == retainedWebID
        }
        if checks["badVideoRestoredWeb"] != true {
            failureFacts["badVideoRestoredWeb"] = "pending=\(WallpaperManager.shared.pendingWallpaper?.path ?? "nil") requested=\(String(describing: WallpaperManager.shared.requestedRuntime)) engine=\(String(describing: engine.currentPlaybackContentKind)) path=\(engine.currentContentPath ?? "nil") web=\(String(describing: engine.currentWebRequestID)) active=\(String(describing: host.activeRequest?.id)) sessions=\(engine.displaySessions.count)"
        }
        guard let videoURL = BundledVideoLibrary.videoURL(named: "Video2") else { return }
        let video = VideoWallpaper(title: "Isolation video", path: videoURL.path)
        WallpaperManager.shared.setAsWallpaper(video, userInitiated: true)
        let supersededVideoPIDs = engine.displaySessions.values.map { $0.process.processIdentifier }
        postWeb(root: root)
        checks["webVideoWebCancelledCandidate"] = await waitUntil {
            engine.displaySessions.isEmpty && host.activeRequest?.id == engine.currentWebRequestID
                && host.activeRequest?.id != retainedWebID
                && supersededVideoPIDs.allSatisfy { kill($0, 0) != 0 && errno == ESRCH }
        }
        WallpaperManager.shared.setAsWallpaper(video, userInitiated: true)
        checks["webToVideo"] = await waitUntil {
            WallpaperManager.shared.activeWallpaperRuntime == .video
                && host.liveProcessIdentifiers.isEmpty && !engine.displaySessions.isEmpty
                && engine.displaySessions.values.allSatisfy {
                    $0.latestReadyPlayRequestID != nil && $0.latestReadyPlayRequestID == $0.latestRequestedPlayRequestID
                }
        }
        checks["videoOverlayCaptureRestored"] = await waitUntil {
            engine.spectrumDelivery.currentOverlayLevels.contains { $0 > 0.001 }
        }
        // This must reach AVPlayer failure, rather than missing-file admission.
        let originalLibrary = WallpaperManager.shared.wallpapers
        WallpaperManager.shared.wallpapers = [video]
        postWeb(root: root)
        WallpaperManager.shared.setAsWallpaper(badVideo, userInitiated: true)
        checks["videoWebBadVideoKeptCommittedVideo"] = await waitUntil {
            WallpaperManager.shared.pendingWallpaper == nil && !host.hasPendingRequest
                && host.activeRequest == nil && engine.currentPlaybackContentKind == .video
                && engine.currentWallpaper?.path == video.path
                && WallpaperManager.shared.currentWallpaper?.path == video.path
                && !engine.displaySessions.isEmpty
        }
        if checks["videoWebBadVideoKeptCommittedVideo"] != true {
            failureFacts["videoWebBadVideoKeptCommittedVideo"] = "pending=\(WallpaperManager.shared.pendingWallpaper?.path ?? "nil") requested=\(String(describing: WallpaperManager.shared.requestedRuntime)) engine=\(String(describing: engine.currentPlaybackContentKind)) path=\(engine.currentContentPath ?? "nil") model=\(engine.currentWallpaper?.path ?? "nil") manager=\(WallpaperManager.shared.currentWallpaper?.path ?? "nil") sessions=\(engine.displaySessions.count)"
        }
        WallpaperManager.shared.wallpapers = originalLibrary
        postWeb(root: root)
        checks["videoToWeb"] = await waitUntil {
            WallpaperManager.shared.activeWallpaperRuntime == .web
                && host.activeRequest?.id == engine.currentWebRequestID && host.activeRequest != nil
                && engine.displaySessions.isEmpty
        }
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--mwx-debug-isolation-scene-root"), args.indices.contains(index + 1) {
            expectedChecks = 30
            let sceneRoot = URL(fileURLWithPath: args[index + 1])
            func postScene() {
                NotificationCenter.default.post(name: .steamWorkshopSceneReadyToRender, object: nil,
                    userInfo: ["request": SteamWorkshopScenePlaybackRequest(rootURL: sceneRoot,
                        propertyOverrides: [:], userPropertyTextures: [:], recordID: "debug-isolation-scene", resourceLifetime: nil)])
            }
            func sceneCommitted() -> Bool {
                WallpaperManager.shared.activeWallpaperRuntime == .scene
                    && engine.currentPlaybackContentKind == nil
                    && host.liveProcessIdentifiers.isEmpty
                    && SceneDaemonClient.shared.activeRecordID == "debug-isolation-scene"
            }
            WallpaperManager.shared.setAsWallpaper(video, userInitiated: true)
            let cancelledVideoPIDs = engine.displaySessions.values.map { $0.process.processIdentifier }
            postScene()
            checks["webVideoSceneCancelledCandidate"] = engine.displaySessions.isEmpty
                && engine.currentPlaybackContentKind == .web
            checks["webToScene"] = await waitUntil(sceneCommitted, attempts: 600)
            checks["webVideoSceneCancelledCandidate"] = checks["webVideoSceneCancelledCandidate"] == true
                && cancelledVideoPIDs.allSatisfy { kill($0, 0) != 0 && errno == ESRCH }
            let activeSceneRequest = SceneDaemonClient.shared.activeRequestID
            postScene()
            postWeb(root: root, entry: "missing.html", recordID: "debug-scene-cancel-web-failure")
            checks["activeSceneCandidateCancelled"] = await waitUntil {
                !host.hasPendingRequest && host.activeRequest == nil
                    && SceneDaemonClient.shared.pendingIntent == nil
                    && SceneDaemonClient.shared.activeRequestID == activeSceneRequest
                    && WallpaperManager.shared.activeWallpaperRuntime == .scene
            }
            WallpaperManager.shared.setAsWallpaper(video, userInitiated: true)
            checks["sceneToVideo"] = await waitUntil {
                WallpaperManager.shared.activeWallpaperRuntime == .video
                    && SceneDaemonClient.shared.activeIntent == nil
            }
            postScene()
            postWeb(root: root, entry: "missing.html", recordID: "debug-pending-scene-web-failure")
            checks["pendingSceneSupersededBeforeHello"] = await waitUntil {
                !host.hasPendingRequest && host.activeRequest == nil
                    && SceneDaemonClient.shared.pendingIntent == nil
                    && SceneDaemonClient.shared.activeIntent == nil
                    && SceneDaemonClient.shared.retiringTransports.values.allSatisfy { !$0.isRunning }
                    && engine.currentPlaybackContentKind == .video
                    && WallpaperManager.shared.activeWallpaperRuntime == .video
            }
            postScene()
            checks["videoToScene"] = await waitUntil(sceneCommitted, attempts: 600)
            postWeb(root: root)
            checks["sceneToWeb"] = await waitUntil {
                WallpaperManager.shared.activeWallpaperRuntime == .web
                    && host.activeRequest?.id == engine.currentWebRequestID && host.activeRequest != nil
                    && SceneDaemonClient.shared.activeIntent == nil
            }
        }
        let previousID = host.activeRequest?.id
        let nextID = UUID()
        host.prepareProcess(requestID: nextID)
        guard await waitUntil({ host.debugPreparedProcessReady }) else { return }
        let nextPID = host.liveProcessIdentifiers.last
        // Adopt after hello without letting an old cancellation retire it.
        postWeb(root: root, requestID: nextID)
        host.cancelPreparedProcess(requestID: nextID)
        checks["webToWeb"] = await waitUntil {
            host.activeRequest != nil && host.activeRequest?.id != previousID
                && host.activeRequest?.id == engine.currentWebRequestID
                && host.liveProcessIdentifiers.count == 1
                && host.liveProcessIdentifiers.first == nextPID
        }
        engine.stopPlayback()
        // A cancelled delayed warmup must not resurrect a renderer after stop.
        try? await Task.sleep(for: .seconds(3))
        checks["stoppedAllProcesses"] = await waitUntil {
            host.liveProcessIdentifiers.isEmpty && engine.displaySessions.isEmpty
                && SceneDaemonClient.shared.retiringTransports.values.allSatisfy { !$0.isRunning }
        }
    }
}
#endif
