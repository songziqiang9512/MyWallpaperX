import Foundation

/// Parsed 2D projection inputs for authored `lspot` objects.
///
/// Parsing preserves incomplete declarations; the rendering plan owns strict
/// admission so malformed or unsupported lights remain fail-closed.
struct SceneSpotLightDefinition: Codable, Equatable {
    let kind: String
    let colorRGB: [Float]?
    let intensity: Float?
    let radius: Float?
    let innerConeDegrees: Float?
    let outerConeDegrees: Float?
    let density: Float?
    let exponent: Float?
    let volumetricsExponent: Float?
    let castsVolumetrics: Bool?
    let castsShadow: Bool?
    let isSolid: Bool?

    nonisolated static func parse(_ root: [String: Any]) -> SceneSpotLightDefinition? {
        guard let kind = string(root["light"]), kind.lowercased() == "lspot" else {
            return nil
        }
        return SceneSpotLightDefinition(
            kind: kind.lowercased(),
            colorRGB: vector(resolvedValue(root["color"])),
            intensity: number(resolvedValue(root["intensity"])),
            radius: number(resolvedValue(root["radius"])),
            innerConeDegrees: number(resolvedValue(root["innercone"])),
            outerConeDegrees: number(resolvedValue(root["outercone"])),
            density: number(resolvedValue(root["density"])),
            exponent: number(resolvedValue(root["exponent"])),
            volumetricsExponent: number(resolvedValue(root["volumetricsexponent"])),
            castsVolumetrics: resolvedValue(root["castvolumetrics"]) as? Bool,
            castsShadow: resolvedValue(root["castshadow"]) as? Bool,
            isSolid: resolvedValue(root["solid"]) as? Bool
        )
    }

    /// Script/user-property wrappers retain an authored value that remains the
    /// safe light input until the typed runtime publishes a newer value.
    private nonisolated static func resolvedValue(_ value: Any?) -> Any? {
        (value as? [String: Any])?["value"] ?? value
    }

    private nonisolated static func string(_ value: Any?) -> String? {
        value as? String
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
        return values.count == 3 && values.allSatisfy(\.isFinite) ? values : nil
    }
}
