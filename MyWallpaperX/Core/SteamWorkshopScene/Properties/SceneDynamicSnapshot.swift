import Foundation

nonisolated enum SceneDynamicValueType: String, Codable, Equatable, Hashable, Sendable {
    case bool
    case scalar
    case vector2
    case vector3
    case vector4
    case string
}

nonisolated enum SceneDynamicValue: Codable, Equatable, Hashable, Sendable {
    case bool(Bool)
    case scalar(Double)
    case vector2(Double, Double)
    case vector3(Double, Double, Double)
    case vector4(Double, Double, Double, Double)
    case string(String)

    nonisolated var valueType: SceneDynamicValueType {
        switch self {
        case .bool: .bool
        case .scalar: .scalar
        case .vector2: .vector2
        case .vector3: .vector3
        case .vector4: .vector4
        case .string: .string
        }
    }

    nonisolated var isFinite: Bool {
        switch self {
        case .bool, .string:
            true
        case let .scalar(value):
            value.isFinite
        case let .vector2(x, y):
            x.isFinite && y.isFinite
        case let .vector3(x, y, z):
            x.isFinite && y.isFinite && z.isFinite
        case let .vector4(x, y, z, w):
            x.isFinite && y.isFinite && z.isFinite && w.isFinite
        }
    }
}

/// Launch-scoped typed publication fact for one direct user-property target.
/// Compiler owner transfer consumes the same identity and value type that the
/// runtime binding program will publish; it is not a second property registry.
nonisolated struct SceneDynamicUserPropertyProducer: Hashable, Sendable {
    let propertyKey: String
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType?

    nonisolated init(
        propertyKey: String,
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType? = nil
    ) {
        self.propertyKey = propertyKey
        self.target = target
        self.valueType = valueType
    }
}

nonisolated enum SceneDynamicCameraField: String, Codable, Equatable, Hashable, Sendable {
    case origin
    case zoom
    case parallaxEnabled
    case parallaxAmount
    case parallaxDelay
    case parallaxMouseInfluence
}

nonisolated enum SceneDynamicSceneField: String, Codable, Equatable, Hashable, Sendable {
    case bloomEnabled
    case bloomThreshold
}

nonisolated enum SceneDynamicLayerField: String, Codable, Equatable, Hashable, Sendable {
    case visibility
    case alpha
    case origin
    case size
    case scale
    case angles
    case color
    case volume
}

nonisolated enum SceneDynamicTextField: String, Codable, Equatable, Hashable, Sendable {
    case content
    case pointSize
    case color
    case maxWidth
}

nonisolated enum SceneDynamicParticleField: Codable, Equatable, Hashable, Sendable {
    case alpha
    case size
    case lifetime
    case rate
    case speed
    case count
    case brightness
    case color
    case normalizedColor
    case controlPoint(Int)
    case controlPointAngles(Int)

    fileprivate nonisolated var sortKey: String {
        switch self {
        case .alpha: "alpha"
        case .size: "size"
        case .lifetime: "lifetime"
        case .rate: "rate"
        case .speed: "speed"
        case .count: "count"
        case .brightness: "brightness"
        case .color: "color"
        case .normalizedColor: "normalizedColor"
        case let .controlPoint(index): "controlPoint:\(index)"
        case let .controlPointAngles(index): "controlPointAngles:\(index)"
        }
    }
}

nonisolated enum SceneDynamicTarget: Codable, Equatable, Hashable, Sendable {
    case scene(SceneDynamicSceneField)
    case camera(SceneDynamicCameraField)
    case layer(layerID: Int, field: SceneDynamicLayerField)
    case effectVisibility(layerID: Int, effectIndex: Int)
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
    case materialConstant(layerID: Int, passIndex: Int, name: String)
    case text(layerID: Int, field: SceneDynamicTextField)
    case particle(layerID: Int, field: SceneDynamicParticleField)
    case scriptInstanceProperty(layerID: Int, path: [String])

    fileprivate nonisolated var sortKey: String {
        switch self {
        case let .scene(field):
            "scene:\(field.rawValue)"
        case let .camera(field):
            "camera:\(field.rawValue)"
        case let .layer(layerID, field):
            "layer:\(layerID):\(field.rawValue)"
        case let .effectVisibility(layerID, effectIndex):
            "layer:\(layerID):effect:\(effectIndex):visible"
        case let .effectConstant(layerID, effectIndex, passIndex, name):
            "layer:\(layerID):effect:\(effectIndex):pass:\(passIndex):\(name)"
        case let .materialConstant(layerID, passIndex, name):
            "layer:\(layerID):material:pass:\(passIndex):\(name)"
        case let .text(layerID, field):
            "layer:\(layerID):text:\(field.rawValue)"
        case let .particle(layerID, field):
            "layer:\(layerID):particle:\(field.sortKey)"
        case let .scriptInstanceProperty(layerID, path):
            "layer:\(layerID):script:\(path.map(Self.sortComponent).joined())"
        }
    }

    private nonisolated static func sortComponent(_ value: String) -> String {
        "\(value.utf8.count)#\(value)"
    }
}

nonisolated enum SceneDynamicSource: String, Codable, Equatable, Hashable, Sendable {
    case authored
    case userProperty
    case timeline
    case sceneScript

    fileprivate nonisolated var priority: Int {
        switch self {
        case .authored: 0
        case .userProperty: 1
        case .timeline: 2
        case .sceneScript: 3
        }
    }
}

nonisolated struct SceneDynamicTargetDefinition: Codable, Equatable, Hashable, Sendable {
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType
    let authoredValue: SceneDynamicValue
    /// The authored UI domain of a direct scalar user-property producer.
    /// This is producer metadata, not a shader annotation: a material may
    /// intentionally expose a wider user range than its editor-time constant.
    let userPropertyNumericRange: ClosedRange<Double>?

    nonisolated init(
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType,
        authoredValue: SceneDynamicValue,
        userPropertyNumericRange: ClosedRange<Double>? = nil
    ) {
        self.target = target
        self.valueType = valueType
        self.authoredValue = authoredValue
        self.userPropertyNumericRange = userPropertyNumericRange
    }

    nonisolated func acceptsUserPropertyValue(_ value: SceneDynamicValue) -> Bool {
        guard let userPropertyNumericRange else { return true }
        guard case let .scalar(component) = value else { return false }
        return component.isFinite && userPropertyNumericRange.contains(component)
    }
}

nonisolated struct SceneDynamicResolvedValue: Equatable, Hashable, Sendable {
    let value: SceneDynamicValue
    let source: SceneDynamicSource
}

nonisolated struct SceneDynamicParticleValues: Equatable, Sendable {
    let alpha: Double?
    let size: Double?
    let lifetime: Double?
    let rate: Double?
    let speed: Double?
    let count: Double?
    let brightness: Double?
    let normalizedColor: SIMD3<Double>?
}

nonisolated struct SceneDynamicSnapshot: Equatable, Sendable {
    let frameIndex: UInt64
    let generation: UInt64
    private let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    private let authoredValues: [SceneDynamicTarget: SceneDynamicValue]
    private let userPropertyNumericRanges:
        [SceneDynamicTarget: ClosedRange<Double>]

    nonisolated var count: Int { values.count }

    nonisolated subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? {
        values[target]
    }

    nonisolated func authoredValue(for target: SceneDynamicTarget) -> SceneDynamicValue? {
        authoredValues[target]
    }

    nonisolated func userPropertyNumericRange(
        for target: SceneDynamicTarget
    ) -> ClosedRange<Double>? {
        userPropertyNumericRanges[target]
    }

    nonisolated func particleControlPoints(layerID: Int) -> [Int: SIMD3<Double>] {
        var result: [Int: SIMD3<Double>] = [:]
        for index in 0 ..< 8 {
            guard let resolved = self[.particle(layerID: layerID, field: .controlPoint(index))],
                  case let .vector3(x, y, z) = resolved.value,
                  x.isFinite, y.isFinite, z.isFinite else { continue }
            result[index] = SIMD3(x, y, z)
        }
        return result
    }
    nonisolated func particleInstanceValues(layerID: Int) -> SceneDynamicParticleValues? {
        func scalar(_ field: SceneDynamicParticleField) -> Double? {
            guard let resolved = self[.particle(layerID: layerID, field: field)],
                  case let .scalar(value) = resolved.value else { return nil }
            return value
        }
        let color: SIMD3<Double>? = {
            guard let value = self[.particle(layerID: layerID, field: .normalizedColor)],
                  case let .vector3(x, y, z) = value.value else { return nil }
            return SIMD3(x, y, z)
        }()
        let result = SceneDynamicParticleValues(
            alpha: scalar(.alpha), size: scalar(.size), lifetime: scalar(.lifetime),
            rate: scalar(.rate), speed: scalar(.speed), count: scalar(.count),
            brightness: scalar(.brightness), normalizedColor: color
        )
        if result.alpha == nil, result.size == nil, result.lifetime == nil,
           result.rate == nil, result.speed == nil, result.count == nil,
           result.brightness == nil, result.normalizedColor == nil {
            return nil
        }
        return result
    }

    nonisolated func hasSameValuePayload(as other: SceneDynamicSnapshot) -> Bool {
        guard values.count == other.values.count else { return false }
        return values.allSatisfy { target, resolved in
            other.values[target]?.value == resolved.value
        }
    }

    nonisolated func replacingIdentity(
        frameIndex: UInt64,
        generation: UInt64
    ) -> SceneDynamicSnapshot {
        SceneDynamicSnapshot(
            frameIndex: frameIndex,
            generation: generation,
            values: values,
            authoredValues: authoredValues,
            userPropertyNumericRanges: userPropertyNumericRanges
        )
    }

    nonisolated static func empty(
        frameIndex: UInt64,
        generation: UInt64 = 0
    ) -> SceneDynamicSnapshot {
        SceneDynamicSnapshot(
            frameIndex: frameIndex, generation: generation,
            values: [:], authoredValues: [:], userPropertyNumericRanges: [:]
        )
    }

    fileprivate nonisolated init(
        frameIndex: UInt64,
        generation: UInt64,
        values: [SceneDynamicTarget: SceneDynamicResolvedValue],
        authoredValues: [SceneDynamicTarget: SceneDynamicValue],
        userPropertyNumericRanges:
            [SceneDynamicTarget: ClosedRange<Double>]
    ) {
        self.frameIndex = frameIndex
        self.generation = generation
        self.values = values
        self.authoredValues = authoredValues
        self.userPropertyNumericRanges = userPropertyNumericRanges
    }
}

nonisolated struct SceneDynamicSnapshotDiagnostic: Equatable, Sendable {
    enum Code: String, Equatable, Sendable {
        case duplicateDefinition
        case authoredTypeMismatch
        case unknownTarget
        case valueTypeMismatch
        case nonFiniteValue
        case userPropertyValueOutOfRange
    }

    let code: Code
    let target: SceneDynamicTarget
    let source: SceneDynamicSource
}

nonisolated struct SceneDynamicSnapshotResolution: Equatable, Sendable {
    let snapshot: SceneDynamicSnapshot
    let diagnostics: [SceneDynamicSnapshotDiagnostic]
}

nonisolated struct SceneDynamicSnapshotResolver {
    nonisolated func resolve(
        frameIndex: UInt64,
        generation: UInt64,
        definitions: [SceneDynamicTargetDefinition],
        userValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    ) -> SceneDynamicSnapshotResolution {
        var diagnostics: [SceneDynamicSnapshotDiagnostic] = []
        var definitionsByTarget: [SceneDynamicTarget: SceneDynamicTargetDefinition] = [:]
        var duplicateTargets: Set<SceneDynamicTarget> = []

        for definition in definitions {
            if definitionsByTarget[definition.target] != nil {
                duplicateTargets.insert(definition.target)
            } else {
                definitionsByTarget[definition.target] = definition
            }
        }
        for target in duplicateTargets {
            diagnostics.append(.init(
                code: .duplicateDefinition,
                target: target,
                source: .authored
            ))
        }

        var resolved: [SceneDynamicTarget: SceneDynamicResolvedValue] = [:]
        for definition in definitions where !duplicateTargets.contains(definition.target) {
            guard definition.authoredValue.valueType == definition.valueType else {
                diagnostics.append(.init(
                    code: .authoredTypeMismatch,
                    target: definition.target,
                    source: .authored
                ))
                continue
            }
            guard definition.authoredValue.isFinite else {
                diagnostics.append(.init(
                    code: .nonFiniteValue,
                    target: definition.target,
                    source: .authored
                ))
                continue
            }
            resolved[definition.target] = .init(
                value: definition.authoredValue,
                source: .authored
            )
        }

        apply(
            userValues,
            source: .userProperty,
            definitions: definitionsByTarget,
            resolved: &resolved,
            diagnostics: &diagnostics
        )
        apply(
            timelineValues,
            source: .timeline,
            definitions: definitionsByTarget,
            resolved: &resolved,
            diagnostics: &diagnostics
        )
        apply(
            sceneScriptValues,
            source: .sceneScript,
            definitions: definitionsByTarget,
            resolved: &resolved,
            diagnostics: &diagnostics
        )

        let orderedDiagnostics = diagnostics.sorted {
            ($0.source.priority, $0.target.sortKey, $0.code.rawValue)
                < ($1.source.priority, $1.target.sortKey, $1.code.rawValue)
        }
        return SceneDynamicSnapshotResolution(
            snapshot: SceneDynamicSnapshot(
                frameIndex: frameIndex,
                generation: generation,
                values: resolved,
                authoredValues: definitionsByTarget.compactMapValues { definition in
                    !duplicateTargets.contains(definition.target)
                        && resolved[definition.target] != nil
                        ? definition.authoredValue : nil
                },
                userPropertyNumericRanges: definitionsByTarget.compactMapValues {
                    definition in
                    guard !duplicateTargets.contains(definition.target),
                          resolved[definition.target] != nil else { return nil }
                    return definition.userPropertyNumericRange
                }
            ),
            diagnostics: orderedDiagnostics
        )
    }

    private nonisolated func apply(
        _ values: [SceneDynamicTarget: SceneDynamicValue],
        source: SceneDynamicSource,
        definitions: [SceneDynamicTarget: SceneDynamicTargetDefinition],
        resolved: inout [SceneDynamicTarget: SceneDynamicResolvedValue],
        diagnostics: inout [SceneDynamicSnapshotDiagnostic]
    ) {
        for (target, value) in values {
            guard let definition = definitions[target] else {
                diagnostics.append(.init(code: .unknownTarget, target: target, source: source))
                continue
            }
            guard resolved[target] != nil else { continue }
            guard value.valueType == definition.valueType else {
                diagnostics.append(.init(code: .valueTypeMismatch, target: target, source: source))
                continue
            }
            guard value.isFinite else {
                diagnostics.append(.init(code: .nonFiniteValue, target: target, source: source))
                continue
            }
            guard source != .userProperty
                    || definition.acceptsUserPropertyValue(value) else {
                diagnostics.append(.init(
                    code: .userPropertyValueOutOfRange,
                    target: target,
                    source: source
                ))
                continue
            }
            resolved[target] = .init(value: value, source: source)
        }
    }
}
