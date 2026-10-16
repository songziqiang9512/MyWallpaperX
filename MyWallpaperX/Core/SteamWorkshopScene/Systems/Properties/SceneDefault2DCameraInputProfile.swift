import Foundation

/// Preparation-only admission for the existing default 2D camera targets.
/// The selected authored layer remains the script/handle identity; it does
/// not become a second camera value store or a second render-time selector.
nonisolated enum SceneDefault2DCameraInputProfile {
    static let maximumOriginMagnitude = 10_000_000.0
    static func sourceLayerID(
        orthoWidth: Float?, orthoHeight: Float?,
        paths: [(id: Int, path: SceneDocument.Scene2DCameraPathDefinition?)],
        authoredConfigurations: [Int: SceneJSONValue]
    ) -> Int? {
        guard let width = orthoWidth, let height = orthoHeight,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let candidates = paths.filter { $0.path != nil }
        guard candidates.count == 1, let candidate = candidates.first,
              candidate.id >= 0, let path = candidate.path,
              path.camera.lowercased() == "default",
              path.queueMode == nil || path.queueMode == "random"
                || path.queueMode == "sequential" else { return nil }
        let markedIDs = Set(authoredConfigurations.compactMap { id, value -> Int? in
            guard case let .object(object) = value, object["camera"] != nil else { return nil }
            return id
        })
        guard markedIDs == [candidate.id],
              case let .object(authored)? = authoredConfigurations[candidate.id],
              staticString(authored["camera"])?.lowercased() == "default",
              staticString(authored["path"]) == path.path,
              authored["queuemode"] == nil || staticString(authored["queuemode"]) != nil
        else { return nil }
        return candidate.id
    }

    static func acceptsOrigin(_ values: [Double], nearZ: Double, farZ: Double) -> Bool {
        values.count == 3 && nearZ.isFinite && farZ.isFinite
            && nearZ >= 0 && farZ > nearZ
            && values.allSatisfy({ $0.isFinite && abs($0) <= maximumOriginMagnitude })
            && values[2] > nearZ && values[2] < farZ
    }

    static func acceptsZoom(_ value: Double) -> Bool {
        value.isFinite && SceneDynamicCameraField.zoom.userPropertyScalarRange?.contains(value) == true
    }

    static func originSourceLayerID(
        sourceLayerID: Int?, authoredConfiguration: SceneJSONValue?,
        parsedOrigin: [Float]?, nearZ: Double, farZ: Double
    ) -> Int? {
        guard let id = sourceLayerID,
              case let .object(authored)? = authoredConfiguration,
              let input = authored["origin"], originInputIsSupported(input),
              let origin = vector(input), let parsedOrigin,
              parsedOrigin.count == 3, origin.count == 3,
              zip(origin, parsedOrigin).allSatisfy({ Float($0.0).bitPattern == $0.1.bitPattern }),
              acceptsOrigin(origin, nearZ: nearZ, farZ: farZ) else { return nil }
        return id
    }

    static func definitions(
        descriptor: SceneRenderDescriptor,
        timelineTargets: Set<SceneDynamicTarget>
    ) -> [SceneDynamicTargetDefinition] {
        guard let id = descriptor.camera.default2DInputLayerID,
              let layer = descriptor.layers.first(where: { $0.id == id }),
              case let .object(authored)? = layer.initialConfiguration else { return [] }
        var definitions: [SceneDynamicTargetDefinition] = []
        if descriptor.camera.default2DOriginInputLayerID == id,
           !timelineTargets.contains(.camera(.origin)),
           let input = authored["origin"], let origin = vector(input), origin.count == 3 {
            definitions.append(.init(target: .camera(.origin), valueType: .vector3,
                authoredValue: .vector3(origin[0], origin[1], origin[2])))
        }
        if !timelineTargets.contains(.camera(.zoom)),
           let input = authored["zoom"], zoomInputIsSupported(input),
           let zoom = scalar(input), acceptsZoom(zoom) {
            definitions.append(.init(target: .camera(.zoom), valueType: .scalar,
                authoredValue: .scalar(zoom)))
        }
        return definitions
    }

    static func originInputIsSupported(_ value: SceneJSONValue) -> Bool {
        guard case let .object(wrapper) = value else { return true }
        guard wrapper["animation"] == nil,
              wrapper["user"] == nil || wrapper["user"] == .null else { return false }
        let keys = Set(wrapper.keys)
        return keys.isSubset(of: ["value", "script", "scriptproperties", "user"])
            && wrapper["value"] != nil
            && (wrapper["script"] == nil || wrapper["script"]?.stringValue != nil)
    }

    private static func zoomInputIsSupported(_ value: SceneJSONValue) -> Bool {
        guard case let .object(wrapper) = value else { return true }
        return Set(wrapper.keys).isSubset(of: ["user", "value"])
            && wrapper["value"] != nil
    }

    private static func scalar(_ value: SceneJSONValue) -> Double? {
        if case let .object(wrapper) = value, let value = wrapper["value"] { return scalar(value) }
        return value.numberValue
    }

    private static func staticString(_ value: SceneJSONValue?) -> String? {
        if case let .object(wrapper)? = value {
            guard Set(wrapper.keys) == ["value"] else { return nil }
            return staticString(wrapper["value"])
        }
        return value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func vector(_ value: SceneJSONValue) -> [Double]? {
        if case let .object(wrapper) = value, let value = wrapper["value"] { return vector(value) }
        if case let .array(values) = value {
            let numbers = values.compactMap(\.numberValue)
            return numbers.count == values.count ? numbers : nil
        }
        guard let string = value.stringValue else { return nil }
        let parts = string.split(whereSeparator: { $0.isWhitespace || $0 == "," })
        let numbers = parts.compactMap { Double($0) }
        return numbers.count == parts.count ? numbers : nil
    }
}
