//
//  DebugWebPlaybackRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation

@MainActor
enum DebugWebPlaybackRunner {
    static var shouldSuppressInitialMainWindow: Bool {
        arguments.contains("--mwx-debug-suppress-main-window")
    }

    static var runsIsolatedWebWorkshopSample: Bool {
        arguments.contains("--mwx-debug-run-web-workshop-id")
            || arguments.contains("--mwx-debug-web-lifecycle-sequence")
            || arguments.contains("--mwx-debug-web-system-state-sequence")
            || arguments.contains("--mwx-debug-web-audio-restart-sequence")
            || arguments.contains("--mwx-debug-web-property-persistence-stage")
            || arguments.contains("--mwx-debug-web-space-lifecycle-sequence")
            || arguments.contains("--mwx-debug-web-runtime-switch-sequence")
            || arguments.contains("--mwx-debug-web-failure-state-report")
    }

    private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    static var hasUsableWorkshopRoot: Bool {
        guard let flagIndex = arguments.firstIndex(of: "--mwx-debug-workshop-root"),
              arguments.indices.contains(flagIndex + 1) else {
            return false
        }
        let rootPath = arguments[flagIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        var isDirectory = ObjCBool(false)
        return !rootPath.isEmpty
            && FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static func scheduleWorkshopPlaybackIfRequested() {
        guard let flagIndex = arguments.firstIndex(of: "--mwx-debug-play-workshop-id"),
              arguments.indices.contains(flagIndex + 1) else { return }
        let itemID = arguments[flagIndex + 1]

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let service = SteamWorkshopService.shared
            service.reloadInstalledItems()
            Task { @MainActor in
                // 整库扫描异步完成：等记录实际可见再走启动（有界）。
                guard let record = await awaitInstalledRecord(itemID, using: service) else {
                    NSLog("MWX DEBUG PLAY: workshop item %@ not found", itemID)
                    return
                }
                NSLog(
                    "MWX DEBUG PLAY: launching workshop item %@ type=%@",
                    itemID,
                    String(describing: record.contentType)
                )
                service.setAsWallpaper(record)
            }
        }
    }

    static func scheduleWebWorkshopRuntimeIfRequested() {
        if DebugWebFailureStateRunner.scheduleIfRequested() {
            return
        }

        if DebugWebRuntimeSwitchRunner.scheduleIfRequested() {
            return
        }

        if DebugWebSpaceLifecycleRunner.scheduleIfRequested() {
            return
        }

        if DebugWebPropertyPersistenceRunner.scheduleIfRequested() {
            return
        }

        if let restartIndex = arguments.firstIndex(of: "--mwx-debug-web-audio-restart-sequence"),
           arguments.indices.contains(restartIndex + 1) {
            scheduleAudioRestartSequence(itemID: arguments[restartIndex + 1])
            return
        }

        if let stateIndex = arguments.firstIndex(of: "--mwx-debug-web-system-state-sequence"),
           arguments.indices.contains(stateIndex + 1) {
            scheduleSystemStateSequence(itemID: arguments[stateIndex + 1])
            return
        }

        if let sequenceIndex = arguments.firstIndex(of: "--mwx-debug-web-lifecycle-sequence"),
           arguments.indices.contains(sequenceIndex + 1) {
            scheduleLifecycleSequence(rawItemIDs: arguments[sequenceIndex + 1])
            return
        }

        guard let flagIndex = arguments.firstIndex(of: "--mwx-debug-run-web-workshop-id"),
              arguments.indices.contains(flagIndex + 1) else { return }
        let itemID = arguments[flagIndex + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard hasUsableWorkshopRoot else {
                NSLog("MWX DEBUG PLAY: workshop item %@ precondition=isolated-root-required", itemID)
                return
            }
            if arguments.contains("--mwx-debug-web-evidence-dir") {
                NSApp.activate(ignoringOtherApps: true)
            }
            let service = SteamWorkshopService.shared
            NSLog("MWX DEBUG PLAY: using workshop root %@", service.libraryRootURL.path)
            service.reloadInstalledItems()
            Task { @MainActor in await launchWebWorkshopItem(itemID, using: service) }
        }
    }

    private static func scheduleLifecycleSequence(rawItemIDs: String) {
        let itemIDs = rawItemIDs
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard itemIDs.count >= 2 else {
            NSLog("MWX DEBUG LIFECYCLE: precondition=at-least-two-items-required")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard hasUsableWorkshopRoot else {
                NSLog("MWX DEBUG LIFECYCLE: precondition=isolated-root-required")
                return
            }
            let service = SteamWorkshopService.shared
            NSLog("MWX DEBUG PLAY: using workshop root %@", service.libraryRootURL.path)
            service.reloadInstalledItems()
            for (index, itemID) in itemIDs.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 4.0) {
                    Task { @MainActor in await launchWebWorkshopItem(itemID, using: service) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(itemIDs.count) * 4.0) {
                WallpaperEngine.shared.stopPlayback()
                NSLog("MWX DEBUG LIFECYCLE: stop requested")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSLog("MWX DEBUG LIFECYCLE: completed")
                }
            }
        }
    }

    private static func scheduleSystemStateSequence(itemID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard hasUsableWorkshopRoot else {
                NSLog("MWX DEBUG SYSTEM STATE: precondition=isolated-root-required")
                return
            }
            let service = SteamWorkshopService.shared
            NSLog("MWX DEBUG PLAY: using workshop root %@", service.libraryRootURL.path)
            service.reloadInstalledItems()
            Task { @MainActor in await launchWebWorkshopItem(itemID, using: service) }

            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                NSLog("MWX DEBUG SYSTEM STATE: action=system-sleep")
                PlaybackPolicyController.shared.setInterruption(.systemSleep, active: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.4) {
                NSLog("MWX DEBUG SYSTEM STATE: action=display-sleep")
                PlaybackPolicyController.shared.setInterruption(.displaySleep, active: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                NSLog("MWX DEBUG SYSTEM STATE: action=system-wake")
                PlaybackPolicyController.shared.setInterruption(.systemSleep, active: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.8) {
                NSLog("MWX DEBUG SYSTEM STATE: action=display-wake")
                PlaybackPolicyController.shared.setInterruption(.displaySleep, active: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.8) {
                NSLog("MWX DEBUG SYSTEM STATE: action=screen-lock")
                PlaybackPolicyController.shared.setInterruption(.screenLock, active: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.8) {
                NSLog("MWX DEBUG SYSTEM STATE: action=screen-unlock")
                PlaybackPolicyController.shared.setInterruption(.screenLock, active: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.8) {
                NSLog("MWX DEBUG SYSTEM STATE: action=stop")
                WallpaperEngine.shared.stopPlayback()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.2) {
                NSLog("MWX DEBUG SYSTEM STATE: action=completed")
            }
        }
    }

    private static func scheduleAudioRestartSequence(itemID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard hasUsableWorkshopRoot else {
                NSLog("MWX DEBUG AUDIO RESTART: precondition=isolated-root-required")
                return
            }
            let service = SteamWorkshopService.shared
            NSLog("MWX DEBUG PLAY: using workshop root %@", service.libraryRootURL.path)
            service.reloadInstalledItems()
            Task { @MainActor in await launchWebWorkshopItem(itemID, using: service) }

            for (index, delay) in [6.0, 6.05, 6.1].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NSLog("MWX DEBUG AUDIO RESTART: action=burst-%d", index + 1)
                    WallpaperEngine.shared.debugSimulateSystemAudioCaptureInvalidation()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                NSLog("MWX DEBUG AUDIO RESTART: action=single")
                WallpaperEngine.shared.debugSimulateSystemAudioCaptureInvalidation()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) {
                NSLog("MWX DEBUG AUDIO RESTART: action=stop")
                WallpaperEngine.shared.stopPlayback()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 11.9) {
                NSLog("MWX DEBUG AUDIO RESTART: action=completed")
            }
        }
    }

    /// 整库扫描是异步单飞（`reloadInstalledItems` 返回不代表 downloads 投影
    /// 已应用）；debug runner 的 reload→guard 链路须等记录实际可见，否则
    /// 在扫描完成前一律误报 not-found。
    static func awaitInstalledRecord(
        _ itemID: String,
        using service: SteamWorkshopService,
        timeout: TimeInterval = 8.0
    ) async -> SteamWorkshopDownloadRecord? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let record = service.latestDownloadRecord(for: itemID) {
                return record
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return service.latestDownloadRecord(for: itemID)
    }

    static func launchWebWorkshopItem(
        _ itemID: String,
        using service: SteamWorkshopService
    ) async {
        guard let record = await awaitInstalledRecord(itemID, using: service) else {
            NSLog("MWX DEBUG PLAY: workshop item %@ not found", itemID)
            return
        }
        if case let .missing(dependencyItemID) = record.dependencyStatus {
            NSLog("MWX DEBUG PLAY: workshop item %@ precondition=missing-dependency-%@", itemID, dependencyItemID)
            return
        }
        guard record.contentType == .web else {
            NSLog(
                "MWX DEBUG PLAY: workshop item %@ type=%@ is not web",
                itemID,
                String(describing: record.contentType)
            )
            return
        }
        guard service.canLaunchDownloadRecord(record) else {
            NSLog("MWX DEBUG PLAY: workshop item %@ precondition=not-launchable", itemID)
            return
        }
        guard let playbackContext = await service.resolvedWebPlaybackContext(for: record) else {
            NSLog("MWX DEBUG PLAY: workshop item %@ precondition=missing-playback-context", itemID)
            return
        }
        NSLog(
            "MWX DEBUG PLAY: launching workshop item %@ type=%@ isolatedRoot=%@",
            itemID,
            String(describing: record.contentType),
            service.libraryRootURL.path
        )
        WallpaperEngine.shared.setSystemAudioSpectrumEnabled(false)
        WallpaperEngine.shared.setWebWallpaper(
            entryURL: playbackContext.effectiveEntryURL,
            rootURL: playbackContext.effectiveRootURL,
            propertiesJSON: debugWebPropertiesJSON(overriding: playbackContext.propertyPayloadJSON),
            recordID: record.id,
            language: playbackContext.language,
            runtimeProfile: service.recommendedWebRuntimeProfile(for: record),
            multiDisplayEnabled: true
        )
        scheduleWebAudioSpectrumIfRequested()
    }

    private static func debugWebPropertiesJSON(overriding baseJSON: String?) -> String? {
        guard let flagIndex = arguments.firstIndex(of: "--mwx-debug-web-properties-file"),
              arguments.indices.contains(flagIndex + 1),
              let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[flagIndex + 1])),
              let overrides = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return baseJSON
        }
        var merged: [String: Any] = [:]
        if let baseJSON,
           let baseData = baseJSON.data(using: .utf8),
           let base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any] {
            merged = base
        }
        for (key, rawOverride) in overrides {
            var propertyPayload = merged[key] as? [String: Any] ?? [:]
            if let overridePayload = rawOverride as? [String: Any] {
                for (field, value) in overridePayload {
                    propertyPayload[field] = value
                }
            } else {
                propertyPayload["value"] = rawOverride
            }
            merged[key] = propertyPayload
        }
        guard JSONSerialization.isValidJSONObject(merged),
              let outputData = try? JSONSerialization.data(withJSONObject: merged),
              let json = String(data: outputData, encoding: .utf8) else {
            return baseJSON
        }
        NSLog("MWX DEBUG PLAY: applied %ld Web property override(s)", overrides.count)
        return json
    }

    private static func scheduleWebAudioSpectrumIfRequested() {
        guard arguments.contains("--mwx-debug-web-audio-spectrum-fixture") else { return }
        for frame in 0..<80 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + Double(frame) * 0.1) {
                let phase = Float(frame % 20) / 20
                let monoLevels = (0..<64).map { index -> Float in
                    let position = Float(index) / 63
                    return 0.12 + 0.72 * abs(sin((position + phase) * .pi * 4))
                }
                _ = WallpaperEngine.shared.dispatchWebAudioSpectrumIfNeeded(monoLevels + monoLevels)
            }
        }
    }
}
#endif
