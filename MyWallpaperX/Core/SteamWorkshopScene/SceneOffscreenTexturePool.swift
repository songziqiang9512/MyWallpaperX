import Metal

final class SceneOffscreenTexturePool {
    struct Pair {
        let primary: MTLTexture
        let secondary: MTLTexture
        let tertiary: MTLTexture
    }

    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat

    private enum CacheKey: Hashable {
        case pair(width: Int, height: Int)
        case graph(SceneAuthoredEffectRenderPlan.EffectKey)
    }

    private enum Allocation {
        case pair(Pair)
        case graph(SceneGraphRenderTargetTable)

        var textureCount: Int {
            switch self {
            case .pair:
                return 3
            case .graph(let table):
                return table.residentTextureCount
            }
        }
    }

    private struct Entry {
        let allocation: Allocation
        let byteCost: Int
        var lastAccess: UInt64
    }

    private let maxDimension: Int
    // This caps cache residency after a transaction commits. Graph replacements
    // build their candidate first, so transient driver allocations can exceed it.
    private let residentByteBudget: Int
    private var cachedAllocations: [CacheKey: Entry] = [:]
    private var accessCounter: UInt64 = 0

    private(set) var residentByteCost = 0

    var residentAllocationCount: Int {
        cachedAllocations.count
    }

    var residentTextureCount: Int {
        cachedAllocations.values.reduce(0) { $0 + $1.allocation.textureCount }
    }

    init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        maxDimension: Int = 2048,
        residentByteBudget: Int = 96 * 1_024 * 1_024
    ) {
        self.device = device
        self.pixelFormat = pixelFormat
        self.maxDimension = max(maxDimension, 1)
        self.residentByteBudget = max(residentByteBudget, 0)
    }

    func textures(for sourceTexture: MTLTexture) -> Pair? {
        textures(width: sourceTexture.width, height: sourceTexture.height)
    }

    func textures(width requestedWidth: Int, height requestedHeight: Int) -> Pair? {
        let (width, height) = limitedDimensions(width: requestedWidth, height: requestedHeight)
        let key = CacheKey.pair(width: width, height: height)
        accessCounter &+= 1
        if var cached = cachedAllocations[key], case .pair(let pair) = cached.allocation {
            cached.lastAccess = accessCounter
            cachedAllocations[key] = cached
            return pair
        }

        guard let byteCost = byteCost(width: width, height: height, textureCount: 3),
              byteCost <= residentByteBudget else {
            return nil
        }
        evictUntilAffordable(byteCost)

        let label = "pair:\(width)x\(height)"
        guard let primary = makeTexture(width: width, height: height, label: "SceneOffscreenA \(label)"),
              let secondary = makeTexture(width: width, height: height, label: "SceneOffscreenB \(label)"),
              let tertiary = makeTexture(width: width, height: height, label: "SceneOffscreenC \(label)") else {
            return nil
        }

        let pair = Pair(primary: primary, secondary: secondary, tertiary: tertiary)
        cachedAllocations[key] = Entry(
            allocation: .pair(pair), byteCost: byteCost, lastAccess: accessCounter
        )
        residentByteCost += byteCost
        return pair
    }

    func graphTargets(
        for executionPlan: SceneAuthoredEffectExecutionPlan,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> SceneGraphRenderTargetTable? {
        graphTargetTransaction(
            stages: [executionPlan],
            layerID: executionPlan.layerID,
            validatesChainOrder: false,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight
        )?.first
    }

    func graphTargets(
        for chain: SceneAuthoredEffectExecutionChain,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> [SceneGraphRenderTargetTable]? {
        graphTargetTransaction(
            stages: chain.stages,
            layerID: chain.layerID,
            validatesChainOrder: true,
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight
        )
    }

    private func graphTargetTransaction(
        stages: [SceneAuthoredEffectExecutionPlan],
        layerID: Int,
        validatesChainOrder: Bool,
        requestedWidth: Int,
        requestedHeight: Int
    ) -> [SceneGraphRenderTargetTable]? {
        guard pixelFormat == .bgra8Unorm else { return nil }
        guard !stages.isEmpty, stages.allSatisfy({ $0.layerID == layerID }) else {
            return nil
        }
        let (width, height) = limitedDimensions(
            width: requestedWidth,
            height: requestedHeight
        )
        if stages.contains(where: \.requiresExactInputExtent),
           (requestedWidth <= 0 || requestedHeight <= 0
               || width != requestedWidth || height != requestedHeight) {
            return nil
        }

        var plans: [SceneGraphRenderTargetPlan] = []
        plans.reserveCapacity(stages.count)
        var priorOutput: SceneAuthoredEffectRenderPlan.TextureIdentity?
        for stage in stages {
            guard case .success(let plan) = SceneGraphRenderTargetPlan.make(
                executionPlan: stage,
                graph: stage.renderGraph,
                inputWidth: width,
                inputHeight: height
            ) else { return nil }
            if validatesChainOrder {
                if let priorOutput {
                    guard plan.inputRole == .priorEffectOutput,
                          plan.input == priorOutput else { return nil }
                } else {
                    guard plan.inputRole == .layerSource else { return nil }
                }
            }
            plans.append(plan)
            priorOutput = plan.output
        }

        var keys: [CacheKey] = []
        var tables: [SceneGraphRenderTargetTable] = []
        var uniqueKeys = Set<CacheKey>()
        keys.reserveCapacity(plans.count)
        tables.reserveCapacity(plans.count)
        for plan in plans {
            guard let effect = plan.output.effect else { return nil }
            let key = CacheKey.graph(effect)
            guard uniqueKeys.insert(key).inserted else { return nil }
            keys.append(key)
            if let cached = cachedAllocations[key],
               case .graph(let table) = cached.allocation,
               table.plan == plan {
                tables.append(table)
                continue
            }
            guard case .success(let table) = SceneGraphRenderTargetTable.make(
                plan: plan,
                device: device,
                byteBudget: residentByteBudget
            ) else { return nil }
            tables.append(table)
        }

        var incomingByteCost = 0
        for table in tables {
            let (nextCost, overflow) = incomingByteCost.addingReportingOverflow(
                table.residentByteCost
            )
            guard !overflow else { return nil }
            incomingByteCost = nextCost
        }
        guard let victims = evictionKeys(
            incomingByteCost: incomingByteCost,
            replacing: uniqueKeys
        ) else { return nil }

        var nextAccess = accessCounter
        let entries = tables.map { table -> Entry in
            nextAccess &+= 1
            return Entry(
                allocation: .graph(table),
                byteCost: table.residentByteCost,
                lastAccess: nextAccess
            )
        }

        var nextAllocations = cachedAllocations
        for victim in victims {
            nextAllocations.removeValue(forKey: victim)
        }
        for key in keys {
            nextAllocations.removeValue(forKey: key)
        }
        for (key, entry) in zip(keys, entries) {
            nextAllocations[key] = entry
        }
        let nextResidentByteCost = nextAllocations.values.reduce(0) { $0 + $1.byteCost }
        guard nextResidentByteCost <= residentByteBudget else { return nil }
        cachedAllocations = nextAllocations
        residentByteCost = nextResidentByteCost
        accessCounter = nextAccess
        return tables
    }

    func reset() {
        cachedAllocations.removeAll()
        residentByteCost = 0
        accessCounter = 0
    }

    private func limitedDimensions(width requestedWidth: Int, height requestedHeight: Int) -> (Int, Int) {
        let sourceWidth = max(1, requestedWidth)
        let sourceHeight = max(1, requestedHeight)
        let longestEdge = max(sourceWidth, sourceHeight)
        let scale = longestEdge > maxDimension ? Double(maxDimension) / Double(longestEdge) : 1
        return (
            max(1, Int((Double(sourceWidth) * scale).rounded())),
            max(1, Int((Double(sourceHeight) * scale).rounded()))
        )
    }

    private func evictUntilAffordable(_ incomingByteCost: Int) {
        while !cachedAllocations.isEmpty,
              residentByteCost > residentByteBudget - incomingByteCost,
              let oldest = cachedAllocations.min(by: {
                  $0.value.lastAccess < $1.value.lastAccess
              }) {
            removeCachedAllocation(for: oldest.key)
        }
    }

    private func evictionKeys(
        incomingByteCost: Int,
        replacing keys: Set<CacheKey>
    ) -> [CacheKey]? {
        guard incomingByteCost <= residentByteBudget else { return nil }
        var replacedByteCost = 0
        for key in keys {
            let (nextCost, overflow) = replacedByteCost.addingReportingOverflow(
                cachedAllocations[key]?.byteCost ?? 0
            )
            guard !overflow else { return nil }
            replacedByteCost = nextCost
        }
        let retainedByteCost = residentByteCost - replacedByteCost
        guard retainedByteCost >= 0 else { return nil }
        let (initialProjectedCost, overflow) = retainedByteCost.addingReportingOverflow(
            incomingByteCost
        )
        guard !overflow else { return nil }
        var projectedByteCost = initialProjectedCost
        if projectedByteCost <= residentByteBudget { return [] }

        var victims: [CacheKey] = []
        let candidates = cachedAllocations
            .filter { !keys.contains($0.key) }
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
        for candidate in candidates where projectedByteCost > residentByteBudget {
            victims.append(candidate.key)
            projectedByteCost -= candidate.value.byteCost
        }
        return projectedByteCost <= residentByteBudget ? victims : nil
    }

    private func removeCachedAllocation(for key: CacheKey) {
        guard let removed = cachedAllocations.removeValue(forKey: key) else { return }
        residentByteCost -= removed.byteCost
    }

    private func byteCost(width: Int, height: Int, textureCount: Int) -> Int? {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow else { return nil }
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !byteOverflow else { return nil }
        let (total, totalOverflow) = bytes.multipliedReportingOverflow(by: textureCount)
        return totalOverflow ? nil : total
    }

    private func makeTexture(width: Int, height: Int, label: String) -> MTLTexture? {
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
