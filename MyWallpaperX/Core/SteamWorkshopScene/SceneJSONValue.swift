import CoreFoundation
import Foundation

indirect enum SceneJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SceneJSONValue])
    case object([String: SceneJSONValue])

    nonisolated init?(jsonObject value: Any) {
        if value is NSNull {
            self = .null
            return
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
            return
        }
        if let string = value as? String {
            self = .string(string)
            return
        }
        if let array = value as? [Any] {
            let values = array.compactMap(SceneJSONValue.init(jsonObject:))
            guard values.count == array.count else { return nil }
            self = .array(values)
            return
        }
        if let object = value as? [String: Any] {
            var values: [String: SceneJSONValue] = [:]
            for (key, rawValue) in object {
                guard let parsed = SceneJSONValue(jsonObject: rawValue) else { return nil }
                values[key] = parsed
            }
            self = .object(values)
            return
        }
        return nil
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SceneJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SceneJSONValue].self))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    nonisolated var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    nonisolated var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    nonisolated var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}
