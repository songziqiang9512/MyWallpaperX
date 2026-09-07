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
    case font
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
        switch value {
        case let .scalar(component):
            return component.isFinite && userPropertyNumericRange.contains(component)
        case let .vector3(x, y, z):
            return x.isFinite && y.isFinite && z.isFinite
                && userPropertyNumericRange.contains(x)
                && userPropertyNumericRange.contains(y)
                && userPropertyNumericRange.contains(z)
        default:
            return false
        }
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
    private let dynamicTransformLayerIDs: Set<Int>

    nonisolated var count: Int { values.count }

    nonisolated var dynamicTransformLayerIDsForFrame: Set<Int> {
        dynamicTransformLayerIDs
    }

    nonisolated subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? {
        values[target]
    }

    nonisolated func authoredValue(for target: SceneDynamicTarget) -> SceneDynamicValue? {
        authoredValues[target]
    }

    /// Returns the last published typed values for the requested runtime
    /// owners.  SceneScript callbacks receive the current property value, not
    /// the immutable authored seed, so the host uses this small projection as
    /// the next frame's callback input.  Keeping the projection here avoids a
    /// second mutable property registry while preserving the snapshot's
    /// identity and source metadata for normal consumers.
    nonisolated func values(
        for targets: Set<SceneDynamicTarget>,
        source: SceneDynamicSource? = nil
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        var result: [SceneDynamicTarget: SceneDynamicValue] = [:]
        for target in targets {
            guard let resolved = values[target],
                  source == nil || source == resolved.source else { continue }
            result[target] = resolved.value
        }
        return result
    }

    /// Projects only the prepared Program input lanes from this snapshot.
    /// Definitions already establish the accepted value types; keeping the
    /// filter here makes every typed consumer use the same producer channel
    /// without exposing or rebuilding the complete resolved map.
    nonisolated func typedValues(
        for targets: Set<SceneDynamicTarget>,
        valueTypes: Set<SceneDynamicValueType>,
        source: SceneDynamicSource? = nil
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        var result: [SceneDynamicTarget: SceneDynamicValue] = [:]
        for target in targets {
            guard let resolved = values[target],
                  valueTypes.contains(resolved.value.valueType),
                  source == nil || source == resolved.source else { continue }
            result[target] = resolved.value
        }
        return result
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

    nonisolated func particleControlPointAngles(layerID: Int) -> [Int: SIMD3<Double>] {
        var result: [Int: SIMD3<Double>] = [:]
        for index in 0 ..< 8 {
            guard let resolved = self[.particle(layerID: layerID, field: .controlPointAngles(index))],
                  case let .vector3(x, y, z) = resolved.value,
                  x.isFinite, y.isFinite, z.isFinite,
                  abs(x) <= 1_000_000, abs(y) <= 1_000_000,
                  abs(z) <= 1_000_000 else { continue }
            let turn = 2 * Double.pi
            result[index] = SIMD3(
                x.remainder(dividingBy: turn),
                y.remainder(dividingBy: turn),
                z.remainder(dividingBy: turn)
            )
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
            userPropertyNumericRanges: userPropertyNumericRanges,
            dynamicTransformLayerIDs: dynamicTransformLayerIDs
        )
    }

    /// Rebuilds only the resolved payload while preserving the authored
    /// metadata carried by this snapshot.  The resolver uses this for a
    /// same-frame SceneScript result overlay after the authored/user/timeline
    /// lanes have already been resolved for VM input.
    fileprivate nonisolated func replacingResolvedValues(
        frameIndex: UInt64,
        generation: UInt64,
        values: [SceneDynamicTarget: SceneDynamicResolvedValue],
        dynamicTransformLayerIDs: Set<Int>
    ) -> SceneDynamicSnapshot {
        SceneDynamicSnapshot(
            frameIndex: frameIndex,
            generation: generation,
            values: values,
            authoredValues: authoredValues,
            userPropertyNumericRanges: userPropertyNumericRanges,
            dynamicTransformLayerIDs: dynamicTransformLayerIDs
        )
    }

    fileprivate nonisolated func resolvedValuesForPreparation()
        -> [SceneDynamicTarget: SceneDynamicResolvedValue] {
        values
    }

    nonisolated static func empty(
        frameIndex: UInt64,
        generation: UInt64 = 0
    ) -> SceneDynamicSnapshot {
        SceneDynamicSnapshot(
            frameIndex: frameIndex, generation: generation,
            values: [:], authoredValues: [:], userPropertyNumericRanges: [:],
            dynamicTransformLayerIDs: []
        )
    }

    fileprivate nonisolated init(
        frameIndex: UInt64,
        generation: UInt64,
        values: [SceneDynamicTarget: SceneDynamicResolvedValue],
        authoredValues: [SceneDynamicTarget: SceneDynamicValue],
        userPropertyNumericRanges:
            [SceneDynamicTarget: ClosedRange<Double>],
        dynamicTransformLayerIDs: Set<Int>
    ) {
        self.frameIndex = frameIndex
        self.generation = generation
        self.values = values
        self.authoredValues = authoredValues
        self.userPropertyNumericRanges = userPropertyNumericRanges
        self.dynamicTransformLayerIDs = dynamicTransformLayerIDs
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

/// Launch/revision-stable projection of dynamic target definitions.
///
/// The definition list is authored topology.  Building its target index and
/// validating authored values is therefore preparation work; frame updates
/// should only apply the current user/timeline/SceneScript values to this
/// immutable projection.
nonisolated struct SceneDynamicSnapshotDefinitionIndex: Sendable {
    fileprivate let definitionsByTarget:
        [SceneDynamicTarget: SceneDynamicTargetDefinition]
    fileprivate let duplicateTargets: Set<SceneDynamicTarget>
    fileprivate let authoredValues:
        [SceneDynamicTarget: SceneDynamicResolvedValue]
    fileprivate let authoredValueLanes:
        [SceneDynamicTarget: SceneDynamicValue]
    fileprivate let userPropertyNumericRanges:
        [SceneDynamicTarget: ClosedRange<Double>]
    fileprivate let dynamicTransformLayerIDs: Set<Int>
    fileprivate let authoredDiagnostics: [SceneDynamicSnapshotDiagnostic]

    fileprivate init(definitions: [SceneDynamicTargetDefinition]) {
        var definitionsByTarget: [
            SceneDynamicTarget: SceneDynamicTargetDefinition
        ] = [:]
        var duplicateTargets: Set<SceneDynamicTarget> = []
        for definition in definitions {
            if definitionsByTarget[definition.target] != nil {
                duplicateTargets.insert(definition.target)
            } else {
                definitionsByTarget[definition.target] = definition
            }
        }

        var authoredValues: [
            SceneDynamicTarget: SceneDynamicResolvedValue
        ] = [:]
        var authoredValueLanes: [
            SceneDynamicTarget: SceneDynamicValue
        ] = [:]
        var userPropertyNumericRanges: [
            SceneDynamicTarget: ClosedRange<Double>
        ] = [:]
        var dynamicTransformLayerIDs: Set<Int> = []
        var authoredDiagnostics: [SceneDynamicSnapshotDiagnostic] = []
        for definition in definitions where
            !duplicateTargets.contains(definition.target) {
            guard definition.authoredValue.valueType == definition.valueType else {
                authoredDiagnostics.append(.init(
                    code: .authoredTypeMismatch,
                    target: definition.target,
                    source: .authored
                ))
                continue
            }
            guard definition.authoredValue.isFinite else {
                authoredDiagnostics.append(.init(
                    code: .nonFiniteValue,
                    target: definition.target,
                    source: .authored
                ))
                continue
            }
            authoredValues[definition.target] = .init(
                value: definition.authoredValue,
                source: .authored
            )
            authoredValueLanes[definition.target] = definition.authoredValue
            if let range = definition.userPropertyNumericRange {
                userPropertyNumericRanges[definition.target] = range
            }
            if case let .layer(layerID, field) = definition.target,
               definition.valueType == .vector3,
               field == .origin || field == .scale || field == .angles {
                dynamicTransformLayerIDs.insert(layerID)
            }
        }

        for target in duplicateTargets {
            authoredDiagnostics.append(.init(
                code: .duplicateDefinition,
                target: target,
                source: .authored
            ))
        }
        self.definitionsByTarget = definitionsByTarget
        self.duplicateTargets = duplicateTargets
        self.authoredValues = authoredValues
        self.authoredValueLanes = authoredValueLanes
        self.userPropertyNumericRanges = userPropertyNumericRanges
        self.dynamicTransformLayerIDs = dynamicTransformLayerIDs
        self.authoredDiagnostics = authoredDiagnostics
    }
}

nonisolated struct SceneDynamicSnapshotResolution: Equatable, Sendable {
    let snapshot: SceneDynamicSnapshot
    let diagnostics: [SceneDynamicSnapshotDiagnostic]
}

nonisolated struct SceneDynamicSnapshotResolver {
    nonisolated static func prepare(
        definitions: [SceneDynamicTargetDefinition]
    ) -> SceneDynamicSnapshotDefinitionIndex {
        SceneDynamicSnapshotDefinitionIndex(definitions: definitions)
    }

    nonisolated func resolve(
        frameIndex: UInt64,
        generation: UInt64,
        definitions: [SceneDynamicTargetDefinition],
        userValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    ) -> SceneDynamicSnapshotResolution {
        return resolve(
            frameIndex: frameIndex,
            generation: generation,
            index: Self.prepare(definitions: definitions),
            userValues: userValues,
            timelineValues: timelineValues,
            sceneScriptValues: sceneScriptValues
        )
    }

    nonisolated func resolve(
        frameIndex: UInt64,
        generation: UInt64,
        index: SceneDynamicSnapshotDefinitionIndex,
        userValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        timelineValues: [SceneDynamicTarget: SceneDynamicValue] = [:],
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue] = [:]
    ) -> SceneDynamicSnapshotResolution {
        var diagnostics = index.authoredDiagnostics
        var resolved = index.authoredValues

        apply(
            userValues,
            source: .userProperty,
            definitions: index.definitionsByTarget,
            resolved: &resolved,
            diagnostics: &diagnostics
        )
        apply(
            timelineValues,
            source: .timeline,
            definitions: index.definitionsByTarget,
            resolved: &resolved,
            diagnostics: &diagnostics
        )
        apply(
            sceneScriptValues,
            source: .sceneScript,
            definitions: index.definitionsByTarget,
            resolved: &resolved,
            diagnostics: &diagnostics
        )

        let orderedDiagnostics = Self.orderedDiagnostics(diagnostics)
        return SceneDynamicSnapshotResolution(
            snapshot: SceneDynamicSnapshot(
                frameIndex: frameIndex,
                generation: generation,
                values: resolved,
                authoredValues: index.authoredValueLanes,
                userPropertyNumericRanges: index.userPropertyNumericRanges,
                dynamicTransformLayerIDs: Self.dynamicTransformLayerIDs(
                    in: resolved,
                    candidates: index.dynamicTransformLayerIDs
                )
            ),
            diagnostics: orderedDiagnostics
        )
    }

    /// Applies a same-frame SceneScript result to an already resolved
    /// authored/user/timeline snapshot.  This keeps the typed producer lane
    /// shared with VM input while avoiding a second pass over every authored
    /// definition on the ordinary frame path.  Validation and diagnostics for
    /// the new producer remain identical to the full resolver.
    nonisolated func resolve(
        frameIndex: UInt64,
        generation: UInt64,
        index: SceneDynamicSnapshotDefinitionIndex,
        base: SceneDynamicSnapshotResolution,
        sceneScriptValues: [SceneDynamicTarget: SceneDynamicValue]
    ) -> SceneDynamicSnapshotResolution {
        var diagnostics = base.diagnostics
        var resolved = base.snapshot.resolvedValuesForPreparation()
        apply(
            sceneScriptValues,
            source: .sceneScript,
            definitions: index.definitionsByTarget,
            resolved: &resolved,
            diagnostics: &diagnostics
        )
        let orderedDiagnostics = Self.orderedDiagnostics(diagnostics)
        return SceneDynamicSnapshotResolution(
            snapshot: base.snapshot.replacingResolvedValues(
                frameIndex: frameIndex,
                generation: generation,
                values: resolved,
                dynamicTransformLayerIDs: Self.dynamicTransformLayerIDs(
                    in: resolved,
                    candidates: index.dynamicTransformLayerIDs
                )
            ),
            diagnostics: orderedDiagnostics
        )
    }

    private nonisolated static func dynamicTransformLayerIDs(
        in values: [SceneDynamicTarget: SceneDynamicResolvedValue],
        candidates: Set<Int>
    ) -> Set<Int> {
        candidates.filter { layerID in
            func hasDynamicValue(
                _ field: SceneDynamicLayerField
            ) -> Bool {
                guard let resolved = values[
                    .layer(layerID: layerID, field: field)
                ], resolved.source != .authored else { return false }
                guard case let .vector3(x, y, z) = resolved.value else {
                    return false
                }
                return x.isFinite && y.isFinite && z.isFinite
            }
            return hasDynamicValue(.origin)
                || hasDynamicValue(.scale)
                || hasDynamicValue(.angles)
        }
    }

    /// Diagnostics are a product-side safety signal, but the ordinary valid
    /// frame has none. Preserve the existing deterministic ordering only when
    /// there is work to order, rather than sorting an empty/singleton array on
    /// every resolution.
    private nonisolated static func orderedDiagnostics(
        _ diagnostics: [SceneDynamicSnapshotDiagnostic]
    ) -> [SceneDynamicSnapshotDiagnostic] {
        guard diagnostics.count > 1 else { return diagnostics }
        return diagnostics.sorted {
            ($0.source.priority, $0.target.sortKey, $0.code.rawValue)
                < ($1.source.priority, $1.target.sortKey, $1.code.rawValue)
        }
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
