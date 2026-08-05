import Foundation

/// Launch-scoped capability catalog compiled from immutable graph-admission
/// products. Strict renderer recovery chains are intentionally not inputs.
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

    private struct Rejection: Error {
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

    final class MaterialCapability {
        let key: MaterialKey
        let template: Template
        let variants: SceneResolvedMaterialVariantCache

        fileprivate init(
            key: MaterialKey,
            template: Template,
            variants: SceneResolvedMaterialVariantCache
        ) {
            self.key = key
            self.template = template
            self.variants = variants
        }
    }

    final class ChainCapability {
        let layerID: Int
        let admittedProducts: [SceneGraphAdmissionProduct]
        let pairPlan: SceneLayerFullFramePairPlan
        let materials: [MaterialKey: MaterialCapability]
        let fullFrameExtentPolicy: SceneFullFrameExtentPolicy
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership

        fileprivate let capabilityID = UUID()

        fileprivate init(
            admitted: SceneResolvedMaterialAdmittedLayer,
            materials: [MaterialKey: MaterialCapability]
        ) {
            layerID = admitted.layerID
            admittedProducts = admitted.products
            pairPlan = admitted.pairPlan
            self.materials = materials
            fullFrameExtentPolicy = .standard
            dependencyOwnership = admitted.dependencyOwnership
        }

        func material(for node: Graph.Node) -> MaterialCapability? {
            materials[.init(effect: node.effect, nodeIndex: node.nodeIndex)]
        }

        func material(effect: Graph.EffectKey, nodeIndex: Int) -> MaterialCapability? {
            materials[.init(effect: effect, nodeIndex: nodeIndex)]
        }

        var effectSubjectsAreConserved: Bool {
            let keys = admittedProducts.flatMap { $0.graph.effects.map(\.key) }
            return !keys.isEmpty && Set(keys).count == keys.count
        }
    }

    private let ownerID = UUID()
    private let capabilitiesByLayerID: [Int: ChainCapability]
    private let rejectedReasons: [String: Int]
    private let candidateCount: Int
    private let variantLimit: Int

    init(
        admissionCandidates: [
            SceneResolvedMaterialExecutionCapabilityAdmission.Candidate
        ],
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        dynamicProducers: DynamicProducerCatalog = .empty,
        maximumVariantsPerMaterial: Int = 16
    ) {
        let demandIssues = Set(materialCatalog.resourceDemandIssues.map(\.key))
        candidateCount = admissionCandidates.count
        variantLimit = maximumVariantsPerMaterial
        var accepted: [Int: ChainCapability] = [:]
        var rejected: [String: Int] = [:]
        for candidate in admissionCandidates {
            switch candidate.result {
            case let .failure(failure):
                rejected[failure.code, default: 0] += 1
            case let .success(admitted):
                switch Self.compileMaterials(
                    admitted,
                    materialCatalog: materialCatalog,
                    demandIssueKeys: demandIssues,
                    dynamicProducers: dynamicProducers,
                    maximumVariantsPerMaterial: maximumVariantsPerMaterial
                ) {
                case let .failure(failure):
                    rejected[failure.code, default: 0] += 1
                case let .success(materials):
                    accepted[candidate.layerID] = .init(
                        admitted: admitted,
                        materials: materials
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

    func resolve(_ token: Token) -> ChainCapability? {
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
        let expected = capability.admittedProducts.flatMap {
            $0.graph.effects.map(\.key)
        }
        let keys = subjects.map(\.key)
        guard !subjects.isEmpty,
              Set(keys).count == keys.count,
              Set(keys) == Set(expected),
              subjects.allSatisfy({
                  $0.key.layerID == capability.layerID
                      && $0.family == "resolved-material"
              }) else { return nil }
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
                subjects: capability.admittedProducts.flatMap { product in
                    product.graph.effects.map {
                        .init(key: $0.key, family: "resolved-material")
                    }
                }
            )
        }
    }

    var reportLines: [String] {
        var result = [
            "resolved material execution capabilities: schema=r4-layer-capability-v2"
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
                return "resolved material execution capability: schema=r4-layer-route-v2"
                    + " layer=\(layerID) status=accepted"
                    + " dependency=missing dependencyReferences=0"
            }
            return "resolved material execution capability: schema=r4-layer-route-v2"
                + " layer=\(layerID) status=accepted"
                + " dependency=\(dependency.reportKind)"
                + " dependencyReferences=\(dependency.referenceCount)"
        }
        return result
    }

    private static func compileMaterials(
        _ admitted: SceneResolvedMaterialAdmittedLayer,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssueKeys: Set<MaterialKey>,
        dynamicProducers: DynamicProducerCatalog,
        maximumVariantsPerMaterial: Int
    ) -> Result<[MaterialKey: MaterialCapability], Rejection> {
        guard (1 ... 256).contains(maximumVariantsPerMaterial) else {
            return .failure(rejection("material-variant-envelope-capacity"))
        }
        var materials: [MaterialKey: MaterialCapability] = [:]
        for product in admitted.products {
            guard let effect = product.graph.effects.first else {
                return .failure(rejection("material-template-unsupported"))
            }
            for node in product.graph.nodes {
                guard case .material = node.kind else { continue }
                let key = MaterialKey(effect: node.effect, nodeIndex: node.nodeIndex)
                guard let template =
                        SceneResolvedMaterialExecutionCapabilityTemplateAdmission.resolve(
                            node: node,
                            effect: effect,
                            key: key,
                            materialCatalog: materialCatalog,
                            demandIssueKeys: demandIssueKeys,
                            existingKeys: Set(materials.keys)
                        ) else {
                    return .failure(rejection("material-template-unsupported"))
                }
                guard let variants = SceneResolvedMaterialVariantCache(
                    template: template,
                    maximumVariantCount: maximumVariantsPerMaterial
                ) else {
                    return .failure(rejection(
                        "material-variant-envelope-sampler-schema"
                    ))
                }
                if case let .failure(failure) = variants.precompileLaunchEnvelope(
                    implicitFramebufferIdentity: effect.input
                ) {
                    SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics
                        .launchEnvelopeFailure(template: template, failure: failure)
                    return .failure(rejection(
                        "material-variant-envelope-\(failure.kind.rawValue)"
                    ))
                }
                guard dynamicUniformsAreExecutable(
                    template,
                    node: node,
                    producers: dynamicProducers
                ) else {
                    return .failure(rejection("dynamic-uniform-unavailable"))
                }
                materials[key] = .init(
                    key: key,
                    template: template,
                    variants: variants
                )
            }
        }
        guard !materials.isEmpty else {
            return .failure(rejection("material-capability-empty"))
        }
        return .success(materials)
    }

    /// This launch-time gate is intentionally no broader than Finalizer's
    /// per-frame policy. It prevents a predictable post-claim failure from
    /// suppressing the still-authoritative legacy route.
    private static func dynamicUniformsAreExecutable(
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

    private static func rejection(_ code: String) -> Rejection {
        .init(code: code)
    }
}
