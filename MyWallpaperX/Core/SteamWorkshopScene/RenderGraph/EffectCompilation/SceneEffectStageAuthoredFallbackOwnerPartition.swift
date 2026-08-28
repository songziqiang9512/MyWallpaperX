import Foundation

/// Filters definition-only property fallbacks at the product-owner boundary.
/// A retained dedicated stage must remain executable until its own compiler
/// has explicitly revoked that owner with the same launch-scoped facts.
nonisolated enum SceneEffectStageAuthoredFallbackOwnerPartition {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    static func executableTargets(
        definitions: [SceneDynamicTargetDefinition],
        liveTargets: Set<SceneDynamicTarget>,
        retainedDedicatedEffects: Set<EffectKey>
    ) -> Set<SceneDynamicTarget> {
        Set(definitions.compactMap { definition in
            let target = definition.target
            if liveTargets.contains(target) {
                return target
            }
            let identity: (layerID: Int, effectIndex: Int)?
            switch target {
            case let .effectVisibility(layerID, effectIndex),
                 let .effectConstant(layerID, effectIndex, _, _):
                identity = (layerID, effectIndex)
            case .scene, .camera, .layer, .text, .particle,
                 .scriptInstanceProperty:
                identity = nil
            }
            guard let identity else { return target }
            let hasRetainedOwner = retainedDedicatedEffects.contains {
                $0.layerID == identity.layerID
                    && $0.effectIndex == identity.effectIndex
            }
            return hasRetainedOwner ? nil : target
        })
    }

    /// Proves one definition-only scalar without collapsing the authored
    /// definition array. Duplicate definitions, type drift, non-finite values,
    /// and signed-zero mismatches must remain visible at the owner boundary.
    static func hasExactScalarDefinition(
        target: SceneDynamicTarget,
        componentBitPatterns: [UInt64],
        definitions: [SceneDynamicTargetDefinition]
    ) -> Bool {
        hasExactNumericDefinition(
            target: target,
            valueType: .scalar,
            componentBitPatterns: componentBitPatterns,
            definitions: definitions
        )
    }

    /// Keeps numeric authored fallback identity lossless for shared owner
    /// transfers. Shape, finiteness, duplicate definitions, and each Double
    /// bit pattern (including signed zero) remain part of the boundary.
    static func hasExactNumericDefinition(
        target: SceneDynamicTarget,
        valueType: SceneDynamicValueType,
        componentBitPatterns: [UInt64],
        definitions: [SceneDynamicTargetDefinition]
    ) -> Bool {
        let matches = definitions.filter { $0.target == target }
        guard matches.count == 1,
              let definition = matches.first,
              definition.valueType == valueType,
              definition.authoredValue.valueType == valueType,
              definition.authoredValue.isFinite,
              let actual = numericBitPatterns(definition.authoredValue)
        else { return false }
        return actual == componentBitPatterns
    }

    private static func numericBitPatterns(
        _ value: SceneDynamicValue
    ) -> [UInt64]? {
        switch value {
        case let .scalar(x): [x.bitPattern]
        case let .vector2(x, y): [x.bitPattern, y.bitPattern]
        case let .vector3(x, y, z): [x.bitPattern, y.bitPattern, z.bitPattern]
        case let .vector4(x, y, z, w):
            [x.bitPattern, y.bitPattern, z.bitPattern, w.bitPattern]
        case .bool, .string: nil
        }
    }
}
