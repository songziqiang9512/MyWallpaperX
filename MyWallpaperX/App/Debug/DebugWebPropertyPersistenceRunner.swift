//
//  DebugWebPropertyPersistenceRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation
import Darwin

@MainActor
enum DebugWebPropertyPersistenceRunner {
    private static let itemID = "1509243786"
    private static let switchItemID = "923576681"
    private static let fileKey = "image"
    private static let directoryKey = "customdirectory"
    private static let modeKey = "wallpapermode"
    private static var observedChildPIDs = Set<Int32>()

    static func scheduleIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let stage = argumentValue(
            after: "--mwx-debug-web-property-persistence-stage",
            in: arguments
        ) else {
            return false
        }
        let filePath = argumentValue(after: "--mwx-debug-web-property-file", in: arguments)
        let directoryPath = argumentValue(after: "--mwx-debug-web-property-directory", in: arguments)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            run(stage: stage, filePath: filePath, directoryPath: directoryPath)
        }
        return true
    }

    private static func run(stage: String, filePath: String?, directoryPath: String?) {
        guard DebugWebPlaybackRunner.hasUsableWorkshopRoot else {
            logEvent(stage: stage, action: "precondition", detail: "isolated-root-required")
            terminate(after: 0.1)
            return
        }
        let service = SteamWorkshopService.shared
        service.reloadInstalledItems()
        // 整库扫描异步完成：等两个样本记录实际可见再判前置（有界）。
        Task { @MainActor in
            guard let record = await DebugWebPlaybackRunner.awaitInstalledRecord(itemID, using: service),
                  let switchRecord = await DebugWebPlaybackRunner.awaitInstalledRecord(switchItemID, using: service),
                  record.contentType == .web,
                  switchRecord.contentType == .web else {
                logEvent(stage: stage, action: "precondition", detail: "samples-required")
                terminate(after: 0.1)
                return
            }
            await runResolved(stage: stage, filePath: filePath, directoryPath: directoryPath, service: service, record: record)
        }
    }

    private static func runResolved(
        stage: String,
        filePath: String?,
        directoryPath: String?,
        service: SteamWorkshopService,
        record: SteamWorkshopDownloadRecord
    ) async {
        captureWebProcessIdentifiers()
        let definitions = service.webPropertyDefinitions(for: record)
        guard let fileDefinition = definitions.first(where: { $0.key == fileKey }),
              let directoryDefinition = definitions.first(where: { $0.key == directoryKey }),
              let modeDefinition = definitions.first(where: { $0.key == modeKey }) else {
            logEvent(stage: stage, action: "precondition", detail: "properties-required")
            terminate(after: 0.1)
            return
        }

        switch stage {
        case "set-switch":
            guard let filePath, let directoryPath else {
                logEvent(stage: stage, action: "precondition", detail: "fixtures-required")
                terminate(after: 0.1)
                return
            }
            service.updateWebPropertyValue(.string(filePath), for: fileDefinition, record: record)
            service.updateWebPropertyValue(.string(directoryPath), for: directoryDefinition, record: record)
            service.updateWebPropertyValue(.number(2), for: modeDefinition, record: record)
            Task { @MainActor in
                await DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)
                await logState(stage: stage, action: "set", service: service, record: record)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                Task { @MainActor in
                    await DebugWebPlaybackRunner.launchWebWorkshopItem(switchItemID, using: service)
                    captureWebProcessIdentifiers()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                Task { @MainActor in
                    await DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)
                    await logState(stage: stage, action: "returned-a", service: service, record: record)
                }
            }
            finish(stage: stage, after: 15.0)
        case "restore-clear":
            Task { @MainActor in
                await DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)
                await logState(stage: stage, action: "restored", service: service, record: record)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                service.resetWebPropertyValues(for: record)
                Task { @MainActor in await logState(stage: stage, action: "cleared", service: service, record: record) }
            }
            finish(stage: stage, after: 6.0)
        case "verify-cleared":
            Task { @MainActor in
                await DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)
                await logState(stage: stage, action: "verified-cleared", service: service, record: record)
            }
            finish(stage: stage, after: 5.0)
        default:
            logEvent(stage: stage, action: "precondition", detail: "unknown-stage")
            terminate(after: 0.1)
        }
    }

    private static func finish(stage: String, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                let engine = WallpaperEngine.shared
                let host = engine.dedicatedWebHostAdapter as? WebDaemonHostAdapter
                let receipt = await stopAndWaitForWebExit(engine: engine, host: host, timeout: 8)
                logEvent(stage: stage, action: "completed", detail: nil, evidence: receipt)
                NSApp.terminate(nil)
            }
        }
    }

    private static func captureWebProcessIdentifiers() {
        guard let host = WallpaperEngine.shared.dedicatedWebHostAdapter as? WebDaemonHostAdapter else { return }
        observedChildPIDs.formUnion(host.liveProcessIdentifiers)
    }

    /// Parent adapter state alone is insufficient: a process may still be
    /// exiting after its logical request has been removed. Only ESRCH proves a
    /// captured PID absent; EPERM and other unknown probe failures stay live.
    private static func stopAndWaitForWebExit(
        engine: WallpaperEngine, host: WebDaemonHostAdapter?, timeout: TimeInterval
    ) async -> [String: String] {
        if let host { observedChildPIDs.formUnion(host.liveProcessIdentifiers) }
        engine.stopPlayback()
        let started = ProcessInfo.processInfo.systemUptime
        guard let host else {
            return ["stopProof": "web-daemon-process-exit-v1", "stopResult": "adapter-unavailable"]
        }
        while true {
            let adapterPIDs = host.liveProcessIdentifiers.sorted()
            observedChildPIDs.formUnion(adapterPIDs)
            let capturedPIDs = observedChildPIDs.sorted()
            let systemLivePIDs = capturedPIDs.filter { Darwin.kill($0, 0) == 0 || errno != ESRCH }
            let active = host.activeRequest != nil
            let pending = host.hasPendingRequest
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let exited = !capturedPIDs.isEmpty && adapterPIDs.isEmpty && systemLivePIDs.isEmpty && !active && !pending
            if exited || elapsed >= timeout {
                return [
                    "stopProof": "web-daemon-process-exit-v1",
                    "stopResult": exited ? "exited" : "timeout",
                    "stopTimedOut": String(!exited),
                    "pidProbe": "kill-zero-esrch-v1",
                    "parentPID": String(ProcessInfo.processInfo.processIdentifier),
                    "capturedChildPIDs": capturedPIDs.map(String.init).joined(separator: ","),
                    "systemLiveChildPIDs": systemLivePIDs.map(String.init).joined(separator: ","),
                    "adapterLiveChildPIDs": adapterPIDs.map(String.init).joined(separator: ","),
                    "activeRequestPresent": String(active),
                    "pendingRequestPresent": String(pending),
                    "stopWaitSeconds": String(elapsed)
                ]
            }
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return ["stopProof": "web-daemon-process-exit-v1", "stopResult": "cancelled"] }
        }
    }

    private static func terminate(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.terminate(nil)
        }
    }

    private static func logState(
        stage: String,
        action: String,
        service: SteamWorkshopService,
        record: SteamWorkshopDownloadRecord
    ) async {
        captureWebProcessIdentifiers()
        let definitions = service.webPropertyDefinitions(for: record)
        guard let fileDefinition = definitions.first(where: { $0.key == fileKey }),
              let directoryDefinition = definitions.first(where: { $0.key == directoryKey }),
              let modeDefinition = definitions.first(where: { $0.key == modeKey }) else {
            logEvent(stage: stage, action: "precondition", detail: "properties-required")
            return
        }
        let context = await service.resolvedWebPlaybackContext(for: record)
        let payload = payloadDictionary(from: context?.propertyPayloadJSON)
        let fileRaw = service.currentWebPropertyValue(for: fileDefinition, record: record).stringValue ?? ""
        let directoryRaw = service.currentWebPropertyValue(for: directoryDefinition, record: record).stringValue ?? ""
        let modeRaw = service.currentWebPropertyValue(
            for: modeDefinition,
            record: record
        ).displayConditionTextValue
        let fileBinding = service.resolvedWebResourceBinding(
            forKey: fileKey,
            definition: fileDefinition,
            rawValue: .string(fileRaw),
            record: record
        )
        let directoryBinding = service.resolvedWebResourceBinding(
            forKey: directoryKey,
            definition: directoryDefinition,
            rawValue: .string(directoryRaw),
            record: record
        )
        logJSON([
            "stage": stage,
            "action": action,
            "fileRaw": fileRaw,
            "fileResolved": fileBinding?.resolvedURL?.path ?? "",
            "fileSource": fileBinding.map { String(describing: $0.source) } ?? "",
            "filePayload": propertyValue(for: fileKey, in: payload),
            "fileBookmarkPresent": String(
                service.hasWebPropertyBookmark(forKey: fileKey, record: record)
            ),
            "directoryRaw": directoryRaw,
            "directoryResolved": directoryBinding?.resolvedURL?.path ?? "",
            "directorySource": directoryBinding.map { String(describing: $0.source) } ?? "",
            "directoryPayload": propertyValue(for: directoryKey, in: payload),
            "directoryBookmarkPresent": String(
                service.hasWebPropertyBookmark(forKey: directoryKey, record: record)
            ),
            "modeRaw": modeRaw,
            "modePayload": propertyValue(for: modeKey, in: payload)
        ])
    }

    private static func logEvent(stage: String, action: String, detail: String?, evidence: [String: String] = [:]) {
        var payload = [
            "stage": stage,
            "action": action,
            "fileRaw": "",
            "fileResolved": "",
            "fileSource": "",
            "filePayload": "",
            "fileBookmarkPresent": "",
            "directoryRaw": "",
            "directoryResolved": "",
            "directorySource": "",
            "directoryPayload": "",
            "directoryBookmarkPresent": "",
            "modeRaw": "",
            "modePayload": ""
        ]
        if let detail { payload["detail"] = detail }
        payload.merge(evidence) { _, current in current }
        logJSON(payload)
    }

    private static func logJSON(_ payload: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        NSLog("MWX DEBUG WEB PROPERTY: %@", json)
    }

    private static func payloadDictionary(from json: String?) -> [String: Any] {
        guard let json, let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func propertyValue(for key: String, in payload: [String: Any]) -> String {
        let value = (payload[key] as? [String: Any])?["value"]
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
#endif
