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

    /// Real product selection and transaction, with no direct-host runner flag.
    /// `single` supports separate App launches against empty/retained HOME;
    /// `sequence` retains the same App and its normal prepared-process policy.
    /// Neither mode claims a cold OS or WebKit cache. Report the stored finalize
    /// timestamp separately from polling observation and its scheduling delay.
    private static func measureStartup(reportURL: URL, itemID: String) async {
        let engine = WallpaperEngine.shared
        let manager = WallpaperManager.shared
        let originalSettings = manager.settings
        var result: [String: Any] = [
            "passed": false, "rows": [[String: Any]](), "itemID": itemID,
            "timingSchemaVersion": 3,
            "parentPID": ProcessInfo.processInfo.processIdentifier,
            "foundationHome": FileManager.default.homeDirectoryForCurrentUser.path,
            "environmentHome": ProcessInfo.processInfo.environment["HOME"] ?? "",
            "fixedUserHome": ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? "",
            "webKitPIDs": "unknown", "systemCacheState": "unknown",
            "timingBoundary": "Product selection entry to matching Web session.committedAt (parent Host finalize)",
            "observationTimingBoundary": "Matching committed/finalized execution observed by nominal 20ms polling; scheduling delay is measured, not bounded",
            "startupTimingScope": "Parent and matching child monotonic event callbacks; prepared-process hello may precede selection; WebKit internals and physical presentation unknown",
            "activationSentBoundary": "Parent enqueue of accepted candidate activate; not pipe completion or child receipt",
            "childStartupTimingBoundary": "Accepted activate handler, current native-policy ACK, and first all-surface visibility observation; producer times, not parent receive times",
            "childPreparationTimingBoundary": "Current prepared cohort snapshot; complete surface creation, load issued and first ready source; native-policy interval is remaining wait, not necessarily a new native call",
            "cacheObservationScope": "Manifest metadata only; presence does not prove a cache hit",
            "launchReplaySuppressed": true,
            "audioIsSeparateGate": true
        ]
        defer {
            manager.stopCurrentPlayback()
            manager.settings = originalSettings
            do {
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: reportURL, options: .atomic)
            } catch { NSLog("MWX Web startup report failed: %@", error.localizedDescription) }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        let args = ProcessInfo.processInfo.arguments
        let mode: String
        if let index = args.firstIndex(of: "--mwx-debug-web-startup-mode") {
            guard args.indices.contains(index + 1), ["single", "sequence"].contains(args[index + 1]) else {
                result["failure"] = "startup-mode-must-be-single-or-sequence"; return
            }
            mode = args[index + 1]
        } else { mode = "sequence" }
        result["mode"] = mode
        result["standardDefaultsDomain"] = Bundle.main.bundleIdentifier ?? ""
        result["standardDefaultsSentinelVerified"] = DebugWebPlaybackRunner.hasIsolatedStartupEnvironment
        result["productCoordinatorConfigured"] = manager.runtimeSwitchingConfigured
        guard DebugWebPlaybackRunner.hasIsolatedStartupEnvironment,
              DebugWebPlaybackRunner.hasUsableWorkshopRoot,
              manager.runtimeSwitchingConfigured,
              let host = engine.dedicatedWebHostAdapter as? WebDaemonHostAdapter else {
            result["failure"] = "isolated-product-coordinator-required"; return
        }
        var settings = WallpaperSettings()
        settings.pauseWhenOtherAppFocused = false
        settings.pauseWhenOtherAppFullscreen = false
        settings.pauseWhenUnplugged = false
        settings.pauseWhenIdle = false
        manager.settings = settings
        result["policyConfiguration"] = "Four automatic pause conditions disabled; default remaining WallpaperSettings"
        guard let rawFPS = DebugScenePlaybackRunner.argumentValue(after: "--mwx-debug-startup-fps"),
              let fps = Int(rawFPS), let profile = PlaybackPerformanceProfile(rawValue: fps) else {
            result["failure"] = "startup-fps-must-be-30-or-60"; return
        }
        PlaybackPerformanceProfile.save(profile)
        PlaybackCommandMultiplexer.shared.dispatch(.setPerformanceProfile(maxFPS: fps))
        result["appliedFPS"] = PlaybackPerformanceProfile.current.maxFPS
        PlaybackCommandMultiplexer.shared.dispatch(.resume)
        let service = SteamWorkshopService.shared
        service.reloadInstalledItems()
        guard let record = await DebugWebPlaybackRunner.awaitInstalledRecord(itemID, using: service),
              record.contentType == .web else {
            result["failure"] = "web-record-unavailable"; return
        }
        result["workshopRoot"] = service.libraryRootURL.path
        result["recordRoot"] = record.folderURL.path
        result["entryPath"] = record.webEntryURL?.path ?? ""
        let selections = mode == "single" ? 1 : 7
        let removePrepared = args.contains("--mwx-debug-web-startup-no-prepared-process")
        var rows: [[String: Any]] = []
        for index in 0..<selections {
            let removesPrepared = removePrepared
            if removesPrepared {
                host.cancelPreparation()
                guard await waitUntil({
                    host.preparedProcess == nil && host.retiringPrepared.isEmpty
                }, attempts: 30) else {
                    rows.append(["index": index, "recordID": itemID, "failed": true,
                        "failure": "prepared-process-did-not-exit"])
                    break
                }
            }
            let before = host.liveProcessIdentifiers
            let preparationFacts = host.debugPreparationFacts
            let previous = host.activeRequest?.id
            let cacheBefore = startupCacheFacts(service: service, record: record)
            let started = ProcessInfo.processInfo.systemUptime
            WallpaperManager.shared.requestDiagnosticPlayback(reference: .init(provider: .steamWorkshop, sourceID: record.id),
                                                               runtime: .web) { pending in
                service.setAsWallpaper(record, libraryPending: pending)
            }
            let selectedEpoch = manager.playbackIntentEpoch
            var completed = false
            let deadline = started + 45
            while ProcessInfo.processInfo.systemUptime < deadline {
                if let request = host.activeRequest, request.id != previous,
                   request.recordID == itemID, engine.currentWebRequestID == request.id,
                   let session = host.active,
                   let committedAt = session.committedAt, committedAt >= started,
                   let committed = manager.playbackSwitch.committed,
                   committed.ticket.epoch == selectedEpoch, committed.ticket.runtime == .web,
                   committed.executionID == session.executionID,
                   manager.activeWallpaperRuntime == .web,
                   manager.lastWorkshopPlaybackRecordID == itemID,
                   !host.hasPendingRequest {
                    let pid = host.debugActiveProcessIdentifier
                    let observedAt = ProcessInfo.processInfo.systemUptime
                    var row: [String: Any] = ["index": index, "preparedProcessRemovalRequested": removesPrepared,
                        "entryToCommitMs": (committedAt - started) * 1_000,
                        "entryToCommitObservedMs": (observedAt - started) * 1_000,
                        "commitObservationDelayMs": (observedAt - committedAt) * 1_000,
                        "recordID": itemID,
                        "requestID": request.id.uuidString, "beforePIDs": before, "activePID": pid ?? 0,
                        "preparationFacts": preparationFacts,
                        "selectionUptime": started, "committedAt": committedAt,
                        "committedExecutionObservedUptime": observedAt,
                        "intentEpoch": selectedEpoch, "ticketID": committed.ticket.id.uuidString,
                        "executionID": session.executionID.uuidString,
                        "runtimeProfile": request.runtimeProfile.id,
                        "originMode": request.runtimeProfile.originMode.rawValue,
                        "dataStorePolicy": request.runtimeProfile.dataStorePolicy.rawValue,
                        "cacheBefore": cacheBefore,
                        "cacheAfter": startupCacheFacts(service: service, record: record),
                        "adoptedExistingProcess": pid.map { before.contains($0) } ?? false]
                    if let timing = session.startupTiming {
                        var parentTimes: [String: TimeInterval] = ["finalized": committedAt]
                        parentTimes["helloReceived"] = timing.helloReceivedAt
                        parentTimes["launchEnqueued"] = timing.launchEnqueuedAt
                        parentTimes["preparedCohortAccepted"] = timing.preparedCohortAcceptedAt
                        parentTimes["activationSent"] = timing.activationSentAt
                        parentTimes["activationConfirmedAccepted"] = timing.activationConfirmedAcceptedAt
                        row["parentStartupUptime"] = parentTimes
                    }
                    row["childStartupTimingStatus"] = "unavailable"
                    row["childPreparationTimingStatus"] = "unavailable"
                    row["childStartupUptime"] = NSNull()
                    if let timing = session.matchingChildStartupTiming {
                        var childTimes: [String: TimeInterval] = ["activateReceived": timing.activateReceivedAt]
                        childTimes["nativePolicyAccepted"] = timing.nativePolicyAcceptedAt
                        childTimes["visibilityFirstConfirmed"] = timing.visibilityFirstConfirmedAt
                        childTimes["firstVisibilityRetry"] = timing.firstVisibilityRetryAt
                        row["childStartupUptime"] = childTimes
                        row["childStartupTimingStatus"] = "matched-activation"
                        row["childStartupActivation"] = ["generation": timing.identity.generation,
                            "activationID": timing.identity.activationID.uuidString] as [String: Any]
                        row["childStartupFirstVisibilityRetryReason"] = timing.firstVisibilityRetryReason as Any? ?? NSNull()
                        if let preparation = timing.preparation,
                           preparation.generation == timing.identity.generation,
                           preparation.surfaces == session.preparedCohort?.surfaces {
                            var times: [String: TimeInterval] = ["launchReceived": preparation.launchReceivedAt]
                            times["hostReady"] = preparation.hostReadyAt
                            times["snapshotRequested"] = preparation.snapshotRequestedAt
                            times["snapshotCompleted"] = preparation.snapshotCompletedAt
                            times["policyWaitStarted"] = preparation.policyWaitStartedAt
                            times["policyAccepted"] = preparation.policyAcceptedAt
                            row["childPreparationUptime"] = times
                            row["childPreparationGeneration"] = preparation.generation
                            row["childSurfacePreparationCoverage"] = preparation.surfaceTimings.count == preparation.surfaces.count
                                ? "complete" : "partial"
                            row["childSurfacePreparation"] = preparation.surfaceTimings.map { surface in
                                var value: [String: Any] = ["displayID": surface.displayID,
                                    "creationStarted": surface.creationStartedAt]
                                value["surfaceID"] = surface.surfaceID?.uuidString
                                value["navigationGeneration"] = surface.navigationGeneration
                                value["creationCompleted"] = surface.creationCompletedAt
                                value["loadIssued"] = surface.loadIssuedAt
                                value["readyObserved"] = surface.readyObservedAt
                                value["readySource"] = surface.readySource
                                return value
                            }
                            row["childPreparationTimingStatus"] = "matched-prepared-cohort"
                        }
                    }
                    rows.append(row)
                    completed = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            if !completed {
                rows.append(["index": index, "failed": true, "failure": "matching-product-commit-not-observed",
                    "recordID": itemID, "intentEpoch": selectedEpoch,
                    "preparationFacts": host.debugPreparationFacts])
                break
            }
            if index + 1 < selections { try? await Task.sleep(for: .seconds(3)) }
        }
        result["rows"] = rows
        result["passed"] = rows.count == selections && rows.allSatisfy { $0["failed"] == nil }
    }

    private static func startupCacheFacts(
        service: SteamWorkshopService, record: SteamWorkshopDownloadRecord
    ) -> [String: Any] {
        func metadata(_ url: URL) -> [String: Any] {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                return ["path": url.path, "exists": false]
            }
            return ["path": url.path, "exists": true, "bytes": values.fileSize ?? 0,
                "modifiedAt": values.contentModificationDate?.timeIntervalSince1970 ?? 0]
        }
        return ["analysis": metadata(service.webAnalysisCacheFileURL(for: record)),
            "descriptorMemoPresent": service.webProjectDescriptorCache[record.id] != nil]
    }

    private static func waitUntil(_ test: () -> Bool, attempts: Int = 150) async -> Bool {
        for _ in 0..<attempts {
            if test() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private static func postWeb(root: URL, entry: String = "index.html", recordID: String = "debug-process-isolation",
                                requestID: UUID = UUID(),
                                preparation: WallpaperLibraryPlaybackRouting.DiagnosticWebPreparation? = nil) {
        WallpaperLibraryPlaybackRouting.postDiagnosticWeb(entryURL: root.appendingPathComponent(entry), rootURL: root,
            recordID: recordID, requestID: requestID, preparation: preparation)
    }

    private static func run(reportURL: URL) async {
        // Long waits with no windows/audio are intentional. Keep this bounded
        // harness awake; App Nap must not turn an expiry check into a timer test.
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Bounded playback lifecycle validation")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let engine = WallpaperEngine.shared
        guard let host = engine.dedicatedWebHostAdapter as? WebDaemonHostAdapter else { return }
        let originalSettings = WallpaperManager.shared.settings
        let root = reportURL.deletingLastPathComponent().appendingPathComponent("fixture")
        var checks: [String: Bool] = [:]
        var metrics: [String: Double] = [:]
        var failureFacts: [String: String] = [:]
        var notCovered: [String: String] = [:]
        var pids: [Int32] = []
        var expectedChecks = 25
        defer {
            WallpaperManager.shared.stopCurrentPlayback()
            WallpaperManager.shared.settings = originalSettings
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
        // Install the complete public policy so a later spectrum-only edit
        // cannot reintroduce persisted pause conditions into this music test.
        WallpaperManager.shared.settings = settings
        PlaybackCommandMultiplexer.shared.dispatch(.resume)
        host.prepareIdleProcess()
        let idleID = host.availablePreparedRequestID
        let idlePIDs = host.liveProcessIdentifiers
        if let idleID {
            checks["idlePrewarmHasNoUserRequest"] = idlePIDs.count == 1
                && !host.hasPendingRequest && host.activeRequest == nil && host.activeRecordIDs.isEmpty
                && host.inUsePersistentDataStoreIdentifiers.isEmpty
            let adoptedIdle = WallpaperLibraryPlaybackRouting.prepareDiagnosticWebProcess()
            checks["idlePrewarmAdoptedOriginalIdentity"] = adoptedIdle?.requestID == idleID
                && host.liveProcessIdentifiers == idlePIDs && host.hasPendingRequest
            postWeb(root: root, requestID: idleID, preparation: adoptedIdle)
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
        WallpaperManager.shared.stopCurrentPlayback()
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
        let stopPreparation = WallpaperLibraryPlaybackRouting.prepareDiagnosticWebProcess()
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
            failureFacts["realMusicContinued"] = "paused=\(PlaybackCommandMultiplexer.shared.isPlaybackPaused) userPaused=\(PlaybackCommandMultiplexer.shared.isUserPaused) demand=\(host.audioSpectrumRequested) engineDemand=\(engine.currentWebAudioSpectrumRequested) capture=\(engine.systemAudioSpectrumService.debugHasCaptureResources) peak=\(engine.spectrumDelivery.currentWebLevels.max() ?? 0)"
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
        let unusedPreparation = WallpaperLibraryPlaybackRouting.prepareDiagnosticWebProcess()
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
        WallpaperManager.shared.requestDiagnosticVideo(badVideo)
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
        WallpaperManager.shared.requestDiagnosticVideo(video)
        let supersededVideoPIDs = engine.displaySessions.values.map { $0.process.processIdentifier }
        postWeb(root: root)
        checks["webVideoWebCancelledCandidate"] = await waitUntil {
            engine.displaySessions.isEmpty && host.activeRequest?.id == engine.currentWebRequestID
                && host.activeRequest?.id != retainedWebID
                && supersededVideoPIDs.allSatisfy { kill($0, 0) != 0 && errno == ESRCH }
        }
        // The Video overlay is an independent, default-off public setting.
        // Web listener demand must not accidentally satisfy this assertion.
        WallpaperManager.shared.settings.systemAudioSpectrumEnabled = true
        WallpaperManager.shared.requestDiagnosticVideo(video)
        checks["webToVideo"] = await waitUntil {
            WallpaperManager.shared.activeWallpaperRuntime == .video
                && host.liveProcessIdentifiers.isEmpty && !engine.displaySessions.isEmpty
                && engine.displaySessions.values.allSatisfy {
                    $0.latestReadyPlayRequestID != nil && $0.latestReadyPlayRequestID == $0.latestRequestedPlayRequestID
                }
        }
        if let alternateURL = BundledVideoLibrary.videoURL(named: "Video3") {
            let alternate = VideoWallpaper(title: "Alternate isolation video", path: alternateURL.path)
            let oldPlayback = engine.activeVideoPlayback?.id
            WallpaperManager.shared.requestDiagnosticVideo(alternate)
            let replaced = await waitUntil { engine.currentWallpaper?.path == alternate.path
                && WallpaperManager.shared.pendingWallpaper == nil && engine.activeVideoPlayback?.id != oldPlayback }
            WallpaperManager.shared.requestDiagnosticVideo(video)
            checks["videoToVideo"] = await waitUntil { replaced && engine.currentWallpaper?.path == video.path
                && WallpaperManager.shared.pendingWallpaper == nil }
        } else { checks["videoToVideo"] = false }
        checks["videoOverlayCaptureRestored"] = await waitUntil {
            engine.currentSystemAudioSpectrumEnabled
                && engine.systemAudioSpectrumService.debugHasCaptureResources
                && engine.spectrumDelivery.currentOverlayLevels.contains { $0 > 0.001 }
        }
        if checks["videoOverlayCaptureRestored"] != true {
            failureFacts["videoOverlayCaptureRestored"] = "enabled=\(engine.currentSystemAudioSpectrumEnabled) capture=\(engine.systemAudioSpectrumService.debugHasCaptureResources) sessions=\(engine.displaySessions.count) peak=\(engine.spectrumDelivery.currentOverlayLevels.max() ?? 0)"
        }
        // This must reach AVPlayer failure, rather than missing-file admission.
        let originalLibrary = WallpaperManager.shared.wallpapers
        WallpaperManager.shared.wallpapers = [video]
        postWeb(root: root)
        WallpaperManager.shared.requestDiagnosticVideo(badVideo)
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
            expectedChecks = 33
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
            WallpaperManager.shared.requestDiagnosticVideo(video)
            let cancelledVideoPIDs = engine.displaySessions.values.map { $0.process.processIdentifier }
            postScene()
            checks["webVideoSceneCancelledCandidate"] = engine.currentPlaybackContentKind == .web
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
            WallpaperManager.shared.requestDiagnosticVideo(video)
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
            let previousScene = SceneDaemonClient.shared.activeRequestID
            postScene()
            checks["sceneToScene"] = await waitUntil {
                sceneCommitted() && SceneDaemonClient.shared.activeRequestID != previousScene
            }
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
        let stoppedRequest = host.activeRequest?.id
        WallpaperManager.shared.stopCurrentPlayback()
        postWeb(root: root)
        checks["stopThenImmediateRestart"] = await waitUntil {
            host.activeRequest != nil && host.activeRequest?.id != stoppedRequest
                && host.activeRequest?.id == engine.currentWebRequestID
                && WallpaperManager.shared.playbackSwitch.retirements.isEmpty
        }
        WallpaperManager.shared.stopCurrentPlayback()
        // A cancelled delayed warmup must not resurrect a renderer after stop.
        try? await Task.sleep(for: .seconds(3))
        checks["stoppedAllProcesses"] = await waitUntil {
            host.liveProcessIdentifiers.isEmpty && engine.displaySessions.isEmpty
                && SceneDaemonClient.shared.retiringTransports.values.allSatisfy { !$0.isRunning }
        }
    }
}
#endif
