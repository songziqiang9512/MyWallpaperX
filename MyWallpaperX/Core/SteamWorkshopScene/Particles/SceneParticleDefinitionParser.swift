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
        case "alpharandom": kind = .alpha
        case "rotationrandom": kind = .rotation
        case "angularvelocityrandom": kind = .angularVelocity
        case "turbulentvelocityrandom": kind = .turbulentVelocity
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
        return SceneParticleInitializer(
            id: Self.integer(root["id"]), kind: kind,
            minimum: Self.numericValue(root["min"]),
            maximum: Self.numericValue(root["max"]),
            exponent: Self.number(root["exponent"]),
            turbulentVelocity: turbulence
        )
    }

    private nonisolated func parseOperator(
        _ root: [String: Any],
        diagnostics: inout [SceneParticleDiagnostic]
    ) -> SceneParticleOperator {
        let name = Self.componentName(root)
        let kind: SceneParticleOperatorKind
        switch name {
        case "movement": kind = .movement
        case "alphafade": kind = .alphaFade
        case "alphachange": kind = .alphaChange
        case "sizechange": kind = .sizeChange
        case "colorchange": kind = .colorChange
        case "angularmovement": kind = .angularMovement
        case "oscillateposition": kind = .oscillatePosition
        case "oscillatealpha": kind = .oscillateAlpha
        case "oscillatesize": kind = .oscillateSize
        case "controlpointattract": kind = .controlPointAttract
        case "turbulence": kind = .turbulence
        case "boids":
            let scalarFields = [
                "neighborthreshold", "separationfactor", "cohesionfactor", "alignmentfactor"
            ]
            let supportedFields = Set([
                "id", "name", "flags", "neighborthreshold", "separationfactor",
                "cohesionfactor", "alignmentfactor"
            ])
            kind = .boids(.init(
                neighborThreshold: Self.number(root["neighborthreshold"]),
                separationFactor: Self.number(root["separationfactor"]),
                cohesionFactor: Self.number(root["cohesionfactor"]),
                alignmentFactor: Self.number(root["alignmentfactor"]),
                hasMalformedFields: scalarFields.contains {
                    root[$0] != nil && !(root[$0] is NSNull) && Self.number(root[$0]) == nil
                } || (root["flags"] != nil && Self.integer(root["flags"]) == nil),
                unsupportedFieldNames: root.keys.filter { !supportedFields.contains($0) }.sorted()
            ))
        case "vortex": kind = .vortex
        default:
            kind = .unsupported(name)
            diagnostics.append(.init(kind: .unsupportedOperator, path: "operator", componentName: name))
        }
        return SceneParticleOperator(
            id: Self.integer(root["id"]), kind: kind,
            rawFlags: Self.integer(root["flags"]) ?? 0,
            gravity: Self.numericValue(root["gravity"]), drag: Self.number(root["drag"]),
            force: Self.numericValue(root["force"]),
            fadeInTime: Self.number(root["fadeintime"]), fadeOutTime: Self.number(root["fadeouttime"]),
            startTime: Self.number(root["starttime"]), endTime: Self.number(root["endtime"]),
            startValue: Self.numericValue(root["startvalue"]), endValue: Self.numericValue(root["endvalue"]),
            frequencyMinimum: Self.number(root["frequencymin"]),
            frequencyMaximum: Self.number(root["frequencymax"]),
            scaleMinimum: Self.numericValue(root["scalemin"]),
            scaleMaximum: Self.numericValue(root["scalemax"]),
            phaseMinimum: Self.number(root["phasemin"]), phaseMaximum: Self.number(root["phasemax"]),
            mask: Self.numericValue(root["mask"]),
            blendInStart: Self.number(root["blendinstart"]), blendInEnd: Self.number(root["blendinend"]),
            blendOutStart: Self.number(root["blendoutstart"]), blendOutEnd: Self.number(root["blendoutend"]),
            controlPoint: Self.integer(root["controlpoint"]),
            origin: Self.numericValue(root["origin"]), scale: Self.numericValue(root["scale"]),
            timeScale: Self.number(root["timescale"]),
            threshold: Self.number(root["threshold"]),
            speedMinimum: Self.number(root["speedmin"]), speedMaximum: Self.number(root["speedmax"]),
            audioResponse: Self.audioResponse(root)
        )
    }

    /// 粒子 audio response 声明。字段名只取 `audioprocessing*` 一套——effect 侧的
    /// `audiobounds`/`audioamount`/`audioexponent` 属于 shader constant schema，
    /// 45 样本语料中的粒子组件从未出现，早前把它们当作 fallback 会解析出恒为 nil 的
    /// 字段，同时漏掉真实存在的 `audioprocessingfrequencyend`。
    private nonisolated static func audioResponse(
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
        .init(
            id: Self.integer(root["id"]), rawFlags: Self.integer(root["flags"]) ?? 0,
            offset: Self.numericValue(root["offset"]), angles: Self.numericValue(root["angles"]), parentControlPoint: Self.integer(root["parentcontrolpoint"])
        )
    }

    private nonisolated func parseChild(_ root: [String: Any]) -> SceneParticleChild {
        .init(
            id: Self.integer(root["id"]), path: Self.normalizedPath(root["name"] as? String),
            type: Self.trimmed(root["type"] as? String)?.lowercased(),
            maximumCount: Self.integer(root["maxcount"]),
            controlPointStartIndex: Self.integer(root["controlpointstartindex"]),
            probability: Self.number(root["probability"]), origin: Self.numericValue(root["origin"]),
            scale: Self.numericValue(root["scale"]), angles: Self.numericValue(root["angles"]),
            rawFlags: Self.integer(root["flags"]) ?? 0
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

    private nonisolated static func componentName(_ root: [String: Any]) -> String {
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
            hasScript: wrapper?["script"] != nil,
            hasAnimation: wrapper?["animation"] != nil
        )
    }

    private nonisolated static func numericValue(_ rawValue: Any?) -> SceneParticleNumericValue? {
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

    private nonisolated static func number(_ rawValue: Any?) -> Double? {
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
