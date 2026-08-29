import Foundation

nonisolated struct SceneParticleDefinitionParser {
    nonisolated enum ParseError: Error {
        case invalidJSON
    }

    nonisolated func parse(data: Data) throws -> SceneParticleDefinition {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        return parse(root: root)
    }

    nonisolated func parse(root: [String: Any]) -> SceneParticleDefinition {
        var diagnostics: [SceneParticleDiagnostic] = []
        if Self.normalizedPath(root["material"] as? String) == nil {
            diagnostics.append(.init(kind: .missingRequiredField, path: "material", componentName: nil))
        }
        let emitters = parseComponents(root["emitter"], section: "emitter", diagnostics: &diagnostics) {
            parseEmitter($0, diagnostics: &$1)
        }
        if emitters.isEmpty {
            diagnostics.append(.init(kind: .missingRequiredField, path: "emitter", componentName: nil))
        }
        let initializers = parseComponents(
            root["initializer"], section: "initializer", diagnostics: &diagnostics
        ) { parseInitializer($0, diagnostics: &$1) }
        let operators = parseComponents(
            root["operator"], section: "operator", diagnostics: &diagnostics
        ) { parseOperator($0, diagnostics: &$1) }
        let rendererWasImplicit = root["renderer"] == nil
        var renderers = parseComponents(
            root["renderer"], section: "renderer", diagnostics: &diagnostics
        ) { parseRenderer($0, diagnostics: &$1) }
        if rendererWasImplicit {
            renderers = [.init(
                id: nil, kind: .sprite, orientation: nil, axis: nil, rawFlags: 0,
                length: nil, minimumLength: nil, maximumLength: nil, segments: nil,
                subdivision: nil, fadesAlpha: nil, fadesSize: nil,
                uvScale: nil, smoothsUV: nil, scrollsUV: nil, hasMalformedFields: false, unsupportedFieldNames: []
            )]
        }

        return SceneParticleDefinition(
            materialPath: Self.normalizedPath(root["material"] as? String),
            maximumCount: Self.integer(root["maxcount"]),
            startTime: Self.number(root["starttime"]),
            flags: .init(rawValue: Self.integer(root["flags"]) ?? 0),
            animationMode: Self.trimmed(root["animationmode"] as? String)?.lowercased(),
            sequenceMultiplier: Self.number(root["sequencemultiplier"]),
            emitters: emitters,
            initializers: initializers,
            operators: operators,
            renderers: renderers,
            rendererWasImplicit: rendererWasImplicit,
            controlPoints: Self.componentRoots(root["controlpoint"]).map(parseControlPoint),
            children: Self.componentRoots(root["children"]).map(parseChild),
            diagnostics: diagnostics
        )
    }

    private nonisolated func parseEmitter(
        _ root: [String: Any],
        diagnostics: inout [SceneParticleDiagnostic]
    ) -> SceneParticleEmitter {
        let name = Self.componentName(root)
        let kind: SceneParticleEmitterKind
        switch name {
        case "sphererandom": kind = .sphereRandom
        case "boxrandom": kind = .boxRandom
        case "layerimage": kind = .layerImage
        default:
            kind = .unsupported(name)
            diagnostics.append(.init(kind: .unsupportedEmitter, path: "emitter", componentName: name))
        }
        return SceneParticleEmitter(
            id: Self.integer(root["id"]), kind: kind,
            origin: Self.numericValue(root["origin"]),
            directions: Self.numericValue(root["directions"]),
            sign: Self.numericValue(root["sign"]),
            distanceMinimum: Self.numericValue(root["distancemin"]),
            distanceMaximum: Self.numericValue(root["distancemax"]),
            rate: Self.number(root["rate"]),
            instantaneousCount: Self.integer(root["instantaneous"]),
            speedMinimum: Self.number(root["speedmin"]),
            speedMaximum: Self.number(root["speedmax"]),
            duration: Self.number(root["duration"]),
            controlPoint: Self.integer(root["controlpoint"]),
            audioResponse: Self.audioResponse(root), periodicEmission: .init(root: root),
            hasMalformedDirectionsOrSign: ["directions", "sign"].contains { root[$0] != nil && !(root[$0] is NSNull) && Self.numericValue(root[$0]) == nil },
            rawFlags: Self.integer(root["flags"]) ?? 0
        )
    }
    private nonisolated func parseInitializer(
        _ root: [String: Any],
        diagnostics: inout [SceneParticleDiagnostic]
    ) -> SceneParticleInitializer {
        let name = Self.componentName(root)
        let kind: SceneParticleInitializerKind
        switch name {
        case "lifetimerandom": kind = .lifetime
        case "sizerandom": kind = .size
        case "velocityrandom": kind = .velocity
        case "colorrandom": kind = .color
        case "hsvcolorrandom": kind = .hsvColor
        case "colorlist": kind = .colorList
        case "alpharandom": kind = .alpha
        case "rotationrandom": kind = .rotation
        case "angularvelocityrandom": kind = .angularVelocity
        case "turbulentvelocityrandom": kind = .turbulentVelocity
        case "positionoffsetrandom": kind = .positionOffset
        case "mapsequencearoundcontrolpoint":
            kind = .positionAroundControlPoint(.init(root: root))
        case "inheritinitialvaluefromevent":
            kind = .inheritEventColor(.init(root: root))
        default:
            kind = .unsupported(name)
            diagnostics.append(.init(kind: .unsupportedInitializer, path: "initializer", componentName: name))
        }
        let turbulence: SceneParticleTurbulentVelocity? = kind == .turbulentVelocity ? .init(
            forward: Self.numericValue(root["forward"]),
            right: Self.numericValue(root["right"]),
            up: Self.numericValue(root["up"]),
            offset: Self.number(root["offset"]),
            phaseMinimum: Self.number(root["phasemin"]),
            phaseMaximum: Self.number(root["phasemax"]),
            scale: Self.number(root["scale"]),
            speedMinimum: Self.number(root["speedmin"]),
            speedMaximum: Self.number(root["speedmax"]),
            timeScale: Self.number(root["timescale"]),
            audioResponse: Self.audioResponse(root)
        ) : nil
        let positionOffset: SceneParticlePositionOffset? = kind == .positionOffset ? .init(
            directions: Self.numericValue(root["directions"]),
            distance: Self.number(root["distance"]),
            octaves: Self.integer(root["octaves"]),
            scale: Self.number(root["scale"]),
            timeScale: Self.number(root["timescale"]),
            hasMalformedFields: Self.hasMalformedPositionOffsetFields(root),
            unsupportedFieldNames: Self.unsupportedPositionOffsetFieldNames(root)
        ) : nil
        let rawColors = root["colors"] as? [Any]
        let colors = rawColors?.compactMap(Self.numericValue)
        let hasMalformedColorList = kind == .colorList && (
            rawColors == nil || colors?.count != rawColors?.count
                || root.keys.contains { !["id", "name", "colors"].contains($0) }
        )
        return SceneParticleInitializer(
            id: Self.integer(root["id"]), kind: kind,
            minimum: Self.numericValue(root["min"]),
            maximum: Self.numericValue(root["max"]),
            exponent: Self.number(root["exponent"]),
            hsvColor: kind == .hsvColor ? .init(root: root) : nil,
            turbulentVelocity: turbulence, positionOffset: positionOffset, colors: colors,
            hasMalformedColorList: hasMalformedColorList
        )
    }

    private nonisolated static func unsupportedPositionOffsetFieldNames(
        _ root: [String: Any]
    ) -> [String] {
        let supported = Set([
            "id", "name", "directions", "distance", "octaves", "scale", "timescale"
        ])
        return root.keys.filter { !supported.contains($0) }.sorted()
    }

    private nonisolated static func hasMalformedPositionOffsetFields(
        _ root: [String: Any]
    ) -> Bool {
        func malformed(_ key: String, parsed: Any?) -> Bool {
            root[key] != nil && parsed == nil
        }
        return malformed("directions", parsed: numericValue(root["directions"]))
            || malformed("distance", parsed: number(root["distance"]))
            || malformed("octaves", parsed: integer(root["octaves"]))
            || malformed("scale", parsed: number(root["scale"]))
            || malformed("timescale", parsed: number(root["timescale"]))
    }

    /// 粒子 audio response 声明。字段名只取 `audioprocessing*` 一套——effect 侧的
    /// `audiobounds`/`audioamount`/`audioexponent` 属于 shader constant schema，
    /// 45 样本语料中的粒子组件从未出现，早前把它们当作 fallback 会解析出恒为 nil 的
    /// 字段，同时漏掉真实存在的 `audioprocessingfrequencyend`。
    nonisolated static func audioResponse(
        _ root: [String: Any]
    ) -> SceneParticleAudioResponse {
        SceneParticleAudioResponse(
            mode: Self.integer(root["audioprocessingmode"]),
            bounds: Self.numericValue(root["audioprocessingbounds"]),
            exponent: Self.number(root["audioprocessingexponent"]),
            frequencyStart: Self.integer(root["audioprocessingfrequencystart"]),
            frequencyEnd: Self.integer(root["audioprocessingfrequencyend"])
        )
    }

    private nonisolated func parseRenderer(
        _ root: [String: Any],
        diagnostics: inout [SceneParticleDiagnostic]
    ) -> SceneParticleRenderer {
        let name = Self.componentName(root)
        let kind: SceneParticleRendererKind
        switch name {
        case "sprite": kind = .sprite
        case "spritetrail": kind = .spriteTrail
        case "rope": kind = .rope
        case "ropetrail": kind = .ropeTrail
        default:
            kind = .unsupported(name)
            diagnostics.append(.init(kind: .unsupportedRenderer, path: "renderer", componentName: name))
        }
        let hasMalformedFields = Self.hasMalformedRendererFields(root)
        if hasMalformedFields {
            diagnostics.append(.init(
                kind: .malformedComponent, path: "renderer", componentName: name
            ))
        }
        return SceneParticleRenderer(
            id: Self.integer(root["id"]), kind: kind,
            orientation: Self.trimmed(root["orientation"] as? String)?.lowercased(),
            axis: Self.numericValue(root["axis"]), rawFlags: Self.integer(root["flags"]) ?? 0,
            length: Self.number(root["length"]), minimumLength: Self.number(root["minlength"]),
            maximumLength: Self.number(root["maxlength"]), segments: Self.integer(root["segments"]),
            subdivision: Self.number(root["subdivision"]),
            fadesAlpha: Self.boolean(root["fadealpha"]),
            fadesSize: Self.boolean(root["fadesize"]),
            uvScale: Self.number(root["uvscale"]),
            smoothsUV: Self.boolean(root["uvsmoothing"]),
            scrollsUV: Self.boolean(root["uvscrolling"]),
            hasMalformedFields: hasMalformedFields,
            unsupportedFieldNames: Self.unsupportedRendererFieldNames(root)
        )
    }

    private nonisolated static func unsupportedRendererFieldNames(_ root: [String: Any]) -> [String] {
        let supported = Set([
            "id", "name", "orientation", "axis", "flags",
            "length", "minlength", "maxlength", "segments", "subdivision",
            "fadealpha", "fadesize", "uvscale", "uvsmoothing", "uvscrolling"
        ])
        return root.keys.filter { !supported.contains($0) }.sorted()
    }

    private nonisolated static func hasMalformedRendererFields(_ root: [String: Any]) -> Bool {
        func authored(_ key: String) -> Bool {
            root[key] != nil && !(root[key] is NSNull)
        }
        let scalarFields = ["length", "minlength", "maxlength", "subdivision", "uvscale"]
        let integerFields = ["flags", "segments"]
        let booleanFields = ["fadealpha", "fadesize", "uvsmoothing", "uvscrolling"]
        return (authored("orientation") && trimmed(root["orientation"] as? String) == nil)
            || (authored("axis") && numericValue(root["axis"]) == nil)
            || scalarFields.contains { authored($0) && number(root[$0]) == nil }
            || integerFields.contains { authored($0) && integer(root[$0]) == nil }
            || booleanFields.contains { authored($0) && boolean(root[$0]) == nil }
    }

    private nonisolated func parseControlPoint(_ root: [String: Any]) -> SceneParticleControlPoint {
        func malformed(_ key: String, parsed: Any?) -> Bool {
            root[key] != nil && !(root[key] is NSNull) && parsed == nil
        }
        let id = Self.integer(root["id"])
        let flags = Self.integer(root["flags"])
        let offset = Self.numericValue(root["offset"])
        let angles = Self.numericValue(root["angles"])
        let parent = Self.integer(root["parentcontrolpoint"])
        return .init(
            id: id, rawFlags: flags ?? 0, offset: offset, angles: angles,
            parentControlPoint: parent,
            hasAuthoredAngles: root["angles"] != nil && !(root["angles"] is NSNull),
            hasMalformedFields: malformed("id", parsed: id)
                || malformed("flags", parsed: flags)
                || malformed("offset", parsed: offset)
                || malformed("angles", parsed: angles)
                || malformed("parentcontrolpoint", parsed: parent)
        )
    }

    private nonisolated func parseChild(_ root: [String: Any]) -> SceneParticleChild {
        let origin = Self.numericValue(root["origin"])
        let scale = Self.numericValue(root["scale"])
        let angles = Self.numericValue(root["angles"])
        let hasMalformedTransformFields = [
            ("origin", origin), ("scale", scale), ("angles", angles),
        ].contains { key, parsed in
            root[key] != nil && !(root[key] is NSNull) && parsed == nil
        }
        return .init(
            id: Self.integer(root["id"]), path: Self.normalizedPath(root["name"] as? String),
            type: Self.trimmed(root["type"] as? String)?.lowercased(),
            maximumCount: Self.integer(root["maxcount"]),
            controlPointStartIndex: Self.integer(root["controlpointstartindex"]),
            probability: Self.number(root["probability"]), origin: origin,
            scale: scale, angles: angles,
            rawFlags: Self.integer(root["flags"]) ?? 0,
            hasMalformedTransformFields: hasMalformedTransformFields
        )
    }

    private nonisolated func parseComponents<T>(
        _ rawValue: Any?,
        section: String,
        diagnostics: inout [SceneParticleDiagnostic],
        transform: ([String: Any], inout [SceneParticleDiagnostic]) -> T
    ) -> [T] {
        guard rawValue != nil else { return [] }
        guard let values = rawValue as? [Any] else {
            diagnostics.append(.init(kind: .malformedComponent, path: section, componentName: nil))
            return []
        }
        return values.enumerated().compactMap { index, value in
            guard let root = value as? [String: Any] else {
                diagnostics.append(.init(
                    kind: .malformedComponent, path: "\(section)[\(index)]", componentName: nil
                ))
                return nil
            }
            return transform(root, &diagnostics)
        }
    }

    private nonisolated static func componentRoots(_ rawValue: Any?) -> [[String: Any]] {
        (rawValue as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }

    nonisolated static func componentName(_ root: [String: Any]) -> String {
        trimmed(root["name"] as? String)?.lowercased() ?? ""
    }

    nonisolated static func boundValue(_ rawValue: Any?) -> SceneParticleBoundValue? {
        guard rawValue != nil, !(rawValue is NSNull) else { return nil }
        let wrapper = rawValue as? [String: Any]
        let userValue = wrapper?["user"]
        let userKey: String? = {
            if let value = userValue as? String { return trimmed(value) }
            if let value = userValue as? [String: Any] { return trimmed(value["name"] as? String) }
            return nil
        }()
        return .init(
            value: numericValue(wrapper?["value"] ?? rawValue),
            userPropertyKey: userKey,
            hasScript: wrapper?["script"].map { !($0 is NSNull) } ?? false,
            hasAnimation: wrapper?["animation"].map { !($0 is NSNull) } ?? false
        )
    }

    nonisolated static func numericValue(_ rawValue: Any?) -> SceneParticleNumericValue? {
        if let wrapper = rawValue as? [String: Any], let value = wrapper["value"] {
            return numericValue(value)
        }
        if let number = rawValue as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return .scalar(number.doubleValue)
        }
        if let value = rawValue as? String {
            let parts = value.split { $0 == " " || $0 == "," || $0 == "\t" }
            let numbers = parts.compactMap(Double.init)
            guard numbers.count == parts.count else { return nil }
            if numbers.count == 1 { return .scalar(numbers[0]) }
            if numbers.count > 1 { return .vector(numbers) }
            return nil
        }
        if let values = rawValue as? [Any] {
            let numbers = values.compactMap { number($0) }
            if numbers.count == 1 { return .scalar(numbers[0]) }
            if numbers.count > 1, numbers.count == values.count { return .vector(numbers) }
        }
        return nil
    }

    nonisolated static func number(_ rawValue: Any?) -> Double? {
        numericValue(rawValue)?.scalarValue
    }

    nonisolated static func integer(_ rawValue: Any?) -> Int? {
        guard let value = number(rawValue), value.isFinite else { return nil }
        return Int(exactly: value)
    }

    private nonisolated static func boolean(_ rawValue: Any?) -> Bool? {
        guard let value = rawValue as? NSNumber else { return nil }
        return CFGetTypeID(value) == CFBooleanGetTypeID() ? value.boolValue : nil
    }

    private nonisolated static func normalizedPath(_ rawValue: String?) -> String? {
        guard var value = trimmed(rawValue)?.replacingOccurrences(of: "\\", with: "/") else { return nil }
        while value.hasPrefix("./") { value.removeFirst(2) }
        return value.lowercased()
    }
    private nonisolated static func trimmed(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
