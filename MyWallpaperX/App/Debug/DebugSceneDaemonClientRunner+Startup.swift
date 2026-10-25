#if DEBUG
import AppKit
import Foundation

extension DebugSceneDaemonClientRunner {
    static func scheduleStartupIfRequested(rootURL: URL) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard DebugSceneProductEntryPolicy.isStartupMeasurementRequested(arguments: arguments)
            else { return false }
        DebugSceneStartupRun.start(rootURL: rootURL)
        return true
    }
}

/// Explicit measurement mode of the existing daemon runner. Every round enters
/// the ordinary settings action; observation never activates or commits output.
@MainActor
private final class DebugSceneStartupRun {
    private struct InvalidConfiguration: Error { let reason: String }
    private static var retained: DebugSceneStartupRun?
    private let reportURL: URL
    private let mode: String
    private let roots: [URL]
    private let timeoutSeconds: TimeInterval
    private let requestedFPS: Int?
    private var observers: [NSObjectProtocol] = []
    private var deadline: DispatchWorkItem?
    private var current: DebugSceneStartupMeasurement?
    private var currentFacts: [String: Any] = [:]
    private var rows: [[String: Any]] = []
    private var finished = false
    private var completionScheduled = false
    private var videoTicket: PlaybackSwitchTicket?
    private var videoFacts: [String: Any] = [:]
    private var wireObservations: [[String: Any]] = []
    private var wireObservationOverflowed = false

    private static func argument(_ flag: String) -> String? {
        DebugScenePlaybackRunner.argumentValue(after: flag)
    }

    static func start(rootURL: URL) {
        do {
            let run = try DebugSceneStartupRun(rootURL: rootURL)
            retained = run
            run.installObservers()
            run.selectNext()
        } catch {
            let reason = (error as? InvalidConfiguration)?.reason ?? String(describing: error)
            if let path = argument("--mwx-debug-scene-startup-report"), path.hasPrefix("/") {
                write(["schemaVersion": 1, "passed": false, "rows": [], "failure": reason],
                    to: URL(fileURLWithPath: path))
            }
            NSLog("MWX SCENE STARTUP: configuration failed: %@", reason)
            NSApp.terminate(nil)
        }
    }

    private init(rootURL: URL) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard DebugSceneDaemonClientRunner.requiresProductCoordinator,
              arguments.contains("--mwx-debug-scene-daemon-stable"),
              !arguments.contains("--mwx-debug-scene-evidence-dir"),
              !arguments.contains("--mwx-debug-scene-switch-root") else {
            throw InvalidConfiguration(reason: "requires-stable-product-entry-without-evidence-or-switch-smoke")
        }
        guard let mode = Self.argument("--mwx-debug-scene-startup-mode"),
              ["single", "sequence", "reentry-video"].contains(mode),
              let reportPath = Self.argument("--mwx-debug-scene-startup-report"),
              reportPath.hasPrefix("/") else {
            throw InvalidConfiguration(reason: "invalid-startup-mode-or-report")
        }
        self.mode = mode
        let reportTarget = URL(fileURLWithPath: reportPath).standardizedFileURL
        reportURL = reportTarget
        guard let realHome = DebugSceneProductEntryPolicy.protectedUserHomeURL(),
              let protected = DebugSceneProductEntryPolicy.protectedWorkshopRootURL(),
              let fixedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"],
              DebugSceneProductEntryPolicy.isolatedExistingDirectory(
                rawPath: fixedHome, disjointFrom: realHome) != nil,
              let workshopRoot = Self.argument("--mwx-debug-workshop-root"),
              DebugSceneProductEntryPolicy.isolatedExistingDirectory(
                rawPath: workshopRoot, disjointFrom: protected) != nil,
              Self.argument("--mwx-debug-user-defaults-suite")
                .map({ $0.hasPrefix("com.songziqiang.MyWallpaperX.Debug.") }) == true else {
            throw InvalidConfiguration(reason: "isolated-home-workshop-and-defaults-required")
        }
        func isolatedScene(_ path: String) throws -> URL {
            guard let url = DebugSceneProductEntryPolicy.isolatedExistingDirectory(
                rawPath: path, disjointFrom: protected),
                FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path),
                !reportTarget.path.hasPrefix(url.path + "/") else {
                throw InvalidConfiguration(reason: "isolated-scene-required")
            }
            return url
        }
        let first = try isolatedScene(rootURL.path)
        if let secondPath = Self.argument("--mwx-debug-scene-startup-second-root") {
            guard mode == "sequence" else { throw InvalidConfiguration(reason: "second-root-requires-sequence") }
            roots = [first, try isolatedScene(secondPath), first]
        } else { roots = mode == "single" ? [first] : [first, first] }
        if let raw = Self.argument("--mwx-debug-scene-duration") {
            guard let value = Double(raw), value.isFinite, (5...120).contains(value) else {
                throw InvalidConfiguration(reason: "invalid-row-timeout")
            }
            timeoutSeconds = value
        } else { timeoutSeconds = 45 }
        if arguments.contains("--mwx-debug-scene-performance-fps") {
            guard let raw = Self.argument("--mwx-debug-scene-performance-fps"),
                  let value = Int(raw), PlaybackPerformanceProfile(rawValue: value) != nil else {
                throw InvalidConfiguration(reason: "invalid-performance-profile")
            }
            requestedFPS = value
        } else { requestedFPS = nil }
        var settings = WallpaperManager.shared.settings
        settings.pauseWhenOtherAppFocused = false
        settings.pauseWhenOtherAppFullscreen = false
        settings.pauseWhenUnplugged = false
        settings.pauseWhenIdle = false
        WallpaperManager.shared.settings = settings
        let fps = requestedFPS ?? PlaybackPerformanceProfile.current.maxFPS
        _ = SceneDaemonClient.shared.handle(.setPerformanceProfile(maxFPS: fps))
    }

    private func installObservers() {
        let client = SceneDaemonClient.shared
        if mode == "reentry-video" {
            client.debugStartupWireObserver = { [weak self] generation, pid, uptime, payload in
                self?.observeWire(generation: generation, pid: pid, uptime: uptime, payload: payload)
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: .wallpaperSwitchDidFail, object: nil, queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, self.videoTicket != nil, !self.finished else { return }
                    self.finish(reason: notification.userInfo?["message"] as? String
                        ?? "Video product switch failed")
                }
            })
        }
        client.debugStartupPrefixObserver = { [weak self] observation in
            guard let self, !self.finished else { return }
            self.current?.observePrefix(observation.phase.rawValue,
                ticketID: observation.ticketID, intentEpoch: observation.intentEpoch,
                requestID: observation.requestID, daemonGeneration: observation.transportGeneration,
                daemonPID: observation.daemonPID, uptimeMicros: observation.uptimeMicros,
                childStartupUptimes: observation.childStartupUptimes)
        }
        client.debugStartupObserver = { [weak self] observation in
            guard let self, !self.finished else { return }
            self.current?.observeEndpoint(observation.phase.rawValue,
                ticketID: observation.ticketID, intentEpoch: observation.intentEpoch,
                requestID: observation.requestID, executionID: observation.executionID,
                daemonGeneration: observation.transportGeneration, daemonPID: observation.daemonPID,
                uptimeMicros: observation.uptimeMicros)
            self.completeCurrentIfReady()
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneWallpaperLaunchStateDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, !self.finished,
                      let state = notification.object as? SceneWallpaperLaunchState,
                      self.current?.recordID == state.recordID else { return }
                if state.phase == .failed || state.phase == .cancelled {
                    guard state.requestID == self.current?.requestID else { return }
                    self.current?.fail("launch-" + state.phase.rawValue)
                    self.finishCurrentAndStop(reason: state.message)
                    return
                }
                guard let ticket = client.pendingSwitchTicket,
                      self.current?.ticketID == ticket.id else { return }
                self.current?.observePhase(state.phase.rawValue, recordID: state.recordID,
                    ticketID: ticket.id, intentEpoch: ticket.epoch, requestID: state.requestID,
                    uptimeMicros: Self.now())
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneWallpaperFirstFrameDidPresent, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, !self.finished,
                      let value = notification.object as? SceneFramePresentation else { return }
                self.current?.observePresentation(requestID: value.requestID, recordID: value.recordID,
                    presentedUptimeMicros: value.uptimeMicros, observedUptimeMicros: Self.now())
                self.completeCurrentIfReady()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .sceneDaemonClientDidFail, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, !self.finished,
                      let value = notification.object as? SceneDaemonClientFailure,
                      value.recordID == self.current?.recordID else { return }
                self.current?.fail("daemon-" + value.code)
                self.finishCurrentAndStop(reason: value.message)
            }
        })
    }

    private func selectNext() {
        guard !finished, rows.count < roots.count else { return }
        let index = rows.count
        let root = roots[index]
        let recordID = root.lastPathComponent
        let client = SceneDaemonClient.shared
        currentFacts = [
            "beforeDaemonPID": client.debugProcessIdentifier.map { $0 as Any } ?? NSNull(),
            "beforeEndpointReady": client.endpointReady,
            "homePath": FileManager.default.homeDirectoryForCurrentUser.path,
            "cacheRootPath": FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first?.path ?? "",
            "shaderCacheOverridePath": ProcessInfo.processInfo.environment["MWX_SCENE_GENERIC_SHADER_CACHE"]
                .map { $0 as Any } ?? NSNull(),
            "appliedFPS": client.debugConfiguredMaximumFPS
        ]
        let record = SteamWorkshopDownloadRecord(id: recordID, title: root.lastPathComponent,
            description: "Isolated product startup measurement", tags: ["Scene"],
            folderURL: root, projectFileURL: root.appendingPathComponent("project.json"),
            ownEntryHTMLURL: nil, dependencyHostEntryHTMLURL: nil, dependencyHostFolderURL: nil,
            entryHTMLURL: nil, resolvedWebRootURL: nil, previewURL: nil, sourceVideoURL: nil,
            exportedVideoURL: nil, updatedAt: Date(), sizeText: "", status: .ready,
            browserItem: nil, contentType: .scene, dependencyItemID: nil, dependencyStatus: .none)
        current = .init(index: index, recordID: recordID, rootPath: root.path, entryUptimeMicros: Self.now())
        SteamWorkshopService.shared.setAsWallpaper(record)
        guard let ticket = WallpaperManager.shared.playbackSwitch.pending?.selection.ticket,
              ticket.runtime == .scene else {
            current?.fail("product-selection-not-admitted")
            finishCurrentAndStop(reason: "Scene product selection was not admitted")
            return
        }
        current?.bindSelection(ticketID: ticket.id, intentEpoch: ticket.epoch)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.current?.ticketID == ticket.id, !self.finished else { return }
            self.current?.fail("row-timeout")
            self.finishCurrentAndStop(reason: "Scene startup did not reach presented and parent finalize")
        }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: work)
    }

    private func completeCurrentIfReady() {
        guard current?.isComplete == true, !completionScheduled else { return }
        completionScheduled = true
        // Observers may run inside the client's finalize method. Leave that
        // product stack before selecting again or shutting the measurement down.
        DispatchQueue.main.async { [weak self] in self?.settleCompletedCurrent() }
    }

    private func settleCompletedCurrent() {
        completionScheduled = false
        guard !finished, current?.isComplete == true else { return }
        deadline?.cancel()
        deadline = nil
        // Observe the request that actually crossed the parent commit barrier.
        // A benchmark input path or a receipt beside it does not prove that
        // this playback request carried the managed source.
        if let intent = SceneDaemonClient.shared.activeIntent,
           intent.recordID == current?.recordID,
           SceneDaemonClient.shared.activeRequestID == current?.requestID {
            do {
                if let source = intent.source {
                    currentFacts["admittedSource"] = try SceneDaemonProtocol.sourceObject(source)
                } else {
                    currentFacts["admittedSource"] = NSNull()
                }
            } catch {
                current?.fail("admitted-source-observation-invalid")
            }
        } else {
            current?.fail("admitted-source-observation-missing")
        }
        appendCurrent()
        if rows.last?["passed"] as? Bool != true {
            finish(reason: "Scene startup observations were invalid")
        } else if rows.count == roots.count { finish(reason: nil) }
        else if mode == "reentry-video" { selectInterstitialVideo() }
        else {
            // Leave the current notification/finalize stack before another selection.
            DispatchQueue.main.async { [weak self] in self?.selectNext() }
        }
    }

    private func appendCurrent() {
        guard let current else { return }
        rows.append(current.report.merging(currentFacts) { _, facts in facts })
        self.current = nil
    }

    private func finishCurrentAndStop(reason: String) {
        appendCurrent()
        finish(reason: reason)
    }

    private func finish(reason: String?) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        SceneDaemonClient.shared.debugStartupObserver = nil
        SceneDaemonClient.shared.debugStartupPrefixObserver = nil
        if mode == "reentry-video" { SceneDaemonClient.shared.debugStartupWireObserver = nil }
        var report: [String: Any] = [
            "schemaVersion": 1, "mode": mode, "launchEntry": "steam-workshop-set-as-wallpaper",
            "passed": reason == nil && rows.count == roots.count
                && rows.allSatisfy { $0["passed"] as? Bool == true },
            "rows": rows, "timeoutSecondsPerRow": timeoutSeconds,
            "launchReplaySuppressed": !WallpaperManager.shared.settings.restorePlaybackOnLaunch,
            "requestedFPS": requestedFPS.map { $0 as Any } ?? NSNull(),
            "executablePath": Bundle.main.executableURL?.path ?? "",
            "standardDefaultsDomain": Bundle.main.bundleIdentifier ?? "",
            "standardDefaultsSentinelVerified": DebugWebPlaybackRunner.hasIsolatedStartupEnvironment,
            "timingBoundary": "setAsWallpaper entry to drawable-presented callback and parent endpoint finalize",
            "daemonFinalizeAndDrainObserved": false
        ]
        if mode == "reentry-video" {
            let cross = crossRuntimeReport
            report["crossRuntimeObservation"] = cross
            report["passed"] = report["passed"] as? Bool == true && cross["passed"] as? Bool == true
        }
        if let reason { report["failure"] = reason }
        Self.write(report, to: reportURL)
        SceneDaemonClient.shared.shutdown {
            Self.retained = nil
            NSApp.terminate(nil)
        }
    }

    // The interstitial selection uses the existing product transaction. These
    // reads observe its visible/finalized endpoint and old-output barrier; they
    // never acknowledge an endpoint or advance the reducer themselves.
    private func selectInterstitialVideo() {
        guard !finished, rows.count == 1,
              let url = BundledVideoLibrary.videoURL(named: "Video2") else {
            finish(reason: "Bundled Video2 is unavailable"); return
        }
        videoFacts = ["entryUptimeMicros": Self.now(), "path": url.path]
        WallpaperManager.shared.setAsWallpaper(
            VideoWallpaper(title: "Scene reentry interstitial", path: url.path),
            userInitiated: true, recordHistory: false, updateRecentList: false)
        let manager = WallpaperManager.shared
        guard let ticket = manager.playbackSwitch.pending?.selection.ticket,
              ticket.runtime == .video else {
            finish(reason: "Video product selection was not admitted"); return
        }
        videoTicket = ticket
        videoFacts["ticketID"] = ticket.id.uuidString
        videoFacts["intentEpoch"] = ticket.epoch
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.finished, self.videoTicket == ticket else { return }
            self.finish(reason: "Video did not reach visible/finalized with the old Scene barrier settled")
        }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: work)
        observeInterstitialVideo(ticket)
    }

    private func observeInterstitialVideo(_ ticket: PlaybackSwitchTicket) {
        guard !finished, videoTicket == ticket else { return }
        let manager = WallpaperManager.shared
        let engine = WallpaperEngine.shared
        if manager.playbackSwitch.committed?.ticket == ticket,
           manager.playbackSwitch.pending == nil, manager.playbackSwitch.activity == nil,
           manager.playbackSwitch.cancellations.isEmpty, manager.playbackSwitch.retirements.isEmpty,
           manager.activeWallpaperRuntime == .video,
           let execution = engine.activeVideoExecution,
           execution.ticket == ticket, execution.id == manager.playbackSwitch.committed?.executionID,
           execution.activated, execution.finalized, !execution.retired, !execution.cancelling,
           !execution.sessions.isEmpty,
           execution.visibleDisplays == Set(execution.sessions.keys),
           Set(execution.requests.keys) == Set(execution.sessions.keys),
           Set(execution.generations.keys) == Set(execution.sessions.keys) {
            let client = SceneDaemonClient.shared
            guard let first = rows.first,
                  let rawRequest = first["requestID"] as? String,
                  let requestID = UUID(uuidString: rawRequest),
                  let rawExecution = first["executionID"] as? String,
                  let executionID = UUID(uuidString: rawExecution),
                  let generation = first["daemonGeneration"] as? UInt64,
                  let pid = first["daemonPID"] as? Int32,
                  !manager.switchEndpoints.keys.contains(executionID),
                  client.activeIntent == nil, client.pendingIntent == nil,
                  client.activeRequestID == nil, client.pendingRequestID == nil,
                  client.activeResourceLifetime == nil, client.pendingResourceLifetime == nil,
                  client.requestResourceLifetimes[requestID] == nil,
                  client.retiringResourceLifetimes[generation] == nil,
                  client.retiringTransports[generation] == nil else {
                finish(reason: "Old Scene endpoint or client resource ownership survived the product barrier")
                return
            }
            deadline?.cancel(); deadline = nil
            videoFacts["finalizedObservedUptimeMicros"] = Self.now()
            videoFacts["executionID"] = execution.id.uuidString
            videoFacts["activationID"] = execution.activationID.uuidString
            videoFacts["oldSceneBarrierSettled"] = true
            videoFacts["oldSceneClientResourceSlotsReleased"] = true
            videoFacts["oldSceneProcessStillRegistered"] =
                DaemonPlaybackProcessRegistry.shared.liveProcessIdentifiers.contains(pid)
            videoFacts["oldSceneTransportStillAttached"] = client.debugProcessIdentifier == pid
            videoFacts["visibleDisplays"] = execution.visibleDisplays.sorted()
            videoFacts["displayRequests"] = execution.requests.map { display, request in
                ["displayID": display, "requestID": request,
                 "preparationGeneration": execution.generations[display] ?? 0,
                 "daemonPID": execution.sessions[display]?.process.processIdentifier ?? 0] as [String: Any]
            }.sorted { ($0["displayID"] as? UInt32 ?? 0) < ($1["displayID"] as? UInt32 ?? 0) }
            videoTicket = nil
            // Leave the engine finalize / old endpoint retirement stack before
            // the real Service performs a fresh Scene admission and lease.
            DispatchQueue.main.async { [weak self] in self?.selectNext() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.observeInterstitialVideo(ticket)
        }
    }

    private func observeWire(generation: UInt64, pid: Int32?, uptime: UInt64,
                             payload: [String: Any]) {
        guard !finished else { return }
        let isHello = payload["role"] as? String == "scene-daemon"
        let event = payload["event"] as? String
        guard isHello || event == "switchControlResult" || event == "launchResourcesReleased"
            || event == "exited" else { return }
        let keys = ["v", "role", "event", "sourceSchemaVersion", "requestRetirementSchemaVersion",
                    "requestID", "operationID", "accepted", "requestRetired", "resourcesRetired", "gpuDrained"]
        guard wireObservations.count < 64 else { wireObservationOverflowed = true; return }
        let controlMatches: Bool
        if let raw = payload["operationID"] as? String, let id = UUID(uuidString: raw),
           let control = SceneDaemonClient.shared.switchControls[id] {
            controlMatches = control.generation == generation
                && control.requestID?.uuidString == payload["requestID"] as? String
                && control.transport.process.processIdentifier == pid
        } else { controlMatches = false }
        wireObservations.append([
            "transportGeneration": generation, "daemonPID": pid.map { $0 as Any } ?? NSNull(),
            "observedUptimeMicros": uptime, "matchedPendingControl": controlMatches,
            "payload": payload.filter { keys.contains($0.key) }
        ])
    }

    private var crossRuntimeReport: [String: Any] {
        let first = rows.first ?? [:], second = rows.count == 2 ? rows[1] : [:]
        let sameSource: Bool
        if let a = first["admittedSource"] as? [String: Any],
           let b = second["admittedSource"] as? [String: Any] {
            sameSource = NSDictionary(dictionary: a).isEqual(to: b)
        } else { sameSource = false }
        let freshIdentity = ["ticketID", "requestID", "executionID"].allSatisfy {
            guard let a = first[$0] as? String, let b = second[$0] as? String else { return false }
            return a != b
        }
        let freshEpoch = (second["intentEpoch"] as? UInt64 ?? 0) > (first["intentEpoch"] as? UInt64 ?? 0)
        let samePID = (first["daemonPID"] as? Int32).map { $0 == second["daemonPID"] as? Int32 } ?? false
        let sameGeneration = (first["daemonGeneration"] as? UInt64)
            .map { $0 == second["daemonGeneration"] as? UInt64 } ?? false
        let strongRetire = wireObservations.filter { observation in
            guard let payload = observation["payload"] as? [String: Any],
                  payload["event"] as? String == "switchControlResult",
                  payload["requestID"] as? String == first["requestID"] as? String,
                  let raw = payload["operationID"] as? String, UUID(uuidString: raw) != nil,
                  observation["transportGeneration"] as? UInt64 == first["daemonGeneration"] as? UInt64,
                  observation["daemonPID"] as? Int32 == first["daemonPID"] as? Int32 else { return false }
            return observation["matchedPendingControl"] as? Bool == true
                && payload["accepted"] as? Bool == true && payload["requestRetired"] as? Bool == true
        }
        return ["schemaVersion": 1,
            "passed": rows.count == 2 && rows.allSatisfy { $0["passed"] as? Bool == true }
                && videoFacts["oldSceneBarrierSettled"] as? Bool == true && freshIdentity && freshEpoch
                && sameSource && !wireObservationOverflowed,
            "route": "Service Scene -> Manager bundled Video2 -> Service Scene",
            "video": videoFacts, "wireObservations": wireObservations,
            "wireObservationLimit": 64, "wireObservationOverflowed": wireObservationOverflowed,
            "processRegistrationBoundary": "original registry liveProcessIdentifiers; final physical exit is separately checked by the outer runner",
            "freshSceneSelectionAndExecution": freshIdentity && freshEpoch, "sameAdmittedSource": sameSource,
            "sameSceneDaemonPID": samePID, "sameTransportGeneration": sameGeneration,
            "matchingStrongRetirementAcknowledgements": strongRetire,
            "exitBoundary": "existing runner explicit client shutdown; ordinary App quit and idle TTL are separate",
            "scope": "product visible/finalized and client resource slots; not final AV borrower or all FD/RSS drain"]
    }

    private static func now() -> UInt64 {
        UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000)
    }

    private static func write(_ report: [String: Any], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("MWX SCENE STARTUP: report write failed: %@", String(describing: error))
        }
    }
}
#endif
