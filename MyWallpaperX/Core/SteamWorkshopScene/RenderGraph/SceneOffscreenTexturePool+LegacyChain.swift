import Metal

extension SceneOffscreenTexturePool {
    /// Legacy authored frame tables prepared and committed atomically for one
    /// frame. The returned value is frame-local; the pool does NOT retain it.
    struct LegacyAuthoredFrameTables {
        let tables: [SceneGraphRenderTargetTable]
        let commit: ScenePreparedPersistentGraphTargets.Commit
    }

    // MARK: - Legacy authored chain plan (unified pair-only & persistent)

    /// Creates a frame plan for any legacy authored chain — both pair-only
    /// (formerly 3-texture rotation) and persistent (FBO-bearing) chains.
    /// Always builds a two-member pair/chain plan with `pairStorage: .shared`.
    func legacyAuthoredChainFramePlan(
        for chain: SceneAuthoredEffectExecutionChain,
        requestedWidth: Int,
        requestedHeight: Int,
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> ScenePersistentGraphTargetFramePlan? {
        legacyAuthoredFramePlan(
            stages: chain.executionStages,
            layerID: chain.layerID,
            finalOutput: chain.renderGraph.finalOutput,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight,
            orderingContext: orderingContext
        )
    }

    func legacyAuthoredStageFramePlan(
        for stage: SceneAuthoredEffectExecutionPlan,
        requestedWidth: Int,
        requestedHeight: Int,
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> ScenePersistentGraphTargetFramePlan? {
        legacyAuthoredFramePlan(
            stages: [stage],
            layerID: stage.layerID,
            finalOutput: stage.renderGraph.finalOutput,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight,
            orderingContext: orderingContext
        )
    }

    private func legacyAuthoredFramePlan(
        stages: [SceneAuthoredEffectExecutionPlan],
        layerID: Int,
        finalOutput: SceneAuthoredEffectRenderPlan.TextureIdentity,
        requestedWidth: Int,
        requestedHeight: Int,
        orderingContext: SceneGraphCommandQueueOrderingContext?
    ) -> ScenePersistentGraphTargetFramePlan? {
        guard pixelFormat == .bgra8Unorm,
              let prepared = targetPlans(
                  stages: stages,
                  layerID: layerID,
                  validatesChainOrder: true,
                  enforcesExactExtent: true,
                  requestedWidth: requestedWidth,
                  requestedHeight: requestedHeight
              ),
              case let .success(pairPlan) = SceneLayerFullFramePairPlan.make(
                  conditionPrunedGraphs: stages.map(\.renderGraph)
              ), prepared.plans.last?.output == finalOutput else { return nil }

        let chainPlan: SceneGraphRenderTargetChainPlan
        switch SceneGraphRenderTargetChainPlan.make(
            plans: prepared.plans,
            pairPlan: pairPlan,
            byteBudget: residentByteBudget,
            pairStorage: .shared
        ) {
        case .success(let shared):
            chainPlan = shared
        case .failure:
            guard case let .success(owned) = SceneGraphRenderTargetChainPlan.make(
                plans: prepared.plans,
                pairPlan: pairPlan,
                byteBudget: residentByteBudget,
                pairStorage: .owned
            ) else { return nil }
            chainPlan = owned
        }
        guard zip(stages, chainPlan.stages).allSatisfy({ stage, planned in
            let aliasesEndpoints = planned.pairStep.inputMember
                == planned.pairStep.outputMember
            return aliasesEndpoints
                == stage.supportsUnifiedFullFrameComposeStage
        }) else { return nil }
        return .init(
            residencyDomainID: residencyDomainID,
            chainPlan: chainPlan,
            orderingContext: orderingContext
        )
    }

    // MARK: - Two-texture shared pair (no tertiary)

    /// Allocates exactly two textures for a shared pair candidate.  Never
    /// creates a tertiary texture — `residentTextureCount` and `byteCost`
    /// are precise.
    func sharedPairCandidate(
        width: Int,
        height: Int,
        textureFactory: ScenePersistentGraphTargetAllocator.TextureFactory? = nil
    ) -> Candidate? {
        let key = CacheKey.sharedGraphPair(width: width, height: height)
        guard let byteCost = byteCost(
            width: width, height: height, textureCount: 2
        ), byteCost <= residentByteBudget else { return nil }
        if let cached = allocationCache.allocation(for: key) {
            guard case .sharedGraphPair = cached else { return nil }
            return .init(key: key, allocation: cached, byteCost: byteCost)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let factory = textureFactory ?? { [device] descriptor, label in
            let texture = device.makeTexture(descriptor: descriptor)
            texture?.label = label
            return texture
        }
        let label = "sharedPair:\(width)x\(height)"
        guard let first = factory(
            descriptor, "SceneSharedPairA \(label)"
        ), let second = factory(
            descriptor, "SceneSharedPairB \(label)"
        ), let physicalIdentity = allocationCache.issuePhysicalIdentity(
            textures: [first, second]
        ) else { return nil }
        return .init(
            key: key,
            allocation: .sharedGraphPair(
                SharedGraphPair(first: first, second: second),
                physicalIdentity
            ),
            byteCost: byteCost
        )
    }

    // MARK: - Frame-level batch prepare & commit (frame-local return)

    /// Aggregately reserves, allocates, and commits all supplied legacy
    /// frame plans against one shared cache snapshot.  Returns a **frame-
    /// local** dictionary keyed by layer ID, or `nil` on any failure.
    /// On failure the cache residents, revision, LRU, and pins are
    /// unchanged — zero partial publication.
    func prepareLegacyAuthoredFrameBatch(
        framePlans: [ScenePersistentGraphTargetFramePlan],
        orderingContext: SceneGraphCommandQueueOrderingContext,
        textureFactory: ScenePersistentGraphTargetAllocator.TextureFactory? = nil
    ) -> [Int: LegacyAuthoredFrameTables]? {
        guard !framePlans.isEmpty,
              orderingContext.isPending,
              framePlans.allSatisfy({
                  $0.residencyDomainID == residencyDomainID
                    && $0.orderingContext?.accepts(
                        orderingContext.commandBuffer
                    ) == true
              }),
              Set(framePlans.map { $0.chainPlan.key.layerID }).count
                == framePlans.count,
              let requiredKeys = requiredSharedPairKeys(for: framePlans),
              let pendingCosts = pendingSharedPairByteCosts(for: requiredKeys),
              let snapshot = allocationCache.preflightLegacyBatch(
                  framePlans.map(\.chainPlan),
                  orderingContext: orderingContext,
                  requiredSharedPairKeys: requiredKeys,
                  pendingSharedPairByteCosts: pendingCosts
              )
        else { return nil }

        var sharedPairCandidates: [Candidate] = []
        for (key, _) in pendingCosts.sorted(by: {
            String(describing: $0.key) < String(describing: $1.key)
        }) {
            guard case let .sharedGraphPair(width, height) = key,
                  let candidate = sharedPairCandidate(
                      width: width,
                      height: height,
                      textureFactory: textureFactory
                  ) else { return nil }
            sharedPairCandidates.append(candidate)
        }
        guard let reservations = allocationCache.reserveLegacyBatch(
            plans: framePlans.map(\.chainPlan),
            orderingContext: orderingContext,
            snapshot: snapshot,
            sharedPairCandidates: sharedPairCandidates
        ) else { return nil }
        let allocator = textureFactory.map {
            ScenePersistentGraphTargetAllocator(
                device: device,
                cache: allocationCache,
                textureFactory: $0
            )
        } ?? ScenePersistentGraphTargetAllocator(
            device: device,
            cache: allocationCache
        )
        guard let allocatorPrepared = allocator.prepare(
            plans: framePlans.map(\.chainPlan),
            reservations: reservations
        ) else { return nil }
        var requests: [ScenePreparedPersistentGraphTargets.CommitRequest] = []
        for (framePlan, prepared) in zip(framePlans, allocatorPrepared) {
            guard let historyTokens = legacyHistoryTokens(
                plan: framePlan.chainPlan,
                prepared: prepared
            ) else { return nil }
            guard let request = prepared.takeCommitRequest(
                historyTokensByEffect: historyTokens,
                commandBuffer: orderingContext.commandBuffer
            ) else { return nil }
            requests.append(request)
        }
        guard let commits = allocationCache.commitAndPinLegacyBatch(
            snapshot: snapshot,
            sharedPairCandidates: sharedPairCandidates,
            requests: requests
        ), commits.count == allocatorPrepared.count else { return nil }

        var tables: [Int: LegacyAuthoredFrameTables] = [:]
        for (plan, (prepared, commit)) in zip(
            framePlans, zip(allocatorPrepared, commits)
        ) {
            tables[plan.chainPlan.key.layerID] = .init(
                tables: prepared.leases.map(\.table),
                commit: commit
            )
        }
        return tables
    }

    private func legacyHistoryTokens(
        plan: SceneGraphRenderTargetChainPlan,
        prepared: ScenePreparedPersistentGraphTargets
    ) -> [SceneAuthoredEffectRenderPlan.EffectKey:
        Set<SceneGraphExecutionState.PhysicalToken>]? {
        guard plan.stages.count == prepared.leases.count else { return nil }
        var result: [SceneAuthoredEffectRenderPlan.EffectKey:
            Set<SceneGraphExecutionState.PhysicalToken>] = [:]
        for (stage, lease) in zip(plan.stages, prepared.leases) {
            let identities = stage.historyClosureIdentities
            guard let effect = stage.plan.output.effect else { return nil }
            if identities.isEmpty { continue }
            let tokens = Set(identities.compactMap {
                lease.allocation.resources[$0]?.token
            })
            guard tokens.count == identities.count,
                  result.updateValue(tokens, forKey: effect) == nil else {
                return nil
            }
        }
        return Set(result.keys) == plan.historyEffects ? result : nil
    }

    // MARK: - Standard pair (3-texture, kept for legacy offscreen path)

    func pairCandidate(width: Int, height: Int) -> Candidate? {
        pairCandidate(
            width: width,
            height: height,
            key: .pair(width: width, height: height)
        )
    }

    func pairCandidate(
        width: Int,
        height: Int,
        key: CacheKey
    ) -> Candidate? {
        guard let resolvedKey: CacheKey = switch key {
        case .pair:
            .pair(width: width, height: height)
        case .authoredPair:
            .authoredPair(width: width, height: height)
        default:
            nil
        } else { return nil }
        guard let byteCost = byteCost(
            width: width,
            height: height,
            textureCount: 3
        ), byteCost <= residentByteBudget else { return nil }
        if let cached = allocationCache.allocation(for: resolvedKey) {
            guard case .pair = cached else { return nil }
            return .init(key: resolvedKey, allocation: cached, byteCost: byteCost)
        }

        let label = "pair:\(width)x\(height)"
        guard let primary = makeTexture(
            width: width, height: height, label: "SceneOffscreenA \(label)"
        ), let secondary = makeTexture(
            width: width, height: height, label: "SceneOffscreenB \(label)"
        ), let tertiary = makeTexture(
            width: width, height: height, label: "SceneOffscreenC \(label)"
        ), let physicalIdentity = allocationCache.issuePhysicalIdentity(
            textures: [primary, secondary, tertiary]
        ) else { return nil }
        return .init(
            key: resolvedKey,
            allocation: .pair(
                Pair(primary: primary, secondary: secondary, tertiary: tertiary),
                physicalIdentity
            ),
            byteCost: byteCost
        )
    }

    func usesPairOnlyLegacyTargets(
        for chain: SceneAuthoredEffectExecutionChain
    ) -> Bool {
        let stages = chain.executionStages
        return !stages.isEmpty && stages.allSatisfy {
            $0.logicalRenderTargetCount == 0
                && $0.renderGraph.renderTargets.isEmpty
        }
    }

    /// Standalone authored plan path — not used by the frame batch.
    func graphTargets(
        for chain: SceneAuthoredEffectExecutionChain,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> [SceneGraphRenderTargetTable]? {
        let stages = chain.executionStages
        guard pixelFormat == .bgra8Unorm,
              usesPairOnlyLegacyTargets(for: chain),
              let prepared = targetPlans(
                  stages: stages,
                  layerID: chain.layerID,
                  validatesChainOrder: true,
                  enforcesExactExtent: true,
                  requestedWidth: requestedWidth,
                  requestedHeight: requestedHeight
              ), prepared.plans.allSatisfy({ $0.logicalTargets.isEmpty }),
              prepared.plans.last?.output == chain.renderGraph.finalOutput
        else { return nil }

        let maxDim = max(prepared.width, prepared.height)
        let (width, height) = SceneOffscreenResolutionPolicy.limitedDimensions(
            width: prepared.width,
            height: prepared.height,
            maximumDimension: maxDim
        )
        guard let candidate = pairCandidate(
            width: width,
            height: height,
            key: .authoredPair(width: width, height: height)
        ), allocationCache.commit([candidate]),
        case let .pair(pair, _) = candidate.allocation
        else { return nil }

        var tables: [SceneGraphRenderTargetTable] = []
        tables.reserveCapacity(prepared.plans.count)
        for (index, plan) in prepared.plans.enumerated() {
            let inputTex = (index % 2 == 0) ? pair.primary : pair.secondary
            let outputTex = (index % 2 == 0) ? pair.secondary : pair.primary
            guard case let .success(table) = SceneGraphRenderTargetTable.makeBorrowed(
                plan: plan,
                inputTexture: inputTex,
                outputTexture: outputTex
            ) else { return nil }
            tables.append(table)
        }
        return tables
    }
}
