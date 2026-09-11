import Foundation

nonisolated struct SceneScriptVectorEvaluation: Equatable, Sendable {
    let value: SceneDynamicValue
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let puppetBoneMutations: [SceneScriptPuppetBoneMutation]
    let videoCommands: [SceneScriptVideoCommand]

    init(
        value: SceneDynamicValue,
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation],
        animationMutations: [SceneTimelinePlaybackMutation],
        layerMutations: [SceneScriptLayerMutation],
        puppetBoneMutations: [SceneScriptPuppetBoneMutation] = [],
        videoCommands: [SceneScriptVideoCommand]
    ) {
        self.value = value
        self.materialFunctionMutations = materialFunctionMutations
        self.animationMutations = animationMutations
        self.layerMutations = layerMutations
        self.puppetBoneMutations = puppetBoneMutations
        self.videoCommands = videoCommands
    }
}

nonisolated struct SceneScriptVectorCandidate: Sendable {
    let authoredOrdinal: Int
    let source: String
    let definition: SceneDynamicTargetDefinition
    let properties: [String: SceneScriptPropertyInput]
    let livePropertyInputTargets: Set<SceneDynamicTarget>
    let hasCurrentAnimation: Bool
    let dynamicImageReferences: [SceneScriptDynamicImageReference]
    let requiresStatefulOwner: Bool
    /// A side-effect-free direct Vec3 projection may observe a `shared` key
    /// before its authored producer has published the first frame. Prepare
    /// these readers after effectful producers; return validation stays live.
    let evaluatesAfterSharedProviders: Bool
    /// Package-local image model whose proven neutral base-material tint is
    /// driven by this typed owner. Dynamic instances reuse the target value;
    /// the model path never selects an algorithm.
    let dynamicMaterialModelPath: String?
    /// A validated user-property input feeding this sole value producer.
    var userPropertyInputKey: String? = nil

    var allowsDynamicLayerSideEffects: Bool {
        requiresStatefulOwner || !dynamicImageReferences.isEmpty
    }
}

/// Side-effect-free projection of authored non-scalar typed bindings. Pass-owned
/// candidates are only metadata until resolved-material admission identifies
/// an actual consumer; projecting this catalog never evaluates JavaScript.
nonisolated struct SceneScriptVectorCandidateCatalog: Sendable {
    let candidates: [SceneScriptVectorCandidate]
    let duplicateTargets: Set<SceneDynamicTarget>

    static let empty = Self(candidates: [])

    init(candidates: [SceneScriptVectorCandidate]) {
        self.candidates = candidates
        let counts = Dictionary(grouping: candidates, by: { $0.definition.target })
            .mapValues(\.count)
        duplicateTargets = Set(counts.compactMap { target, count in
            count > 1 ? target : nil
        })
    }

    var uniqueCandidates: [SceneScriptVectorCandidate] {
        candidates.filter { !duplicateTargets.contains($0.definition.target) }
    }

    var definitions: [SceneDynamicTargetDefinition] {
        candidates.map(\.definition)
    }

    var targets: Set<SceneDynamicTarget> {
        Set(uniqueCandidates.map { $0.definition.target })
    }

    var passTargets: Set<SceneDynamicTarget> {
        Set(uniqueCandidates.compactMap { candidate in
            guard case .effectConstant = candidate.definition.target else {
                return nil
            }
            return candidate.definition.target
        })
    }

    func consumesUserProperty(
        key: String, target: SceneDynamicTarget, valueType: SceneDynamicValueType?
    ) -> Bool {
        uniqueCandidates.contains {
            $0.userPropertyInputKey == key && $0.definition.target == target
                && $0.definition.valueType == valueType
        }
    }

    var nonPassTargets: Set<SceneDynamicTarget> {
        targets.subtracting(passTargets)
    }

    var animationTargets: Set<SceneDynamicTarget> {
        Set(uniqueCandidates.compactMap { candidate in
            candidate.hasCurrentAnimation ? candidate.definition.target : nil
        })
    }

    func excludingTargets(
        _ targets: Set<SceneDynamicTarget>
    ) -> SceneScriptVectorCandidateCatalog {
        guard !targets.isEmpty else { return self }
        return .init(candidates: candidates.filter {
            !targets.contains($0.definition.target)
        })
    }

    var admittedScaleLayerIDs: Set<Int> {
        Set(uniqueCandidates.compactMap { candidate in
            guard case let .layer(layerID, .scale) = candidate.definition.target else {
                return nil
            }
            return layerID
        })
    }

    var dynamicImageModelPaths: Set<String> {
        Set(uniqueCandidates.flatMap(\.dynamicImageReferences).map(\.modelPath))
    }

    var dynamicImageMaterialColorTargets: [String: SceneDynamicTarget] {
        let entries = uniqueCandidates.compactMap { candidate -> (
            String, SceneDynamicTarget
        )? in
            guard let path = candidate.dynamicMaterialModelPath else {
                return nil
            }
            return (path.lowercased(), candidate.definition.target)
        }
        let grouped = Dictionary(grouping: entries, by: \.0)
        return Dictionary(uniqueKeysWithValues: grouped.compactMap { path, values in
            guard values.count == 1, let target = values.first?.1 else {
                return nil
            }
            return (path, target)
        })
    }
}

nonisolated struct SceneScriptVectorPassCompilation: Sendable {
    let requestedTargets: Set<SceneDynamicTarget>
    let instantiatedTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]

    var failedTargets: Set<SceneDynamicTarget> { Set(failures.keys) }
    var deferredTargets: Set<SceneDynamicTarget> {
        requestedTargets.subtracting(instantiatedTargets).subtracting(failedTargets)
    }
}

nonisolated struct SceneScriptVectorProgramConstruction: @unchecked Sendable {
    let program: SceneScriptVectorProgram
    let requestedTargets: Set<SceneDynamicTarget>
    let instantiatedTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]

    var deferredTargets: Set<SceneDynamicTarget> {
        requestedTargets.subtracting(instantiatedTargets).subtracting(failures.keys)
    }
}
