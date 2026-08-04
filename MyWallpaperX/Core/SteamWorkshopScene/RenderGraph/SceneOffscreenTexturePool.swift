import Foundation
import Metal

extension SceneResolvedMaterialInFlightCapacity {
    static func admitsNewSubmission(
        _ entries: [SceneOffscreenTextureAllocationCache.Entry],
        chainKey: SceneGraphRenderTargetChainPlan.Key
    ) -> Bool {
        admitsNewSubmission(entries.compactMap { entry in
            guard case .chain(let chain) = entry.allocation,
                  chain.plan.key == chainKey else { return nil }
            return entry.submissionPins.count
        })
    }

    static func admitsNewAllocation(
        _ allocations: [SceneOffscreenTextureAllocationCache.Allocation],
        chainKey: SceneGraphRenderTargetChainPlan.Key,
        replacingGenerations: Set<UInt64>
    ) -> Bool {
        var unmatched = replacingGenerations
        let retainedCount = allocations.reduce(into: 0) { count, allocation in
            guard case .chain(let chain) = allocation,
                  chain.plan.key == chainKey else { return }
            if unmatched.remove(chain.generation) == nil { count += 1 }
        }
        return unmatched.isEmpty && retainedCount < maximumSubmissions
    }
}

final class SceneOffscreenTexturePool {
    struct Pair {
        let primary: MTLTexture
        let secondary: MTLTexture
        let tertiary: MTLTexture
    }

    struct SharedGraphPair {
        let first: MTLTexture
        let second: MTLTexture
    }

    let device: MTLDevice
    let pixelFormat: MTLPixelFormat
    typealias AllocationCache = SceneOffscreenTextureAllocationCache
    typealias CacheKey = AllocationCache.Key
    typealias Allocation = AllocationCache.Allocation
    typealias Candidate = AllocationCache.Candidate

    let maxDimension: Int
    let residentByteBudget: Int
    let allocationCache: AllocationCache
    let residencyDomainID = UUID()

    var residentAllocationCount: Int { allocationCache.residentAllocationCount }
    var residentTextureCount: Int { allocationCache.residentTextureCount }
    var residentByteCost: Int { allocationCache.residentByteCost }

    init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        maxDimension: Int = 4096,
        residentByteBudget: Int = 128 * 1_024 * 1_024
    ) {
        self.device = device
        self.pixelFormat = pixelFormat
        self.maxDimension = max(maxDimension, 1)
        let normalizedBudget = max(residentByteBudget, 0)
        self.residentByteBudget = normalizedBudget
        allocationCache = .init(byteBudget: normalizedBudget)
    }

    func textures(for sourceTexture: MTLTexture) -> Pair? {
        textures(width: sourceTexture.width, height: sourceTexture.height)
    }

    func textures(
        width requestedWidth: Int,
        height requestedHeight: Int,
        maximumDimension: Int? = nil
    ) -> Pair? {
        let (width, height) = SceneOffscreenResolutionPolicy.limitedDimensions(
            width: requestedWidth,
            height: requestedHeight,
            maximumDimension: maximumDimension ?? SceneOffscreenResolutionPolicy.maximumDimension(
                hardLimit: maxDimension, includesAuthoredShader: false
            )
        )
        let key = CacheKey.pair(width: width, height: height)
        if let cached = allocationCache.cachedPair(for: key) {
            return cached
        }
        guard let candidate = pairCandidate(width: width, height: height),
              allocationCache.commit([candidate]),
              case .pair(let pair, _) = candidate.allocation else { return nil }
        return pair
    }

    func graphTargets(
        for executionPlan: SceneAuthoredEffectExecutionPlan,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> SceneGraphRenderTargetTable? {
        graphTargetLease(
            for: executionPlan,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight
        )?.table
    }

    func graphTargetLease(
        for executionPlan: SceneAuthoredEffectExecutionPlan,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> SceneGraphRenderTargetLease? {
        graphTargetLeaseTransaction(
            stages: [executionPlan],
            layerID: executionPlan.layerID,
            validatesChainOrder: false,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight
        )?.first
    }

    func framePlanForPersistentGraphTargets(
        for chain: SceneAuthoredEffectExecutionChain,
        requestedWidth: Int,
        requestedHeight: Int,
        orderingContext: SceneGraphCommandQueueOrderingContext? = nil
    ) -> ScenePersistentGraphTargetFramePlan? {
        let stages = chain.executionStages
        guard pixelFormat == .bgra8Unorm,
              !usesPairOnlyLegacyTargets(for: chain),
              let prepared = targetPlans(
                  stages: stages,
                  layerID: chain.layerID,
                  validatesChainOrder: true,
                  enforcesExactExtent: true,
                  requestedWidth: requestedWidth,
                  requestedHeight: requestedHeight
              ), case .success(let pairPlan) = SceneLayerFullFramePairPlan.make(
                  conditionPrunedGraphs: stages.map(\.renderGraph)
              ), case .success(let chainPlan) = SceneGraphRenderTargetChainPlan.make(
                  plans: prepared.plans,
                  pairPlan: pairPlan,
                  byteBudget: residentByteBudget,
                  pairStorage: .shared
              ), prepared.plans.last?.output == chain.renderGraph.finalOutput,
              chainPlan.historyEffects.isEmpty,
              chainPlan.stages.allSatisfy({
                  $0.pairStep.inputMember != $0.pairStep.outputMember
              }) else { return nil }
        return .init(
            residencyDomainID: residencyDomainID,
            chainPlan: chainPlan,
            orderingContext: orderingContext
        )
    }

    /// Allocates effect-keyed candidates without publishing them to cache/LRU
    /// residency. The coordinator commits and pins only after graph preflight.
    func preparePersistentGraphTargets(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> ScenePreparedPersistentGraphTargets? {
        guard pixelFormat == .bgra8Unorm,
              let prepared = persistentTargetPlans(
                  admittedGraphs: admittedGraphs,
                  pairPlan: pairPlan,
                  extentPolicy: extentPolicy,
                  requestedWidth: requestedWidth,
                  requestedHeight: requestedHeight
              ), case .success(let plan) = SceneGraphRenderTargetChainPlan.make(
                  plans: prepared.plans,
                  pairPlan: pairPlan,
                  byteBudget: residentByteBudget
              ) else { return nil }
        return ScenePersistentGraphTargetAllocator(
            device: device, cache: allocationCache
        ).prepare(plan: plan)
    }

    private func graphTargetLeaseTransaction(
        stages: [SceneAuthoredEffectExecutionPlan],
        layerID: Int,
        validatesChainOrder: Bool,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> [SceneGraphRenderTargetLease]? {
        guard let prepared = graphTargetLeaseCandidates(
            stages: stages,
            layerID: layerID,
            validatesChainOrder: validatesChainOrder,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight
        ), allocationCache.commit(prepared.candidates) else { return nil }
        return prepared.leases
    }

    private func graphTargetLeaseCandidates(
        stages: [SceneAuthoredEffectExecutionPlan],
        layerID: Int,
        validatesChainOrder: Bool,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> (leases: [SceneGraphRenderTargetLease], candidates: [Candidate])? {
        guard pixelFormat == .bgra8Unorm,
              let prepared = targetPlans(
                  stages: stages,
                  layerID: layerID,
                  validatesChainOrder: validatesChainOrder,
                  enforcesExactExtent: true,
                  requestedWidth: requestedWidth,
                  requestedHeight: requestedHeight
              ) else { return nil }
        let plans = prepared.plans

        var candidates: [Candidate] = []
        var leases: [SceneGraphRenderTargetLease] = []
        var uniqueKeys = Set<CacheKey>()
        candidates.reserveCapacity(plans.count)
        leases.reserveCapacity(plans.count)
        for plan in plans {
            guard let effect = plan.output.effect else { return nil }
            let key = CacheKey.graph(effect)
            guard uniqueKeys.insert(key).inserted else { return nil }
            let lease: SceneGraphRenderTargetLease
            if let cached = allocationCache.allocation(for: key),
               case .graph(let existing) = cached,
               existing.table.plan == plan {
                lease = existing
            } else {
                guard case .success(let table) = SceneGraphRenderTargetTable.make(
                    plan: plan,
                    device: device,
                    byteBudget: residentByteBudget
                ), let textures = SceneGraphRenderTargetLease.orderedTextures(
                    for: table
                ), let physicalIdentity = allocationCache.issuePhysicalIdentity(
                    textures: textures
                ), case .success(let created) = SceneGraphRenderTargetLease.make(
                    table: table,
                    generation: physicalIdentity.generation,
                    tokenForTexture: physicalIdentity.token(for:)
                ) else { return nil }
                lease = created
            }
            candidates.append(.init(
                key: key,
                allocation: .graph(lease),
                byteCost: lease.table.residentByteCost
            ))
            leases.append(lease)
        }
        return (leases, candidates)
    }

    func persistentTargetPlans(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> (plans: [SceneGraphRenderTargetPlan], width: Int, height: Int)? {
        guard !admittedGraphs.isEmpty,
              admittedGraphs.count == pairPlan.effects.count,
              admittedGraphs.allSatisfy({ $0.layerID == pairPlan.layerID }) else {
            return nil
        }
        guard let size = SceneOffscreenResolutionPolicy.resolvedDimensions(
            width: requestedWidth,
            height: requestedHeight,
            hardLimit: maxDimension,
            policy: extentPolicy
        ) else { return nil }
        var plans: [SceneGraphRenderTargetPlan] = []
        plans.reserveCapacity(admittedGraphs.count)
        for (index, values) in zip(admittedGraphs, pairPlan.effects).enumerated() {
            let (graph, pairStep) = values
            let inputRole: SceneAuthoredEffectInputRole = index == 0
                ? .layerSource : .priorEffectOutput
            guard graph.effects.first?.key == pairStep.effect,
                  case .success(let plan) = SceneGraphRenderTargetPlan.make(
                      graph: graph,
                      inputRole: inputRole,
                      inputWidth: size.0,
                      inputHeight: size.1
                  ), plan.input == pairStep.inputIdentity,
                  plan.output == pairStep.outputIdentity else { return nil }
            plans.append(plan)
        }
        return (plans, size.0, size.1)
    }

    func targetPlans(
        stages: [SceneAuthoredEffectExecutionPlan],
        layerID: Int,
        validatesChainOrder: Bool,
        enforcesExactExtent: Bool,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> (plans: [SceneGraphRenderTargetPlan], width: Int, height: Int)? {
        guard !stages.isEmpty, stages.allSatisfy({ $0.layerID == layerID }) else {
            return nil
        }
        let limit = SceneOffscreenResolutionPolicy.maximumDimension(
            hardLimit: maxDimension,
            includesAuthoredShader: stages.contains { $0.authoredShader != nil }
        )
        let size = SceneOffscreenResolutionPolicy.limitedDimensions(
            width: requestedWidth,
            height: requestedHeight,
            maximumDimension: limit
        )
        if enforcesExactExtent && stages.contains(where: \.requiresExactInputExtent),
           (requestedWidth <= 0 || requestedHeight <= 0
               || size.0 != requestedWidth || size.1 != requestedHeight) {
            return nil
        }
        var plans: [SceneGraphRenderTargetPlan] = []
        var priorOutput: SceneAuthoredEffectRenderPlan.TextureIdentity?
        for stage in stages {
            guard case .success(let plan) = SceneGraphRenderTargetPlan.make(
                executionPlan: stage,
                graph: stage.renderGraph,
                inputWidth: size.0,
                inputHeight: size.1
            ) else { return nil }
            if validatesChainOrder, let priorOutput {
                guard plan.inputRole == .priorEffectOutput,
                      plan.input == priorOutput else { return nil }
            } else if validatesChainOrder {
                guard plan.inputRole == .layerSource else { return nil }
            }
            plans.append(plan)
            priorOutput = plan.output
        }
        return (plans, size.0, size.1)
    }

    func reset() {
        allocationCache.reset()
    }

    func byteCost(width: Int, height: Int, textureCount: Int) -> Int? {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow else { return nil }
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !byteOverflow else { return nil }
        let (total, totalOverflow) = bytes.multipliedReportingOverflow(by: textureCount)
        return totalOverflow ? nil : total
    }

    func makeTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }
}
