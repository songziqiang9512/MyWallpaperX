import CoreFoundation
import Foundation

/// Loss-preserving point-light inputs consumed by the shared frame lighting
/// snapshot. Both current Workshop `lpoint` and shipping default-project
/// `point` declarations name the same authored light kind.
struct ScenePointLightDefinition: Codable, Equatable {
    let kind: String
    let colorRGB: [Float]?
    let intensity: Float?
    let radius: Float?
    let castsVolumetrics: Bool?
    let castsShadow: Bool?
    let isSolid: Bool?

    nonisolated static func parse(
        _ root: [String: Any]
    ) -> ScenePointLightDefinition? {
        guard let rawKind = root["light"] as? String else { return nil }
        let kind = rawKind.localizedLowercase
        guard kind == "lpoint" || kind == "point" else { return nil }
        return ScenePointLightDefinition(
            kind: kind,
            colorRGB: vector(resolvedValue(root["color"])),
            intensity: number(resolvedValue(root["intensity"])),
            radius: number(resolvedValue(root["radius"])),
            castsVolumetrics: resolvedValue(root["castvolumetrics"]) as? Bool,
            castsShadow: resolvedValue(root["castshadow"]) as? Bool,
            isSolid: resolvedValue(root["solid"]) as? Bool
        )
    }

    /// Preserve the authored fallback carried by dynamic wrappers. Live
    /// intensity publication remains a separate runtime capability.
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
