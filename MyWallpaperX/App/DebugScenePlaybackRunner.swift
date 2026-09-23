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
            launchScene(rootPath: rootPath, requestUptime: requestUptime)
        }
    }

    private static func launchScene(rootPath: String, requestUptime: TimeInterval) {
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
            WallpaperEngine.shared.updateSettings(
                pauseWhenOtherAppFocused: false,
                pauseWhenOtherAppFullscreen: false,
                pauseWhenUnplugged: false,
                pauseWhenIdle: false,
                idleTimeoutMinutes: 10
            )
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
            let model = try runtimeHost.launch(
                rootURL: rootURL,
                propertyOverrides: requestedPropertyOverrides,
                userPropertyTextureURLs: userPropertyTextureURLs,
                logURL: previewLogURL,
                recordID: debugRecordID
            )
            scheduleRequestedMediaThumbnailSequence(rootURL: rootURL)
            // 隔离证据进程必须显式解除宿主在首个窗口出现前捕获的 focus pause。
            runtimeHost.setPlaybackPaused(false)
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

    static var requestedDuration: TimeInterval {
        guard let raw = argumentValue(after: "--mwx-debug-scene-duration"),
              let duration = TimeInterval(raw), duration.isFinite else {
            return 10
        }
        return min(max(duration, 7), 3_600)
    }

    static var requestedDropDynamicValuesFrameIndex: UInt64? {
        guard let raw = argumentValue(
            after: "--mwx-debug-scene-drop-dynamic-values-frame"
        ),
              let frameIndex = UInt64(raw),
              frameIndex > 0 else {
            return nil
        }
        return frameIndex
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

    private static var requestedAfterSnapshotDelay: TimeInterval {
        guard let raw = argumentValue(after: "--mwx-debug-scene-after-snapshot-delay"),
              let delay = TimeInterval(raw), delay.isFinite else {
            return 3
        }
        return min(max(delay, 1.1), requestedDuration - 0.5)
    }

    private static var requestedPeriodicSnapshotInterval: TimeInterval? {
        if let raw = argumentValue(
            after: "--mwx-debug-scene-periodic-snapshot-interval"
        ),
           let interval = TimeInterval(raw),
           interval.isFinite,
           interval >= 0.08 {
            return min(interval, 10)
        }
        return ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-periodic-snapshots"
        ) ? 5 : nil
    }

    private static var requestedResizeSequence: [(delay: TimeInterval, scale: CGFloat)] {
        guard let raw = argumentValue(after: "--mwx-debug-scene-resize-sequence") else {
            return []
        }
        return raw.split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let delay = TimeInterval(String(parts[0])),
                  let scale = Double(String(parts[1])),
                  delay > 0,
                  delay < requestedDuration - 0.75,
                  scale.isFinite,
                  scale > 0,
                  scale <= 1 else { return nil }
            return (delay, CGFloat(scale))
        }.sorted { $0.delay < $1.delay }
    }

    private static var requestedHoverPointer: SIMD2<Float>? {
        guard let payload = argumentValue(
            after: "--mwx-debug-scene-hover-pointer-json"
        ),
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let x = (object["x"] as? NSNumber)?.doubleValue,
              let y = (object["y"] as? NSNumber)?.doubleValue,
              x.isFinite,
              y.isFinite,
              (-1...1).contains(x),
              (-1...1).contains(y) else {
            return nil
        }
        return SIMD2(Float(x), Float(y))
    }

    private static var requestedHoverPointerStationaryEntry: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-hover-pointer-stationary-entry"
        )
    }

    private static var requestedPrimaryClick: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-primary-click"
        )
    }

    static var requestedPrimaryClickSubframe: Bool {
        ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-primary-click-subframe"
        )
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

    static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func terminate(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.terminate(nil)
        }
    }

    private static var requestedPropertyOverrides: [String: SceneUserPropertyValue] {
        requestedPropertyValues(after: "--mwx-debug-scene-properties-json")
    }

    private static var requestedLivePropertyOverrides: [String: SceneUserPropertyValue] {
        requestedPropertyValues(after: "--mwx-debug-scene-live-properties-json")
    }

    static func requestedPropertyValues(
        after flag: String
    ) -> [String: SceneUserPropertyValue] {
        strictRequestedPropertyValues(after: flag) ?? [:]
    }

    static func strictRequestedPropertyValues(
        after flag: String
    ) -> [String: SceneUserPropertyValue]? {
        guard let payload = argumentValue(after: flag) else { return [:] }
        guard let data = payload.data(using: .utf8), data.count <= 65_536,
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              object.count <= 64 else {
            return nil
        }
        var values: [String: SceneUserPropertyValue] = [:]
        for (key, rawValue) in object {
            guard !key.isEmpty,
                  key.utf8.count <= 512,
                  key.unicodeScalars.allSatisfy({
                      $0.value >= 32 && $0.value != 127
                  }),
                  let value = SceneUserPropertyValue.parse(rawValue) else {
                return nil
            }
            values[key] = value
        }
        return values
    }

    static func requestedUserPropertyTextureURLs(rootURL: URL) -> [String: URL] {
        guard let payload = argumentValue(after: "--mwx-debug-scene-textures-json"),
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        let resolvedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = resolvedRootURL.path + "/"
        return object.reduce(into: [:]) { urls, entry in
            let url = URL(fileURLWithPath: entry.value, relativeTo: resolvedRootURL)
                .resolvingSymlinksInPath().standardizedFileURL
            guard url.path.hasPrefix(rootPrefix),
                  SceneUserPropertyTextureLoader.supports(url: url),
                  FileManager.default.fileExists(atPath: url.path) else {
                NSLog(
                    "MWX DEBUG SCENE: phase=user-texture-rejected key=%@ file=%@",
                    entry.key,
                    url.lastPathComponent
                )
                return
            }
            urls[entry.key] = url
        }
    }
}
#endif
