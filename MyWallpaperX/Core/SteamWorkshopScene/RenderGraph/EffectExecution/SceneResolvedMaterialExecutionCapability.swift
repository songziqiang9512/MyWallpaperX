import Foundation

/// Launch-scoped capability catalog compiled from immutable graph-admission
/// products. No secondary renderer route participates in capability ownership.
final class SceneResolvedMaterialExecutionCapabilityCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias MaterialKey = SceneResolvedMaterialRuntimeCatalog.Key
    typealias Template = SceneResolvedMaterialTemplate
    typealias ExactEffectSubject = SceneEffectExactRuntimeSubject

    struct DynamicProducerCatalog {
        typealias UserProperty = SceneDynamicUserPropertyProducer

        let userProperties: Set<UserProperty>
        private(set) var authoredFallbackTargets: Set<SceneDynamicTarget> = []
        let timelineDefinitions: Set<SceneDynamicTargetDefinition>
        private let legacyTimelineTargets: Set<SceneDynamicTarget>
        let sceneScriptTargets: Set<SceneDynamicTarget>

        var timelineTargets: Set<SceneDynamicTarget> {
            timelineDefinitions.isEmpty
                ? legacyTimelineTargets
                : Set(timelineDefinitions.map(\.target))
        }

        init(
            userProperties: Set<UserProperty>,
            authoredFallbackTargets: Set<SceneDynamicTarget> = [],
            timelineTargets: Set<SceneDynamicTarget> = [],
            timelineDefinitions: Set<SceneDynamicTargetDefinition> = [],
            sceneScriptTargets: Set<SceneDynamicTarget>
        ) {
            self.userProperties = userProperties
            self.authoredFallbackTargets = authoredFallbackTargets
            self.timelineDefinitions = timelineDefinitions
            legacyTimelineTargets = timelineDefinitions.isEmpty
                ? timelineTargets : []
            self.sceneScriptTargets = sceneScriptTargets
        }

        static let empty = Self(
            userProperties: [], timelineTargets: [], sceneScriptTargets: []
        )
    }

    struct Rejection: Error {
        struct ProgramFailureAttribution {
            enum SourceRouteFailure {
                case directDrawSourceDependent
                case capturedMainTargetTextureUnsupported

                var code: String {
                    switch self {
                    case .directDrawSourceDependent:
                        "directDrawSourceDependent"
                    case .capturedMainTargetTextureUnsupported:
                        "capturedMainTargetTextureUnsupported"
                    }
                }

                var details: [String] {
                    switch self {
                    case .directDrawSourceDependent:
                        ["transparent-direct-draw-source-dependent"]
                    case .capturedMainTargetTextureUnsupported:
                        ["captured-main-target-program-contract-unproven"]
                    }
                }
            }

            enum Cause {
                case launchEnvelope(
                    SceneResolvedMaterialVariantCache.LaunchEnvelopeFailure
                )
                case sourceRoute(SourceRouteFailure)

                var producer: String {
                    switch self {
                    case .launchEnvelope: "launch-envelope"
                    case .sourceRoute: "source-route"
                    }
                }

                var envelopeKind: String {
                    switch self {
                    case let .launchEnvelope(failure): failure.kind.rawValue
                    case .sourceRoute: "none"
                    }
                }

                var phase: String {
                    switch self {
                    case let .launchEnvelope(.material(failure)):
                        failure.phase.rawValue
                    case .launchEnvelope(.capacity): "none"
                    case .sourceRoute: "source-route"
                    }
                }

                var code: String {
                    switch self {
                    case let .launchEnvelope(.material(failure)):
                        failure.code.rawValue
                    case .launchEnvelope(.capacity): "none"
                    case let .sourceRoute(failure): failure.code
                    }
                }

                var slot: Int? {
                    guard case let .launchEnvelope(.material(failure)) = self
                    else { return nil }
                    return failure.slot
                }

                var details: [String] {
                    switch self {
                    case let .launchEnvelope(.material(failure)):
                        failure.boundedDetails
                    case .launchEnvelope(.capacity): []
                    case let .sourceRoute(failure): failure.details
                    }
                }
            }

            let effect: Graph.EffectKey
            let nodeIndex: Int
            let materialPath: String
            let materialPassID: String
            let shaderPath: String
            let reasonCode: String
            let cause: Cause

            var reportLine: String {
                let details = Self.detailsToken(cause.details)
                return [
                    "resolved material execution capability program rejection:",
                    "schema=program-failure-attribution-v1",
                    "layer=\(effect.layerID)",
                    "effectOrdinal=\(effect.effectIndex)",
                    "effectDescriptor=\(Self.token(effect.descriptorID))",
                    "node=\(nodeIndex)",
                    "material=\(Self.token(materialPath))",
                    "materialPass=\(Self.token(materialPassID))",
                    "shader=\(Self.token(shaderPath))",
                    "reason=\(reasonCode)",
                    "producer=\(cause.producer)",
                    "envelope=\(cause.envelopeKind)",
                    "phase=\(cause.phase)",
                    "code=\(cause.code)",
                    "slot=\(cause.slot.map(String.init) ?? "none")",
                    "details=\(details)",
                ].joined(separator: " ")
            }

            private static func detailsToken(_ details: [String]) -> String {
                details.isEmpty ? "-" : details.map(token).joined(separator: ",")
            }

            private static func token(_ value: String) -> String {
                let allowed = CharacterSet.alphanumerics.union(
                    CharacterSet(charactersIn: "-._~/")
                )
                return value.addingPercentEncoding(
                    withAllowedCharacters: allowed
                ) ?? "<invalid>"
            }
        }

        let code: String
        let programFailureAttribution: ProgramFailureAttribution?

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

    struct SceneBackgroundRequirement: Equatable {
        let layerID: Int
        let effect: Graph.EffectKey
        let nodeIndex: Int
        let slot: Int
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
            materials: [MaterialKey: MaterialCapability],
            activation: SceneResolvedMaterialStageActivationPolicy?
        )
        case visualFailurePassthrough(
            product: SceneGraphAdmissionProduct,
            reasonCode: String
        )
        case initiallyInactivePassthrough(
            product: SceneGraphAdmissionProduct,
            reasonCode: String
        )
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
        let sceneBackgroundRequirement: SceneBackgroundRequirement?
        let graphFramebufferColorRepresentations: [
            Graph.TextureIdentity: SceneShaderColorRepresentation
        ]
        let isVisibleExecutionRoot: Bool
        let isGraphOutputProvider: Bool
        let requiresGraphOutputProvider: Bool

        fileprivate let capabilityID = UUID()

        fileprivate init(
            admitted: SceneResolvedMaterialAdmittedLayer,
            stages: [StageCapability],
            materials: [MaterialKey: MaterialCapability],
            dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
            sceneBackgroundRequirement: SceneBackgroundRequirement?
        ) {
            layerID = admitted.layerID
            admittedProducts = admitted.products
            self.stages = stages
            pairPlan = admitted.pairPlan
            self.materials = materials
            fullFrameExtentPolicy = .standard
            self.dependencyOwnership = dependencyOwnership
            sourceRoute = admitted.sourceRoute
            self.sceneBackgroundRequirement = sceneBackgroundRequirement
            var graphColorRepresentations: [
                Graph.TextureIdentity: SceneShaderColorRepresentation
            ] = [:]
            var hasIdentityConflict = false
            for stage in stages {
                guard case let .resolved(product, materials, _) = stage else {
                    continue
                }
                for (identity, representation) in
                    SceneResolvedMaterialExecutionCapabilityCatalog
                        .independentAlphaSignalTargetRepresentations(
                            product.graph,
                            materials: materials
                        ) {
                    if graphColorRepresentations.updateValue(
                        representation,
                        forKey: identity
                    ) != nil {
                        hasIdentityConflict = true
                    }
                }
            }
            graphFramebufferColorRepresentations = hasIdentityConflict
                ? [:] : graphColorRepresentations
            isVisibleExecutionRoot = admitted.isVisibleExecutionRoot
            isGraphOutputProvider = admitted.isGraphOutputProvider
            requiresGraphOutputProvider = admitted.requiresGraphOutputProvider
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
    private let productAuthorityRejectionReasonsByLayerID: [Int: String]
    private let rejectedReasons: [String: Int]
    private let programFailureAttributions: [
        Rejection.ProgramFailureAttribution
    ]
    private let visualFailurePassthroughReasons: [String: Int]
    private let initiallyInactivePassthroughReasons: [String: Int]
    private let candidateCount: Int
    private let variantLimit: Int

    init(
        admissionCandidates: [
            SceneResolvedMaterialExecutionCapabilityAdmission.Candidate
        ],
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        dynamicProducers: DynamicProducerCatalog = .empty,
        assetFormatFacts: [String: Int] = [:],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:],
        maximumVariantsPerMaterial: Int = 16
    ) {
        let demandIssues = materialCatalog.resourceDemandIssues
        candidateCount = admissionCandidates.count
        variantLimit = maximumVariantsPerMaterial
        var accepted: [Int: LayerCapability] = [:]
        var productAuthorityRejectedByLayerID: [Int: String] = [:]
        var rejected: [String: Int] = [:]
        var programFailures: [Rejection.ProgramFailureAttribution] = []
        var visualFailurePassthroughs: [String: Int] = [:]
        var initiallyInactivePassthroughs: [String: Int] = [:]
        let preparationLock = NSLock()
        var preparations = Array<Result<CompiledStages, Rejection>?>(
            repeating: nil,
            count: admissionCandidates.count
        )
        DispatchQueue.concurrentPerform(iterations: admissionCandidates.count) { index in
            let candidate = admissionCandidates[index]
            guard case let .success(admitted) = candidate.result else { return }
            let result = Self.compileProgramFirstStages(
                admitted,
                materialCatalog: materialCatalog,
                demandIssues: demandIssues,
                dynamicProducers: dynamicProducers,
                assetFormatFacts: assetFormatFacts,
                assetStates: assetStates,
                maximumVariantsPerMaterial: maximumVariantsPerMaterial
            )
            preparationLock.withLock { preparations[index] = result }
        }
        for (index, candidate) in admissionCandidates.enumerated() {
            switch candidate.result {
            case let .failure(failure):
                rejected[failure.code, default: 0] += 1
                if failure.code == "material-generic-owner-revoked" {
                    productAuthorityRejectedByLayerID[candidate.layerID] = failure.code
                }
            case let .success(admitted):
                guard let preparation = preparations[index] else {
                    rejected["parallel-preparation-missing", default: 0] += 1
                    continue
                }
                switch preparation {
                case let .failure(failure):
                    rejected[failure.code, default: 0] += 1
                    if let attribution = failure.programFailureAttribution {
                        programFailures.append(attribution)
                    }
                    if failure.code == "material-generic-owner-revoked" {
                        productAuthorityRejectedByLayerID[candidate.layerID] = failure.code
                    }
                case let .success(compiled):
                    accepted[candidate.layerID] = .init(
                        admitted: admitted,
                        stages: compiled.stages,
                        materials: compiled.materials,
                        dependencyOwnership: compiled.dependencyOwnership,
                        sceneBackgroundRequirement:
                            compiled.sceneBackgroundRequirement
                    )
                    productAuthorityRejectedByLayerID.removeValue(
                        forKey: candidate.layerID
                    )
                    for reason in compiled.stages.compactMap(
                        \.visualFailureReasonCode
                    ) {
                        visualFailurePassthroughs[reason, default: 0] += 1
                    }
                    for reason in compiled.stages.compactMap(
                        \.initiallyInactivePassthroughReasonCode
                    ) {
                        initiallyInactivePassthroughs[reason, default: 0] += 1
                    }
                }
            }
        }
        Self.retainExecutableDependencyClosure(
            in: &accepted,
            rejected: &rejected
        )
        capabilitiesByLayerID = accepted
        productAuthorityRejectionReasonsByLayerID =
            productAuthorityRejectedByLayerID
        rejectedReasons = rejected
        programFailureAttributions = programFailures
        visualFailurePassthroughReasons = visualFailurePassthroughs
        initiallyInactivePassthroughReasons = initiallyInactivePassthroughs
    }

    /// A hidden graph-output provider has product execution authority only
    /// while it remains reachable from an admitted visible consumer. The
    /// closure is recomputed after Program compilation so a
    /// rejected consumer cannot leave an orphan provider transaction that has
    /// no named-target reservation and would otherwise drop the whole frame.
    private static func retainExecutableDependencyClosure(
        in accepted: inout [Int: LayerCapability],
        rejected: inout [String: Int]
    ) {
        var didChange = true
        while didChange {
            didChange = false

            let graphProviderLayerIDs = Set(accepted.compactMap { layerID, capability in
                capability.isGraphOutputProvider ? layerID : nil
            })
            let unavailableConsumers = accepted.compactMap { layerID, capability -> Int? in
                guard case let .externalPrimary(binding) =
                        capability.dependencyOwnership,
                      binding.consumerLayerID == layerID,
                      capability.requiresGraphOutputProvider else { return nil }
                return graphProviderLayerIDs.contains(binding.providerLayerID)
                    ? nil : layerID
            }
            if !unavailableConsumers.isEmpty {
                for layerID in unavailableConsumers {
                    accepted.removeValue(forKey: layerID)
                    rejected["dependency-graph-provider-unavailable", default: 0] += 1
                }
                didChange = true
                continue
            }

            var reachable = Set(accepted.compactMap { layerID, capability in
                capability.isVisibleExecutionRoot ? layerID : nil
            })
            var frontier = Array(reachable)
            while let layerID = frontier.popLast() {
                guard let capability = accepted[layerID],
                      case let .externalPrimary(binding) =
                        capability.dependencyOwnership,
                      let provider = accepted[binding.providerLayerID],
                      provider.isGraphOutputProvider,
                      reachable.insert(binding.providerLayerID).inserted else {
                    continue
                }
                frontier.append(binding.providerLayerID)
            }
            let unreachableProviders = accepted.compactMap {
                layerID, capability -> Int? in
                capability.isGraphOutputProvider && !reachable.contains(layerID)
                    ? layerID : nil
            }
            if !unreachableProviders.isEmpty {
                for layerID in unreachableProviders {
                    accepted.removeValue(forKey: layerID)
                    rejected["dependency-graph-provider-unreachable", default: 0] += 1
                }
                didChange = true
            }
        }
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

    func productAuthorityRejectionReason(layerID: Int) -> String? {
        productAuthorityRejectionReasonsByLayerID[layerID]
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

    var admittedResolvedMaterialReferences: Set<SceneDependencyRenderPlan.Reference> {
        capabilitiesByLayerID.values.reduce(into: []) { result, capability in
            guard case let .externalPrimary(binding) =
                    capability.dependencyOwnership else { return }
            for slot in binding.referenceSlots {
                result.insert(.init(
                    consumerLayerID: binding.consumerLayerID,
                    providerLayerID: binding.providerLayerID,
                    slot: slot,
                    variant: .primary
                ))
            }
        }
    }

    var sceneBackgroundLayerIDs: Set<Int> {
        Set(capabilitiesByLayerID.values.compactMap {
            $0.sceneBackgroundRequirement?.layerID
        })
    }

    var launchPipelineWarmupCapabilities: [LayerCapability] {
        capabilitiesByLayerID.keys.sorted().compactMap {
            capabilitiesByLayerID[$0]
        }
    }

    /// Dynamic uniforms owned by an admitted resolved graph remain live
    /// property consumers.
    var liveConsumerTargets: Set<SceneDynamicTarget> {
        capabilitiesByLayerID.values.reduce(into: Set<SceneDynamicTarget>()) {
            targets, capability in
            for stage in capability.stages {
                switch stage {
                case .resolved(_, let materials, let activation):
                    targets.formUnion(activation?.liveConsumerTargets ?? [])
                    for material in materials.values {
                        for declaration in material.template.uniformDeclarations {
                            guard case let .dynamic(dynamic) = declaration.value,
                                  dynamic.valueContributors.count == 1,
                                  case .userProperty = dynamic.valueContributors[0]
                            else { continue }
                            targets.insert(dynamic.target)
                        }
                    }
                case .visualFailurePassthrough, .initiallyInactivePassthrough:
                    break
                }
            }
        }
    }

    /// SceneScript value producers remain live through the shared Program executor.
    var sceneScriptConsumerTargets: Set<SceneDynamicTarget> {
        capabilitiesByLayerID.values.reduce(into: Set<SceneDynamicTarget>()) {
            targets, capability in
            for stage in capability.stages {
                switch stage {
                case .resolved(_, let materials, _):
                    for material in materials.values {
                        for declaration in material.template.uniformDeclarations {
                            guard case let .dynamic(dynamic) = declaration.value,
                                  dynamic.valueContributors == [.sceneScript] else {
                                continue
                            }
                            targets.insert(dynamic.target)
                        }
                    }
                case .visualFailurePassthrough, .initiallyInactivePassthrough:
                    break
                }
            }
        }
    }

    /// Unified owner migration preserves capture demand for every audio stage.
    var hasAudioSpectrumConsumer: Bool {
        capabilitiesByLayerID.values.contains { capability in
            capability.stages.contains { stage in
                switch stage {
                case .resolved(_, let materials, _):
                    return materials.values.contains { $0.variants.hasAudioSpectrumConsumer }
                case .visualFailurePassthrough, .initiallyInactivePassthrough:
                    return false
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
        result += programFailureAttributions.map(\.reportLine)
        result += visualFailurePassthroughReasons.keys.sorted().map {
            "resolved material execution capability fallback:"
                + " state=prefer-generic outcome=effect-local-passthrough"
                + " reason=\($0)"
                + " count=\(visualFailurePassthroughReasons[$0] ?? 0)"
        }
        result += initiallyInactivePassthroughReasons.keys.sorted().map {
            "resolved material execution capability passthrough:"
                + " scope=startup-property-inactive outcome=previous-current"
                + " reason=\($0)"
                + " count=\(initiallyInactivePassthroughReasons[$0] ?? 0)"
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
        result += capabilitiesByLayerID.keys.sorted().compactMap { layerID in
            guard let requirement = capabilitiesByLayerID[layerID]?
                .sceneBackgroundRequirement else { return nil }
            return "resolved material scene background:"
                + " schema=scene-background-provider-v1"
                + " layer=\(layerID)"
                + " effect=\(requirement.effect.effectIndex)"
                + " node=\(requirement.nodeIndex)"
                + " slot=\(requirement.slot)"
                + " mode=same-frame-main-target"
        }
        return result
    }

    /// This launch-time gate is intentionally no broader than Finalizer's
    /// per-frame policy. It prevents a predictable post-claim failure from
    /// preventing duplicate execution ownership.
    static func dynamicUniformExecutionRejection(
        _ template: Template,
        node: Graph.Node,
        producers: DynamicProducerCatalog
    ) -> Rejection? {
        for declaration in template.uniformDeclarations {
            guard case let .dynamic(dynamic) = declaration.value else { continue }
            guard case let .effectConstant(
                layerID, effectIndex, passIndex, name
            ) = dynamic.target,
                layerID == node.effect.layerID,
                effectIndex == node.effect.effectIndex,
                passIndex == node.instancePassIndex,
                name == declaration.name else {
                return rejection("dynamic-uniform-unavailable")
            }
            let hasProducer: (Template.DynamicUniformSource) -> Bool = { contributor in
                switch contributor {
                case let .userProperty(propertyKey):
                    return soleUserPropertyProducerMatches(
                        propertyKey, dynamic: dynamic, producers: producers
                    )
                case .timeline:
                    return timelineDefinitionMatches(
                        dynamic,
                        producers: producers
                    )
                case .sceneScript:
                    return producers.sceneScriptTargets.contains(dynamic.target)
                }
            }
            let hasMismatchedProducerIdentity: (
                Template.DynamicUniformSource
            ) -> Bool = { contributor in
                switch contributor {
                case let .userProperty(propertyKey):
                    return producers.userProperties.contains {
                        $0.propertyKey == propertyKey && $0.target != dynamic.target
                    }
                case .timeline, .sceneScript:
                    return false
                }
            }
            if dynamic.valueContributors.isEmpty {
                guard dynamic.authoredFallback != nil,
                      dynamic.scriptAttachments == [.unproven] else {
                    return rejection("dynamic-uniform-unavailable")
                }
                return rejection("material-dynamic-uniform-script-attachment-unproven")
            }
            guard dynamic.valueContributors.count == 1 else {
                guard dynamic.scriptAttachments.isEmpty,
                      !dynamic.valueContributors.contains(
                          where: hasMismatchedProducerIdentity
                      ) else {
                    return rejection("dynamic-uniform-unavailable")
                }
                guard dynamic.valueContributors.allSatisfy(hasProducer) else {
                    return rejection(
                        "material-dynamic-uniform-contributor-producer-unavailable"
                    )
                }
                return rejection("material-dynamic-uniform-contributor-policy")
            }
            guard let contributor = dynamic.valueContributors.first else {
                return rejection("dynamic-uniform-unavailable")
            }
            if !hasProducer(contributor) {
                if hasAuthoredUserPropertyFallback(
                    contributor, dynamic: dynamic, producers: producers
                ) {
                    guard dynamic.scriptAttachments.isEmpty else {
                        return rejection("dynamic-uniform-unavailable")
                    }
                    continue
                }
                guard dynamic.scriptAttachments.isEmpty,
                      !hasMismatchedProducerIdentity(contributor) else {
                    return rejection("dynamic-uniform-unavailable")
                }
                return rejection("material-dynamic-uniform-producer-unavailable")
            }
            if dynamic.scriptAttachments == [.unproven] {
                return rejection("material-dynamic-uniform-script-attachment-unproven")
            }
            guard dynamic.scriptAttachments.isEmpty else {
                return rejection("dynamic-uniform-unavailable")
            }
        }
        return nil
    }

    static func rejection(
        _ code: String,
        programFailureAttribution: Rejection.ProgramFailureAttribution? = nil
    ) -> Rejection {
        .init(
            code: code,
            programFailureAttribution: programFailureAttribution
        )
    }
}
