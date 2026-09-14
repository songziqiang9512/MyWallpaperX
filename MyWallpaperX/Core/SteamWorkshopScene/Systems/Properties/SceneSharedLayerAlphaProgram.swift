import Foundation

/// A data-only projection of shared-boolean-driven layer alpha ramps.
///
/// The program owns neither a JavaScript VM nor generic object mutation. It
/// carries only initializer values and scalar consumers admitted from complete
/// source/owner/target evidence.
nonisolated struct SceneSharedLayerAlphaProgram: Equatable, Sendable {
    let initialFlags: [String: Bool]
    let bindings: [SceneSharedLayerAlphaBinding]

    nonisolated static let empty = SceneSharedLayerAlphaProgram(
        initialFlags: [:], bindings: []
    )

    nonisolated var definitions: [SceneDynamicTargetDefinition] {
        bindings.map(\.definition)
    }

    nonisolated var layerIDs: [Int] {
        bindings.compactMap { binding in
            guard case let .layer(layerID, .alpha) = binding.definition.target else {
                return nil
            }
            return layerID
        }.sorted()
    }

    nonisolated static func validated(
        initialFlags: [String: Bool],
        bindings: [SceneSharedLayerAlphaBinding]
    ) -> Self? {
        let targets = bindings.map(\.definition.target)
        guard Set(targets).count == targets.count,
              bindings.allSatisfy({ initialFlags[$0.plan.sharedFlag] != nil }) else {
            return nil
        }
        return Self(
            initialFlags: initialFlags,
            bindings: bindings.sorted {
                $0.definition.target.sortKeyForSharedAlpha
                    < $1.definition.target.sortKeyForSharedAlpha
            }
        )
    }
}

nonisolated struct SceneSharedLayerAlphaBinding: Equatable, Sendable {
    let definition: SceneDynamicTargetDefinition
    let plan: SceneSharedLayerAlphaPlan
}

nonisolated struct SceneSharedLayerAlphaPlan: Equatable, Sendable {
    let sharedFlag: String
    let activeFlagValue: Bool
    let upperBound: SceneSharedLayerAlphaScalarInput
    let lowerBound: Double
    let riseRate: Double
    let fallRate: Double
}

nonisolated struct SceneSharedLayerAlphaScalarInput: Equatable, Sendable {
    let fallback: Double
    let userPropertyKey: String?
}

private nonisolated extension SceneDynamicTarget {
    var sortKeyForSharedAlpha: String {
        guard case let .layer(layerID, .alpha) = self else { return "~" }
        return String(format: "%020d", layerID)
    }
}
