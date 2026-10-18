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
        parsedOrigin: [Float]?, nearZ: Double, farZ: Double,
        timelines: [SceneDocument.SceneObjectTimeline] = []
    ) -> Int? {
        guard let id = sourceLayerID,
              case let .object(authored)? = authoredConfiguration,
              let input = authored["origin"],
              let origin = vector(input), let parsedOrigin,
              parsedOrigin.count == 3, origin.count == 3,
              zip(origin, parsedOrigin).allSatisfy({ Float($0.0).bitPattern == $0.1.bitPattern }),
              acceptsOrigin(origin, nearZ: nearZ, farZ: farZ) else { return nil }
        if originInputIsSupported(input) { return id }
        guard let animation = independentAnimation(host: .origin, timelines: timelines,
                authoredConfiguration: authoredConfiguration),
              acceptsOrigin(parsedOrigin, animation: animation, nearZ: nearZ, farZ: farZ)
        else { return nil }
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
           let input = authored["origin"], originInputIsSupported(input),
           let origin = vector(input), origin.count == 3 {
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

    /// An independent field keeps its own clock. Connected or malformed peers
    /// cannot be made standalone by discarding their authored references.
    static func independentAnimation(
        host: SceneDocument.SceneObjectTimeline.Host,
        timelines: [SceneDocument.SceneObjectTimeline],
        authoredConfiguration: SceneJSONValue?
    ) -> SceneTimelineAnimation? {
        guard host == .origin || host == .zoom,
              case let .object(authored)? = authoredConfiguration,
              case let .object(wrapper)? = authored[host.rawValue],
              Set(wrapper.keys).isSubset(of: ["value", "animation", "script", "user"]),
              wrapper["value"] != nil, wrapper["animation"] != nil,
              wrapper["script"] == nil || wrapper["script"] == .null,
              wrapper["user"] == nil || wrapper["user"] == .null else { return nil }
        let matches = timelines.filter { $0.host == host }
        guard matches.count == 1, let animation = matches.first?.animation,
              animation.options.mode == .single,
              animation.options.parent == nil, animation.options.children.isEmpty,
              animation.options.smoothing == nil, animation.options.stiffness == nil,
              animation.componentCount == (host == .origin ? 3 : 1),
              (host == .origin ? animation.isRelative : !animation.isRelative),
              animation.hasExecutableWrapLoop,
              !hasDeclaredIncomingPeer(to: host, authored: authored) else { return nil }
        return animation
    }

    static func hasDeclaredIncomingPeer(
        to target: SceneDocument.SceneObjectTimeline.Host,
        authored: [String: SceneJSONValue],
        excludingHosts: [SceneDocument.SceneObjectTimeline.Host] = []
    ) -> Bool {
        // initialConfiguration preserves declarations whose invalid curves or
        // options have no executable entry in `timelines`.
        SceneDocument.SceneObjectTimeline.Host.allCases.contains { host in
            guard !excludingHosts.contains(host),
                  case let .object(wrapper)? = authored[host.rawValue],
                  case let .object(animation)? = wrapper["animation"],
                  case let .object(options)? = animation["options"] else { return false }
            return SceneTimelineAnimationParser.declaredGroupReferences(
                parent: options["parent"].map(referenceObject),
                children: options["children"].map(referenceObject)
            ).contains { $0.key == target.rawValue }
        }
    }

    /// Adapt only reference payloads to the existing parser; no second options
    /// or curve decoder, whole-document serialization or frame-time lookup.
    private static func referenceObject(_ value: SceneJSONValue) -> Any {
        switch value {
        case .null: NSNull()
        case let .bool(value): value
        case let .number(value): value
        case let .string(value): value
        case let .array(values): values.map(referenceObject)
        case let .object(values): values.mapValues(referenceObject)
        }
    }

    /// The camera compiler and preparation alias use the same consumed-control
    /// bounds. Relative values are checked after adding the authored base.
    static func acceptsOrigin(
        _ authored: [Float], animation: SceneTimelineAnimation,
        nearZ: Double, farZ: Double
    ) -> Bool {
        guard authored.count == 3, animation.componentCount == 3,
              nearZ.isFinite, farZ.isFinite, nearZ >= 0, farZ > nearZ,
              authored.allSatisfy({ $0.isFinite && abs(Double($0)) <= maximumOriginMagnitude })
        else { return false }
        for (index, lane) in animation.lanes.enumerated() {
            let base = Double(authored[index])
            guard animation.consumedControlValues(in: lane).allSatisfy({ control in
                let value = base + control
                let bounded = value.isFinite && abs(value) <= maximumOriginMagnitude
                return index == 2 ? bounded && value > nearZ && value < farZ : bounded
            }) else { return false }
        }
        return true
    }

    static func acceptsZoom(_ authored: Double, animation: SceneTimelineAnimation) -> Bool {
        guard acceptsZoom(authored), animation.componentCount == 1 else { return false }
        return animation.consumedControlValues(in: animation.lanes[0]).allSatisfy(acceptsZoom)
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
