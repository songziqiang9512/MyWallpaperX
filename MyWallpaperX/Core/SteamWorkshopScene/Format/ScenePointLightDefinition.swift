import CoreFoundation
import Foundation

/// Loss-preserving point-light inputs consumed by the shared frame lighting
/// snapshot. `lpoint` and `point` parse identically here; consumers split by
/// kind (official: `lpoint` lights static models, `point` lights 2D lit
/// images only — own-fixture black-box, 2026-10-06).
struct ScenePointLightDefinition: Codable, Equatable {
    nonisolated struct Volume: Codable, Equatable, Sendable {
        let density: Float
        let exponent: Float
    }

    let kind: String
    let colorRGB: [Float]?
    let intensity: Float?
    let radius: Float?
    let castsVolumetrics: Bool?
    let castsShadow: Bool?
    let isSolid: Bool?
    var exponent: Float? = nil
    var volume: Volume? = nil

    nonisolated var unshadowedVolume: Volume? {
        guard kind == "lpoint", castsVolumetrics == true, castsShadow != true,
              let volume, volume.density > 0 else { return nil }
        return volume
    }

    nonisolated static func parse(
        _ root: [String: Any]
    ) -> ScenePointLightDefinition? {
        guard let rawKind = root["light"] as? String else { return nil }
        let kind = rawKind.localizedLowercase
        guard kind == "lpoint" || kind == "point" else { return nil }
        let shadow = SceneShadowCastIntent.parse(root["castshadow"])
        let volume: Volume?
        if let density = number(resolvedValue(root["density"])), density >= 0,
           let exponent = number(resolvedValue(root["volumetricsexponent"])), exponent >= 0 {
            volume = Volume(density: density, exponent: exponent)
        } else {
            volume = nil
        }
        return ScenePointLightDefinition(
            kind: kind,
            colorRGB: vector(resolvedValue(root["color"])),
            intensity: number(resolvedValue(root["intensity"])),
            radius: number(resolvedValue(root["radius"])),
            castsVolumetrics: resolvedValue(root["castvolumetrics"]) as? Bool,
            castsShadow: shadow == .enabled ? true : shadow == .disabled ? false : nil,
            isSolid: resolvedValue(root["solid"]) as? Bool,
            exponent: number(resolvedValue(root["exponent"])).flatMap { $0 >= 0 ? $0 : nil },
            volume: volume
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
