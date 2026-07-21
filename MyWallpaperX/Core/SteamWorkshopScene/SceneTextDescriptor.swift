import Foundation

struct SceneTextDescriptor: Codable {
    let fontPath: String?
    let pointSize: Float
    let colorRGB: [Float]
    let brightness: Float
    let horizontalAlignment: String
    let verticalAlignment: String
    let padding: Float
    let opaqueBackground: Bool
    let backgroundColorRGB: [Float]
    let backgroundBrightness: Float

    nonisolated static func parse(_ root: [String: Any]) -> SceneTextDescriptor {
        SceneTextDescriptor(
            fontPath: normalizedPath(string(root["font"])),
            pointSize: max(1, number(root["pointsize"]) ?? 32),
            colorRGB: paddedColor(SceneDocumentLoader.floatVector(root["color"]), fill: 1),
            brightness: max(0, number(root["brightness"]) ?? 1),
            horizontalAlignment: string(root["horizontalalign"]) ?? "center",
            verticalAlignment: string(root["verticalalign"]) ?? "center",
            padding: max(0, number(root["padding"]) ?? 0),
            opaqueBackground: bool(root["opaquebackground"]) ?? false,
            backgroundColorRGB: paddedColor(SceneDocumentLoader.floatVector(root["backgroundcolor"]), fill: 0),
            backgroundBrightness: max(0, number(root["backgroundbrightness"]) ?? 1)
        )
    }

    nonisolated private static func unwrapped(_ value: Any?) -> Any? {
        if let keyed = value as? [String: Any] {
            return keyed["value"]
        }
        return value
    }

    nonisolated private static func string(_ value: Any?) -> String? {
        unwrapped(value) as? String
    }

    nonisolated private static func number(_ value: Any?) -> Float? {
        let value = unwrapped(value)
        if let number = value as? NSNumber { return number.floatValue }
        if let string = value as? String { return Float(string) }
        return nil
    }

    nonisolated private static func bool(_ value: Any?) -> Bool? {
        unwrapped(value) as? Bool
    }

    nonisolated private static func normalizedPath(_ value: String?) -> String? {
        guard let value else { return nil }
        let path = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        return path.isEmpty ? nil : path
    }

    nonisolated private static func paddedColor(_ value: [Float]?, fill: Float) -> [Float] {
        var result = Array((value ?? []).prefix(3))
        while result.count < 3 { result.append(fill) }
        return result
    }
}
