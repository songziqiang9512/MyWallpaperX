import Foundation

enum SteamWorkshopWebPropertyKind: String, Codable, Equatable, Hashable {
    case slider
    case color
    case toggle
    case text
    case combo
    case file
    case directory
    case label
    case group
    case unknown
}

enum SteamWorkshopWebPropertyValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    var displayConditionTextValue: String {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            if let integer = Int(exactly: value) {
                return String(integer)
            }
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case string
        case number
        case bool
    }

    private enum Kind: String, Codable {
        case string
        case number
        case bool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .number:
            self = .number(try container.decode(Double.self, forKey: .number))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .bool))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .string)
        case let .number(value):
            try container.encode(Kind.number, forKey: .kind)
            try container.encode(value, forKey: .number)
        case let .bool(value):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(value, forKey: .bool)
        }
    }
}

struct SteamWorkshopWebPropertyOption: Identifiable, Codable, Equatable, Hashable {
    let label: String
    let value: SteamWorkshopWebPropertyValue
    let displayCondition: String?

    var id: String { "\(label)|\(value)" }
}

struct SteamWorkshopWebPropertyDefinition: Identifiable, Codable, Equatable, Hashable {
    let key: String
    let title: String
    let kind: SteamWorkshopWebPropertyKind
    let runtimeType: String
    let order: Int
    let minimumValue: Double?
    let maximumValue: Double?
    let allowsFractionalValues: Bool
    let fractionalPrecision: Int?
    let displayCondition: String?
    let directoryMode: String?
    let fileType: String?
    let defaultValue: SteamWorkshopWebPropertyValue
    let options: [SteamWorkshopWebPropertyOption]

    var id: String { key }
}

enum SteamWorkshopWebPropertySource: Codable, Equatable, Hashable {
    case ownProject
    case dependencyHost(itemID: String)

    var displayName: String {
        switch self {
        case .ownProject:
            return "本体项目"
        case let .dependencyHost(itemID):
            return "宿主项目 \(itemID)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, itemID
    }

    private enum Kind: String, Codable {
        case ownProject, dependencyHost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .ownProject:
            self = .ownProject
        case .dependencyHost:
            self = .dependencyHost(itemID: try container.decode(String.self, forKey: .itemID))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ownProject:
            try container.encode(Kind.ownProject, forKey: .kind)
        case let .dependencyHost(itemID):
            try container.encode(Kind.dependencyHost, forKey: .kind)
            try container.encode(itemID, forKey: .itemID)
        }
    }
}
