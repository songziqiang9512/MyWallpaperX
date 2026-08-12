import Foundation

/// Launch-scoped capability catalog compiled from immutable graph-admission
/// products. No secondary renderer route participates in capability ownership.
final class SceneResolvedMaterialExecutionCapabilityCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias MaterialKey = SceneResolvedMaterialRuntimeCatalog.Key
    typealias Template = SceneResolvedMaterialTemplate
    typealias ExactEffectSubject = SceneEffectExactRuntimeSubject

    struct DynamicProducerCatalog {
        struct UserProperty: Hashable {
            let propertyKey: String
            let target: SceneDynamicTarget
        }

        let userProperties: Set<UserProperty>
        let timelineTargets: Set<SceneDynamicTarget>
        let sceneScriptTargets: Set<SceneDynamicTarget>

        static let empty = Self(userProperties: [], timelineTargets: [], sceneScriptTargets: [])
    }

    struct Rejection: Error {
        let code: String
    }

    struct Token: Hashable {
        fileprivate let ownerID: UUID
        fileprivate let capabilityID: UUID
        fileprivate let layerID: Int
    }

    struct ClaimedLayer {
        let token: Token
        let layerID: Int
    }

    struct RuntimeDispositionOwnership {
        let layerID: Int
        let subjects: [ExactEffectSubject]

        fileprivate init(layerID: Int, subjects: [ExactEffectSubject]) {
            self.layerID = layerID
            self.subjects = subjects
        }
    }

    enum StageCapability {
        case resolved(
            product: SceneGraphAdmissionProduct,
            materials: [MaterialKey: MaterialCapability]
        )
        case dedicated(
            product: SceneGraphAdmissionProduct,
            program: SceneEffectStageProgram,
            family: String
        )

        var product: SceneGraphAdmissionProduct {
            switch self {
            case .resolved(let product, _), .dedicated(let product, _, _): product
            }
        }

        var subject: ExactEffectSubject? {
            guard let key = product.graph.effects.first?.key else { return nil }
            switch self {
            case .resolved:
                return .init(key: key, family: "resolved-material")
            case .dedicated(_, _, let family):
                return .init(key: key, family: family)
            }
        }

        /// Projects only the dedicated leaf's execution plan for resource
        /// loading. Resolved material stages own their resources elsewhere.
        var dedicatedExecutionPlan: SceneEffectStageExecutionPlan? {
            guard case .dedicated(_, let program, _) = self else { return nil }
            return program.executionPlan
        }
    }

    final class LayerCapability {
        let layerID: Int
        let admittedProducts: [SceneGraphAdmissionProduct]
        let stages: [StageCapability]
        let pairPlan: SceneLayerFullFramePairPlan
        let materials: [MaterialKey: MaterialCapability]
        let fullFrameExtentPolicy: SceneFullFrameExtentPolicy
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
        let sourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute

        fileprivate let capabilityID = UUID()

        fileprivate init(
            admitted: SceneResolvedMaterialAdmittedLayer,
            stages: [StageCapability],
            materials: [MaterialKey: MaterialCapability]
        ) {
            layerID = admitted.layerID
            admittedProducts = admitted.products
            self.stages = stages
            pairPlan = admitted.pairPlan
            self.materials = materials
            fullFrameExtentPolicy = .standard
            dependencyOwnership = admitted.dependencyOwnership
            sourceRoute = admitted.sourceRoute
        }

        func material(for node: Graph.Node) -> MaterialCapability? {
            materials[.init(effect: node.effect, nodeIndex: node.nodeIndex)]
        }

        func material(effect: Graph.EffectKey, nodeIndex: Int) -> MaterialCapability? {
            materials[.init(effect: effect, nodeIndex: nodeIndex)]
        }

        var effectSubjectsAreConserved: Bool {
            let keys = admittedProducts.flatMap { $0.graph.effects.map(\.key) }
            let subjects = stages.compactMap(\.subject)
            return !keys.isEmpty && Set(keys).count == keys.count
                && subjects.count == keys.count
                && subjects.map(\.key) == keys
        }
    }

    private let ownerID = UUID()
    private let capabilitiesByLayerID: [Int: LayerCapability]
    private let rejectedReasons: [String: Int]
    private let candidateCount: Int
    private let variantLimit: Int

    init(
        admissionCandidates: [
            SceneResolvedMaterialExecutionCapabilityAdmission.Candidate
        ],
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        dynamicProducers: DynamicProducerCatalog = .empty,
        assetFormatFacts: [String: Int] = [:],
        dedicatedStageFamilies: [Graph.EffectKey: String] = [:],
        dedicatedLeafKeys: Set<Graph.EffectKey> = [],
        dedicatedGraphStageKeys: Set<Graph.EffectKey> = [],
        dedicatedFullFrameComposeStageKeys: Set<Graph.EffectKey> = [],
        maximumVariantsPerMaterial: Int = 16
    ) {
        let demandIssues = Set(materialCatalog.resourceDemandIssues.map(\.key))
        candidateCount = admissionCandidates.count
        variantLimit = maximumVariantsPerMaterial
        var accepted: [Int: LayerCapability] = [:]
        var rejected: [String: Int] = [:]
        for candidate in admissionCandidates {
            switch candidate.result {
            case let .failure(failure):
                rejected[failure.code, default: 0] += 1
            case let .success(admitted):
                switch Self.compileProgramFirstStages(
                    admitted,
                    materialCatalog: materialCatalog,
                    demandIssueKeys: demandIssues,
                    dynamicProducers: dynamicProducers,
                    assetFormatFacts: assetFormatFacts,
                    dedicatedStagePrograms: candidate.dedicatedStagePrograms,
                    dedicatedStageFamilies: dedicatedStageFamilies,
                    dedicatedLeafKeys: dedicatedLeafKeys,
                    dedicatedGraphStageKeys: dedicatedGraphStageKeys,
                    dedicatedFullFrameComposeStageKeys:
                        dedicatedFullFrameComposeStageKeys,
                    maximumVariantsPerMaterial: maximumVariantsPerMaterial
                ) {
                case let .failure(failure):
                    rejected[failure.code, default: 0] += 1
                case let .success(compiled):
                    accepted[candidate.layerID] = .init(
                        admitted: admitted,
                        stages: compiled.stages,
                        materials: compiled.materials
                    )
                }
            }
        }
        capabilitiesByLayerID = accepted
        rejectedReasons = rejected
    }

    func claim(layerID: Int) -> ClaimedLayer? {
        guard let capability = capabilitiesByLayerID[layerID] else { return nil }
        return .init(
            token: .init(
                ownerID: ownerID,
                capabilityID: capability.capabilityID,
                layerID: layerID
            ),
            layerID: layerID
        )
    }

    func resolve(_ token: Token) -> LayerCapability? {
        guard token.ownerID == ownerID,
              let capability = capabilitiesByLayerID[token.layerID],
              token.capabilityID == capability.capabilityID else { return nil }
        return capability
    }

    func runtimeDispositionOwnership(
        token: Token,
        subjects: [ExactEffectSubject]
    ) -> RuntimeDispositionOwnership? {
        guard let capability = resolve(token),
              capability.effectSubjectsAreConserved else { return nil }
        let expected = capability.stages.compactMap(\.subject)
        let keys = subjects.map(\.key)
        guard !subjects.isEmpty,
              Set(keys).count == keys.count,
              Set(keys) == Set(expected.map(\.key)),
              Dictionary(uniqueKeysWithValues: subjects.map { ($0.key, $0.family) })
                == Dictionary(uniqueKeysWithValues: expected.map { ($0.key, $0.family) }),
              subjects.allSatisfy({ $0.key.layerID == capability.layerID }) else {
            return nil
        }
        return .init(
            layerID: capability.layerID,
            subjects: subjects.sorted {
                if $0.key.effectIndex != $1.key.effectIndex {
                    return $0.key.effectIndex < $1.key.effectIndex
                }
                return $0.key.descriptorID < $1.key.descriptorID
            }
        )
    }

    var runtimeDispositionOwnerships: [RuntimeDispositionOwnership] {
        capabilitiesByLayerID.keys.sorted().compactMap { layerID in
            guard let claim = claim(layerID: layerID),
                  let capability = resolve(claim.token) else { return nil }
            return runtimeDispositionOwnership(
                token: claim.token,
                subjects: capability.stages.compactMap(\.subject)
            )
        }
    }

    var executionLayerIDs: Set<Int> {
        Set(capabilitiesByLayerID.keys)
    }

    /// Dynamic uniforms owned by an admitted resolved graph remain live
    /// property consumers.
    var liveConsumerTargets: Set<SceneDynamicTarget> {
        capabilitiesByLayerID.values.reduce(into: Set<SceneDynamicTarget>()) {
            targets, capability in
            for stage in capability.stages {
                switch stage {
                case .resolved(_, let materials):
                    for material in materials.values {
                        for declaration in material.template.uniformDeclarations {
                            guard case let .dynamic(dynamic) = declaration.value,
                                  dynamic.valueContributors.count == 1,
                                  case .userProperty = dynamic.valueContributors[0]
                            else { continue }
                            targets.insert(dynamic.target)
                        }
                    }
                case .dedicated(_, let program, _):
                    targets.formUnion(program.executionPlan.liveConsumerTargets)
                }
            }
        }
    }

    /// SceneScript value producers must survive when their material stage moves
    /// from the dedicated catalog into the shared Program executor.
    var sceneScriptConsumerTargets: Set<SceneDynamicTarget> {
        capabilitiesByLayerID.values.reduce(into: Set<SceneDynamicTarget>()) {
            targets, capability in
            for stage in capability.stages {
                switch stage {
                case .resolved(_, let materials):
                    for material in materials.values {
                        for declaration in material.template.uniformDeclarations {
                            guard case let .dynamic(dynamic) = declaration.value,
                                  dynamic.valueContributors == [.sceneScript] else {
                                continue
                            }
                            targets.insert(dynamic.target)
                        }
                    }
                case .dedicated(_, let program, _):
                    targets.formUnion(program.executionPlan.liveConsumerTargets)
                }
            }
        }
    }

    /// Unified owner migration preserves capture demand for every audio stage.
    var hasAudioSpectrumConsumer: Bool {
        capabilitiesByLayerID.values.contains { capability in
            capability.stages.contains { stage in
                switch stage {
                case .resolved(_, let materials):
                    return materials.values.contains { $0.variants.hasAudioSpectrumConsumer }
                case .dedicated(_, let program, _):
                    let plan = program.executionPlan
                    return plan.shake?.audio != nil || plan.pulse?.audio != nil || plan.workshopAudioBars != nil
                }
            }
        }
    }

    var reportLines: [String] {
        var result = [
            "resolved material execution capabilities: schema=layer-graph-capability-v1"
                + " candidates=\(candidateCount)"
                + " accepted=\(capabilitiesByLayerID.count)"
                + " rejected=\(rejectedReasons.values.reduce(0, +))"
                + " variantLimit=\(variantLimit)"
        ]
        result += rejectedReasons.keys.sorted().map {
            "resolved material execution capability rejection: \($0)"
                + " count=\(rejectedReasons[$0] ?? 0)"
        }
        result += capabilitiesByLayerID.keys.sorted().map { layerID in
            guard let dependency = capabilitiesByLayerID[layerID]?
                .dependencyOwnership else {
                return "resolved material execution capability: schema=layer-graph-route-v1"
                    + " layer=\(layerID) status=accepted"
                    + " dependency=missing dependencyReferences=0"
            }
            return "resolved material execution capability: schema=layer-graph-route-v1"
                + " layer=\(layerID) status=accepted"
                + " dependency=\(dependency.reportKind)"
                + " dependencyReferences=\(dependency.referenceCount)"
        }
        return result
    }

    /// This launch-time gate is intentionally no broader than Finalizer's
    /// per-frame policy. It prevents a predictable post-claim failure from
    /// preventing duplicate execution ownership.
    static func dynamicUniformsAreExecutable(
        _ template: Template,
        node: Graph.Node,
        producers: DynamicProducerCatalog
    ) -> Bool {
        for declaration in template.uniformDeclarations {
            guard case let .dynamic(dynamic) = declaration.value else { continue }
            guard case let .effectConstant(
                layerID, effectIndex, passIndex, name
            ) = dynamic.target,
                layerID == node.effect.layerID,
                effectIndex == node.effect.effectIndex,
                passIndex == node.instancePassIndex,
                name == declaration.name,
                dynamic.valueContributors.count == 1,
                let contributor = dynamic.valueContributors.first,
                Set(dynamic.controlAttachments).count
                    == dynamic.controlAttachments.count,
                dynamic.controlAttachments.allSatisfy({
                    $0 == .mediaThumbnailAnimationRestart
                        && contributor == .timeline
                }) else { return false }
            switch contributor {
            case let .userProperty(propertyKey):
                guard producers.userProperties.contains(.init(
                    propertyKey: propertyKey,
                    target: dynamic.target
                )) else { return false }
            case .timeline:
                guard producers.timelineTargets.contains(dynamic.target) else {
                    return false
                }
            case .sceneScript:
                guard producers.sceneScriptTargets.contains(dynamic.target) else {
                    return false
                }
            }
        }
        return true
    }

    static func rejection(_ code: String) -> Rejection {
        .init(code: code)
    }
}
