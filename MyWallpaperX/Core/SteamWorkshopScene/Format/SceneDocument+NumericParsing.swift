import Foundation

extension SceneDocumentLoader {
    /// Parses Wallpaper Engine vector strings ("x y z" or "x y") and JSON arrays.
    nonisolated static func floatVector(_ value: Any?) -> [Float]? {
        if let array = value as? [Any] {
            let values = array.compactMap(Self.floatValue)
            return values.isEmpty ? nil : values
        }
        if let keyed = value as? [String: Any], let inner = keyed["value"] {
            return floatVector(inner)
        }
        if let string = value as? String {
            let parts = string.split { $0 == " " || $0 == "," || $0 == "\t" }
            let values = parts.compactMap { Double($0).map(Self.saturatingFloat) }
            return values.count == parts.count && !values.isEmpty ? values : nil
        }
        return nil
    }

    nonisolated static func floatValue(_ value: Any?) -> Float? {
        if let float = value as? Float { return float }
        if let double = value as? Double { return saturatingFloat(double) }
        if let integer = value as? Int { return saturatingFloat(Double(integer)) }
        if let string = value as? String {
            return Double(string).map(saturatingFloat)
        }
        if let keyed = value as? [String: Any] { return floatValue(keyed["value"]) }
        return nil
    }

    /// Authored numbers are narrowed to the renderer's Float ABI. A finite
    /// Double outside that range used to become `inf` here and fail a shared
    /// consumer at a much wider radius (world transform, camera, script
    /// owner construction), so the narrowing saturates to the representable
    /// limit and keeps the authored magnitude ordering. Genuinely non-finite
    /// inputs keep their meaning; JSON cannot carry them anyway.
    nonisolated static func saturatingFloat(_ value: Double) -> Float {
        guard value.isFinite else { return Float(value) }
        if value > Double(Float.greatestFiniteMagnitude) {
            return .greatestFiniteMagnitude
        }
        if value < -Double(Float.greatestFiniteMagnitude) {
            return -.greatestFiniteMagnitude
        }
        return Float(value)
    }
}
