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
            let previewLogURL = evidenceDirectory?.appendingPathComponent("scene-preview.log")
            let userPropertyTextureURLs = requestedUserPropertyTextureURLs(rootURL: rootURL)
            let model = try SceneDesktopWallpaperHost.shared.launch(
                rootURL: rootURL,
                propertyOverrides: requestedPropertyOverrides,
                userPropertyTextureURLs: userPropertyTextureURLs,
                logURL: previewLogURL,
                recordID: debugRecordID
            )
            // 隔离证据进程必须显式解除宿主在首个窗口出现前捕获的 focus pause。
            WallpaperEngine.shared.resumeAllPlayers()
            let runtimeEvidenceURL = try writeRuntimeEvidence(
                model: model,
                to: evidenceDirectory
            )

            let snapshot = SceneDesktopWallpaperHost.shared.debugSnapshot()
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
                        hoverPointer: hoverPointer
                    )
                } else {
                    scheduleSnapshots(outputDirectory: evidenceDirectory)
                }
            }
            let livePropertyOverrides = requestedLivePropertyOverrides
            if !livePropertyOverrides.isEmpty {
                scheduleLivePropertyUpdate(livePropertyOverrides)
            }
            schedulePerformanceMeasurement(
                duration: requestedDuration,
                afterSnapshotDelay: requestedAfterSnapshotDelay
            )
            scheduleStop(after: requestedDuration)
        } catch {
            SceneDesktopWallpaperHost.shared.stop()
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
            let before = SceneDesktopWallpaperHost.shared.debugSnapshot()
            SceneDesktopWallpaperHost.shared.stop()
            let after = SceneDesktopWallpaperHost.shared.debugSnapshot()
            NSLog(
                "MWX DEBUG SCENE: phase=stopped surfacesBefore=%d surfacesAfter=%d",
                before.surfaceCount,
                after.surfaceCount
            )
            terminate(after: 0.2)
        }
    }

    private static func scheduleSnapshots(
        outputDirectory: URL
    ) {
        for (reason, delay) in [("ready", 1.0), ("after", requestedAfterSnapshotDelay)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                requestSnapshot(reason: reason, outputDirectory: outputDirectory)
            }
        }
        guard ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-periodic-snapshots"
        ) else { return }
        var delay: TimeInterval = 5
        while delay < requestedDuration - 1 {
            let reason = "t\(Int(delay))"
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                requestSnapshot(reason: reason, outputDirectory: outputDirectory)
            }
            delay += 5
        }
    }

    private static func schedulePointerSnapshots(
        outputDirectory: URL,
        hoverPointer: SIMD2<Float>
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            requestSnapshot(reason: "before", outputDirectory: outputDirectory)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            setPointer(hoverPointer)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            requestSnapshot(reason: "hover", outputDirectory: outputDirectory)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            setPointerOutside()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            requestSnapshot(reason: "after", outputDirectory: outputDirectory)
        }
    }

    private static func requestSnapshot(reason: String, outputDirectory: URL) {
        guard let windowNumber = SceneDesktopWallpaperHost.shared
            .debugSnapshot().windowNumbers.first else {
            NSLog(
                "MWX DEBUG SCENE: phase=snapshot-failed reason=%@ stage=surface-lookup error=unknown",
                reason
            )
            return
        }
        let accepted = SceneDesktopWallpaperHost.shared.requestDebugSnapshot(
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

    private static func setPointer(_ normalized: SIMD2<Float>) {
        SceneDesktopWallpaperHost.shared.setDebugPointerOverride(.init(
            current: normalized,
            previous: normalized,
            isInside: true,
            isPrimaryButtonDown: false
        ))
        NSLog(
            "MWX DEBUG SCENE: phase=pointer-state state=hover x=%.6f y=%.6f",
            normalized.x,
            normalized.y
        )
    }

    private static func setPointerOutside() {
        SceneDesktopWallpaperHost.shared.setDebugPointerOverride(.init())
        NSLog("MWX DEBUG SCENE: phase=pointer-state state=outside")
    }

    private static func scheduleLivePropertyUpdate(
        _ replacements: [String: SceneUserPropertyValue]
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let before = SceneDesktopWallpaperHost.shared.debugSnapshot()
            let accepted = SceneDesktopWallpaperHost.shared.applyUserPropertyValues(
                replacements,
                changedPropertyKeys: Set(replacements.keys),
                recordID: debugRecordID
            )
            let after = SceneDesktopWallpaperHost.shared.debugSnapshot()
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

    private static var requestedDuration: TimeInterval {
        guard let raw = argumentValue(after: "--mwx-debug-scene-duration"),
              let duration = TimeInterval(raw) else {
            return 10
        }
        return min(max(duration, 7), 60)
    }

    private static var requestedAfterSnapshotDelay: TimeInterval {
        guard let raw = argumentValue(after: "--mwx-debug-scene-after-snapshot-delay"),
              let delay = TimeInterval(raw), delay.isFinite else {
            return 3
        }
        return min(max(delay, 1.1), requestedDuration - 0.5)
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

    private static func isIsolatedSampleRoot(_ rootURL: URL) -> Bool {
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

    private static func argumentValue(after flag: String) -> String? {
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

    private static func requestedPropertyValues(
        after flag: String
    ) -> [String: SceneUserPropertyValue] {
        guard let payload = argumentValue(after: flag),
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object.reduce(into: [:]) { values, entry in
            values[entry.key] = SceneUserPropertyValue.parse(entry.value)
        }
    }

    private static func requestedUserPropertyTextureURLs(rootURL: URL) -> [String: URL] {
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
