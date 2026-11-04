import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    struct Rejection: Error {
        struct ProgramFailureAttribution {
            enum SourceRouteFailure {
                case directDrawSourceDependent

                var code: String {
                    "directDrawSourceDependent"
                }

                var details: [String] {
                    ["transparent-direct-draw-source-dependent"]
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

    convenience init(
        admissionCandidates: [
            SceneResolvedMaterialExecutionCapabilityAdmission.Candidate
        ],
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        dynamicProducers: DynamicProducerCatalog = .empty,
        assetFormatFacts: [String: Int] = [:],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState] = [:],
        systemProviderStates: [SceneSystemProviderTextureIdentity: SceneTextureProviderState] = [:],
        maximumVariantsPerMaterial: Int = 16,
        dynamicVisibleRootLayerIDs: Set<Int> = [],
        backbufferFormat: SceneGraphRenderTargetPlan.TextureFormat = .rgbaBackbuffer,
        cancellationCheck: (() throws -> Void)? = nil
    ) throws {
        let ownerID = UUID()
        let demandIssues = materialCatalog.resourceDemandIssues
        let candidateCount = admissionCandidates.count
        let variantLimit = maximumVariantsPerMaterial
        var accepted: [Int: LayerCapability] = [:]
        var productAuthorityRejectedByLayerID: [Int: String] = [:]
        var rejected: [String: Int] = [:]
        var programFailures: [Rejection.ProgramFailureAttribution] = []
        var visualFailurePassthroughs: [String: Int] = [:]
        var initiallyInactivePassthroughs: [String: Int] = [:]
        let preparationLock = NSLock()
        var preparationError: Error?
        var preparations = Array<Result<CompiledStages, Rejection>?>(
            repeating: nil,
            count: admissionCandidates.count
        )
        let admittedIndices = admissionCandidates.indices.filter {
            if case .success = admissionCandidates[$0].result { return true }
            return false
        }
        // Share one bounded launch budget across layers and their stages.
        // A single effect-heavy layer can use idle preparation capacity;
        // nested preparation never multiplies the total worker budget.
        let workerBudget = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
#if DEBUG
        SceneResolvedMaterialVariantCompileProfile.reset()
#endif
        let layerWorkers = min(workerBudget, admittedIndices.count)
        DispatchQueue.concurrentPerform(iterations: layerWorkers) { worker in
            let stageWorkers = workerBudget / layerWorkers
                + (worker < workerBudget % layerWorkers ? 1 : 0)
            for offset in stride(from: worker, to: admittedIndices.count, by: layerWorkers) {
                do {
                    try preparationLock.withLock {
                        if let preparationError { throw preparationError }
                        try cancellationCheck?()
                    }
                    let index = admittedIndices[offset]
                    guard case let .success(admitted) = admissionCandidates[index].result else {
                        continue
                    }
                    let result = try Self.compileProgramFirstStages(
                        admitted,
                        materialCatalog: materialCatalog,
                        demandIssues: demandIssues,
                        dynamicProducers: dynamicProducers,
                        assetFormatFacts: assetFormatFacts,
                        assetStates: assetStates,
                        systemProviderStates: systemProviderStates,
                        maximumVariantsPerMaterial: maximumVariantsPerMaterial,
                        maximumStageWorkers: stageWorkers,
                        backbufferFormat: backbufferFormat,
                        cancellationCheck: cancellationCheck
                    )
                    preparationLock.withLock { preparations[index] = result }
                } catch {
                    preparationLock.withLock {
                        if preparationError == nil { preparationError = error }
                    }
                    return
                }
            }
        }
        // concurrentPerform joins every entered worker before cancellation
        // escapes. Never fold a cancelled partial result into visual failure.
        if let preparationError { throw preparationError }
        try cancellationCheck?()
        for (index, candidate) in admissionCandidates.enumerated() {
            switch candidate.result {
            case let .failure(failure):
                rejected[failure.code, default: 0] += 1
#if DEBUG
                NSLog(
                    "MWX DEBUG SCENE: phase=capability-admission layer=%d outcome=rejected-by-admission reason=%@",
                    candidate.layerID,
                    failure.code
                )
#endif
                if failure.code == "material-generic-owner-revoked" {
                    productAuthorityRejectedByLayerID[candidate.layerID] = failure.code
                }
            case let .success(admitted):
                guard let preparation = preparations[index] else {
                    rejected["parallel-preparation-missing", default: 0] += 1
#if DEBUG
                    NSLog(
                        "MWX DEBUG SCENE: phase=capability-admission layer=%d outcome=rejected-by-preparation reason=parallel-preparation-missing",
                        candidate.layerID
                    )
#endif
                    continue
                }
                switch preparation {
                case let .failure(failure):
                    rejected[failure.code, default: 0] += 1
#if DEBUG
                    NSLog(
                        "MWX DEBUG SCENE: phase=capability-admission layer=%d outcome=rejected-by-preparation reason=%@",
                        candidate.layerID,
                        failure.code
                    )
#endif
                    if let attribution = failure.programFailureAttribution {
                        programFailures.append(attribution)
                    }
                    if failure.code == "material-generic-owner-revoked" {
                        productAuthorityRejectedByLayerID[candidate.layerID] = failure.code
                    }
                case let .success(compiled):
                    var directDrawGeometry: FrameInputContract.DirectDrawGeometryBinding?
                    var directDrawGeometryFallback = admitted.directDrawGeometryFallback
                    if let role = admitted.directDrawGeometryRole {
                        let key = MaterialKey(effect: role.effect, nodeIndex: role.nodeIndex)
                        if let material = compiled.materials[key],
                           material.variants.launchEnvelopeSupportsAuthoredQuadGeometry {
                            if let points = material.variants.directDrawPointBindings(
                                materialKeys: role.materialKeys
                            ) {
                                directDrawGeometry = .init(sourceMaterialKey: key, pointBindings: points)
                            } else {
                                directDrawGeometryFallback = .pointBindingsUnproven
                            }
                        } else {
                            directDrawGeometryFallback = .vertexInputUnqualified
                        }
                    }
                    accepted[candidate.layerID] = .init(
                        admitted: admitted,
                        stages: compiled.stages,
                        materials: compiled.materials,
                        dependencyOwnership: compiled.dependencyOwnership,
                        sceneBackgroundRequirement:
                            compiled.sceneBackgroundRequirement,
                        directDrawGeometry: directDrawGeometry,
                        directDrawGeometryFallback: directDrawGeometryFallback
                    )
                    productAuthorityRejectedByLayerID.removeValue(
                        forKey: candidate.layerID
                    )
                    for reason in compiled.stages.compactMap({ $0.execution.visualFailureReasonCode }) {
                        visualFailurePassthroughs[reason, default: 0] += 1
                    }
                    for reason in compiled.stages.compactMap({ $0.execution.initiallyInactivePassthroughReasonCode }) {
                        initiallyInactivePassthroughs[reason, default: 0] += 1
                    }
                }
            }
        }
        Self.retainExecutableDependencyClosure(
            in: &accepted,
            rejected: &rejected,
            staticModelGraphOutputProviderLayerIDs: Set(
                admissionCandidates.compactMap { candidate in
                    guard case let .success(admitted) = candidate.result,
                          admitted.isStaticModelGraphOutputPreparationRoot
                    else { return nil }
                    return admitted.layerID
                }
            )
        )
#if DEBUG
        SceneResolvedMaterialVariantCompileProfile.logSummaryIfMeasured()
#endif
        let audioConsumerLayerIDs = Set(accepted.compactMap { layerID, capability in
            capability.stages.contains { stage in
                guard case let .resolved(materials, _) = stage.execution else { return false }
                return materials.values.contains { $0.variants.hasAudioSpectrumConsumer }
            } ? layerID : nil
        })
        var providerConsumers: [SceneSystemProviderTextureIdentity: Set<Int>] = [:]
        for (layerID, capability) in accepted {
            for stage in capability.stages {
                guard case let .resolved(materials, _) = stage.execution else { continue }
                for key in materials.keys {
                    for provider in materialCatalog.systemProviderDemandsByMaterial[key] ?? [] {
                        providerConsumers[provider, default: []].insert(layerID)
                    }
                }
            }
        }
        self.init(
            ownerID: ownerID,
            capabilitiesByLayerID: accepted,
            audioConsumerLayerIDs: audioConsumerLayerIDs,
            systemProviderConsumerLayerIDs: providerConsumers,
            productAuthorityRejectionReasonsByLayerID: productAuthorityRejectedByLayerID,
            dynamicVisibleRootLayerIDs: dynamicVisibleRootLayerIDs,
            reportLines: Self.prepareReportLines(
                capabilitiesByLayerID: accepted,
                candidateCount: candidateCount,
                variantLimit: variantLimit,
                rejectedReasons: rejected,
                programFailureAttributions: programFailures,
                visualFailurePassthroughReasons: visualFailurePassthroughs,
                initiallyInactivePassthroughReasons: initiallyInactivePassthroughs
            )
        )
    }

    /// A hidden graph-output provider has product execution authority only
    /// while it remains reachable from an admitted visible consumer or an
    /// admitted direct model material demand. Failed or inactive-passthrough
    /// stages contribute no named inputs, so their providers need no transaction.
    private static func retainExecutableDependencyClosure(
        in accepted: inout [Int: LayerCapability],
        rejected: inout [String: Int],
        staticModelGraphOutputProviderLayerIDs: Set<Int>
    ) {
        let graphProviderLayerIDs = Set(accepted.compactMap { layerID, capability in
            capability.isGraphOutputProvider ? layerID : nil
        })
        var reachable = Set(accepted.compactMap { layerID, capability in
            capability.isVisibleExecutionRoot ? layerID : nil
        })
        reachable.formUnion(
            staticModelGraphOutputProviderLayerIDs.intersection(
                graphProviderLayerIDs
            )
        )
        var frontier = Array(reachable)
        while let layerID = frontier.popLast() {
            guard let capability = accepted[layerID] else { continue }
            switch capability.dependencyOwnership {
            case let .externalPrimary(binding):
                guard let provider = accepted[binding.providerLayerID],
                      provider.isGraphOutputProvider,
                      reachable.insert(binding.providerLayerID).inserted else {
                    continue
                }
                frontier.append(binding.providerLayerID)
            case let .externalAggregate(aggregate):
                for providerLayerID in aggregate.providerLayerIDs {
                    guard let provider = accepted[providerLayerID],
                          provider.isGraphOutputProvider,
                          reachable.insert(providerLayerID).inserted else {
                        continue
                    }
                    frontier.append(providerLayerID)
                }
            case .none, .graphInternal:
                continue
            }
        }
        let unreachableProviders = accepted.compactMap {
            layerID, capability -> Int? in
            capability.isGraphOutputProvider && !reachable.contains(layerID)
                ? layerID : nil
        }
        for layerID in unreachableProviders {
            accepted.removeValue(forKey: layerID)
            rejected["dependency-graph-provider-unreachable", default: 0] += 1
        }
    }

    private static func prepareReportLines(
        capabilitiesByLayerID: [Int: LayerCapability],
        candidateCount: Int,
        variantLimit: Int,
        rejectedReasons: [String: Int],
        programFailureAttributions: [Rejection.ProgramFailureAttribution],
        visualFailurePassthroughReasons: [String: Int],
        initiallyInactivePassthroughReasons: [String: Int]
    ) -> [String] {
        var result = [
            "resolved material execution capabilities: schema=layer-graph-capability-v1"
                + " candidates=\(candidateCount)"
                + " accepted=\(capabilitiesByLayerID.count)"
                + " rejected=\(rejectedReasons.values.reduce(0, +))"
                + " variantLimit=\(variantLimit)"
        ]
        result += rejectedReasons.sorted { $0.key < $1.key }.map {
            "resolved material execution capability rejection: \($0.key)"
                + " count=\($0.value)"
        }
        result += programFailureAttributions.map(\.reportLine)
        result += visualFailurePassthroughReasons.sorted { $0.key < $1.key }.map {
            "resolved material execution capability fallback:"
                + " state=prefer-generic outcome=effect-local-passthrough"
                + " reason=\($0.key)"
                + " count=\($0.value)"
        }
        result += initiallyInactivePassthroughReasons.sorted { $0.key < $1.key }.map {
            "resolved material execution capability passthrough:"
                + " scope=startup-property-inactive outcome=previous-current"
                + " reason=\($0.key)"
                + " count=\($0.value)"
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
            guard let capability = capabilitiesByLayerID[layerID],
                  case .authoredCanvasDirectDraw = capability
                    .frameInputContract.emittedOutputGeometrySource else {
                return nil
            }
            if let geometry = capability.frameInputContract.directDrawGeometry {
                return "resolved material output geometry:"
                    + " schema=direct-draw-geometry-v3 layer=\(layerID)"
                    + " extent=authored-quad units=authored-canvas-height anchor=authored-origin"
                    + " sourceEffect=\(geometry.sourceMaterialKey.effect.effectIndex)"
                    + " sourceNode=\(geometry.sourceMaterialKey.nodeIndex)"
                    + " pointUniforms=\(geometry.pointBindings.map(\.field.authoredName).joined(separator: ","))"
                    + " vertexFootprint=identity-mvp capture=transparent-aabb"
            }
            return "resolved material output geometry:"
                + " schema=direct-draw-geometry-v2"
                + " layer=\(layerID)"
                + " extent=authored-canvas-height-square anchor=authored-origin"
                + (capability.frameInputContract.directDrawGeometryFallback.map {
                    " domain=unit-preserved reason=\($0.rawValue)"
                } ?? "")
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
                + " bindings=\(requirement.bindingCount)"
                + " mode=same-frame-main-target"
        }
        return result
    }
}

extension SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability {
    fileprivate convenience init(
        admitted: SceneResolvedMaterialAdmittedLayer,
        stages: [SceneResolvedMaterialExecutionCapabilityCatalog.CompiledStages.Stage],
        materials: [SceneResolvedMaterialKey:
            SceneResolvedMaterialExecutionCapabilityCatalog.MaterialCapability],
        dependencyOwnership: SceneResolvedMaterialDependencyOwnership,
        sceneBackgroundRequirement:
            SceneResolvedMaterialExecutionCapabilityCatalog.SceneBackgroundRequirement?,
        directDrawGeometry: SceneResolvedMaterialFrameInputContract.DirectDrawGeometryBinding?,
        directDrawGeometryFallback: SceneResolvedMaterialFrameInputContract.DirectDrawGeometryFallback?
    ) {
        let capabilityID = UUID()
        let preparedStages: [SceneResolvedMaterialExecutionCapabilityCatalog.StageCapability] = stages.map { stage in
            .init(product: stage.product, execution: stage.execution,
                  passthroughTopologies: stage.passthroughTopologies,
                  preEncodeVisualFailureSlots: dependencyOwnership
                    .preEncodeVisualFailureSlots(in: stage.product.graph))
        }
        let effectKeys = admitted.products.flatMap { $0.graph.effects.map(\.key) }
        let subjects = preparedStages.compactMap(\.subject)
        let effectSubjectsAreConserved = !effectKeys.isEmpty
            && Set(effectKeys).count == effectKeys.count
            && subjects.count == effectKeys.count && subjects.map(\.key) == effectKeys
        let requiresSceneEnvironment = materials.values.contains {
            $0.variants.hasSceneEnvironmentConsumer
        }
        let emittedOutputGeometrySource: SceneResolvedMaterialFrameInputContract
            .EmittedOutputGeometrySource = switch admitted.sourceRoute {
        case .capturedLayerTexture:
            .layerCard
        case .capturedMainTargetTexture:
            .captureGeometry
        case .transparentDirectDraw:
            .authoredCanvasDirectDraw
        }
        let frameInputContract = SceneResolvedMaterialFrameInputContract(
            effectTextureProjectionSource: .emittedOutputGeometry,
            emittedOutputGeometrySource: emittedOutputGeometrySource,
            requiresInvertibleEffectTextureProjection:
                preparedStages.contains { $0.execution.requiresInvertibleEffectTextureProjection },
            directDrawGeometry: directDrawGeometry,
            directDrawGeometryFallback: directDrawGeometryFallback
        )
        var graphColorRepresentations: [
            SceneAuthoredEffectRenderPlan.TextureIdentity: SceneShaderColorRepresentation
        ] = [:]
        var hasIdentityConflict = false
        for stage in preparedStages {
            guard case let .resolved(materials, _) = stage.execution else {
                continue
            }
            for (identity, representation) in
                SceneResolvedMaterialExecutionCapabilityCatalog
                    .independentAlphaSignalTargetRepresentations(
                        stage.product.graph,
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
        let graphFramebufferColorRepresentations = hasIdentityConflict
            ? [:] : graphColorRepresentations
        let simpleColor = Self.simpleColorChainCapabilities(
            admitted: admitted,
            stages: preparedStages,
            materials: materials,
            dependencyOwnership: dependencyOwnership,
            sceneBackgroundRequirement: sceneBackgroundRequirement
        )
        let supportsTerminalMaterialReplay = simpleColor.terminal
            || Self.backgroundAttachmentReplaySupported(
                admitted: admitted, stages: preparedStages, materials: materials,
                dependencyOwnership: dependencyOwnership,
                sceneBackgroundRequirement: sceneBackgroundRequirement)
        self.init(
            capabilityID: capabilityID,
            layerID: admitted.layerID,
            admittedProducts: admitted.products,
            stages: preparedStages,
            pairPlan: admitted.pairPlan,
            materials: materials,
            dependencyOwnership: dependencyOwnership,
            sourceRoute: admitted.sourceRoute,
            sceneBackgroundRequirement: sceneBackgroundRequirement,
            requiresSceneEnvironment: requiresSceneEnvironment,
            frameInputContract: frameInputContract,
            graphFramebufferColorRepresentations: graphFramebufferColorRepresentations,
            isVisibleExecutionRoot: admitted.isVisibleExecutionRoot,
            isGraphOutputProvider: admitted.isGraphOutputProvider,
            supportsSourceSizedSolidEffects: simpleColor.intermediates,
            supportsTerminalMaterialReplay: supportsTerminalMaterialReplay,
            supportsPlacementSpaceTerminalReplay: simpleColor.placement,
            terminalReplayBlendMode: admitted.terminalReplayBlendMode,
            effectSubjectsAreConserved: effectSubjectsAreConserved
        )
    }
}
