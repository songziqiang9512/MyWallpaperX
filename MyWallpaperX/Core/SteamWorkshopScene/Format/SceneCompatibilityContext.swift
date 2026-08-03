import CoreFoundation
import Foundation

/// Loss-preserving integer field used by compatibility normalization. Missing,
/// explicit zero and malformed author data are intentionally distinct.
nonisolated enum SceneDeclaredInteger: Codable, Equatable, Sendable {
    case missing
    case value(Int64)
    case invalidType(String)
    case outOfRange(String)

    nonisolated static func parse(
        root: [String: Any],
        fieldName: String
    ) -> SceneDeclaredInteger {
        guard root.keys.contains(fieldName) else { return .missing }
        guard let raw = root[fieldName] else { return .missing }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return .invalidType(typeName(raw))
        }

        let rawText = number.stringValue
        if let value = Int64(rawText) { return .value(value) }
        let floating = number.doubleValue
        guard floating.isFinite else { return .outOfRange(rawText) }
        guard floating.rounded(.towardZero) == floating else {
            return .invalidType("non-integer-number")
        }
        guard let value = Int64(exactly: floating) else {
            return .outOfRange(rawText)
        }
        return .value(value)
    }

    nonisolated var integerValue: Int64? {
        guard case let .value(value) = self else { return nil }
        return value
    }

    nonisolated private static func typeName(_ value: Any) -> String {
        switch value {
        case is NSNull: "null"
        case is Bool: "boolean"
        case is String: "string"
        case is [Any]: "array"
        case is [String: Any]: "object"
        default: String(describing: type(of: value))
        }
    }
}

nonisolated struct SceneCompatibilityFact<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    nonisolated enum SourceKind: String, Codable, Equatable, Sendable {
        case projectJSON = "project-json"
        case sceneEntry = "scene-entry"
    }

    let value: Value
    let sourceKind: SourceKind
    let sourceRelativePath: String
    let fieldName: String
}

/// R2 records compatibility inputs without inventing an effective version or
/// applying unverified upgrade rules. A later normalizer must consume each fact
/// explicitly and include any actual decision in its program/cache identity.
nonisolated struct SceneCompatibilityContext: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let projectVersion: SceneCompatibilityFact<SceneDeclaredInteger>
    let sceneVersion: SceneCompatibilityFact<SceneDeclaredInteger>

    nonisolated init(
        projectVersion: SceneCompatibilityFact<SceneDeclaredInteger>,
        sceneVersion: SceneCompatibilityFact<SceneDeclaredInteger>
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.projectVersion = projectVersion
        self.sceneVersion = sceneVersion
    }
}
