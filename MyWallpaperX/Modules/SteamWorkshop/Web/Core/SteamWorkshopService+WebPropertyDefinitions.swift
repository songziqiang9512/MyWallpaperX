import Foundation

extension SteamWorkshopService {
    func webPropertyDefinitions(for record: SteamWorkshopDownloadRecord) -> [SteamWorkshopWebPropertyDefinition] {
        guard let sourceRecord = webPropertyDefinitionSourceRecord(for: record),
              let root = Self.loadWebProjectRootStatic(for: sourceRecord) else {
            return []
        }
        return Self.webPropertyDefinitions(projectRoot: root)
    }

    /// 解析核：project root 由调用方加载后传入，可在任意线程执行。
    nonisolated static func webPropertyDefinitions(projectRoot root: [String: Any]) -> [SteamWorkshopWebPropertyDefinition] {
        guard let general = root["general"] as? [String: Any],
              let properties = general["properties"] as? [String: Any] else {
            return []
        }

        let localization = Self.webProjectLocalization(from: root)
        var definitions: [SteamWorkshopWebPropertyDefinition] = []
        for (key, rawValue) in properties {
            guard let propertyObject = rawValue as? [String: Any] else {
                continue
            }
            let rawType = (propertyObject["type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let runtimeType = rawType.isEmpty ? SteamWorkshopWebPropertyKind.unknown.rawValue : rawType
            let kind: SteamWorkshopWebPropertyKind
            switch rawType {
            case "slider": kind = .slider
            case "color": kind = .color
            case "bool", "boolean", "checkbox": kind = .toggle
            case "textinput": kind = .text
            case "text", "label": kind = .label
            case "file": kind = .file
            case "directory": kind = .directory
            case "combo", "combobox", "dropdown": kind = .combo
            case "group": kind = .group
            default:
                kind = SteamWorkshopService.inferWebPropertyKind(
                    key: key,
                    rawTitle: propertyObject["text"] as? String,
                    value: propertyObject["value"]
                )
            }

            let value = Self.webPropertyValue(from: propertyObject["value"]) ?? .string("")
            let rawTitle = Self.trimmedNonEmptyString(propertyObject["text"] as? String)

            definitions.append(
                SteamWorkshopWebPropertyDefinition(
                    key: key,
                    title: Self.webPropertyTitle(
                        key: key,
                        rawTitle: rawTitle.flatMap { Self.localizedWebString($0, localization: localization) }
                    ),
                    kind: kind,
                    runtimeType: runtimeType,
                    order: propertyObject["order"] as? Int ?? propertyObject["index"] as? Int ?? 0,
                    minimumValue: Self.webPropertyNumber(from: propertyObject["min"]),
                    maximumValue: Self.webPropertyNumber(from: propertyObject["max"]),
                    allowsFractionalValues: Self.webPropertyBool(from: propertyObject["fraction"]) ?? true,
                    fractionalPrecision: Self.webPropertyPrecision(from: propertyObject["precision"]),
                    displayCondition: Self.trimmedNonEmptyString(propertyObject["condition"] as? String),
                    directoryMode: Self.normalizedWebDirectoryMode(from: propertyObject),
                    fileType: kind == .file
                        ? Self.normalizedWebPropertyFileType(
                            from: propertyObject,
                            key: key,
                            rawTitle: rawTitle
                        )
                        : nil,
                    defaultValue: value,
                    options: Self.webPropertyOptions(
                        from: propertyObject["options"] ?? propertyObject["values"],
                        localization: localization
                    )
                )
            )
        }

        return definitions.sorted {
            if $0.order == $1.order {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.order < $1.order
        }
    }

    nonisolated func webShellResourcePathLikePresetValues(for record: SteamWorkshopDownloadRecord) -> [String: SteamWorkshopWebPropertyValue] {
        guard record.isDependencyBackedWeb else { return [:] }
        let presetValues = Self.webPresetValues(for: record)
        var values: [String: SteamWorkshopWebPropertyValue] = [:]
        for (key, value) in presetValues {
            guard let raw = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard Self.fallbackResourceSemantic(forKey: normalizedKey, rawPath: raw) != nil else {
                continue
            }
            values[key] = value
        }
        return values
    }

    nonisolated func webShellResourcePathLikeKeys(for record: SteamWorkshopDownloadRecord) -> Set<String> {
        Set(
            webShellResourcePathLikePresetValues(for: record)
                .keys
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
    }

    nonisolated static func trimmedNonEmptyString(_ rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
