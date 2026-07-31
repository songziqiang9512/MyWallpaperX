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
            colorRGB: vector(root["color"]),
            intensity: number(root["intensity"]),
            radius: number(root["radius"]),
            innerConeDegrees: number(root["innercone"]),
            outerConeDegrees: number(root["outercone"]),
            density: number(root["density"]),
            exponent: number(root["exponent"]),
            volumetricsExponent: number(root["volumetricsexponent"]),
            castsVolumetrics: root["castvolumetrics"] as? Bool,
            castsShadow: root["castshadow"] as? Bool,
            isSolid: root["solid"] as? Bool
        )
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
