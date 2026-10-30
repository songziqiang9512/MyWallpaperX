import Foundation

nonisolated struct ScenePuppetAnimationLayer: Codable, Equatable {
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
    var visibilityBinding: String?
    // Optional for decoding older prepared descriptors; only true adds a script owner.
    var hasVisibilityScript: Bool? = nil
    var rateBinding: String? = nil
    var hasRateScript: Bool? = nil
    // Preparation provenance, never inferred from raw author keys. Missing in
    // older descriptors and on legacy String/script visibility inputs.
    var hasPreparedVisibilityProperty: Bool? = nil
    var rateTimeline: SceneTimelineAnimation? = nil
    var blendTimeline: SceneTimelineAnimation? = nil
    var parameterTimelineDiagnostics: [String]? = nil

    nonisolated static func parse(_ value: Any?) -> [ScenePuppetAnimationLayer] {
        (value as? [[String: Any]] ?? []).map { root in
            let visibleWrapper = root["visible"] as? [String: Any]
            let rateWrapper = root["rate"] as? [String: Any]
            let rateTimeline = parameterTimeline(root["rate"], field: "rate")
            let blendTimeline = parameterTimeline(root["blend"], field: "blend")
            var layer = ScenePuppetAnimationLayer(
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
                visibilityBinding: visibleWrapper?["user"] as? String,
                hasVisibilityScript: visibleWrapper?["script"] is String ? true : nil,
                rateBinding: rateWrapper?["user"] as? String,
                hasRateScript: rateWrapper?["script"] is String ? true : nil
            )
            layer.rateTimeline = rateTimeline.animation
            layer.blendTimeline = blendTimeline.animation
            let diagnostics = rateTimeline.diagnostics + blendTimeline.diagnostics
            layer.parameterTimelineDiagnostics = diagnostics.isEmpty ? nil : diagnostics
            return layer
        }
    }

    private static func parameterTimeline(_ value: Any?, field: String)
        -> (animation: SceneTimelineAnimation?, diagnostics: [String]) {
        let parsed = SceneTimelineAnimationParser.parse(host: value)
        var diagnostics = parsed.diagnostics.map { "\(field):\($0.token)" }
        if let wrapper = value as? [String: Any], wrapper["animation"] != nil,
           wrapper["script"] is String || wrapper["user"] is String {
            diagnostics.append("\(field):unsupportedSourceCombination")
            return (nil, diagnostics)
        }
        return (parsed.animation, diagnostics)
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
