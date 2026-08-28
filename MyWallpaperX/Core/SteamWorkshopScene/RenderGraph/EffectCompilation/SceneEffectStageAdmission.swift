import Foundation

/// Planning provenance for one descriptor effect. Activity and admission are
/// deliberately separate from GPU execution; admission alone is not execution.
nonisolated struct SceneEffectStageAdmission {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    enum Activity: String, CaseIterable {
        case authorDisabled = "author-disabled"
        case propertyInactive = "property-inactive"
        case layerHidden = "layer-hidden"
        case active
    }

    enum Admission: String, CaseIterable {
        case inactive
        case admittedDedicated = "admitted-dedicated"
        case admittedFallback = "admitted-fallback"
        case admittedGeneric = "admitted-generic"
        case admittedPassthrough = "admitted-passthrough"
        case notAdmitted = "not-admitted"
    }

    enum Coverage: String, CaseIterable {
        case inactive
        case complete
        case rejectedMissingGraph = "rejected-missing-graph"
        case rejectedAmbiguousGraph = "rejected-ambiguous-graph"
        case rejectedGraphMismatch = "rejected-graph-mismatch"
        case rejectedCapability = "rejected-capability"
    }

    let key: EffectKey
    let definitionPath: String
    let activity: Activity
    let admission: Admission
    let coverage: Coverage
    let backendName: String?
    let profileName: String?
    let reasonCode: String?

    var reportLine: String {
        "effectStageAdmission: layer=\(key.layerID) "
            + "effect=\(key.effectIndex) descriptor=\(token(key.descriptorID)) "
            + "activity=\(activity.rawValue) admission=\(admission.rawValue) "
            + "coverage=\(coverage.rawValue) backend=\(backendName ?? "-") "
            + "profile=\(profileName ?? "-") reason=\(reasonCode ?? "-") "
            + "path=\(token(definitionPath))"
    }

    private func token(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~/")
        )
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "<invalid>"
    }
}

extension SceneEffectStageAdmission.Activity {
    nonisolated var participatesInUnifiedRoute: Bool {
        self == .active || self == .propertyInactive
    }
}

enum SceneEffectStageAdmissionBuilder {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Admission = SceneEffectStageAdmission

    nonisolated static func make(
        layer: SceneRenderDescriptor.Layer,
        graphCandidates: [Graph],
        layerIsExecutable: Bool,
        startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget> = [],
        unifiedExecutionSubjects: [SceneEffectExactRuntimeSubject] = []
    ) -> [Admission] {
        layer.effects.enumerated().map { effectIndex, descriptorEffect in
            let key = Graph.EffectKey(
                layerID: layer.id,
                effectIndex: effectIndex,
                descriptorID: descriptorEffect.id
            )
            let propertyInactive = descriptorEffect.visible == false
                && startupInactiveEffectVisibilityTargets.contains(
                    .effectVisibility(
                        layerID: layer.id,
                        effectIndex: effectIndex
                    )
                )
                && graphCandidates.count == 1
                && graphCandidates[0].effects.contains(where: {
                    $0.key == key
                })
            if descriptorEffect.visible == false && !propertyInactive {
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: .authorDisabled,
                    admission: .inactive,
                    coverage: .inactive
                )
            }
            let activity: Admission.Activity = propertyInactive
                ? .propertyInactive : .active
            guard layerIsExecutable else {
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: .layerHidden,
                    admission: .inactive,
                    coverage: .inactive
                )
            }
            guard graphCandidates.count == 1, let graph = graphCandidates.first else {
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: activity,
                    admission: .notAdmitted,
                    coverage: graphCandidates.isEmpty
                        ? .rejectedMissingGraph
                        : .rejectedAmbiguousGraph,
                    reasonCode: graphCandidates.isEmpty
                        ? "missing-graph"
                        : "duplicate-graph"
                )
            }
            guard let graphEffect = graph.effects.first(where: { $0.key == key }),
                  graphEffect.definitionPath == descriptorEffect.file else {
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: activity,
                    admission: .notAdmitted,
                    coverage: .rejectedGraphMismatch,
                    reasonCode: "graph-mismatch"
                )
            }
            if let subject = unifiedExecutionSubjects.first(where: { $0.key == key }) {
                let admissionKind: Admission.Admission
                let profileName: String?
                switch subject.family {
                case "resolved-material":
                    admissionKind = .admittedGeneric
                    profileName = "program"
                case "visual-failure-passthrough":
                    admissionKind = .admittedFallback
                    profileName = "effect-local-passthrough"
                case "initially-inactive-passthrough":
                    admissionKind = .admittedPassthrough
                    profileName = "inactive-passthrough"
                default:
                    admissionKind = .admittedDedicated
                    profileName = nil
                }
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: activity,
                    admission: admissionKind,
                    coverage: .complete,
                    backendName: subject.family,
                    profileName: profileName
                )
            }
            return admission(
                key: key,
                path: descriptorEffect.file,
                activity: activity,
                admission: .notAdmitted,
                coverage: .rejectedCapability,
                reasonCode: "unified-capability-unavailable"
            )
        }
    }

    private nonisolated static func admission(
        key: Graph.EffectKey,
        path: String,
        activity: Admission.Activity,
        admission: Admission.Admission,
        coverage: Admission.Coverage,
        backendName: String? = nil,
        profileName: String? = nil,
        reasonCode: String? = nil
    ) -> Admission {
        Admission(
            key: key,
            definitionPath: path,
            activity: activity,
            admission: admission,
            coverage: coverage,
            backendName: backendName,
            profileName: profileName,
            reasonCode: reasonCode
        )
    }
}

extension SceneEffectStageExecutionPlan.Backend {
    nonisolated var stableName: String {
        switch self {
        case .standardBlur: "standard-blur"
        case .pulse: "pulse"
        }
    }
}
