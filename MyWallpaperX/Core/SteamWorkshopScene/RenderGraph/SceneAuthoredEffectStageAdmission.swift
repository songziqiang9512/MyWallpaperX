import Foundation

/// Planning provenance for one descriptor effect. Activity and strict admission are
/// deliberately separate from GPU execution; a strict plan is not an executed stage.
nonisolated struct SceneAuthoredEffectStageAdmission {
    typealias EffectKey = SceneAuthoredEffectRenderPlan.EffectKey

    enum Activity: String, CaseIterable {
        case authorDisabled = "author-disabled"
        case layerHidden = "layer-hidden"
        case active
    }

    enum StrictAdmission: String, CaseIterable {
        case inactive
        case admittedDedicated = "admitted-dedicated"
        case admittedGeneric = "admitted-generic"
        case notAdmitted = "not-admitted"
    }

    enum Coverage: String, CaseIterable {
        case inactive
        case complete
        case terminalInlinePrefix = "terminal-inline-prefix"
        case terminalInlineSuffix = "terminal-inline-suffix"
        case isolatedAccepted = "isolated-accepted"
        case isolatedOmitted = "isolated-omitted"
        case prefixAccepted = "prefix-accepted"
        case prefixOmitted = "prefix-omitted"
        case rejectedMissingGraph = "rejected-missing-graph"
        case rejectedAmbiguousGraph = "rejected-ambiguous-graph"
        case rejectedChain = "rejected-chain"
        case rejectedGraphMismatch = "rejected-graph-mismatch"
        case rejectedInvariant = "rejected-invariant"
    }

    let key: EffectKey
    let definitionPath: String
    let activity: Activity
    let strictAdmission: StrictAdmission
    let coverage: Coverage
    let backendName: String?
    let profileName: String?
    let reasonCode: String?

    var reportLine: String {
        "authoredEffectStageAdmission: layer=\(key.layerID) "
            + "effect=\(key.effectIndex) descriptor=\(token(key.descriptorID)) "
            + "activity=\(activity.rawValue) strict=\(strictAdmission.rawValue) "
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

enum SceneAuthoredEffectStageAdmissionBuilder {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Admission = SceneAuthoredEffectStageAdmission

    nonisolated static func make(
        layer: SceneRenderDescriptor.Layer,
        graphCandidates: [Graph],
        chainAdmission: SceneAuthoredEffectChainAdmission?,
        layerIsVisible: Bool,
        resolvedMaterialKeys: Set<Graph.EffectKey> = []
    ) -> [Admission] {
        layer.effects.enumerated().map { effectIndex, descriptorEffect in
            let key = Graph.EffectKey(
                layerID: layer.id,
                effectIndex: effectIndex,
                descriptorID: descriptorEffect.id
            )
            if descriptorEffect.visible == false {
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: .authorDisabled,
                    strictAdmission: .inactive,
                    coverage: .inactive
                )
            }
            guard layerIsVisible else {
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: .layerHidden,
                    strictAdmission: .inactive,
                    coverage: .inactive
                )
            }
            guard graphCandidates.count == 1, let graph = graphCandidates.first else {
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: .active,
                    strictAdmission: .notAdmitted,
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
                    activity: .active,
                    strictAdmission: .notAdmitted,
                    coverage: .rejectedGraphMismatch,
                    reasonCode: "graph-mismatch"
                )
            }
            if resolvedMaterialKeys.contains(key) {
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: .active,
                    strictAdmission: .admittedGeneric,
                    coverage: .complete,
                    backendName: "resolved-material",
                    profileName: "program"
                )
            }
            guard let chainAdmission else {
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: .active,
                    strictAdmission: .notAdmitted,
                    coverage: .rejectedInvariant,
                    reasonCode: "missing-chain-admission"
                )
            }
            switch chainAdmission {
            case .rejected(let rejection):
                return admission(
                    key: key,
                    path: descriptorEffect.file,
                    activity: .active,
                    strictAdmission: .notAdmitted,
                    coverage: .rejectedChain,
                    reasonCode: stageRejectionReason(
                        key: key,
                        rejection: rejection
                    )
                )
            case .accepted(let chain, let coverage):
                return plannedAdmission(
                    key: key,
                    path: descriptorEffect.file,
                    chain: chain,
                    chainCoverage: coverage
                )
            }
        }
    }

    private nonisolated static func plannedAdmission(
        key: Graph.EffectKey,
        path: String,
        chain: SceneAuthoredEffectExecutionChain,
        chainCoverage: SceneAuthoredEffectChainAdmission.Coverage
    ) -> Admission {
        let stageMatches = chain.executionStages.filter {
            $0.renderGraph.effects.count == 1
                && $0.renderGraph.effects.first?.key == key
        }
        guard stageMatches.count <= 1 else {
            return invalidStageIdentity(key: key, path: path)
        }
        if let stage = stageMatches.first {
            guard stage.renderGraph.effects.first?.definitionPath == path else {
                return invalidStageIdentity(key: key, path: path)
            }
            guard let coverage = acceptedCoverage(
                for: key,
                chainCoverage: chainCoverage
            ) else {
                return invalidStageIdentity(key: key, path: path)
            }
            return admission(
                key: key,
                path: path,
                activity: .active,
                strictAdmission: .admittedDedicated,
                coverage: coverage,
                backendName: stage.backend.stableName
            )
        }
        if let omitted = omittedCoverage(for: key, chainCoverage: chainCoverage) {
            return admission(
                key: key,
                path: path,
                activity: .active,
                strictAdmission: .notAdmitted,
                coverage: omitted.coverage,
                reasonCode: omitted.reason
            )
        }
        return invalidStageIdentity(key: key, path: path)
    }

    private nonisolated static func acceptedCoverage(
        for key: Graph.EffectKey,
        chainCoverage: SceneAuthoredEffectChainAdmission.Coverage
    ) -> Admission.Coverage? {
        switch chainCoverage {
        case .complete:
            .complete
        case .terminalIrisInlineSuffix:
            .terminalInlinePrefix
        case .xRayPrefix:
            .prefixAccepted
        case .isolatedCursorRipple(let executed, _),
             .isolatedShine(let executed, _):
            executed == key ? .isolatedAccepted : nil
        }
    }

    private nonisolated static func omittedCoverage(
        for key: Graph.EffectKey,
        chainCoverage: SceneAuthoredEffectChainAdmission.Coverage
    ) -> (coverage: Admission.Coverage, reason: String)? {
        switch chainCoverage {
        case .complete:
            nil
        case .terminalIrisInlineSuffix(let effect) where effect == key:
            (.terminalInlineSuffix, "terminal-inline-suffix")
        case .xRayPrefix(let omitted) where omitted.contains(key):
            (.prefixOmitted, "prefix-omitted")
        case .isolatedCursorRipple(_, let omitted) where omitted.contains(key):
            (.isolatedOmitted, "isolated-omitted")
        case .isolatedShine(_, let omitted) where omitted.contains(key):
            (.isolatedOmitted, "isolated-omitted")
        default:
            nil
        }
    }

    private nonisolated static func invalidStageIdentity(
        key: Graph.EffectKey,
        path: String
    ) -> Admission {
        admission(
            key: key,
            path: path,
            activity: .active,
            strictAdmission: .notAdmitted,
            coverage: .rejectedInvariant,
            reasonCode: "invalid-stage-identity"
        )
    }

    private nonisolated static func stageRejectionReason(
        key: Graph.EffectKey,
        rejection: SceneAuthoredEffectChainRejection
    ) -> String {
        guard let failedKey = rejection.effectKey else {
            return rejection.code.rawValue
        }
        if key == failedKey { return rejection.code.rawValue }
        return key.effectIndex < failedKey.effectIndex
            ? "discarded-strict-prefix"
            : "not-evaluated-after-chain-rejection"
    }

    private nonisolated static func admission(
        key: Graph.EffectKey,
        path: String,
        activity: Admission.Activity,
        strictAdmission: Admission.StrictAdmission,
        coverage: Admission.Coverage,
        backendName: String? = nil,
        profileName: String? = nil,
        reasonCode: String? = nil
    ) -> Admission {
        Admission(
            key: key,
            definitionPath: path,
            activity: activity,
            strictAdmission: strictAdmission,
            coverage: coverage,
            backendName: backendName,
            profileName: profileName,
            reasonCode: reasonCode
        )
    }
}

extension SceneAuthoredEffectExecutionPlan.Backend {
    nonisolated var stableName: String {
        switch self {
        case .preciseGaussian: "precise-gaussian"
        case .standardBlur: "standard-blur"
        case .localContrast: "local-contrast"
        case .opacity: "opacity"
        case .colorKey: "color-key"
        case .colorGrading: "color-grading"
        case .workshopShiftHue: "workshop-shift-hue"
        case .workshopAudioBars: "workshop-audio-bars"
        case .workshopGradient: "workshop-gradient"
        case .workshopAudioHueShift: "workshop-audio-hue-shift"
        case .workshopShadow: "workshop-shadow"
        case .spin: "spin"
        case .proceduralNoise: "procedural-noise"
        case .filmGrain: "film-grain"
        case .lightShafts: "light-shafts"
        case .shake: "shake"
        case .waterFlow: "water-flow"
        case .waterWaves: "water-waves"
        case .waterCaustics: "water-caustics"
        case .cursorRipple: "cursor-ripple"
        case .foliageSway: "foliage-sway"
        case .waterRipple: "water-ripple"
        case .depthParallax: "depth-parallax"
        case .xRay: "x-ray"
        case .clippingMask: "clipping-mask"
        case .blend: "blend"
        case .tint: "tint"
        case .transform: "transform"
        case .fisheyeZeroDistortion: "fisheye-zero-distortion"
        case .pulse: "pulse"
        case .godrays: "godrays"
        case .shine: "shine"
        }
    }
}
