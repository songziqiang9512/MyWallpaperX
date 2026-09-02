import Foundation

/// Loss-preserving inputs needed by lit material programs for authored
/// directional lights. Dynamic wrappers contribute their authored fallback;
/// the live typed-input owner can replace it without changing this shape.
struct SceneDirectionalLightDefinition: Codable, Equatable {
    let colorRGB: [Float]?
    let intensity: Float?

    nonisolated static func parse(
        _ root: [String: Any]
    ) -> SceneDirectionalLightDefinition? {
        guard let kind = root["light"] as? String,
              kind.localizedLowercase == "ldirectional" else {
            return nil
        }
        return SceneDirectionalLightDefinition(
            colorRGB: vector(resolvedValue(root["color"])),
            intensity: number(resolvedValue(root["intensity"]))
        )
    }

    private nonisolated static func resolvedValue(_ value: Any?) -> Any? {
        (value as? [String: Any])?["value"] ?? value
    }

    private nonisolated static func number(_ value: Any?) -> Float? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.floatValue
        return result.isFinite ? result : nil
    }

    private nonisolated static func vector(_ value: Any?) -> [Float]? {
        guard let string = value as? String else { return nil }
        let values = string
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
            .compactMap { Float($0) }
        return values.count == 3 && values.allSatisfy(\.isFinite)
            ? values : nil
    }
}
