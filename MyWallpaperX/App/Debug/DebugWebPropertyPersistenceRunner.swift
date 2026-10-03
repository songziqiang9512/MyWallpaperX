//
//  DebugWebPropertyPersistenceRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation

@MainActor
enum DebugWebPropertyPersistenceRunner {
    private static let itemID = "1509243786"
    private static let switchItemID = "923576681"
    private static let fileKey = "image"
    private static let directoryKey = "customdirectory"
    private static let modeKey = "wallpapermode"

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
        guard let record = service.latestDownloadRecord(for: itemID),
              let switchRecord = service.latestDownloadRecord(for: switchItemID),
              record.contentType == .web,
              switchRecord.contentType == .web else {
            logEvent(stage: stage, action: "precondition", detail: "samples-required")
            terminate(after: 0.1)
            return
        }
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
            DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)
            logState(stage: stage, action: "set", service: service, record: record)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                DebugWebPlaybackRunner.launchWebWorkshopItem(switchItemID, using: service)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)
                logState(stage: stage, action: "returned-a", service: service, record: record)
            }
            finish(stage: stage, after: 15.0)
        case "restore-clear":
            DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)
            logState(stage: stage, action: "restored", service: service, record: record)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                service.resetWebPropertyValues(for: record)
                logState(stage: stage, action: "cleared", service: service, record: record)
            }
            finish(stage: stage, after: 6.0)
        case "verify-cleared":
            DebugWebPlaybackRunner.launchWebWorkshopItem(itemID, using: service)
            logState(stage: stage, action: "verified-cleared", service: service, record: record)
            finish(stage: stage, after: 5.0)
        default:
            logEvent(stage: stage, action: "precondition", detail: "unknown-stage")
            terminate(after: 0.1)
        }
    }

    private static func finish(stage: String, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            WallpaperEngine.shared.stopPlayback()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                logEvent(stage: stage, action: "completed", detail: nil)
                NSApp.terminate(nil)
            }
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
    ) {
        let definitions = service.webPropertyDefinitions(for: record)
        guard let fileDefinition = definitions.first(where: { $0.key == fileKey }),
              let directoryDefinition = definitions.first(where: { $0.key == directoryKey }),
              let modeDefinition = definitions.first(where: { $0.key == modeKey }) else {
            logEvent(stage: stage, action: "precondition", detail: "properties-required")
            return
        }
        let context = service.resolvedWebPlaybackContext(for: record)
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

    private static func logEvent(stage: String, action: String, detail: String?) {
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
