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
    /// A neutral source-copy target used by structural composition. Effect
    /// stages never receive this surface; they use persistent graph targets.
    struct CompositionTarget {
        let texture: MTLTexture
        let pin: SceneGraphRenderTargetResidencyPin?
    }

    struct SharedGraphPair {
        let first: MTLTexture
        let second: MTLTexture
    }

    let device: MTLDevice
    let pixelFormat: MTLPixelFormat

    var backbufferFormat: SceneGraphRenderTargetPlan.TextureFormat {
        pixelFormat == .rgba16Float ? .rgba16f : .rgbaBackbuffer
    }
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
        SceneOffscreenTextureResidentBudgetPolicy.automatic(
            recommendedMaxWorkingSetSize: recommendedMaxWorkingSetSize
        )
    }

    func compositionTarget(
        width requestedWidth: Int,
        height requestedHeight: Int,
        commandBuffer: MTLCommandBuffer?,
        extentPolicy: SceneFullFrameExtentPolicy = .standard
    ) -> CompositionTarget? {
        guard let (width, height) = SceneOffscreenResolutionPolicy.resolvedDimensions(
            width: requestedWidth, height: requestedHeight,
            hardLimit: maxDimension, policy: extentPolicy) else { return nil }
        let key = CacheKey.composition(width: width, height: height)
        func pinCurrent() -> CompositionTarget? {
            allocationCache.locked {
                guard var entry = allocationCache.residents[.current(key)],
                      !entry.isResetInvalidated,
                      entry.submissionPins.values.allSatisfy({ $0.orderingContext?.accepts(commandBuffer) == true }),
                      case .composition(let texture, let identity) = entry.allocation else { return nil }
                var pin: SceneGraphRenderTargetResidencyPin?
                if let commandBuffer {
                    let pinID = UUID()
                    entry.submissionPins[pinID] = .init(orderingContext: .init(commandBuffer: commandBuffer))
                    allocationCache.residents[.current(key)] = entry
                    allocationCache.revision = UUID()
                    pin = .init(identity: pinID, purpose: .submission,
                        generation: identity.generation, cache: allocationCache)
                }
                return CompositionTarget(texture: texture, pin: pin)
            }
        }
        if let current = pinCurrent() { return current }
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
        return pinCurrent()
    }

    struct PinnedTexture {
        let texture: MTLTexture
        let pin: SceneGraphRenderTargetResidencyPin
    }

    /// Stage all actual textures before changing residency. Completion/reset can
    /// change the revision while Metal allocates; that aborts the whole group.
    func reserveCompositionTargets(
        dimensions: [(width: Int, height: Int)], commandBuffer: MTLCommandBuffer,
        textureFactory: ((MTLTextureDescriptor) -> MTLTexture?)? = nil
    ) -> [PinnedTexture]? {
        reserveFrameTextures(dimensions: dimensions, mipmapped: false,
            commandBuffer: commandBuffer, textureFactory: textureFactory)
    }

    func reserveEnvironment(
        width: Int, height: Int, commandBuffer: MTLCommandBuffer,
        textureFactory: ((MTLTextureDescriptor) -> MTLTexture?)? = nil
    ) -> PinnedTexture? {
        reserveFrameTextures(dimensions: [(width, height)], mipmapped: true,
            commandBuffer: commandBuffer, textureFactory: textureFactory)?.first
    }

    private func reserveFrameTextures(
        dimensions: [(width: Int, height: Int)], mipmapped: Bool,
        commandBuffer: MTLCommandBuffer, textureFactory: ((MTLTextureDescriptor) -> MTLTexture?)?
    ) -> [PinnedTexture]? {
        if dimensions.isEmpty { return [] }
        var keys: Set<CacheKey> = []
        var descriptors: [CacheKey: MTLTextureDescriptor] = [:]
        var costs: [CacheKey: Int] = [:]
        for (width, height) in dimensions {
            let key = mipmapped ? CacheKey.environment(width: width, height: height)
                : .composition(width: width, height: height)
            if !keys.insert(key).inserted { continue }
            guard width > 0, height > 0, width <= maxDimension, height <= maxDimension else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                width: width, height: height, mipmapped: mipmapped)
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .renderTarget]
            var cost = 0, w = width, h = height
            for _ in 0..<descriptor.mipmapLevelCount {
                guard let level = byteCost(width: w, height: h, textureCount: 1) else { return nil }
                let (next, overflow) = cost.addingReportingOverflow(level)
                guard !overflow else { return nil }
                cost = next; w = max(1, w / 2); h = max(1, h / 2)
            }
            descriptors[key] = descriptor; costs[key] = cost
        }
        let planned: (revision: UUID, missing: Set<CacheKey>)? = allocationCache.locked {
            var proposed = allocationCache.residents
            var missing: Set<CacheKey> = []
            var incoming = 0
            for key in keys {
                if let entry = proposed[.current(key)], !entry.isResetInvalidated,
                   entry.submissionPins.values.allSatisfy({ $0.orderingContext?.accepts(commandBuffer) == true }) {
                    continue
                }
                missing.insert(key)
                if let previous = proposed.removeValue(forKey: .current(key)), previous.isPinned {
                    proposed[.retired(previous.allocation.generation)] = previous
                }
                let (next, overflow) = incoming.addingReportingOverflow(costs[key]!)
                guard !overflow else { return nil }
                incoming = next
            }
            guard allocationCache.evictToFit(&proposed, incomingCost: incoming, protected: keys) else { return nil }
            return (allocationCache.revision, missing)
        }
        guard let planned else { return nil }
        var candidates: [Candidate] = []
        for key in planned.missing {
            let descriptor = descriptors[key]!
            guard let texture = textureFactory?(descriptor) ?? (textureFactory == nil ? device.makeSceneTexture(descriptor: descriptor) : nil),
                  let identity = allocationCache.issuePhysicalIdentity(textures: [texture]) else { return nil }
            candidates.append(.init(key: key, allocation: .composition(texture, identity), byteCost: costs[key]!))
        }
        return allocationCache.locked {
            guard allocationCache.revision == planned.revision else { return nil }
            let staged: AllocationCache.Staged
            if candidates.isEmpty {
                staged = (allocationCache.residents, allocationCache.accessCounter)
            } else {
                guard let value = allocationCache.stageCandidates(candidates, protectedKeys: keys) else { return nil }
                staged = value
            }
            var values = staged.values
            var result: [PinnedTexture] = []
            for key in keys {
                guard var entry = values[.current(key)],
                      case let .composition(texture, identity) = entry.allocation else { return nil }
                let id = UUID()
                entry.submissionPins[id] = .init(orderingContext: .init(commandBuffer: commandBuffer))
                values[.current(key)] = entry
                result.append(.init(texture: texture, pin: .init(identity: id, purpose: .submission,
                    generation: identity.generation, cache: allocationCache)))
            }
            allocationCache.apply((values, staged.access))
            return result
        }
    }

    /// D1 composition-group target. The allocation is keyed by the logical
    /// group (its root layer) and the extent, so simultaneous groups each
    /// own isolated storage; the format follows the pool's backbuffer color
    /// contract and the caller clears transparently each frame. Content is
    /// never preserved across frames — history retention stays explicit
    /// graph-target territory.
    func compositionGroupTarget(
        layerID: Int,
        width requestedWidth: Int,
        height requestedHeight: Int,
        commandBuffer: MTLCommandBuffer
    ) -> (texture: MTLTexture, pin: SceneGraphRenderTargetResidencyPin)? {
        guard let (width, height) = SceneOffscreenResolutionPolicy.resolvedDimensions(
            width: requestedWidth,
            height: requestedHeight,
            hardLimit: maxDimension,
            policy: .exactSamplingTexture
        ) else { return nil }
        let key = CacheKey.compositionGroup(
            layerID: layerID,
            width: width,
            height: height
        )
        func pinCurrent() -> (MTLTexture, SceneGraphRenderTargetResidencyPin)? {
            allocationCache.locked {
                guard var entry = allocationCache.residents[.current(key)],
                      !entry.isResetInvalidated,
                      entry.submissionPins.values.allSatisfy({
                          $0.orderingContext?.accepts(commandBuffer) == true
                      }),
                      case .composition(let texture, let identity) = entry.allocation
                else { return nil }
                let pinID = UUID()
                entry.submissionPins[pinID] = .init(orderingContext:
                    .init(commandBuffer: commandBuffer))
                allocationCache.residents[.current(key)] = entry
                allocationCache.revision = UUID()
                return (texture, .init(identity: pinID, purpose: .submission,
                    generation: identity.generation, cache: allocationCache))
            }
        }
        if let current = pinCurrent() { return current }
        guard let byteCost = byteCost(width: width, height: height, textureCount: 1),
              byteCost <= residentByteBudget,
              allocationCache.locked({
                  var proposed = allocationCache.residents
                  return allocationCache.evictToFit(&proposed, incomingCost: byteCost)
              }),
              let texture = makeTexture(
                  width: width,
                  height: height,
                  label: "SceneCompositionGroup \(layerID) \(width)x\(height)"
              ), let identity = allocationCache.issuePhysicalIdentity(
                  textures: [texture]
              ) else { return nil }
        let candidate = Candidate(
            key: key,
            allocation: .composition(texture, identity),
            byteCost: byteCost
        )
        guard allocationCache.commit([candidate]) else { return nil }
        return pinCurrent()
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
        /// 缺口 5b 候选 A：原始 extent policy 纳入 memo 键——规划档位
        /// 变更时旧条目不可能命中新计划（M4.1 键覆盖全部输入）。
        let extentPolicy: SceneFullFrameExtentPolicy
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
        // 缺口 5b 候选 A：链工作 extent 拓扑档在规划入口统一裁决——非
        // exact 合同层一律 .standard（2048 上限），裸 poolLimit/hardLimit
        // 不进入链规划；exactSamplingTexture 层原 policy 逐字保留（含
        // resolvedDimensions 的 exactness 硬拒与终端 effectOutput 合同）。
        // make 的同 inputExtent 合同使"中间降档/终端保原幅"异构不可行，
        // 故整链共用这一个降档 extent（SceneLayerGraphTargetPlan.make 的
        // 同 extent 合同不改）。compositionTarget 的 sizing 不经过本入口。
        guard let size = SceneOffscreenResolutionPolicy.resolvedDimensions(
            width: requestedWidth,
            height: requestedHeight,
            hardLimit: maxDimension,
            policy: SceneOffscreenResolutionPolicy.chainPlanningPolicy(
                extentPolicy
            )
        ) else { return .failure(.invalidExtent) }
        // M4.1：make 为纯函数，键覆盖全部输入；命中即跳过逐层 make
        // （帧路径 adm 段 25.5ms 主项）。capability 换代自动换键；
        // reset() 清空；失败结果不缓存（保持重试语义）。
        if let plansMemoIdentity {
            let memoKey = PersistentPlansMemoKey(
                identity: plansMemoIdentity,
                extentPolicy: extentPolicy,
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
                materialFunctionTargets: targets,
                backbufferFormat: backbufferFormat
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
                materialFunctionTargets: targets,
                backbufferFormat: backbufferFormat
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
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: backbufferFormat.logicalBytesPerPixel)
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
        let texture = device.makeSceneTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }
}
