import Foundation

extension SceneResolvedMaterialExecutionCapabilityCatalog {
    typealias Template = SceneResolvedMaterialTemplate

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

    /// Compiles every authored stage through the shared Program owner.
    static func compileProgramFirstStages(
        _ admitted: SceneResolvedMaterialAdmittedLayer,
        materialCatalog: SceneResolvedMaterialRuntimeCatalog,
        demandIssues: Set<SceneResolvedMaterialRuntimeCatalog.ResourceDemandIssue>,
        dynamicProducers: DynamicProducerCatalog,
        assetFormatFacts: [String: Int],
        assetStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        systemProviderStates: [SceneSystemProviderTextureIdentity: SceneTextureProviderState] = [:],
        maximumVariantsPerMaterial: Int,
        maximumStageWorkers: Int = 1,
        backbufferFormat: SceneGraphRenderTargetPlan.TextureFormat = .rgbaBackbuffer,
        cancellationCheck: (() throws -> Void)? = nil
    ) throws -> Result<CompiledStages, Rejection> {
        // Stage inputs are immutable and do not consume another stage's
        // compiler result. Prepare independently, then fold in authored order
        // so identity checks, the first failure and dependency ownership keep
        // exactly one deterministic authority.
        let workers = min(max(maximumStageWorkers, 1), admitted.products.count)
        let resultLock = NSLock()
        var preparationError: Error?
        var programResults = Array<(
            topologies: Set<StageCapability.PassthroughTopology>,
            result: Result<CompiledStages, Rejection>
        )?>(
            repeating: nil, count: admitted.products.count
        )
        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            for index in stride(from: worker, to: admitted.products.count, by: workers) {
                do {
                    try resultLock.withLock {
                        if let preparationError { throw preparationError }
                        try cancellationCheck?()
                    }
                    let product = admitted.products[index]
                    guard let effect = product.graph.effects.first else { continue }
                    let topologies = preparePassthroughTopologies(
                        graph: product.graph,
                        pairStep: admitted.pairPlan.effects.first { $0.effect == effect.key }
                    )
                    let initiallyInactive = admitted.initiallyInactiveEffectKeys.contains(effect.key)
                    // The renderer captures the layer/main target exactly once into
                    // the pair member identified by baseCaptureIdentity. Every later
                    // effect consumes the preceding effect output already resident in
                    // that pair, so it must not be required to prove the original
                    // layer source route again.
                    let stageSourceRoute: SceneResolvedMaterialAdmittedLayer.SourceRoute =
                        effect.input == admitted.pairPlan.baseCaptureIdentity
                            ? admitted.sourceRoute
                            : .capturedLayerTexture
                    let singleStage = SceneResolvedMaterialAdmittedLayer(
                        layerID: admitted.layerID,
                        products: [product],
                        pairPlan: admitted.pairPlan,
                        dependencyOwnership: admitted.dependencyOwnership,
                        initiallyInactiveEffectKeys:
                            initiallyInactive ? [effect.key] : [],
                        sourceRoute: stageSourceRoute,
                        isVisibleExecutionRoot: admitted.isVisibleExecutionRoot,
                        isGraphOutputProvider: admitted.isGraphOutputProvider,
                        terminalReplayBlendMode: admitted.terminalReplayBlendMode
                    )
                    let programResult = try compileStage(
                        singleStage,
                        product: product,
                        passthroughTopologies: topologies,
                        materialCatalog: materialCatalog,
                        demandIssues: demandIssues,
                        dynamicProducers: dynamicProducers,
                        assetFormatFacts: assetFormatFacts,
                        assetStates: assetStates,
                        systemProviderStates: systemProviderStates,
                        maximumVariantsPerMaterial: maximumVariantsPerMaterial,
                        backbufferFormat: backbufferFormat,
                        cancellationCheck: cancellationCheck
                    )
                    resultLock.withLock { programResults[index] = (topologies, programResult) }
                } catch {
                    resultLock.withLock {
                        if preparationError == nil { preparationError = error }
                    }
                    return
                }
            }
        }
        if let preparationError { throw preparationError }
        try cancellationCheck?()
        var stages: [CompiledStages.Stage] = []
        var allMaterials: [MaterialKey: MaterialCapability] = [:]
        var namedInputBindings: [SceneDependencyRenderPlan.Binding] = []
        var internalReferenceCount = 0
        for (index, product) in admitted.products.enumerated() {
            guard let effect = product.graph.effects.first else {
                return .failure(rejection("stage-effect-identity-missing"))
            }
            let initiallyInactive = admitted.initiallyInactiveEffectKeys
                .contains(effect.key)
            guard let preparation = programResults[index] else {
                return .failure(rejection("execution-stage-conservation"))
            }
            let passthroughTopologies = preparation.topologies
            switch preparation.result {
            case let .success(compiled):
                guard compiled.stages.count == 1,
                      case .resolved = compiled.stages[0].execution,
                      Set(allMaterials.keys).isDisjoint(with: compiled.materials.keys)
                else { return .failure(rejection("material-identity-duplicate")) }
                let expectedVisibilityTarget = SceneDynamicTarget
                    .effectVisibility(
                        layerID: effect.key.layerID,
                        effectIndex: effect.key.effectIndex
                    )
                if initiallyInactive,
                   compiled.stages[0].execution.activationPolicy?
                    .effectVisibilityTarget != expectedVisibilityTarget {
                    guard initiallyInactiveStageMayPassthrough(
                        product,
                        passthroughTopologies: passthroughTopologies
                    ) else {
                        return .failure(rejection(
                            "initially-inactive-stage-passthrough-unsafe"
                        ))
                    }
                    stages.append((
                        product: product,
                        execution: .initiallyInactivePassthrough(
                            reasonCode: "initially-inactive-property-stage-passthrough"
                        ),
                        passthroughTopologies: passthroughTopologies
                    ))
                    continue
                }
                switch preparedNamedInputs(
                    stage: compiled.stages[0],
                    ownership: admitted.dependencyOwnership,
                    candidates: admitted.potentialExternalPrimaryBindings,
                    layerID: admitted.layerID
                ) {
                case let .success(inputs):
                    namedInputBindings.append(contentsOf: inputs.bindings)
                    internalReferenceCount += inputs.internalReferenceCount
                case let .failure(failure):
                    if initiallyInactive {
                        guard initiallyInactiveStageMayPassthrough(
                            product, passthroughTopologies: passthroughTopologies
                        ) else { return .failure(failure) }
                        stages.append((product: product,
                            execution: .initiallyInactivePassthrough(
                                reasonCode: "inactive-dependency-preproof-mismatch"),
                            passthroughTopologies: passthroughTopologies))
                    } else {
                        guard visualFailureMayPassthrough(
                            failure, product: product,
                            passthroughTopologies: passthroughTopologies
                        ) else { return .failure(failure) }
                        stages.append((product: product,
                            execution: .visualFailurePassthrough(reasonCode: failure.code),
                            passthroughTopologies: passthroughTopologies))
                    }
                    continue
                }
                stages.append(compiled.stages[0])
                allMaterials.merge(compiled.materials) { current, _ in current }

            case let .failure(programFailure):
                if initiallyInactive {
                    guard initiallyInactiveStageMayPassthrough(
                        product,
                        passthroughTopologies: passthroughTopologies
                    ) else {
                        return .failure(rejection(
                            "initially-inactive-stage-passthrough-unsafe"
                        ))
                    }
                    stages.append((
                        product: product,
                        execution: .initiallyInactivePassthrough(
                            reasonCode: "initially-inactive-property-stage-passthrough"
                        ),
                        passthroughTopologies: passthroughTopologies
                    ))
                    continue
                }
                guard visualFailureMayPassthrough(
                          programFailure,
                          product: product,
                          passthroughTopologies: passthroughTopologies
                      ) else { return .failure(programFailure) }
                stages.append((
                    product: product,
                    execution: .visualFailurePassthrough(
                        reasonCode: programFailure.code
                    ),
                    passthroughTopologies: passthroughTopologies
                ))
            }
        }

        guard !stages.isEmpty,
              stages.count == admitted.products.count else {
            return .failure(rejection("execution-stage-conservation"))
        }
        let dependencyOwnership: SceneResolvedMaterialDependencyOwnership
        // A legacy direct binding owns its precomposite blend. Program inputs
        // otherwise carry raw publications and leave blend semantics to shader.
        if case let .externalPrimary(binding) = admitted.dependencyOwnership,
           !binding.requiresResolvedMaterialProgram,
           namedInputBindings.map(\.slot) == binding.referenceSlots,
           namedInputBindings.allSatisfy({ $0.providerLayerID == binding.providerLayerID }) {
            dependencyOwnership = .externalPrimary(binding)
        } else if namedInputBindings.count == 1, let binding = namedInputBindings.first {
            dependencyOwnership = .externalPrimary(binding)
        } else if !namedInputBindings.isEmpty {
            dependencyOwnership = .externalAggregate(.init(
                consumerLayerID: admitted.layerID, bindings: namedInputBindings))
        } else if internalReferenceCount > 0 {
            dependencyOwnership = .graphInternal(referenceCount: internalReferenceCount)
        } else {
            dependencyOwnership = .none
        }
        let background: SceneBackgroundRequirement?
        switch sceneBackgroundRequirement(
            admitted: admitted,
            stages: stages
        ) {
        case let .success(value):
            background = value
        case let .failure(failure):
            return .failure(failure)
        }
        return .success(.init(
            stages: stages,
            materials: allMaterials,
            dependencyOwnership: dependencyOwnership,
            sceneBackgroundRequirement: background
        ))
    }

    private static func initiallyInactiveStageMayPassthrough(
        _ product: SceneGraphAdmissionProduct,
        passthroughTopologies: Set<StageCapability.PassthroughTopology>
    ) -> Bool {
        product.clearFunctions.functions.isEmpty
            && (passthroughTopologies.contains(.dependencyStage)
                || passthroughTopologies.contains(.preEncodeGraph))
    }

    /// Missing prepared inputs and launch-time visual failures discard the
    /// complete effect candidate. Live target, state and lifecycle failures
    /// remain hard rejections; no partial authored result is published.
    /// Besides the pair-only compose shape, this admits any framebuffer graph
    /// already accepted by the shared target planner. Because failure happens
    /// before authored commands encode, the executor can discard the complete
    /// candidate and retain only the effect-entry current and committed history.
    private static func visualFailureMayPassthrough(
        _ failure: Rejection,
        product: SceneGraphAdmissionProduct,
        passthroughTopologies: Set<StageCapability.PassthroughTopology>
    ) -> Bool {
        guard product.clearFunctions.functions.isEmpty else { return false }
        let ordinaryVisualFailure = [
            "dependency-stage-reference-unavailable",
            "dependency-stage-reference-unsupported",
            "material-optional-named-fallback-unproven",
            "material-generic-owner-revoked",
            "material-variant-envelope-frontend",
            "material-variant-envelope-shader-preparation",
            "material-variant-envelope-color-contract",
            "material-variant-envelope-sampler-schema",
            "material-variant-envelope-uniform-schema",
            "material-variant-envelope-animated-frame-metadata",
            "material-variant-envelope-texture-purpose",
            "material-dynamic-uniform-contributor-policy",
            "material-dynamic-uniform-contributor-producer-unavailable",
            "material-dynamic-uniform-script-attachment-unproven",
            "material-dynamic-uniform-producer-unavailable",
        ].contains(failure.code)
        let framebufferPreparationLimitation = product.graph.renderTargets
            .isEmpty == false
            && failure.programFailureAttribution.map { attribution in
                guard case let .launchEnvelope(.material(materialFailure)) =
                        attribution.cause else { return false }
                return materialFailure.phase == .preparation
                    && materialFailure.code == .samplerInternalTargetUnsupported
            } == true
        // No Program has encoded yet. An attributed missing launch binding
        // can discard the complete effect candidate under the same topology
        // proof below; reference, identity and live frame failures cannot.
        let launchTextureBindingLimitation = failure.programFailureAttribution
            .map { attribution in
                guard case let .launchEnvelope(.material(materialFailure)) =
                        attribution.cause,
                      materialFailure.phase == .texture,
                      materialFailure.code == .textureBindingInvalid,
                      let slot = materialFailure.slot,
                      (0 ..< 8).contains(slot) else { return false }
                return true
            } == true
        return (ordinaryVisualFailure || framebufferPreparationLimitation
            || launchTextureBindingLimitation)
            && (passthroughTopologies.contains(.dependencyStage)
                || passthroughTopologies.contains(.preEncodeGraph))
    }

    /// Projects the Program's actual named reads onto prepared source carriers.
    /// An unavailable operation contributes no provider demand to the layer.
    private static func preparedNamedInputs(
        stage: CompiledStages.Stage,
        ownership: SceneResolvedMaterialDependencyOwnership,
        candidates: [SceneDependencyRenderPlan.Binding],
        layerID: Int
    ) -> Result<(bindings: [SceneDependencyRenderPlan.Binding], internalReferenceCount: Int), Rejection> {
        let dependencies: [ResolvedExternalDependency]
        switch resolvedExternalDependencies(in: stage) {
        case .none: return .success(([], 0))
        case .invalid: return .failure(rejection("dependency-stage-reference-unsupported"))
        case let .exact(value): dependencies = value
        }
        let external = dependencies.filter { $0.providerLayerID != layerID }
        let internalReferenceCount = dependencies.count - external.count
        let existing: [SceneDependencyRenderPlan.Binding]
        switch ownership {
        case let .externalPrimary(binding): existing = [binding]
        case let .externalAggregate(aggregate): existing = aggregate.bindings
        case .none, .graphInternal: existing = []
        }
        let available = candidates + existing
        var result: [SceneDependencyRenderPlan.Binding] = []
        for dependency in external {
            guard let source = available.first(where: {
                $0.consumerLayerID == layerID
                    && $0.providerLayerID == dependency.providerLayerID
                    && $0.referenceSlots.contains(dependency.slot)
            }) else { return .failure(rejection("dependency-stage-reference-unavailable")) }
            result.append(.init(
                consumerLayerID: layerID, providerLayerID: source.providerLayerID,
                slot: dependency.slot, blendMode: 0, kind: source.kind,
                requiresForwardCapture: source.requiresForwardCapture,
                requiresResolvedMaterialProgram: true))
        }
        return .success((result, internalReferenceCount))
    }
}
