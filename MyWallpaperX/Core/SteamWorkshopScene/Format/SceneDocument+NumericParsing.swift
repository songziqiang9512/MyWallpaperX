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
            let values = parts.compactMap { Float($0) }
            return values.count == parts.count && !values.isEmpty ? values : nil
        }
        return nil
    }

    nonisolated static func floatValue(_ value: Any?) -> Float? {
        if let float = value as? Float { return float }
        if let double = value as? Double { return Float(double) }
        if let integer = value as? Int { return Float(integer) }
        if let string = value as? String { return Float(string) }
        if let keyed = value as? [String: Any] { return floatValue(keyed["value"]) }
        return nil
    }
}
