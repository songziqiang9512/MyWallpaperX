import Metal
import simd

extension SceneResolvedMaterialGraphExecutor {
    func validate(
        capability: SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability,
        leases: [SceneGraphRenderTargetLease],
        materialFunctionTargetsByEffect: [
            Graph.EffectKey: Set<Graph.TextureIdentity>
        ] = [:]
    ) -> Bool {
        let products = capability.admittedProducts
        let pairPlan = capability.pairPlan
        guard !products.isEmpty,
              products.count == pairPlan.effects.count,
              leases.count == products.count,
              pairPlan.layerID == capability.layerID,
              pairPlan.terminalMember == Pair.fixedTerminalMember,
              let first = leases.first,
              first.generation > 0,
              first.fullFramePair.first != first.fullFramePair.second,
              let zero = first.texturesByToken[first.fullFramePair.first],
              let one = first.texturesByToken[first.fullFramePair.second],
              zero === first.table.fullFramePair.first,
              one === first.table.fullFramePair.second else { return false }
        for index in products.indices {
            let graph = products[index].graph
            let step = pairPlan.effects[index]
            let lease = leases[index]
            let targetPlanResult = capability.stages[index].dedicatedExecutionPlan.map {
                SceneGraphRenderTargetPlan.make(
                    executionPlan: $0,
                    graph: graph,
                    inputWidth: lease.table.plan.inputExtent.width,
                    inputHeight: lease.table.plan.inputExtent.height,
                    materialFunctionTargets:
                        materialFunctionTargetsByEffect[step.effect] ?? []
                )
            } ?? SceneGraphRenderTargetPlan.make(
                graph: graph,
                inputRole: index == 0 ? .layerSource : .priorEffectOutput,
                inputWidth: lease.table.plan.inputExtent.width,
                inputHeight: lease.table.plan.inputExtent.height,
                materialFunctionTargets:
                    materialFunctionTargetsByEffect[step.effect] ?? []
            )
            let role: SceneAuthoredEffectInputRole = index == 0
                ? .layerSource : .priorEffectOutput
            guard graph.effects.count == 1,
                  graph.effects.first?.key == step.effect,
                  lease.table.plan.layerID == capability.layerID,
                  lease.table.plan.inputRole == role,
                  lease.table.plan.input == step.inputIdentity,
                  lease.table.plan.output == step.outputIdentity,
                  lease.generation == first.generation,
                  lease.fullFramePair.first == first.fullFramePair.first,
                  lease.fullFramePair.second == first.fullFramePair.second,
                  lease.table.fullFramePair.first === zero,
                  lease.table.fullFramePair.second === one,
                  case let .success(expected) = targetPlanResult,
                  expected.inputRole == role,
                  expected == lease.table.plan,
                  lease.framebufferAllocation.resources.count
                    == lease.table.plan.logicalTargets.count else { return false }
        }
        return true
    }

    func resolveMaterialFunctionInvocations(
        _ requests: [SceneGraphMaterialFunctionInvocationRequest],
        capability: SceneResolvedMaterialExecutionCapabilityCatalog.LayerCapability,
        leases: [SceneGraphRenderTargetLease],
        frameEpoch: UInt64
    ) -> Result<[
        Graph.EffectKey: [SceneGraphClearFunctionRegistry.ClearFunction]
    ], Failure> {
        guard capability.admittedProducts.count == leases.count else {
            return .failure(.functionInvocationTargetUnavailable)
        }
        guard !requests.isEmpty else { return .success([:]) }
        guard frameEpoch > 0 else { return .failure(.functionInvocationStaleFrame) }
        let indexed = Dictionary(grouping: capability.admittedProducts.indices, by: {
            capability.admittedProducts[$0].graph.effects.first?.key
        })
        var resolved: [
            Graph.EffectKey: [SceneGraphClearFunctionRegistry.ClearFunction]
        ] = [:]
        for request in requests {
            guard request.frameEpoch == frameEpoch else {
                return .failure(.functionInvocationStaleFrame)
            }
            guard let matches = indexed[request.effect], matches.count == 1,
                  let index = matches.first else {
                return .failure(.functionInvocationUnknownEffect)
            }
            let product = capability.admittedProducts[index]
            let lease = leases[index]
            guard !request.functionName.isEmpty,
                  request.functionName == request.functionName.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ), let function = product.clearFunctions.function(
                      named: request.functionName
                  ) else {
                return .failure(.functionInvocationUnknownFunction)
            }
            let graphTargets = Set(product.graph.renderTargets.map(\.texture))
            let planTargets = Set(lease.table.plan.logicalTargets.map(\.identity))
            guard !function.targets.isEmpty,
                  function.targets.allSatisfy({ identity in
                      identity.effect == request.effect
                          && identity.kind == .framebuffer
                          && graphTargets.contains(identity)
                          && planTargets.contains(identity)
                          && lease.framebufferAllocation.resources[identity] != nil
                          && lease.texture(for: identity) != nil
                  }) else {
                return .failure(.functionInvocationTargetUnavailable)
            }
            resolved[request.effect, default: []].append(function)
        }
        return .success(resolved)
    }

    func pairTexture(
        lease: SceneGraphRenderTargetLease,
        member: Pair.Member
    ) -> MTLTexture {
        member == .zero
            ? lease.table.fullFramePair.first
            : lease.table.fullFramePair.second
    }

    func pairResource(
        lease: SceneGraphRenderTargetLease,
        identity: Graph.TextureIdentity,
        member: Pair.Member,
        generation: UInt64,
        representation: SceneShaderColorRepresentation
    ) -> SceneFrameTextureResource? {
        guard case let .success(resource) = lease.fullFrameResource(
            for: identity,
            member: member,
            contentGeneration: generation,
            fragmentColorRepresentation: .resolved(representation)
        ) else { return nil }
        return resource
    }

    func prepareHistoryContext(
        _ copies: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy],
        previous: State,
        previousResources: [Graph.TextureIdentity: SceneFrameTextureResource],
        lease: SceneGraphRenderTargetLease,
        effectGeneration: UInt64,
        resetGeneration: UInt64
    ) -> HistoryContext? {
        let preservesPriorState = previous.effectGeneration == effectGeneration
            && previous.resetGeneration == resetGeneration
            && previous.allocationGeneration != nil
        let readable = preservesPriorState ? previous.logicalMapping.filter {
            $0.value.contentGeneration > 0
        } : [:]
        guard preservesPriorState || copies.isEmpty else { return nil }
        if !preservesPriorState {
            guard validPreviousResources(previousResources, state: previous) else {
                return nil
            }
            return .init(
                rehydration: [:],
                commands: [],
                discardsPreviousContent: !previousResources.isEmpty
            )
        }
        if readable.isEmpty {
            guard copies.isEmpty else { return nil }
            return .init(
                rehydration: [:],
                commands: [],
                discardsPreviousContent: false
            )
        }

        let previousDescriptors = previous.authoredResources.mapValues(\.descriptor)
        let nextDescriptors = lease.framebufferAllocation.resources.mapValues(\.descriptor)
        guard Set(previousDescriptors.keys) == Set(nextDescriptors.keys),
              validPreviousResources(previousResources, state: previous) else {
            return nil
        }
        if previousDescriptors != nextDescriptors {
            guard copies.isEmpty else { return nil }
            return .init(
                rehydration: [:],
                commands: [],
                discardsPreviousContent: true
            )
        }

        if previous.allocationGeneration == lease.generation {
            guard copies.isEmpty else { return nil }
            return .init(
                rehydration: [:],
                commands: [],
                discardsPreviousContent: false
            )
        }

        let expectedSources = Set(readable.values.map(\.token))
        let sourceTokens = copies.map(\.sourceToken)
        let targetTokens = copies.map(\.targetToken)
        guard copies.count == expectedSources.count,
              Set(sourceTokens) == expectedSources,
              Set(sourceTokens).count == sourceTokens.count,
              Set(targetTokens).count == targetTokens.count,
              validPreviousResources(
                  previousResources,
                  state: previous,
                  sourceTextures: Dictionary(uniqueKeysWithValues: copies.map {
                      ($0.sourceToken, $0.sourceTexture)
                  })
              ) else { return nil }

        let oldDescriptors = Dictionary(uniqueKeysWithValues:
            previous.authoredResources.values.map { ($0.token, $0.descriptor) }
        )
        let newDescriptors = Dictionary(uniqueKeysWithValues:
            lease.framebufferAllocation.resources.values.map {
                ($0.token, $0.descriptor)
            }
        )
        var rehydration: [State.PhysicalToken: State.PhysicalToken] = [:]
        var commands: [SceneGraphResourcePassEncoder.PreparedCommand] = []
        for copy in copies {
            guard copy.sourceToken != copy.targetToken,
                  oldDescriptors[copy.sourceToken]
                    == newDescriptors[copy.targetToken],
                  lease.texturesByToken[copy.targetToken] === copy.targetTexture,
                  let prepared = resourceEncoder?.prepareCopy(
                      source: copy.sourceTexture,
                      target: copy.targetTexture
                  ), rehydration.updateValue(
                      copy.targetToken,
                      forKey: copy.sourceToken
                  ) == nil else { return nil }
            commands.append(prepared)
        }
        return .init(
            rehydration: rehydration,
            commands: commands,
            discardsPreviousContent: false
        )
    }

    func validPreviousResources(
        _ resources: [Graph.TextureIdentity: SceneFrameTextureResource],
        state: State
    ) -> Bool {
        let readable = state.logicalMapping.filter {
            $0.value.contentGeneration > 0
        }
        guard Set(resources.keys) == Set(readable.keys),
              let allocationGeneration = state.allocationGeneration else {
            return resources.isEmpty && readable.isEmpty
                && state.allocationGeneration == nil
        }
        return resources.allSatisfy { identity, resource in
            guard let versioned = readable[identity],
                  SceneGraphRenderTargetLease.graphSamplingMatches(
                      resource,
                      descriptor: versioned.descriptor
                  ),
                  resource.publication.requestIdentity == .graph(identity),
                  resource.resourceGeneration == versioned.contentGeneration,
                  resource.publication.contentGeneration
                    == versioned.contentGeneration,
                  SceneGraphRenderTargetLease.textureMatches(
                      resource.publication.texture,
                      descriptor: versioned.descriptor
                  ), case let .provider(.graph(generation, token)) =
                    resource.publication.candidate.identity else { return false }
            return generation == allocationGeneration
                && token == versioned.token.rawValue
        }
    }

    func validPreviousResources(
        _ resources: [Graph.TextureIdentity: SceneFrameTextureResource],
        state: State,
        sourceTextures: [State.PhysicalToken: MTLTexture]
    ) -> Bool {
        let readable = state.logicalMapping.filter {
            $0.value.contentGeneration > 0
        }
        guard validPreviousResources(resources, state: state),
              Set(sourceTextures.keys) == Set(readable.values.map(\.token)),
              state.allocationGeneration != nil else { return false }
        return resources.allSatisfy { identity, resource in
            guard let versioned = readable[identity],
                  let texture = sourceTextures[versioned.token],
                  resource.publication.texture === texture,
                  SceneGraphRenderTargetLease.textureMatches(
                      texture, descriptor: versioned.descriptor
                  ) else { return false }
            return true
        }
    }

    func publishRehydratedHistory(
        transition: State.Transition,
        previous: State,
        previousResources: [Graph.TextureIdentity: SceneFrameTextureResource],
        history: HistoryContext,
        lease: SceneGraphRenderTargetLease,
        publications: inout [Graph.TextureIdentity: SceneFrameTextureResource]
    ) -> Bool {
        let readable = transition.transaction.mappingBefore.filter {
            $0.value.contentGeneration > 0
        }
        if history.discardsPreviousContent {
            return readable.isEmpty
        }
        guard Set(readable.keys) == Set(previousResources.keys) else {
            return readable.isEmpty && previousResources.isEmpty
        }
        for (identity, resource) in readable {
            guard let old = previous.logicalMapping[identity],
                  history.rehydration[old.token] == resource.token
                    || (history.rehydration[old.token] == nil
                        && old.token == resource.token),
                  let prior = previousResources[identity],
                  let representation = representation(prior),
                  case let .success(published) = lease.graphResource(
                      for: identity,
                      versionedResource: resource,
                      fragmentColorRepresentation: .resolved(representation)
                  ) else { return false }
            publications[identity] = published
        }
        return true
    }

    func resources(
        matching mapping: [Graph.TextureIdentity: State.VersionedResource],
        from publications: [Graph.TextureIdentity: SceneFrameTextureResource]
    ) -> [Graph.TextureIdentity: SceneFrameTextureResource]? {
        let readable = mapping.filter { $0.value.contentGeneration > 0 }
        var result: [Graph.TextureIdentity: SceneFrameTextureResource] = [:]
        for (identity, versioned) in readable {
            guard let resource = publications[identity],
                  SceneGraphRenderTargetLease.graphSamplingMatches(
                      resource,
                      descriptor: versioned.descriptor
                  ),
                  resource.publication.requestIdentity == .graph(identity),
                  resource.resourceGeneration == versioned.contentGeneration,
                  case let .provider(.graph(_, token)) =
                    resource.publication.candidate.identity,
                  token == versioned.token.rawValue else { return nil }
            result[identity] = resource
        }
        return result
    }

    func historyTokens(
        _ stages: [PreparedStage]
    ) -> [Graph.EffectKey: Set<State.PhysicalToken>]? {
        var result: [Graph.EffectKey: Set<State.PhysicalToken>] = [:]
        for value in stages {
            let identities = value.transition.nextState.historyClosureIdentities
            guard Set(value.persistentResources.keys) == identities else {
                return nil
            }
            if !identities.isEmpty {
                result[value.effect] = Set(value.transition.nextState.logicalMapping
                    .filter { identities.contains($0.key) }
                    .map(\.value.token))
            }
        }
        return result
    }

    func initialization(
        _ reason: State.InitializationReason
    ) -> (clear: SceneGraphRenderTargetPlan.ClearColor,
          representation: SceneShaderColorRepresentation)? {
        let clear: SceneGraphRenderTargetPlan.ClearColor
        switch reason {
        case let .authoredClear(value): clear = value
        case .transparentHistorySeed, .materialFunctionClear:
            clear = .init(red: 0, green: 0, blue: 0, alpha: 0)
        }
        guard clear.red == 0, clear.green == 0,
              clear.blue == 0, clear.alpha == 0 else { return nil }
        return (clear, .premultipliedAlpha)
    }

    func representation(
        _ resource: SceneFrameTextureResource
    ) -> SceneShaderColorRepresentation? {
        guard case let .color(.resolved(value)) =
                resource.publication.candidate.content,
              value != .straightAlpha else { return nil }
        return value
    }

    static func fullTargetMVP(_ target: MTLTexture) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(
            2 / Float(target.width), 2 / Float(target.height), 1, 1
        ))
    }
}

extension SceneResolvedMaterialGraphExecutor.Failure {
    var rawValue: String {
        switch self {
        case .invalidClaim: "invalid-claim"
        case .invalidFrame: "invalid-frame"
        case .invalidLease: "invalid-lease"
        case .stateRejected: "state-rejected"
        case .historyRejected: "history-rejected"
        case .graphPublicationRejected: "graph-publication-rejected"
        case .graphStructureRejected: "graph-structure-rejected"
        case let .materialFinalizerRejected(
            stageIndex, effect, nodeIndex, ordinal, failure
        ):
            "stage-\(stageIndex)-layer-\(effect.layerID)-effect-\(effect.effectIndex)-"
                + "descriptor-\(Self.descriptorDigest(effect.descriptorID))-"
                + "node-\(nodeIndex)-material-\(ordinal)-finalizer-"
                + "\(failure.phase.rawValue)-\(failure.code.rawValue)"
                + Self.detailSuffix(failure.boundedDetails.first)
        case .materialPassEncoderRejected: "material-pass-encoder-rejected"
        case let .materialPassPreparationRejected(
            stageIndex, nodeIndex, ordinal, programKey, failure
        ):
            "stage-\(stageIndex)-node-\(nodeIndex)-material-\(ordinal)-"
                + "program-\(programKey.prefix(12))-pass-\(failure.code)-rejected"
        case .dedicatedLeafRejected(let reason):
            "dedicated-leaf-rejected-\(reason)"
        case .resourceCommandRejected: "resource-command-rejected"
        case .functionInvocationStaleFrame: "function-invocation-stale-frame"
        case .functionInvocationUnknownEffect: "function-invocation-unknown-effect"
        case .functionInvocationUnknownFunction: "function-invocation-unknown-function"
        case .functionInvocationTargetUnavailable:
            "function-invocation-target-unavailable"
        case .functionClearEncodeRejected: "function-clear-encode-rejected"
        case .captureRejected: "capture-rejected"
        case .encodeRejected: "encode-rejected"
        case .contentGenerationOverflow: "content-generation-overflow"
        case .stalePreparation: "stale-preparation"
        }
    }

    private static func detailSuffix(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let characters = value.utf8.prefix(64).map { byte -> Character in
            switch byte {
            case 45, 46, 48 ... 57, 65 ... 90, 95, 97 ... 122:
                Character(UnicodeScalar(byte))
            default:
                "_"
            }
        }
        return "-detail-" + String(characters)
    }

    private static func descriptorDigest(_ value: String) -> String {
        String(SceneShaderStableDigest.hash(value).prefix(12))
    }
}
