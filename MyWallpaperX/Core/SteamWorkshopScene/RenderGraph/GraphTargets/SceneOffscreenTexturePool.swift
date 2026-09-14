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
        // Apple GPU family limits are 16384; 8192 lets enlarged authored
        // scales (e.g. close-up characters) capture without an upscale
        // while the resident byte budget still gates total memory.
        maxDimension: Int = 8192,
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

    func persistentTargetPlans(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        materialFunctionTargetsByEffect: [SceneAuthoredEffectRenderPlan.EffectKey: Set<SceneAuthoredEffectRenderPlan.TextureIdentity>] = [:],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> (plans: [SceneGraphRenderTargetPlan], makeInputsDigests: [Int], width: Int, height: Int)? {
        guard case let .success(value) = persistentTargetPlansResult(
            admittedGraphs: admittedGraphs,
            materialFunctionTargetsByEffect: materialFunctionTargetsByEffect,
            pairPlan: pairPlan,
            extentPolicy: extentPolicy,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight
        ) else { return nil }
        return value
    }

    /// M4.1：persistentTargetPlansResult 的内容键身份。capability token
    /// 值等价于 owner+capability+layer（catalog 不可变）——图集合随
    /// capabilityID 不变；capability 换代自动换键。
    struct PersistentPlansMemoIdentity: Hashable {
        let capabilityToken: SceneResolvedMaterialExecutionCapabilityCatalog.Token
        let layerID: Int
    }

    private struct PersistentPlansMemoKey: Hashable {
        let identity: PersistentPlansMemoIdentity
        let width: Int
        let height: Int
        let materialFunctionTargets: [SceneAuthoredEffectRenderPlan.EffectKey: Set<SceneAuthoredEffectRenderPlan.TextureIdentity>]
    }

    private var persistentPlansMemo: [PersistentPlansMemoKey: (
        plans: [SceneGraphRenderTargetPlan],
        makeInputsDigests: [Int],
        width: Int,
        height: Int
    )] = [:]

    func persistentTargetPlansResult(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        materialFunctionTargetsByEffect: [SceneAuthoredEffectRenderPlan.EffectKey: Set<SceneAuthoredEffectRenderPlan.TextureIdentity>] = [:],
        pairPlan: SceneLayerFullFramePairPlan,
        extentPolicy: SceneFullFrameExtentPolicy = .standard,
        requestedWidth: Int,
        requestedHeight: Int,
        plansMemoIdentity: PersistentPlansMemoIdentity? = nil
    ) -> Result<(
        plans: [SceneGraphRenderTargetPlan],
        makeInputsDigests: [Int],
        width: Int,
        height: Int
    ), ScenePersistentGraphTargetPlanningFailure> {
        guard !admittedGraphs.isEmpty,
              admittedGraphs.count == pairPlan.effects.count,
              admittedGraphs.allSatisfy({ $0.layerID == pairPlan.layerID }) else {
            return .failure(.invalidRequest)
        }
        guard let size = SceneOffscreenResolutionPolicy.resolvedDimensions(
            width: requestedWidth,
            height: requestedHeight,
            hardLimit: maxDimension,
            policy: extentPolicy
        ) else { return .failure(.invalidExtent) }
        // M4.1：make 为纯函数，键覆盖全部输入；命中即跳过逐层 make
        // （帧路径 adm 段 25.5ms 主项）。capability 换代自动换键；
        // reset() 清空；失败结果不缓存（保持重试语义）。
        if let plansMemoIdentity {
            let memoKey = PersistentPlansMemoKey(
                identity: plansMemoIdentity,
                width: size.0,
                height: size.1,
                materialFunctionTargets: materialFunctionTargetsByEffect
            )
            if let cached = persistentPlansMemo[memoKey] {
                return .success(
                    (plans: cached.plans,
                     makeInputsDigests: cached.makeInputsDigests,
                     width: cached.width,
                     height: cached.height)
                )
            }
            let derived = persistentTargetPlans(
                admittedGraphs: admittedGraphs,
                materialFunctionTargetsByEffect: materialFunctionTargetsByEffect,
                pairPlan: pairPlan,
                size: size
            )
            guard case let .success(value) = derived else { return derived }
            persistentPlansMemo[memoKey] = value
            return .success(
                (plans: value.plans,
                 makeInputsDigests: value.makeInputsDigests,
                 width: value.width,
                 height: value.height)
            )
        }
        return persistentTargetPlans(
            admittedGraphs: admittedGraphs,
            materialFunctionTargetsByEffect: materialFunctionTargetsByEffect,
            pairPlan: pairPlan,
            size: size
        )
    }

    /// make 的纯推导体（无状态；memo 未命中时执行）。
    private func persistentTargetPlans(
        admittedGraphs: [SceneAuthoredEffectRenderPlan],
        materialFunctionTargetsByEffect: [SceneAuthoredEffectRenderPlan.EffectKey: Set<SceneAuthoredEffectRenderPlan.TextureIdentity>],
        pairPlan: SceneLayerFullFramePairPlan,
        size: (width: Int, height: Int)
    ) -> Result<(
        plans: [SceneGraphRenderTargetPlan],
        makeInputsDigests: [Int],
        width: Int,
        height: Int
    ), ScenePersistentGraphTargetPlanningFailure> {
        var plans: [SceneGraphRenderTargetPlan] = []
        plans.reserveCapacity(admittedGraphs.count)
        var makeInputsDigests: [Int] = []
        makeInputsDigests.reserveCapacity(admittedGraphs.count)
        for (index, values) in zip(admittedGraphs, pairPlan.effects).enumerated() {
            let (graph, pairStep) = values
            let inputRole: SceneAuthoredEffectInputRole = index == 0
                ? .layerSource : .priorEffectOutput
            let targets = materialFunctionTargetsByEffect[pairStep.effect] ?? []
            let planResult = SceneGraphRenderTargetPlan.make(
                graph: graph,
                inputRole: inputRole,
                inputWidth: size.width,
                inputHeight: size.height,
                materialFunctionTargets: targets
            )
            let plan: SceneGraphRenderTargetPlan
            switch planResult {
            case let .success(value): plan = value
            case let .failure(failure): return .failure(.graphTargetPlan(failure))
            }
            makeInputsDigests.append(SceneGraphRenderTargetPlan.makeInputsDigest(
                inputRole: inputRole,
                inputWidth: size.width,
                inputHeight: size.height,
                materialFunctionTargets: targets
            ))
            guard graph.effects.first?.key == pairStep.effect else {
                return .failure(.graphTargetIdentityMismatch)
            }
            guard plan.inputRole == inputRole,
                  plan.input == pairStep.inputIdentity,
                  plan.output == pairStep.outputIdentity else {
                return .failure(.graphTargetIdentityMismatch)
            }
            plans.append(plan)
        }
        return .success((
            plans: plans,
            makeInputsDigests: makeInputsDigests,
            width: size.width,
            height: size.height
        ))
    }

    func reset() {
        allocationCache.reset()
        persistentPlansMemo.removeAll(keepingCapacity: true)
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
