//
//  DebugScenePlaybackRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation

@MainActor
enum DebugScenePlaybackRunner {
    private static let debugRecordID = "debug-scene-playback"
    private struct SceneRuntimeEvidence: Encodable {
        let schemaVersion = 1
        let sourceEntryPath: String
        let runtimeInput: SceneRuntimeInput

        init(model: SceneRuntimeModel) {
            sourceEntryPath = model.project.entryPath
            runtimeInput = model.runtimeInput
        }
    }

    static var runsIsolatedSceneSample: Bool {
        argumentValue(after: "--mwx-debug-scene-root") != nil
    }

    static func scheduleScenePlaybackIfRequested() {
        guard let rootPath = argumentValue(after: "--mwx-debug-scene-root") else { return }
        let requestUptime = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Task { await launchScene(rootPath: rootPath, requestUptime: requestUptime) }
        }
    }

    private static func launchScene(rootPath: String, requestUptime: TimeInterval) async {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        guard isIsolatedSampleRoot(rootURL) else {
            NSLog("MWX DEBUG SCENE: phase=precondition-failed reason=isolated-root-required root=%@", rootURL.path)
            terminate(after: 0.1)
            return
        }
        guard applyRequestedPerformanceProfile() else { return }
        let requestsDynamicValuesFault = ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-drop-dynamic-values-frame"
        )
        guard !requestsDynamicValuesFault
                || requestedDropDynamicValuesFrameIndex != nil else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=invalid-drop-dynamic-values-frame"
            )
            terminate(after: 0.1)
            return
        }
        let requestsPointerTrajectory = ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-pointer-trajectory-json"
        )
        guard !requestsPointerTrajectory
                || requestedPointerTrajectory != nil else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=invalid-pointer-trajectory"
            )
            terminate(after: 0.1)
            return
        }
        guard requestedPointerTrajectory == nil
                || (!requestedPrimaryClick
                    && requestedDragPointer == nil
                    && !requestedHoverPointerFromLaunch
                    && !requestedHoverPointerStationaryEntry) else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=ambiguous-pointer-trajectory"
            )
            terminate(after: 0.1)
            return
        }
        let environment = ProcessInfo.processInfo.environment
        let surfaceStopRelaunchDelay = requestedSurfaceStopRelaunchDelay(
            duration: requestedDuration
        )
        let pauseResumeRequest = requestedPauseResumeRequest(
            duration: requestedDuration
        )
        let sceneSwitchRequest = requestedSceneSwitchRequest(
            duration: requestedDuration,
            currentRootURL: rootURL
        )
        guard environment[executorInvalidationDelayEnvironmentKey] == nil
                || requestedExecutorInvalidationDelay != nil else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=invalid-executor-invalidation-delay"
            )
            terminate(after: 0.1)
            return
        }
        guard !containsSceneSwitchRequest(in: environment)
                || sceneSwitchRequest != nil else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=invalid-scene-switch-delay"
            )
            terminate(after: 0.1)
            return
        }
        guard environment[surfaceStopRelaunchDelayEnvironmentKey] == nil
                || surfaceStopRelaunchDelay != nil else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=invalid-surface-stop-relaunch-delay"
            )
            terminate(after: 0.1)
            return
        }
        guard environment[pauseResumeRequestEnvironmentKey] == nil
                || pauseResumeRequest != nil else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=invalid-pause-resume-request"
            )
            terminate(after: 0.1)
            return
        }
        let runtimeLifecycleProbeCount = [
            requestedExecutorInvalidationDelay != nil,
            sceneSwitchRequest != nil,
            surfaceStopRelaunchDelay != nil,
            pauseResumeRequest != nil,
        ].filter { $0 }.count
        guard runtimeLifecycleProbeCount <= 1 else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=multiple-runtime-lifecycle-faults"
            )
            terminate(after: 0.1)
            return
        }
        guard !SceneDependencyCaptureFault.containsRequest(in: environment)
                || SceneDependencyCaptureFault.requestedOrdinal(
                    in: environment
                ) != nil else {
            NSLog(
                "MWX DEBUG SCENE: phase=precondition-failed reason=invalid-named-provider-capture-fault"
            )
            terminate(after: 0.1)
            return
        }

        let evidenceDirectory = argumentValue(after: "--mwx-debug-scene-evidence-dir")
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
        if let evidenceDirectory {
            do {
                try FileManager.default.createDirectory(
                    at: evidenceDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                NSLog("MWX DEBUG SCENE: phase=precondition-failed reason=evidence-directory error=%@", error.localizedDescription)
                terminate(after: 0.1)
                return
            }
        }

        do {
            if evidenceDirectory != nil {
                NSApp.activate(ignoringOtherApps: true)
            }
            PlaybackPolicyController.shared.updateSettings({
                var settings = WallpaperSettings()
                settings.pauseWhenOtherAppFocused = false
                settings.pauseWhenOtherAppFullscreen = false
                settings.pauseWhenUnplugged = false
                settings.pauseWhenIdle = false
                return settings
            }())
            if let frameIndex = requestedDropDynamicValuesFrameIndex {
                guard runtimeHost
                    .setDebugDropDynamicValuesFrameIndex(frameIndex) else {
                    NSLog(
                        "MWX DEBUG SCENE: phase=precondition-failed reason=dynamic-values-fault-requires-evidence-window"
                    )
                    terminate(after: 0.1)
                    return
                }
                NSLog(
                    "MWX DEBUG SCENE: phase=dynamic-snapshot-fault state=configured frame=%llu",
                    frameIndex
                )
            }
            if let ordinal = SceneDependencyCaptureFault.requestedOrdinal(
                in: ProcessInfo.processInfo.environment
            ) {
                NSLog(
                    "MWX DEBUG SCENE: phase=named-provider-capture-fault state=configured providerOrdinal=%d",
                    ordinal
                )
            }
            if let delay = requestedExecutorInvalidationDelay {
                NSLog(
                    "MWX DEBUG SCENE: phase=executor-invalidation state=configured delay=%.3f",
                    delay
                )
            }
            logConfiguredSceneSwitch(sceneSwitchRequest)
            if let delay = surfaceStopRelaunchDelay {
                NSLog(
                    "MWX DEBUG SCENE: phase=surface-stop-relaunch state=configured delay=%.3f",
                    delay
                )
            }
            if let request = pauseResumeRequest {
                NSLog(
                    "MWX DEBUG SCENE: phase=pause-resume state=configured delay=%.3f dwell=%.3f",
                    request.delay,
                    request.dwell
                )
            }
            let previewLogURL = evidenceDirectory?.appendingPathComponent("scene-preview.log")
            let userPropertyTextureURLs = requestedUserPropertyTextureURLs(rootURL: rootURL)
            publishRequestedMediaThumbnail(rootURL: rootURL)
            if ProcessInfo.processInfo.arguments.contains(
                "--mwx-debug-scene-async-launch-smoke"
            ) {
                runtimeHost.requestLaunch(
                    rootURL: rootURL,
                    propertyOverrides: requestedPropertyOverrides,
                    userPropertyTextureURLs: userPropertyTextureURLs,
                    logURL: previewLogURL,
                    recordID: debugRecordID
                ) { result in
                    switch result {
                    case let .success(model):
                        runtimeHost.setPlaybackPaused(false)
                        let snapshot = runtimeHost.debugSnapshot()
                        NSLog(
                            "MWX DEBUG SCENE: phase=async-launch-ready root=%@ layers=%d surfaces=%d",
                            rootURL.path,
                            model.renderDescriptor.layers.count,
                            snapshot.surfaceCount
                        )
                        if let evidenceDirectory {
                            scheduleSnapshots(outputDirectory: evidenceDirectory, previewLogURL: previewLogURL)
                        }
                        terminate(after: requestedDuration)
                    case let .failure(error):
                        NSLog(
                            "MWX DEBUG SCENE: phase=async-launch-failed error=%@",
                            error.localizedDescription
                        )
                        terminate(after: 0.1)
                    }
                }
                DispatchQueue.main.async {
                    NSLog("MWX DEBUG SCENE: phase=async-launch-request-returned mainResponsive=true")
                }
                return
            }
            if let hoverPointer = requestedHoverPointer {
                // Freeze the synthetic pointer outside before surface creation so
                // the first authored edge belongs to the declared benchmark step,
                // not to the operator's current mouse location. The explicit
                // from-launch opt-in keeps that edge but declares it as the
                // requested point, which is the only way to reach an authored
                // callback that depends on first-frame state.
                runtimeHost.setDebugPointerOverride(
                    requestedHoverPointerFromLaunch
                        ? .init(
                            current: hoverPointer,
                            isInside: true,
                            isPrimaryButtonDown: false
                        )
                        : .init()
                )
            }
            NSLog(
                "MWX LAUNCH-STAGE: stage=runner-pre-launch elapsedMs=%.0f",
                (ProcessInfo.processInfo.systemUptime - requestUptime) * 1_000
            )
            let model = try await runtimeHost.launch(
                rootURL: rootURL,
                propertyOverrides: requestedPropertyOverrides,
                userPropertyTextureURLs: userPropertyTextureURLs,
                logURL: previewLogURL,
                recordID: debugRecordID
            )
            NSLog(
                "MWX LAUNCH-STAGE: stage=host-launch-return elapsedMs=%.0f",
                (ProcessInfo.processInfo.systemUptime - requestUptime) * 1_000
            )
            scheduleRequestedMediaThumbnailSequence(rootURL: rootURL)
            // 隔离证据进程必须显式解除宿主在首个窗口出现前捕获的 focus pause。
            runtimeHost.setPlaybackPaused(false)
            NSLog(
                "MWX LAUNCH-STAGE: stage=launch-return elapsedMs=%.0f",
                (ProcessInfo.processInfo.systemUptime - requestUptime) * 1_000
            )
            scheduleRequestedAudioSpectrumFixture()
            let runtimeEvidenceURL = try writeRuntimeEvidence(
                model: model,
                to: evidenceDirectory
            )
            let snapshot = runtimeHost.debugSnapshot()
            let imageLayerCount = model.renderDescriptor.layers.filter(\.isImageRenderable).count
            let startupElapsedMS = (
                ProcessInfo.processInfo.systemUptime - requestUptime
            ) * 1_000
            NSLog(
                "MWX DEBUG SCENE: phase=ready root=%@ layers=%d imageLayers=%d effects=%d surfaces=%d startupElapsedMS=%.3f windows=%@ previewLog=%@ runtimeEvidence=%@",
                rootURL.path,
                model.renderDescriptor.layers.count,
                imageLayerCount,
                model.sceneDocument.effectCount,
                snapshot.surfaceCount,
                startupElapsedMS,
                snapshot.windowNumbers.map(String.init).joined(separator: ","),
                previewLogURL?.path ?? "-",
                runtimeEvidenceURL?.path ?? "-"
            )
            if let evidenceDirectory {
                if let hoverPointer = requestedHoverPointer {
                    setPointerOutside()
                    schedulePointerSnapshots(
                        outputDirectory: evidenceDirectory,
                        hoverPointer: hoverPointer,
                        stationaryEntry: requestedHoverPointerStationaryEntry,
                        primaryClick: requestedPrimaryClick,
                        dragPointer: requestedDragPointer,
                        pointerTrajectory: requestedPointerTrajectory
                    )
                    schedulePeriodicSnapshots(outputDirectory: evidenceDirectory)
                } else {
                    scheduleSnapshots(outputDirectory: evidenceDirectory, previewLogURL: previewLogURL)
                }
                scheduleResizeSequence(outputDirectory: evidenceDirectory)
                scheduleExecutorInvalidation(
                    outputDirectory: evidenceDirectory
                )
                scheduleSceneSwitch(
                    request: sceneSwitchRequest,
                    recordID: debugRecordID,
                    propertyOverrides: requestedPropertyOverrides,
                    logURL: previewLogURL,
                    outputDirectory: evidenceDirectory
                )
                scheduleSurfaceStopRelaunch(
                    delay: surfaceStopRelaunchDelay,
                    recordID: debugRecordID,
                    rootURL: rootURL,
                    propertyOverrides: requestedPropertyOverrides,
                    userPropertyTextureURLs: userPropertyTextureURLs,
                    logURL: previewLogURL,
                    outputDirectory: evidenceDirectory
                )
                schedulePauseResume(
                    request: pauseResumeRequest,
                    outputDirectory: evidenceDirectory
                )
            }
            let livePropertyOverrides = requestedLivePropertyOverrides
            if !livePropertyOverrides.isEmpty {
                scheduleAudioSpectrumLivePropertyObservations()
                scheduleLivePropertyUpdate(livePropertyOverrides)
            }
            schedulePerformanceMeasurement(
                duration: requestedDuration,
                afterSnapshotDelay: requestedAfterSnapshotDelay
            )
            scheduleStop(after: requestedDuration)
        } catch {
            runtimeHost.stop()
            NSLog(
                "MWX DEBUG SCENE: phase=launch-failed root=%@ error=%@",
                rootURL.path,
                error.localizedDescription
            )
            terminate(after: 0.1)
        }
    }

    private static func writeRuntimeEvidence(
        model: SceneRuntimeModel,
        to outputDirectory: URL?
    ) throws -> URL? {
        guard let outputDirectory else { return nil }
        let outputURL = outputDirectory.appendingPathComponent(
            "scene-runtime-evidence.json"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(SceneRuntimeEvidence(model: model)).write(
            to: outputURL,
            options: [.atomic]
        )
        return outputURL
    }

    private static func scheduleStop(after duration: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            let before = runtimeHost.debugSnapshot()
            runtimeHost.stop()
            let after = runtimeHost.debugSnapshot()
            NSLog(
                "MWX DEBUG SCENE: phase=stopped surfacesBefore=%d surfacesAfter=%d",
                before.surfaceCount,
                after.surfaceCount
            )
            terminate(after: 0.2)
        }
    }

    private static func scheduleSnapshots(
        outputDirectory: URL,
        previewLogURL: URL?
    ) {
        for (reason, delay) in [("ready", 1.0), ("after", requestedAfterSnapshotDelay)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                requestSnapshot(reason: reason, outputDirectory: outputDirectory)
                // The launch-time particle summary undercounts child-only
                // containers (their particles spawn after advance-by-0); the
                // after point captures the settled state for the evidence.
                if reason == "after", let previewLogURL {
                    // Append: the launch-time evidence lines above must
                    // survive for the benchmark's validation gates.
                    let lines = runtimeHost.debugParticleLoadReportLines()
                    let report = lines.joined(separator: "\n") + "\n"
                    if let handle = try? FileHandle(forWritingTo: previewLogURL) {
                        defer { try? handle.close() }
                        try? handle.seekToEnd()
                        try? handle.write(contentsOf: Data(report.utf8))
                    }
                }
            }
        }
        schedulePeriodicSnapshots(outputDirectory: outputDirectory)
    }

    private static func scheduleResizeSequence(outputDirectory: URL) {
        for (index, event) in requestedResizeSequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + event.delay) {
                let accepted = runtimeHost
                    .debugResizeSurfaces(scale: event.scale)
                NSLog(
                    "MWX DEBUG SCENE: phase=surface-resize index=%d scale=%.4f accepted=%@",
                    index,
                    event.scale,
                    accepted ? "true" : "false"
                )
                guard accepted else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    requestSnapshot(
                        reason: String(format: "resize-%02d", index),
                        outputDirectory: outputDirectory
                    )
                }
            }
        }
    }

    private static func scheduleExecutorInvalidation(outputDirectory: URL) {
        guard let delay = requestedExecutorInvalidationDelay else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let before = runtimeHost.debugSnapshot()
            let accepted = runtimeHost
                .debugInvalidateResolvedMaterialRuntimes(
                    reason: .executorInvalidation
                )
            let after = runtimeHost.debugSnapshot()
            NSLog(
                "MWX DEBUG SCENE: phase=executor-invalidation state=triggered accepted=%@ surfacesBefore=%d surfacesAfter=%d",
                accepted ? "true" : "false",
                before.surfaceCount,
                after.surfaceCount
            )
            guard accepted else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                requestSnapshot(
                    reason: "executor-invalidation-after",
                    outputDirectory: outputDirectory
                )
            }
        }
    }

    private static func schedulePeriodicSnapshots(outputDirectory: URL) {
        guard let interval = requestedPeriodicSnapshotInterval else { return }
        var delay = max(1.5, interval)
        var index = 0
        while delay < requestedDuration - 0.5 {
            let reason = String(format: "series-%04d", index)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                requestSnapshot(reason: reason, outputDirectory: outputDirectory)
            }
            delay += interval
            index += 1
        }
    }


    static func requestSnapshot(reason: String, outputDirectory: URL) {
        guard let windowNumber = runtimeHost
            .debugSnapshot().windowNumbers.first else {
            NSLog(
                "MWX DEBUG SCENE: phase=snapshot-failed reason=%@ stage=surface-lookup error=unknown",
                reason
            )
            return
        }
        let accepted = runtimeHost.requestDebugSnapshot(
            windowNumber: windowNumber,
            reason: reason,
            outputDirectory: outputDirectory
        )
        if !accepted {
            NSLog(
                "MWX DEBUG SCENE: phase=snapshot-failed reason=%@ stage=surface-lookup error=unknown",
                reason
            )
        }
    }

    private static func scheduleLivePropertyUpdate(
        _ replacements: [String: SceneUserPropertyValue]
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let before = runtimeHost.debugSnapshot()
            let accepted = runtimeHost.applyUserPropertyValues(
                replacements,
                changedPropertyKeys: Set(replacements.keys),
                recordID: debugRecordID
            )
            let after = runtimeHost.debugSnapshot()
            NSLog(
                "MWX DEBUG SCENE: phase=live-property-update accepted=%@ surfacesBefore=%d surfacesAfter=%d windowsBefore=%@ windowsAfter=%@ keys=%@",
                accepted ? "true" : "false",
                before.surfaceCount,
                after.surfaceCount,
                before.windowNumbers.map(String.init).joined(separator: ","),
                after.windowNumbers.map(String.init).joined(separator: ","),
                replacements.keys.sorted().joined(separator: ",")
            )
        }
    }

    private static let executorInvalidationDelayEnvironmentKey =
        "MWX_SCENE_DEBUG_EXECUTOR_INVALIDATE_AFTER"

    private static var requestedExecutorInvalidationDelay: TimeInterval? {
        guard let raw = ProcessInfo.processInfo.environment[
            executorInvalidationDelayEnvironmentKey
        ], let delay = TimeInterval(raw), delay.isFinite,
              delay >= 1,
              delay < requestedDuration - 0.75 else { return nil }
        return delay
    }

    static func isIsolatedSampleRoot(_ rootURL: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        let realWorkshopRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/MyWallpaperX/创意工坊", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        return rootURL.path != realWorkshopRoot
            && rootURL.path.hasPrefix(realWorkshopRoot + "/") == false
    }

    private static func terminate(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.terminate(nil)
        }
    }
}
#endif
