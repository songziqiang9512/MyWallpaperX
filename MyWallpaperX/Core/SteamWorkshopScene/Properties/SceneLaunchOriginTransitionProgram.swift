import Foundation

/// Data-only projection of one bounded cursor-click origin cohort plus exact
/// pass scalar consumers of the same shared flag. It carries no JavaScript VM.
nonisolated struct SceneLaunchOriginTransitionProgram: Equatable, Sendable {
    let cohorts: [SceneLaunchOriginTransitionCohort]

    nonisolated static let empty = SceneLaunchOriginTransitionProgram(cohorts: [])

    nonisolated var bindings: [SceneLaunchOriginTransitionBinding] {
        cohorts.flatMap(\.bindings)
    }

    nonisolated var definitions: [SceneDynamicTargetDefinition] {
        bindings.map(\.definition) + scalarBindings.map(\.definition)
    }

    nonisolated var scalarBindings: [SceneSharedBooleanEffectScalarBinding] {
        cohorts.flatMap(\.scalarBindings)
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
        cohorts: [SceneLaunchOriginTransitionCohort]
    ) -> Self? {
        let flags = cohorts.map(\.sharedFlag)
        let targets = cohorts.flatMap {
            $0.bindings.map(\.definition.target)
                + $0.scalarBindings.map(\.definition.target)
        }
        guard Set(flags).count == flags.count,
              Set(targets).count == targets.count,
              cohorts.allSatisfy(\.isValid) else {
            return nil
        }
        return Self(cohorts: cohorts.sorted { $0.sharedFlag < $1.sharedFlag })
    }
}

nonisolated struct SceneLaunchOriginTransitionCohort: Equatable, Sendable {
    let sharedFlag: String
    let masterTarget: SceneDynamicTarget
    let bindings: [SceneLaunchOriginTransitionBinding]
    let scalarBindings: [SceneSharedBooleanEffectScalarBinding]

    fileprivate nonisolated var isValid: Bool {
        !sharedFlag.isEmpty
            && bindings.count >= 2
            && bindings.filter { $0.role == .master }.count == 1
            && bindings.contains { $0.definition.target == masterTarget && $0.role == .master }
            && Set(bindings.map(\.definition.target)).count == bindings.count
            && Set(scalarBindings.map(\.definition.target)).count
                == scalarBindings.count
            && Set(bindings.map(\.definition.target)).isDisjoint(
                with: Set(scalarBindings.map(\.definition.target))
            )
    }
}

nonisolated struct SceneSharedBooleanEffectScalarBinding: Equatable, Sendable {
    let definition: SceneDynamicTargetDefinition
    let trueValue: Double
    let falseValue: Double
}

nonisolated struct SceneLaunchOriginTransitionBinding: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case master
        case follower
    }

    let definition: SceneDynamicTargetDefinition
    let role: Role
    let plan: SceneLaunchOriginTransitionPlan
}

/// Exact runtime inputs needed to reproduce the admitted launch branch.
nonisolated struct SceneLaunchOriginTransitionPlan: Equatable, Sendable {
    enum InitialFalseTarget: Equatable, Sendable {
        case base(offset: SIMD3<Double>)
        case endpoint
    }

    let authoredOrigin: SIMD3<Double>
    let base: SceneLaunchOriginTransitionVectorInput
    let endpoint: SceneLaunchOriginTransitionVectorInput
    let speed: SceneLaunchOriginTransitionScalarInput
    let speedDivisor: Double
    let triggerPropertyKey: String
    let initialFalseTarget: InitialFalseTarget
}

nonisolated struct SceneLaunchOriginTransitionVectorInput: Equatable, Sendable {
    let x: SceneLaunchOriginTransitionScalarInput
    let y: SceneLaunchOriginTransitionScalarInput
    let z: SceneLaunchOriginTransitionScalarInput
}

nonisolated struct SceneLaunchOriginTransitionScalarInput: Equatable, Sendable {
    let fallback: Double
    let userPropertyKey: String?
}
