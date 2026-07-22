import CoreFoundation
import Foundation

enum SceneUserPropertyKind: String, Codable, Equatable, Hashable {
    case bool
    case slider
    case color
    case combo
    case textInput = "textinput"
    case text
    case group
    case sceneTexture = "scenetexture"
    case unsupported
}

enum SceneUserPropertyValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    nonisolated var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    nonisolated var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    nonisolated var boolValue: Bool? {
        switch self {
        case let .bool(value):
            return value
        case let .number(value):
            return value != 0
        case let .string(value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off": return false
            default: return nil
            }
        }
    }

    nonisolated var foundationValue: Any {
        switch self {
        case let .string(value): value
        case let .number(value): value
        case let .bool(value): value
        }
    }

    nonisolated func matches(_ other: SceneUserPropertyValue) -> Bool {
        comparisonToken == other.comparisonToken
    }

    nonisolated static func parse(_ rawValue: Any?) -> SceneUserPropertyValue? {
        switch rawValue {
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        case let value as Bool:
            return .bool(value)
        case let value as String:
            return .string(value)
        case let value as NSString:
            return .string(value as String)
        default:
            return nil
        }
    }

    private nonisolated var comparisonToken: String {
        switch self {
        case let .bool(value):
            return "bool:\(value)"
        case let .number(value):
            return "number:\(Self.normalizedNumber(value))"
        case let .string(value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercase = trimmed.lowercased()
            if ["true", "yes", "on"].contains(lowercase) { return "bool:true" }
            if ["false", "no", "off"].contains(lowercase) { return "bool:false" }
            if let number = Double(trimmed) {
                return "number:\(Self.normalizedNumber(number))"
            }
            return "string:\(trimmed)"
        }
    }

    private nonisolated static func normalizedNumber(_ value: Double) -> String {
        String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case string
        case number
        case bool
    }

    private enum EncodedKind: String, Codable {
        case string
        case number
        case bool
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EncodedKind.self, forKey: .kind) {
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .number:
            self = .number(try container.decode(Double.self, forKey: .number))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .bool))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(value):
            try container.encode(EncodedKind.string, forKey: .kind)
            try container.encode(value, forKey: .string)
        case let .number(value):
            try container.encode(EncodedKind.number, forKey: .kind)
            try container.encode(value, forKey: .number)
        case let .bool(value):
            try container.encode(EncodedKind.bool, forKey: .kind)
            try container.encode(value, forKey: .bool)
        }
    }
}

struct SceneUserPropertyOption: Identifiable, Codable, Equatable, Hashable {
    let label: String
    let value: SceneUserPropertyValue
    let displayCondition: String?

    nonisolated var id: String { "\(label)|\(value)" }
}

struct SceneUserPropertyDefinition: Identifiable, Codable, Equatable, Hashable {
    let key: String
    let title: String
    let kind: SceneUserPropertyKind
    let runtimeType: String
    let order: Int
    let index: Int?
    let minimumValue: Double?
    let maximumValue: Double?
    let stepValue: Double?
    let allowsFractionalValues: Bool
    let fractionalPrecision: Int?
    let displayCondition: String?
    let defaultValue: SceneUserPropertyValue?
    let options: [SceneUserPropertyOption]

    nonisolated var id: String { key }
}

struct SceneUserPropertyCatalog {
    let definitions: [SceneUserPropertyDefinition]

    nonisolated var defaultValues: [String: SceneUserPropertyValue] {
        definitions.reduce(into: [:]) { values, definition in
            if let defaultValue = definition.defaultValue {
                values[definition.key] = defaultValue
            }
        }
    }

    nonisolated var unsupportedDefinitions: [SceneUserPropertyDefinition] {
        definitions.filter { $0.kind == .unsupported }
    }

    nonisolated func effectiveValues(
        overrides: [String: SceneUserPropertyValue]
    ) -> [String: SceneUserPropertyValue] {
        let knownKeys = Set(definitions.map(\.key))
        return overrides.reduce(into: defaultValues) { values, override in
            guard knownKeys.contains(override.key) else { return }
            values[override.key] = override.value
        }
    }

    static let empty = SceneUserPropertyCatalog(definitions: [])
}
