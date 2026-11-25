#if DEBUG
import AppKit
import CoreGraphics
import Foundation

@MainActor
enum DebugPlaybackCoexistenceRunner {
    static let bundleID = "com.songziqiang.MyWallpaperX.Debug.Coexistence"
    private static let reportFlag = "--mwx-debug-coexistence-report"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(reportFlag) }
    static var hasIsolatedEnvironment: Bool {
        isRequested
            && !DebugWebPlaybackRunner.runsIsolatedWebWorkshopSample
            && !DebugScenePlaybackRunner.runsIsolatedSceneSample
            && !DebugSceneDaemonClientRunner.isRequested
            && !DebugSystemMediaRunner.isRequested
            && DebugWebPlaybackRunner.hasIsolatedProductEnvironment(bundleID: bundleID, reportFlag: reportFlag)
    }

    private struct Receipt {
        let selection: PlaybackSwitchTransaction.Selection
        let pid: Int32
        let evidence: [String: Any]
        let windows: [Int]
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static var sceneCapture: [String: Any]?

    static func prepareIfRequested() {
        guard isRequested else { return }
        let scene = SceneDaemonClient.shared
        // Use the existing child launch flag that includes clocks and window IDs in capture replies.
        scene.debugStartupPrefixObserver = { _ in }
        scene.debugStartupWireObserver = { _, _, _, payload in
            if let capture = payload["debugCapture"] as? [String: Any] { sceneCapture = capture }
        }
    }

    static func scheduleIfRequested() {
        guard isRequested, let rawReport = DebugScenePlaybackRunner.argumentValue(after: reportFlag) else { return }
        let report = URL(fileURLWithPath: rawReport)
        Task { @MainActor in
            // Deferred AppKit termination runs a nested loop while the library flushes.
            defer { RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } } }
            var result: [String: Any] = ["parentPID": ProcessInfo.processInfo.processIdentifier]
            do {
                try await run(
                    sceneID: DebugScenePlaybackRunner.argumentValue(after: "--mwx-debug-coexistence-scene"),
                    webID: DebugScenePlaybackRunner.argumentValue(after: "--mwx-debug-coexistence-web"),
                    phase: DebugScenePlaybackRunner.argumentValue(after: "--mwx-debug-coexistence-phase"),
                    directory: report.deletingLastPathComponent(), result: &result)
                result["passed"] = true
            } catch {
                result["passed"] = false
                result["failure"] = error.localizedDescription
                NSLog("MWX COEXISTENCE: %@", error.localizedDescription)
            }
            do {
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: report, options: .atomic)
            } catch {
                NSLog("MWX COEXISTENCE report: %@", error.localizedDescription)
            }
        }
    }

    private static func run(sceneID: String?, webID: String?, phase: String?, directory: URL,
                            result: inout [String: Any]) async throws {
        guard let sceneID, let webID, let workspace = MyWallpaperXApplication.libraryWorkspace,
              phase == "switch" || phase == "restore" || phase == "quality-import" || phase == "scene-reapply"
        else { throw Failure("invalid phase or product library unavailable") }
        let manager = WallpaperManager.shared
        let mux = PlaybackCommandMultiplexer.shared
        let scene = WallpaperReference(provider: .steamWorkshop, sourceID: sceneID)
        let web = WallpaperReference(provider: .steamWorkshop, sourceID: webID)
        var preference = PlaybackQualityPreference.defaults
        SceneQualityPreset.medium.apply(to: &preference)
        preference.webFrameRateMode = .followAnimationFrameRate
        let selectedFPS = preference.animationFrameRate.rawValue
        result["requestedFPS"] = selectedFPS

        if phase == "restore" {
            preference.scene.postProcessing = .disabled
            guard manager.settings.restorePlaybackOnLaunch, PlaybackQualityPreference.current == preference,
                  SceneQualityPreset.matching(preference) == nil else { throw Failure("restored quality request differs") }
            SteamWorkshopService.shared.performStartupLibraryReloadIfNeeded()
            let restored = try await receipt(for: scene, runtime: .scene, after: nil)
            guard mux.isUserPaused, mux.isPlaybackPaused else { throw Failure("restoration lost user's pause request") }
            result["restored"] = restored.evidence
            result["scene"] = try await scenePauseResume("restored", receipt: restored, fps: selectedFPS,
                initiallyPaused: true, directory: directory)
            return
        }

        guard manager.playbackSwitch.committed == nil, manager.playbackSwitch.pending == nil,
              SceneQualityPreset.matching(preference) == .medium else { throw Failure("fresh product was not idle") }
        var settings = manager.settings
        settings.restorePlaybackOnLaunch = true
        settings.multiDisplayEnabled = false
        settings.pauseWhenOtherAppFocused = false
        settings.pauseWhenOtherAppFullscreen = false
        settings.pauseWhenUnplugged = false
        settings.pauseWhenIdle = false
        settings.syncSystemWallpaper = false
        manager.settings = settings
        mux.applyQualityPreference(preference)
        let workshop = SteamWorkshopService.shared
        workshop.reloadInstalledItems()
        guard await DebugWebPlaybackRunner.awaitInstalledRecord(sceneID, using: workshop)?.contentType == .scene,
              await DebugWebPlaybackRunner.awaitInstalledRecord(webID, using: workshop)?.contentType == .web,
              let videoURL = BundledVideoLibrary.videoURL(named: "Video2") else { throw Failure("installed fixtures unavailable") }
        let video = try await wait("real bundled video index") {
            manager.wallpapers.first { URL(fileURLWithPath: $0.path).standardizedFileURL == videoURL.standardizedFileURL }
        }
        let videoReference = WallpaperReference(provider: .videoLibrary, sourceID: video.id)
        if phase == "scene-reapply" {
            result["sceneReapply"] = try await reapplySceneQuality(scene, web: web, video: videoReference,
                workspace: workspace, directory: directory)
            return
        }
        let importsQuality = phase == "quality-import"
        let references: [(String, WallpaperReference, WallpaperRuntimeKind)] = [
            ("scene-in", scene, .scene), ("web", web, .web), ("video", videoReference, .video), ("scene-back", scene, .scene)
        ]
        var previous: Receipt?
        var rows: [[String: Any]] = []
        for (label, reference, runtime) in importsQuality ? references.dropLast() : references[...] {
            if importsQuality && runtime == .video {
                let view = workspace.presentation
                guard view.switchPage(.videos) else { throw Failure("Videos page unavailable for import") }
                var query = view.queryState
                query.sort = .name
                query.ascending = true
                guard view.setQueryState(query) else { throw Failure("Video name order unavailable") }
                _ = try await wait("multiple indexed Videos entries") {
                    let items = view.queryResult.items
                    return items.count > 1 && items.contains { $0.reference == reference } ? items.count : nil
                }
                workspace.play(reference)
            } else {
                workspace.requestSingle(reference)
            }
            let current = try await receipt(for: reference, runtime: runtime, after: previous)
            rows.append(current.evidence)
            result["switches"] = rows
            if importsQuality {
                result["import-\(runtime.rawValue)"] = try await qualityImport(runtime, receipt: current,
                    presentation: workspace.presentation, directory: directory)
                previous = current
                continue
            }
            switch runtime {
            case .scene:
                result[label] = try await scenePauseResume(label, receipt: current, fps: selectedFPS,
                    initiallyPaused: false, directory: directory)
            case .web, .video:
                if runtime == .video, WallpaperEngine.shared.currentContentPath != video.path {
                    throw Failure("video selected a different input")
                }
                try await captureMotion(label, receipt: current, directory: directory)
            case .systemStill: break
            }
            previous = current
        }
        if importsQuality {
            guard references.dropLast().allSatisfy({ (result["import-\($0.2.rawValue)"] as? [String: Any])?["preserved"] as? Bool == true })
            else { throw Failure("quality import interrupted active playback") }
            return
        }
        preference.scene.postProcessing = .disabled
        mux.applyQualityPreference(preference)
        mux.dispatch(.pause)
        guard PlaybackQualityPreference.current == preference, mux.isUserPaused,
              SceneQualityPreset.matching(preference) == nil else { throw Failure("custom quality or pause not retained") }
        result["savedPaused"] = true
    }

    private static func reapplySceneQuality(_ scene: WallpaperReference, web: WallpaperReference,
                                            video: WallpaperReference, workspace: WallpaperLibraryWorkspace,
                                            directory: URL) async throws -> [String: Any] {
        let manager = WallpaperManager.shared
        let mux = PlaybackCommandMultiplexer.shared
        let controller = SettingsWindowController.shared
        controller.showWindow()
        defer { controller.window?.close() }
        guard let window = controller.window, let root = window.contentView,
              let settings = root.subviews.compactMap({ $0 as? AppKitSettingsContainerView }).first,
              !settings.reapplySceneQualityButton.isEnabled, workspace.presentation.switchPage(.downloads)
        else { throw Failure("native Scene quality control or Downloads page unavailable") }
        _ = try await wait("Scene and Web in Downloads") {
            let references = workspace.presentation.queryResult.items.map(\.reference)
            return references.contains(scene) && references.contains(web) ? true : nil
        }
        workspace.play(scene)
        let initial = try await receipt(for: scene, runtime: .scene, after: nil)
        guard let original = manager.libraryPlaybackSequence.committed?.snapshot,
              original.source == .page(.downloads), original.entries.count > 1,
              settings.reapplySceneQualityButton.isEnabled else { throw Failure("Scene page reapply unavailable") }
        let button = settings.reapplySceneQualityButton
        let standardTitle = button.title
        let originalTextures = PlaybackQualityPreference.current.scene.textures
        root.layoutSubtreeIfNeeded()
        button.scrollToVisible(button.bounds)
        root.layoutSubtreeIfNeeded()
        guard button.visibleRect.width + 1 >= button.intrinsicContentSize.width,
              button.visibleRect.height > 0 else { throw Failure("Scene reapply control was clipped") }
        try await captureWindow("settings-reapply", id: window.windowNumber, directory: directory)
        mux.dispatch(.pause)
        try await Task.sleep(for: .milliseconds(350))
        let before = try await captureScene("scene-reapply-before", receipt: initial, directory: directory)
        let post = settings.scenePostProcessingPopup
        post.selectItem(at: post.indexOfItem(withRepresentedObject: ScenePostProcessingMode.disabled.rawValue))
        guard post.sendAction(post.action, to: post.target), PlaybackQualityPreference.current.scene.postProcessing == .disabled
        else { throw Failure("native quality choice did not save") }
        let pendingTitle = button.title
        guard pendingTitle != standardTitle else { throw Failure("saved cold quality did not show a pending change") }
        root.layoutSubtreeIfNeeded()
        button.scrollToVisible(button.bounds)
        guard button.visibleRect.width + 1 >= button.intrinsicContentSize.width else {
            throw Failure("pending quality title was clipped")
        }
        try await captureWindow("settings-reapply-pending", id: window.windowNumber, directory: directory)
        let held = try await captureScene("scene-reapply-held", receipt: initial, directory: directory)
        guard held["sessionID"] as? String == before["sessionID"] as? String,
              held["sceneTime"] as? Double == before["sceneTime"] as? Double else {
            throw Failure("quality selection changed the frozen active Scene")
        }

        let daemon = SceneDaemonClient.shared
        let observer = daemon.debugStartupObserver
        let texture = settings.sceneTextureQualityPopup
        var newerQualitySaved = false
        daemon.debugStartupObserver = { observation in
            observer?(observation)
            guard observation.phase == .prepared, !newerQualitySaved else { return }
            texture.selectItem(at: texture.indexOfItem(withRepresentedObject: SceneTextureQuality.performance.rawValue))
            newerQualitySaved = texture.sendAction(texture.action, to: texture.target)
                && PlaybackQualityPreference.current.scene.textures == .performance
        }
        defer { daemon.debugStartupObserver = observer }
        button.performClick(nil)
        guard let pending = manager.libraryPlaybackSequence.pending, pending.proposal.cause == .settingsReload,
              manager.playbackSwitch.committed == initial.selection,
              initial.windows.allSatisfy({ onscreenWindows()[$0] == initial.pid }),
              !button.isEnabled else { throw Failure("Scene reapply did not stage behind the old window") }
        let updated = try await receipt(for: scene, runtime: .scene, after: initial)
        daemon.debugStartupObserver = observer
        guard let session = manager.libraryPlaybackSequence.committed, session.ticket == pending.ticket,
              session.snapshot.source == original.source, session.snapshot.sourceQuery == original.sourceQuery,
              session.snapshot.entries.map(\.reference) == original.entries.map(\.reference),
              mux.isUserPaused, button.isEnabled else {
            throw Failure("Scene reapply lost its playback scope or pause intent")
        }
        let after = try await captureScene("scene-reapply-after", receipt: updated, directory: directory)
        try await Task.sleep(for: .milliseconds(350))
        let still = try await captureScene("scene-reapply-still", receipt: updated, directory: directory)
        guard still["isPlaybackPaused"] as? Bool == true, still["isFrameDriverActive"] as? Bool == false,
              still["sceneTime"] as? Double == after["sceneTime"] as? Double,
              still["sessionID"] as? String != before["sessionID"] as? String else {
            throw Failure("reapplied Scene did not remain frozen in its new session")
        }
        let intermediateTitle = button.title
        guard newerQualitySaved, intermediateTitle == pendingTitle,
              daemon.activePreparedRenderQuality?.textures == originalTextures else {
            throw Failure("a newer saved texture setting was confused with the presented candidate")
        }
        button.performClick(nil)
        let latest = try await receipt(for: scene, runtime: .scene, after: updated)
        _ = try await wait("latest cold quality confirmed") {
            button.title == standardTitle && daemon.activePreparedRenderQuality?.textures == .performance ? true : nil
        }
        let latestFrame = try await captureScene("scene-reapply-latest", receipt: latest, directory: directory)
        guard latestFrame["sceneTime"] as? Double == 0, latestFrame["isPlaybackPaused"] as? Bool == true else {
            throw Failure("the latest cold quality did not preserve pause")
        }
        let latestTitle = button.title
        mux.dispatch(.resume)
        try await Task.sleep(for: .milliseconds(500))
        let resumed = try await captureScene("scene-reapply-resumed", receipt: latest, directory: directory)
        guard let frozen = latestFrame["sceneTime"] as? Double, let time = resumed["sceneTime"] as? Double, time > frozen
        else { throw Failure("reapplied Scene clock did not resume") }

        var previous = latest
        for (reference, kind) in [(web, WallpaperRuntimeKind.web), (video, .video)] {
            workspace.requestSingle(reference)
            previous = try await receipt(for: reference, runtime: kind, after: previous)
            button.performClick(nil)
            guard !button.isEnabled, manager.playbackSwitch.pending == nil,
                  manager.playbackSwitch.committed == previous.selection else {
                throw Failure("a non-Scene wallpaper accepted the Scene control")
            }
        }
        return ["before": before, "held": held, "after": after, "still": still, "resumed": resumed,
                "original": initial.evidence, "reapplied": updated.evidence,
                "latest": latest.evidence, "latestFrame": latestFrame,
                "qualityTitles": ["original": standardTitle, "pending": pendingTitle,
                                  "intermediate": intermediateTitle, "latest": latestTitle],
                "entryCount": original.entries.count, "nonSceneActionsRejected": true,
                "control": ["language": Bundle.main.preferredLocalizations.first ?? "",
                            "title": button.title, "visibleWidth": Double(button.visibleRect.width),
                            "intrinsicWidth": Double(button.intrinsicContentSize.width)]]
    }

    private static func qualityImport(_ runtime: WallpaperRuntimeKind, receipt: Receipt,
                                      presentation: WallpaperLibraryPresentation, directory: URL) async throws -> [String: Any] {
        guard let coordinator = MyWallpaperXApplication.personalSettings, coordinator.allowsEditing else {
            throw Failure("product import owner unavailable")
        }
        let mux = PlaybackCommandMultiplexer.shared
        let scene = SceneDaemonClient.shared
        let isScene = runtime == .scene
        let isWeb = runtime == .web
        let fps: Int
        switch runtime {
        case .scene: fps = 25
        case .web: fps = 30
        case .video: fps = 24
        case .systemStill: throw Failure("quality import requires an active dynamic engine")
        }
        let label = "\(runtime.rawValue)-import"
        let isVideo = runtime == .video
        let videoPath = WallpaperEngine.shared.currentContentPath
        let videoOrder = isVideo ? presentation.queryResult.items.map(\.reference.sourceID) : []
        let videoSequence = isVideo ? WallpaperManager.shared.libraryPlaybackSequence.committed?.snapshot : nil
        if isVideo {
            guard videoSequence?.source == .page(.videos), videoSequence?.sourceQuery?.sort == .name,
                  videoSequence?.sourceQuery?.ascending == true,
                  videoSequence?.entries.map(\.reference.sourceID) == videoOrder else {
                throw Failure("active Video sequence did not capture the ascending page")
            }
        }
        let before: [String: Any]
        if isScene {
            before = try await captureScene(label + "-before", receipt: receipt, directory: directory)
        } else {
            before = [:]
            try await capture(label + "-before", receipt: receipt, directory: directory)
        }
        if isWeb { mux.dispatch(.pause) }
        defer { if isWeb && mux.isUserPaused { mux.dispatch(.resume) } }
        let file = directory.appendingPathComponent(label + ".json")
        var fields: [String: Any] = [isWeb ? "playbackPerformanceProfile" : "animationFramesPerSecond": fps]
        if isScene { fields["sceneTextureQuality"] = SceneTextureQuality.performance.rawValue }
        if isVideo { fields["videoLibrarySort"] = ["mode": "name", "ascending": false] }
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 8, "exportedAt": "2026-01-01T00:00:00Z",
            "preferences": fields, "sources": [], "collections": ["libraryExclusionStates": []]
        ]).write(to: file)
        _ = try await coordinator.importPersonalSettings(from: file)
        let applied = PlaybackQualityPreference.current
        guard applied.animationFrameRate.rawValue == fps,
              !isScene || applied.scene.textures == .performance else { throw Failure("portable quality was not saved") }
        let onscreen = onscreenWindows()
        let preserved = WallpaperManager.shared.playbackSwitch.committed == receipt.selection
            && receipt.windows.allSatisfy { onscreen[$0] == receipt.pid }
        var result: [String: Any] = ["savedFPS": fps, "preserved": preserved, "identity": receipt.evidence]
        if isVideo {
            let sorted = presentation.queryResult.items.map(\.reference.sourceID)
            guard try presentation.videoSortPreference() == .init(mode: .name, ascending: false),
                  sorted == Array(videoOrder.reversed()) else { throw Failure("imported Videos order did not reverse") }
            result["orderBefore"] = videoOrder
            result["orderAfter"] = sorted
        }
        guard preserved else { return result }
        if isVideo {
            let sequence = WallpaperManager.shared.libraryPlaybackSequence.committed?.snapshot
            guard videoPath != nil, WallpaperEngine.shared.currentContentPath == videoPath,
                  sequence?.sourceQuery == videoSequence?.sourceQuery,
                  sequence?.entries.map(\.reference.sourceID) == videoOrder else {
                throw Failure("Videos sort import changed the active file or captured playback order")
            }
            result["playbackOrder"] = videoOrder
        }
        if isScene {
            let cadence = try await wait("imported Scene cadence") {
                scene.activeAnimationCadence.flatMap { $0.requestedFPS.rawValue == fps ? $0 : nil }
            }
            let after = try await captureScene(label + "-after", receipt: receipt, directory: directory)
            guard cadence.effectiveFPS == Double(fps),
                  let start = before["sceneTime"] as? Double, let end = after["sceneTime"] as? Double,
                  end > start, before["sessionID"] as? String == after["sessionID"] as? String else {
                throw Failure("live Scene did not preserve its session and clock")
            }
            result["sceneBefore"] = before
            result["sceneAfter"] = after
            result["effectiveFPS"] = cadence.effectiveFPS
        } else {
            if isWeb {
                guard mux.isPlaybackPaused, mux.isUserPaused else { throw Failure("quality import cleared the Web pause") }
                mux.dispatch(.resume)
            }
            try await Task.sleep(for: .milliseconds(550))
            try await capture(label + "-after", receipt: receipt, directory: directory)
        }
        return result
    }

    private static func receipt(for reference: WallpaperReference, runtime: WallpaperRuntimeKind,
                                after previous: Receipt?) async throws -> Receipt {
        let manager = WallpaperManager.shared
        let engine = WallpaperEngine.shared
        let scene = SceneDaemonClient.shared
        guard let web = engine.dedicatedWebHostAdapter as? WebDaemonHostAdapter else {
            throw Failure("product Web daemon adapter unavailable")
        }
        return try await wait("finalized \(runtime.rawValue) \(reference.sourceID)") {
            guard let current = manager.playbackSwitch.committed, let execution = current.executionID,
                  current.ticket.runtime == runtime, current.ticket != previous?.selection.ticket,
                  current.executionID != previous?.selection.executionID,
                  manager.libraryPlaybackSequence.committed?.ticket == current.ticket,
                  manager.libraryPlaybackSequence.committed?.reference == reference,
                  manager.playbackSwitch.retirements.isEmpty else { return nil }
            let onscreen = onscreenWindows()
            guard previous?.windows.allSatisfy({ onscreen[$0] == nil }) != false else { return nil }
            let pid: Int32
            let request: String
            switch runtime {
            case .scene:
                guard scene.activeRecordID == reference.sourceID, scene.activeSwitchTicket == current.ticket,
                      let id = scene.activeRequestID, let activePID = scene.debugProcessIdentifier,
                      engine.activeVideoExecution == nil, web.activeRequest == nil else { return nil }
                (pid, request) = (activePID, id.uuidString)
            case .web:
                guard let open = web.activeRequest, open.recordID == reference.sourceID,
                      let activePID = web.debugActiveProcessIdentifier, scene.activeIntent == nil,
                      engine.activeVideoExecution == nil else { return nil }
                (pid, request) = (activePID, open.id.uuidString)
            case .video:
                guard let active = engine.activeVideoExecution, active.id == execution, active.finalized,
                      let display = active.sessions.values.first, let id = display.latestFinalizedPlayRequestID,
                      id == active.requests[display.displayID],
                      scene.activeIntent == nil, web.activeRequest == nil else { return nil }
                (pid, request) = (display.process.processIdentifier, String(id))
            case .systemStill: return nil
            }
            let windows = onscreen.filter { $0.value == pid }.map(\.key).sorted()
            guard !windows.isEmpty else { return nil }
            return Receipt(selection: current, pid: pid, evidence: ["runtime": runtime.rawValue,
                "reference": reference.sourceID, "ticket": current.ticket.id.uuidString,
                "epoch": current.ticket.epoch, "execution": execution.uuidString,
                "request": request, "pid": pid, "windows": windows], windows: windows)
        }
    }

    private static func scenePauseResume(_ label: String, receipt: Receipt, fps: Int,
                                         initiallyPaused: Bool, directory: URL) async throws -> [String: Any] {
        let scene = SceneDaemonClient.shared
        let mux = PlaybackCommandMultiplexer.shared
        let cadence = try await wait("Scene cadence") { scene.activeAnimationCadence }
        guard cadence.requestedFPS.rawValue == fps, cadence.effectiveFPS == Double(fps) else {
            throw Failure("Scene did not adopt the requested cadence on this display")
        }
        if !initiallyPaused { mux.dispatch(.pause) }
        try await Task.sleep(for: .milliseconds(300))
        let first = try await captureScene(label + "-paused", receipt: receipt, directory: directory)
        try await Task.sleep(for: .milliseconds(400))
        let still = try await captureScene(label + "-still", receipt: receipt, directory: directory)
        guard let frozen = first["sceneTime"] as? Double, still["sceneTime"] as? Double == frozen,
              first["isPlaybackPaused"] as? Bool == true, still["isPlaybackPaused"] as? Bool == true,
              still["isFrameDriverActive"] as? Bool == false else { throw Failure("Scene clock did not freeze") }
        mux.dispatch(.resume)
        try await Task.sleep(for: .milliseconds(500))
        let resumed = try await captureScene(label + "-resumed", receipt: receipt, directory: directory)
        guard resumed["isPlaybackPaused"] as? Bool == false, resumed["isFrameDriverActive"] as? Bool == true,
              let time = resumed["sceneTime"] as? Double, time > frozen else { throw Failure("Scene clock did not resume") }
        return ["requestedFPS": fps, "effectiveFPS": cadence.effectiveFPS, "paused": first,
            "still": still, "resumed": resumed]
    }

    private static func captureScene(_ name: String, receipt: Receipt, directory: URL) async throws -> [String: Any] {
        sceneCapture = nil
        let url: URL? = await withCheckedContinuation { continuation in
            SceneDaemonClient.shared.captureSurfaceFrame { continuation.resume(returning: $0) }
        }
        guard let url else { throw Failure("Scene window capture unavailable") }
        let prefix = "mwx-scene-frame-"
        let stem = url.deletingPathExtension().lastPathComponent
        let isOwnedCapture = url.deletingLastPathComponent().path == "/private/tmp"
            && url.pathExtension == "jpg" && stem.hasPrefix(prefix)
            && UUID(uuidString: String(stem.dropFirst(prefix.count))) != nil
        defer { if isOwnedCapture { try? FileManager.default.removeItem(at: url) } }
        guard isOwnedCapture, let snapshot = sceneCapture, let captureID = snapshot["captureID"] as? String,
              url.lastPathComponent == "\(prefix)\(captureID).jpg" else {
            throw Failure("Scene capture lacked a matched debug receipt")
        }
        guard snapshot["requestID"] as? String == receipt.evidence["request"] as? String,
              snapshot["daemonPID"] as? Int32 == receipt.pid,
              WallpaperManager.shared.playbackSwitch.committed == receipt.selection else {
            throw Failure("Scene capture did not belong to the active execution")
        }
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name + ".jpg"))
        return snapshot
    }

    private static func captureMotion(_ label: String, receipt: Receipt, directory: URL) async throws {
        let mux = PlaybackCommandMultiplexer.shared
        mux.dispatch(.pause)
        try await Task.sleep(for: .milliseconds(350))
        try await capture(label + "-paused", receipt: receipt, directory: directory)
        try await Task.sleep(for: .milliseconds(400))
        try await capture(label + "-still", receipt: receipt, directory: directory)
        mux.dispatch(.resume)
        try await Task.sleep(for: .milliseconds(450))
        try await capture(label + "-resumed", receipt: receipt, directory: directory)
        try await Task.sleep(for: .milliseconds(450))
        try await capture(label + "-running", receipt: receipt, directory: directory)
    }

    private static func capture(_ name: String, receipt: Receipt, directory: URL) async throws {
        let image = directory.appendingPathComponent(name + ".png")
        if receipt.selection.ticket.runtime == .web {
            let frame: NSImage? = await withCheckedContinuation { continuation in
                WallpaperEngine.shared.captureWebWallpaperFrame { continuation.resume(returning: $0) }
            }
            guard let tiff = frame?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                throw Failure("Web window capture unavailable")
            }
            try png.write(to: image, options: .atomic)
        } else {
            // The outer runner owns Screen Recording for the actual Video daemon window.
            let window = receipt.windows[0]
            guard onscreenWindows()[window] == receipt.pid else { throw Failure("Video window lost its owner") }
            try await captureWindow(name, id: window, directory: directory)
            guard onscreenWindows()[window] == receipt.pid else { throw Failure("Video window changed during capture") }
        }
        guard WallpaperManager.shared.playbackSwitch.committed == receipt.selection else {
            throw Failure("window capture left the committed execution")
        }
    }

    private static func captureWindow(_ name: String, id: Int, directory: URL) async throws {
        let request = ["window": id, "name": name] as [String: Any]
        try JSONSerialization.data(withJSONObject: request)
            .write(to: directory.appendingPathComponent("capture-request.json"), options: .atomic)
        let image = directory.appendingPathComponent(name + ".png")
        try await wait("physical window capture \(name)") {
            FileManager.default.fileExists(atPath: image.path) ? true : nil
        }
    }

    private static func onscreenWindows() -> [Int: Int32] {
        let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let level = Int(CGWindowLevelForKey(.desktopWindow))
        return info.reduce(into: [:]) { windows, row in
            guard let number = row[kCGWindowNumber as String] as? Int,
                  let pid = row[kCGWindowOwnerPID as String] as? Int32,
                  let layer = row[kCGWindowLayer as String] as? Int, (level...level + 2).contains(layer) else { return }
            windows[number] = pid
        }
    }

    private static func wait<Value>(_ fact: String, _ observe: () -> Value?) async throws -> Value {
        let deadline = ProcessInfo.processInfo.systemUptime + 25
        repeat {
            if let value = observe() { return value }
            try await Task.sleep(for: .milliseconds(75))
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw Failure("timed out waiting for " + fact)
    }
}
#endif
