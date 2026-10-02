import CoreFoundation
import Foundation

/// Loss-preserving inputs needed by lit material programs for authored
/// directional lights. Dynamic wrappers contribute their authored fallback;
/// the live typed-input owner can replace it without changing this shape.
enum SceneShadowCastIntent: String, Codable, Equatable {
    case omitted, enabled, disabled, invalid

    nonisolated static func parse(_ raw: Any?) -> Self {
        guard let raw else { return .omitted }
        let value = (raw as? [String: Any])?["value"] ?? raw
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return .invalid }
        return number.boolValue ? .enabled : .disabled
    }

    var modelCastsShadow: Bool { self == .omitted || self == .enabled }
}

struct SceneDirectionalLightDefinition: Codable, Equatable {
    let colorRGB: [Float]?
    let intensity: Float?
    var shadowCastIntent: SceneShadowCastIntent? = nil

    nonisolated static func parse(
        _ root: [String: Any]
    ) -> SceneDirectionalLightDefinition? {
        guard let kind = root["light"] as? String,
              kind.localizedLowercase == "ldirectional" else {
            return nil
        }
        return SceneDirectionalLightDefinition(
            colorRGB: vector(resolvedValue(root["color"])),
            intensity: number(resolvedValue(root["intensity"])),
            shadowCastIntent: .parse(root["castshadow"])
        )
    }

    private nonisolated static func resolvedValue(_ value: Any?) -> Any? {
        (value as? [String: Any])?["value"] ?? value
    }

    private nonisolated static func number(_ value: Any?) -> Float? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.floatValue
        return result.isFinite ? result : nil
    }

    private nonisolated static func vector(_ value: Any?) -> [Float]? {
        guard let string = value as? String else { return nil }
        let tokens = string
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
        guard tokens.count == 3 else { return nil }
        let values = tokens.compactMap { Float($0) }
        return values.count == 3 && values.allSatisfy(\.isFinite)
            ? values : nil
    }
}
