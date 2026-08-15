import Foundation
import Metal

extension SceneResolvedMaterialInFlightCapacity {
    static func admitsNewSubmission(
        _ entries: [SceneOffscreenTextureAllocationCache.Entry],
        graphKey: SceneLayerGraphTargetPlan.Key
    ) -> Bool {
        admitsNewSubmission(entries.compactMap { entry in
            guard case .layerGraph(let graph) = entry.allocation,
                  graph.plan.key == graphKey else { return nil }
            return entry.submissionPins.count
        })
    }

    static func admitsNewAllocation(
        _ allocations: [SceneOffscreenTextureAllocationCache.Allocation],
        graphKey: SceneLayerGraphTargetPlan.Key,
        replacingGenerations: Set<UInt64>
    ) -> Bool {
        var unmatched = replacingGenerations
        let retainedCount = allocations.reduce(into: 0) { count, allocation in
            guard case .layerGraph(let graph) = allocation,
                  graph.plan.key == graphKey else { return }
            if unmatched.remove(graph.generation) == nil { count += 1 }
        }
        return unmatched.isEmpty && retainedCount < maximumSubmissions
    }
}

final class SceneOffscreenTexturePool {
    private static let minimumAutomaticResidentByteBudget = 192 * 1_024 * 1_024
    private static let maximumAutomaticResidentByteBudget = 512 * 1_024 * 1_024

    /// A neutral source-copy target used by structural composition. Effect
    /// stages never receive this surface; they use persistent graph targets.
    struct CompositionTarget {
        let texture: MTLTexture
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
        residentByteBudget: Int? = nil
    ) {
        self.device = device
        self.pixelFormat = pixelFormat
        self.maxDimension = max(maxDimension, 1)
        let normalizedBudget = max(
            residentByteBudget ?? Self.automaticResidentByteBudget(
                recommendedMaxWorkingSetSize: device.recommendedMaxWorkingSetSize
            ),
            0
        )
        self.residentByteBudget = normalizedBudget
        allocationCache = .init(byteBudget: normalizedBudget)
    }

    /// Chooses a conservative logical allocation ceiling for graph targets
    /// from Metal's approximate total working-set guidance. No memory is
    /// reserved until a frame plan actually needs it.
    static func automaticResidentByteBudget(
        recommendedMaxWorkingSetSize: UInt64
    ) -> Int {
        let proposed = min(
            recommendedMaxWorkingSetSize / 32,
            UInt64(maximumAutomaticResidentByteBudget)
        )
        return max(Int(proposed), minimumAutomaticResidentByteBudget)
    }

    func compositionTarget(
        width requestedWidth: Int,
        height requestedHeight: Int
    ) -> CompositionTarget? {
        let (width, height) = SceneOffscreenResolutionPolicy.limitedDimensions(
            width: requestedWidth,
            height: requestedHeight,
            maximumDimension: SceneOffscreenResolutionPolicy.maximumDimension(
                hardLimit: maxDimension, includesAuthoredShader: false
            )
        )
        let key = CacheKey.composition(width: width, height: height)
        if let cached = allocationCache.allocation(for: key),
           case .composition(let texture, _) = cached {
            return CompositionTarget(texture: texture)
        }
        guard let byteCost = byteCost(width: width, height: height, textureCount: 1),
              byteCost <= residentByteBudget,
              let texture = makeTexture(
                  width: width,
                  height: height,
                  label: "SceneCompositionSource \(width)x\(height)"
              ), let identity = allocationCache.issuePhysicalIdentity(
                  textures: [texture]
              ) else { return nil }
        let candidate = Candidate(
            key: key,
            allocation: .composition(texture, identity),
            byteCost: byteCost
        )
        guard allocationCache.commit([candidate]) else { return nil }
        return CompositionTarget(texture: texture)
    }

    /// Allocates effect-keyed candidates without publishing them to cache/LRU
    /// residency. The coordinator commits and pins only after graph preflight.
    func preparePersistentGraphTargets(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        targetExecutionPlans: [SceneEffectStageExecutionPlan?] = [],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> ScenePreparedPersistentGraphTargets? {
        guard pixelFormat == .bgra8Unorm,
              let prepared = persistentTargetPlans(
                  admittedGraphs: admittedGraphs,
                  targetExecutionPlans: targetExecutionPlans,
                  pairPlan: pairPlan,
                  extentPolicy: extentPolicy,
                  requestedWidth: requestedWidth,
                  requestedHeight: requestedHeight
              ), case .success(let plan) = SceneLayerGraphTargetPlan.make(
                  plans: prepared.plans,
                  pairPlan: pairPlan,
                  byteBudget: residentByteBudget
              ) else { return nil }
        return ScenePersistentGraphTargetAllocator(
            device: device, cache: allocationCache
        ).prepare(plan: plan)
    }

    func persistentTargetPlans(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        targetExecutionPlans: [SceneEffectStageExecutionPlan?] = [],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> (plans: [SceneGraphRenderTargetPlan], width: Int, height: Int)? {
        guard !admittedGraphs.isEmpty,
              admittedGraphs.count == pairPlan.effects.count,
              (targetExecutionPlans.isEmpty
                || targetExecutionPlans.count == admittedGraphs.count),
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
            let targetExecutionPlan = targetExecutionPlans.isEmpty
                ? nil : targetExecutionPlans[index]
            let planResult = targetExecutionPlan.map {
                SceneGraphRenderTargetPlan.make(
                    executionPlan: $0,
                    graph: graph,
                    inputWidth: size.0,
                    inputHeight: size.1
                )
            } ?? SceneGraphRenderTargetPlan.make(
                graph: graph,
                inputRole: inputRole,
                inputWidth: size.0,
                inputHeight: size.1
            )
            guard graph.effects.first?.key == pairStep.effect,
                  case .success(let plan) = planResult,
                  plan.inputRole == inputRole,
                  plan.input == pairStep.inputIdentity,
                  plan.output == pairStep.outputIdentity else { return nil }
            plans.append(plan)
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
