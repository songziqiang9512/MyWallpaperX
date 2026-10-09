import Foundation

extension SteamWorkshopService {
    nonisolated static func inferWebPropertyKind(
        key: String,
        rawTitle: String?,
        value: Any?
    ) -> SteamWorkshopWebPropertyKind {
        if value is Bool { return .toggle }
        if value is NSNumber { return .slider }
        let label = "\(key) \(rawTitle ?? "")".lowercased()
        if label.contains("color") || label.contains("colour") { return .color }
        if label.contains("file") { return .file }
        if label.contains("folder") || label.contains("directory") { return .directory }
        return .text
    }

    nonisolated static func webPropertyValue(from rawValue: Any?) -> SteamWorkshopWebPropertyValue? {
        switch rawValue {
        case let value as String:
            return .string(value)
        case let value as NSString:
            return .string(value as String)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        case let value as Bool:
            return .bool(value)
        default:
            return nil
        }
    }

    nonisolated static func webPropertyTitle(key: String, rawTitle: String?) -> String {
        if let rawTitle, !rawTitle.isEmpty {
            return normalizedWebPropertyTitleText(rawTitle)
        }
        let spaced = key.replacingOccurrences(of: "_", with: " ")
        return spaced.isEmpty ? key : normalizedWebPropertyTitleText(spaced.capitalized)
    }

    nonisolated static func webPropertyNumber(from rawValue: Any?) -> Double? {
        switch rawValue {
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    nonisolated static func webPropertyPrecision(from rawValue: Any?) -> Int? {
        switch rawValue {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    static func effectiveWebSliderPrecision(for definition: SteamWorkshopWebPropertyDefinition) -> Int? {
        guard definition.kind == .slider,
              definition.allowsFractionalValues else {
            return nil
        }
        return definition.fractionalPrecision ?? 2
    }

    nonisolated static func webPropertyBool(from rawValue: Any?) -> Bool? {
        switch rawValue {
        case let value as Bool:
            return value
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return value.boolValue
            }
            return value.intValue != 0
        case let value as String:
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    nonisolated static func webPropertyOptions(
        from rawValue: Any?,
        localization: [String: String]
    ) -> [SteamWorkshopWebPropertyOption] {
        if let array = rawValue as? [[String: Any]] {
            return array.compactMap { option in
                guard let value = webPropertyValue(from: option["value"]) else { return nil }
                let label = localizedWebString((option["label"] as? String) ?? (option["text"] as? String) ?? "\(value)", localization: localization)
                let condition = (option["condition"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                return SteamWorkshopWebPropertyOption(label: label, value: value, displayCondition: condition)
            }
        }
        if let dictionary = rawValue as? [String: Any] {
            return dictionary.compactMap { key, value in
                guard let normalized = webPropertyValue(from: value) else { return nil }
                return SteamWorkshopWebPropertyOption(label: localizedWebString(key, localization: localization), value: normalized, displayCondition: nil)
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }
        if let array = rawValue as? [String] {
            return array.map { SteamWorkshopWebPropertyOption(label: localizedWebString($0, localization: localization), value: .string($0), displayCondition: nil) }
        }
        return []
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
