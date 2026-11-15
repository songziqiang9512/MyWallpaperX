import CoreFoundation
import Foundation

struct SceneTubeLightDefinition: Codable, Equatable {
    let controlPoint: SIMD3<Float>
    let colorRGB: [Float]?
    let intensity: Float?
    let radius: Float?
    var exponent: Float? = nil

    nonisolated static func parse(_ root: [String: Any]) -> Self? {
        guard let kind = root["light"] as? String,
              kind.localizedLowercase == "ltube",
              let endpoint = vector(resolvedValue(root["controlpoint"])) else { return nil }
        return Self(
            controlPoint: SIMD3(endpoint[0], endpoint[1], endpoint[2]),
            colorRGB: vector(resolvedValue(root["color"])),
            intensity: number(resolvedValue(root["intensity"])),
            radius: number(resolvedValue(root["radius"])),
            exponent: number(resolvedValue(root["exponent"])).flatMap { $0 >= 0 ? $0 : nil }
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
        let tokens = string.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
        guard tokens.count == 3 else { return nil }
        let values = tokens.compactMap { Float($0) }
        return values.count == 3 && values.allSatisfy(\.isFinite) ? values : nil
    }
}
