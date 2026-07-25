import Foundation

struct ScenePuppetAnimationLayer: Codable, Equatable {
    let id: Int?
    let animationID: Int?
    let name: String?
    let additive: Bool?
    let blend: Double?
    let blendIn: Bool?
    let blendOut: Bool?
    let blendTime: Double?
    let rate: Double?
    let visible: Bool?
    let visibilityBinding: String?

    nonisolated static func parse(_ value: Any?) -> [ScenePuppetAnimationLayer] {
        (value as? [[String: Any]] ?? []).map { root in
            let visibleWrapper = root["visible"] as? [String: Any]
            return ScenePuppetAnimationLayer(
                id: root["id"] as? Int,
                animationID: root["animation"] as? Int,
                name: root["name"] as? String,
                additive: boolValue(root["additive"]),
                blend: doubleValue(root["blend"]),
                blendIn: boolValue(root["blendin"]),
                blendOut: boolValue(root["blendout"]),
                blendTime: doubleValue(root["blendtime"]),
                rate: doubleValue(root["rate"]),
                visible: boolValue(root["visible"]),
                visibilityBinding: visibleWrapper?["user"] as? String
            )
        }
    }

    nonisolated private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        return (value as? [String: Any])?["value"] as? Bool
    }

    nonisolated private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        guard let wrappedValue = (value as? [String: Any])?["value"] else { return nil }
        if let wrappedValue = wrappedValue as? Double { return wrappedValue }
        if let wrappedValue = wrappedValue as? Int { return Double(wrappedValue) }
        return nil
    }
}
