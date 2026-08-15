import Foundation

/// Data-only projection of a cursor enter/leave shared flag and the bounded
/// origin consumers driven by that flag. It owns no general JavaScript runtime.
nonisolated struct SceneHoverOriginTransitionProgram: Equatable, Sendable {
    let cohorts: [SceneHoverOriginTransitionCohort]

    nonisolated static let empty = SceneHoverOriginTransitionProgram(cohorts: [])

    nonisolated var bindings: [SceneHoverOriginTransitionBinding] {
        cohorts.flatMap(\.bindings)
    }

    nonisolated var definitions: [SceneDynamicTargetDefinition] {
        bindings.map(\.definition)
    }

    nonisolated var ownerLayerIDs: [Int] {
        cohorts.map(\.ownerLayerID).sorted()
    }

    nonisolated var layerIDs: [Int] {
        bindings.compactMap { binding in
            guard case let .layer(layerID, .origin) = binding.definition.target else {
                return nil
            }
            return layerID
        }.sorted()
    }

    nonisolated static func validated(
        cohorts: [SceneHoverOriginTransitionCohort]
    ) -> Self? {
        let flags = cohorts.map(\.sharedFlag)
        let owners = cohorts.map(\.ownerLayerID)
        let targets = cohorts.flatMap(\.bindings).map(\.definition.target)
        guard Set(flags).count == flags.count,
              Set(owners).count == owners.count,
              Set(targets).count == targets.count,
              cohorts.allSatisfy(\.isValid) else { return nil }
        return Self(cohorts: cohorts.sorted { $0.sharedFlag < $1.sharedFlag })
    }
}

nonisolated struct SceneHoverOriginTransitionCohort: Equatable, Sendable {
    let sharedFlag: String
    let ownerLayerID: Int
    let bindings: [SceneHoverOriginTransitionBinding]

    fileprivate nonisolated var isValid: Bool {
        !sharedFlag.isEmpty && sharedFlag != "__proto__"
            && ownerLayerID >= 0 && !bindings.isEmpty
            && Set(bindings.map(\.definition.target)).count == bindings.count
    }
}

nonisolated struct SceneHoverOriginTransitionBinding: Equatable, Sendable {
    let definition: SceneDynamicTargetDefinition
    let plan: SceneHoverOriginTransitionPlan
}

nonisolated struct SceneHoverOriginTransitionPlan: Equatable, Sendable {
    let authoredOrigin: SIMD3<Double>
    let base: SceneLaunchOriginTransitionVectorInput
    let endpoint: SceneLaunchOriginTransitionVectorInput
    let speed: SceneLaunchOriginTransitionScalarInput
    let speedDivisor: Double
    let triggerPropertyKey: String
    let baseOffset: SIMD3<Double>
    let falseUsesEndpoint: Bool
}
