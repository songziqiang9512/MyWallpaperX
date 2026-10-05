// Appended to the existing offscreen-pool harness's pre-@main type support.
// Uses real plans, cache transitions, native textures and submission pins.
// Factory nil injection makes retry/transaction behavior deterministic; this
// does not replace the separate native process-budget pressure experiment.
@main
enum SceneGraphAllocationRecoveryHarness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Cache = SceneOffscreenTextureAllocationCache
    typealias Prepared = ScenePreparedPersistentGraphTargets

    enum Failure: Error { case setup(String) }
    final class Witness { weak var texture: MTLTexture? }

    static func need<T>(_ value: T?, _ description: String) throws -> T {
        guard let value else { throw Failure.setup(description) }
        return value
    }

    static func makePool(_ device: MTLDevice) -> SceneOffscreenTexturePool {
        .init(device: device, residentByteBudget: 16 * 1024 * 1024)
    }

    /// A small authored graph with one scaled framebuffer, so shared-pair
    /// preparation still has a subsequent graph-owned physical allocation.
    static func graph(layer: Int) -> Graph {
        let effect = Graph.EffectKey(layerID: layer, effectIndex: 0,
            descriptorID: "\(layer)#effect#0")
        let input = Graph.TextureIdentity(kind: .layerSource, layerID: layer,
            effect: nil, name: nil)
        let output = Graph.TextureIdentity(kind: .effectOutput, layerID: layer,
            effect: effect, name: nil)
        let scratch = Graph.TextureIdentity(kind: .framebuffer, layerID: layer,
            effect: effect, name: "scratch")
        func node(_ index: Int, _ target: Graph.TextureIdentity,
                  _ source: Graph.TextureIdentity) -> Graph.Node {
            .init(nodeIndex: index, effect: effect, definitionPassIndex: index,
                materialOrdinal: index, instancePassIndex: index, kind: .material,
                materialPath: "materials/recovery-\(index).json",
                materialPassID: "materials/recovery-\(index).json#0", target: target,
                bindings: [.init(slot: 0, authoredName: source.name ?? "previous",
                    texture: source, conditions: nil)],
                commandSource: nil, commandTarget: nil, compose: nil, conditions: nil)
        }
        let nodes = [node(0, scratch, input), node(1, output, scratch)]
        return .init(layerID: layer,
            effects: [.init(key: effect, definitionPath: "effects/recovery/effect.json",
                input: input, output: output, nodeIndices: nodes.map(\.nodeIndex))],
            renderTargets: [.init(texture: scratch,
                extent: .init(kind: .scale, first: 2, second: nil),
                format: "rgba_backbuffer", declaredUnique: false,
                clear: nil, uvs: nil, conditions: nil)],
            nodes: nodes, finalOutput: output, blockers: [])
    }

    static func plan(_ pool: SceneOffscreenTexturePool, layer: Int,
                     shared: Bool = false) throws -> SceneLayerGraphTargetPlan {
        try framePlan(pool, layer: layer, shared: shared).graphPlan
    }

    static func framePlan(_ pool: SceneOffscreenTexturePool, layer: Int,
                          shared: Bool) throws -> ScenePersistentGraphTargetFramePlan {
        let authored = graph(layer: layer)
        guard case let .success(pair) = SceneLayerFullFramePairPlan.make(
            conditionPrunedGraphs: [authored]
        ) else { throw Failure.setup("full-frame pair plan") }
        return try need(pool.framePlanForPersistentGraphTargets(
            admittedGraphs: [authored], pairPlan: pair,
            requestedWidth: 32, requestedHeight: 32,
            usesSharedFullFrameWorkingPair: shared
        ), "persistent graph frame plan")
    }

    static func native(_ device: MTLDevice, _ descriptor: MTLTextureDescriptor,
                       _ label: String) -> MTLTexture? {
        let texture = device.makeSceneTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    static func seedIdle(_ pool: SceneOffscreenTexturePool,
                         commandBuffer: MTLCommandBuffer) throws {
        try autoreleasepool {
            let value = try need(pool.reserveEnvironment(width: 17, height: 17,
                commandBuffer: commandBuffer), "idle environment")
            value.pin.release()
        }
    }

    static func objects(_ allocation: SceneLayerGraphTargetAllocation)
        -> Set<ObjectIdentifier> {
        Set(allocation.texturesBySlot.values.map { ObjectIdentifier($0) })
    }

    static func currentGraph(_ cache: Cache, _ plan: SceneLayerGraphTargetPlan)
        -> SceneLayerGraphTargetAllocation? {
        guard case let .layerGraph(value)? = cache.allocation(for: .layerGraph(plan.key))
        else { return nil }
        return value
    }

    static func requests(_ prepared: [Prepared]) throws -> [Prepared.CommitRequest] {
        try prepared.map {
            try need($0.takeCommitRequest(historyTokensByEffect: [:],
                commandBuffer: nil), "one-shot commit request")
        }
    }

    static func sharedThenGraph(_ device: MTLDevice, _ queue: MTLCommandQueue)
        throws -> [String: Bool] {
        let pool = makePool(device), cache = pool.allocationCache
        let commandBuffer = try need(queue.makeCommandBuffer(), "idle pin buffer")
        try seedIdle(pool, commandBuffer: commandBuffer)
        let graphPlan = try plan(pool, layer: 710, shared: true)
        let extent = try need(graphPlan.sharedPairDimensions, "shared pair extent")
        let key = Cache.Key.sharedGraphPair(width: extent.width, height: extent.height)
        let batch = SceneGraphAllocationRecoveryBatch(cache: cache,
            protectedKeys: [.layerGraph(graphPlan.key), key])
        var calls: [String: Int] = [:]
        let candidate = try need(pool.sharedPairCandidate(
            width: extent.width, height: extent.height,
            textureFactory: { descriptor, label in
                calls[label, default: 0] += 1
                if label.hasPrefix("SceneSharedPairB"), calls[label] == 1 { return nil }
                return native(device, descriptor, label)
            }, recoveryBatch: batch
        ), "shared pair recovered candidate")
        let pairCommitted = batch.commitSharedPairs([candidate], requiredKeys: [key])
        guard pairCommitted else { throw Failure.setup("shared pair commit") }
        // A second real idle resident remains available. Install it through the
        // same atomic commit API (which returns our own revision), so a second
        // recovery would have an observable victim instead of being a no-op.
        let idleKey = Cache.Key.sharedGraphPair(width: 9, height: 9)
        let idle = try need(pool.sharedPairCandidate(width: 9, height: 9,
            recoveryBatch: batch), "second idle pair")
        guard batch.commitSharedPairs([idle], requiredKeys: [idleKey]) else {
            throw Failure.setup("second idle pair commit")
        }
        var graphCalls = 0
        let allocator = ScenePersistentGraphTargetAllocator(device: device,
            cache: cache, textureFactory: { descriptor, label in
                graphCalls += 1
                return graphCalls == 1 ? nil : native(device, descriptor, label)
            })
        let prepared = allocator.prepare(plans: [graphPlan], recoveryBatch: batch)
        return [
            "sharedPairRecovered": pairCommitted
                && cache.allocation(for: .environment(width: 17, height: 17)) == nil,
            "sharedPairPrefixAllocatedOnce": calls.count == 2
                && calls.filter { $0.key.hasPrefix("SceneSharedPairA") }.values.first == 1
                && calls.filter { $0.key.hasPrefix("SceneSharedPairB") }.values.first == 2,
            "graphSecondFailureNotRetried": prepared == nil && graphCalls == 1,
            "secondIdleVictimNotReclaimed": cache.allocation(for: idleKey) != nil,
            "failedGraphNotPublished": currentGraph(cache, graphPlan) == nil,
        ]
    }

    static func prefixRecovery(_ device: MTLDevice, _ queue: MTLCommandQueue)
        throws -> [String: Bool] {
        let pool = makePool(device), cache = pool.allocationCache
        try seedIdle(pool, commandBuffer: need(queue.makeCommandBuffer(), "prefix buffer"))
        let first = try plan(pool, layer: 720), second = try plan(pool, layer: 721)
        guard second.slots.count >= 2 else { throw Failure.setup("multiple owned slots") }
        let failLabel = "SceneLayerGraphRT layer=721 slot=\(second.slots[1].id)"
        var calls: [String: Int] = [:]
        var produced: [String: ObjectIdentifier] = [:]
        let allocator = ScenePersistentGraphTargetAllocator(device: device,
            cache: cache, textureFactory: { descriptor, label in
                calls[label, default: 0] += 1
                if label == failLabel, calls[label] == 1 { return nil }
                let texture = native(device, descriptor, label)
                if let texture { produced[label] = ObjectIdentifier(texture) }
                return texture
            })
        let prepared = try need(allocator.prepare(plans: [first, second]), "prefix recovery")
        let unpublished = [first, second].allSatisfy { currentGraph(cache, $0) == nil }
        let requests = try requests(prepared)
        let identitiesPreserved = requests.allSatisfy { request in
            guard case let .layerGraph(allocation) = request.candidate.allocation else { return false }
            return allocation.texturesBySlot.allSatisfy { slot, texture in
                produced["SceneLayerGraphRT layer=\(allocation.plan.key.layerID) slot=\(slot)"]
                    == ObjectIdentifier(texture)
            }
        }
        let commits = cache.commitAndPin(requests)
        defer { commits?.forEach { $0.releaseAll() } }
        return [
            "laterGraphRecovered": calls[failLabel] == 2
                && cache.allocation(for: .environment(width: 17, height: 17)) == nil,
            "prefixFactoriesNotRepeated": calls.count == first.slots.count + second.slots.count
                && calls.allSatisfy { $0.value == ($0.key == failLabel ? 2 : 1) },
            "prefixTextureIdentitiesPreserved": identitiesPreserved,
            "prepareDidNotPublishGraphs": unpublished,
            "recoveredBatchCommittedAtomically": commits?.count == 2
                && [first, second].allSatisfy { currentGraph(cache, $0) != nil },
        ]
    }

    static func retiredRecovery(_ device: MTLDevice, _ queue: MTLCommandQueue)
        throws -> [String: Bool] {
        let pool = makePool(device), cache = pool.allocationCache
        let reusablePlan = try plan(pool, layer: 730), laterPlan = try plan(pool, layer: 731)
        let allocator = ScenePersistentGraphTargetAllocator(device: device, cache: cache)
        let first = try need(allocator.prepare(plan: reusablePlan), "first allocation")
        let firstCommit = try need(first.commitAndPin(historyTokensByEffect: [:]), "first commit")
        defer { firstCommit.releaseAll() }
        let original = try need(currentGraph(cache, reusablePlan), "original graph")
        let retiredGeneration = original.generation
        let originalObjects = objects(original)
        // No command-queue ordering proof is supplied. The pinned first graph
        // must be replaced, then releasing its pin leaves a real retired entry.
        let second = try need(allocator.prepare(plan: reusablePlan), "replacement allocation")
        let secondCommit = try need(second.commitAndPin(historyTokensByEffect: [:]), "replacement commit")
        defer { secondCommit.releaseAll() }
        firstCommit.releaseAll()
        try seedIdle(pool, commandBuffer: need(queue.makeCommandBuffer(), "retired buffer"))
        let reservations = try need(cache.reserveGraphs(plans: [reusablePlan, laterPlan]),
            "reusable reservations")
        let selected = reservations[0].consumedRetiredGeneration == retiredGeneration
            && reservations[0].reusableAllocation?.generation == retiredGeneration
        var calls: [String: Int] = [:]
        var failed = false
        let recovering = ScenePersistentGraphTargetAllocator(device: device, cache: cache,
            textureFactory: { descriptor, label in
                calls[label, default: 0] += 1
                if !failed { failed = true; return nil }
                return native(device, descriptor, label)
            })
        let prepared = try need(recovering.prepare(plans: [reusablePlan, laterPlan],
            reservations: reservations), "retired recovery")
        let survived = cache.locked { cache.residents[.retired(retiredGeneration)] != nil }
        let requests = try requests(prepared)
        let preserved: Bool
        if case let .layerGraph(reused) = requests[0].candidate.allocation {
            preserved = objects(reused) == originalObjects && reused.generation != retiredGeneration
        } else { preserved = false }
        let commits = cache.commitAndPin(requests)
        defer { commits?.forEach { $0.releaseAll() } }
        return [
            "reservationSelectedRetiredReusable": selected,
            "retiredGenerationSurvivedReclaim": survived
                && cache.allocation(for: .environment(width: 17, height: 17)) == nil,
            "reusableTexturesNotAllocatedAgain": !calls.isEmpty
                && calls.keys.allSatisfy { $0.hasPrefix("SceneLayerGraphRT layer=731 ") },
            "reusablePhysicalTexturesPreserved": preserved,
            "reusableBatchCommitted": commits?.count == 2,
            "retiredGenerationConsumedOnlyAtCommit": survived && commits?.count == 2
                && cache.locked { cache.residents[.retired(retiredGeneration)] == nil },
        ]
    }

    static func externalRevision(_ device: MTLDevice, _ queue: MTLCommandQueue)
        throws -> [String: Bool] {
        let pool = makePool(device), cache = pool.allocationCache
        let commandBuffer = try need(queue.makeCommandBuffer(), "external revision buffer")
        try seedIdle(pool, commandBuffer: commandBuffer)
        let pinned = try need(pool.reserveEnvironment(width: 19, height: 19,
            commandBuffer: commandBuffer), "external mutation pin")
        defer { pinned.pin.release() }
        let graphPlan = try plan(pool, layer: 740)
        let revision = cache.locked { cache.revision }
        var calls = 0
        let allocator = ScenePersistentGraphTargetAllocator(device: device, cache: cache,
            textureFactory: { _, _ in
                calls += 1
                // Actual pin release changes revision without changing resetEpoch.
                // Recovery must not absorb this as its own successful reclaim.
                pinned.pin.release()
                return nil
            })
        let prepared = allocator.prepare(plans: [graphPlan])
        return [
            "externalRevisionAbort": prepared == nil && cache.locked { cache.revision != revision },
            "externalRevisionNoRetry": calls == 1,
            "externalRevisionKeptIdleVictim": cache.allocation(
                for: .environment(width: 17, height: 17)) != nil,
            "externalRevisionNoGraphPublication": currentGraph(cache, graphPlan) == nil,
        ]
    }

    static func cachedCompletion(_ device: MTLDevice, _ queue: MTLCommandQueue,
                                 shared: Bool) throws -> [String: Bool] {
        let pool = makePool(device), cache = pool.allocationCache
        let frame = try framePlan(pool, layer: 745, shared: shared)
        let initial = try need(pool.preparePersistentGraphTargets(framePlans: [frame]), "cached seed")
        let commits = try need(cache.commitAndPin(try requests(initial)), "cached seed commit")
        commits.forEach { $0.releaseAll() }
        let original = try need(currentGraph(cache, frame.graphPlan), "cached graph")
        let external = try need(pool.reserveEnvironment(width: 19, height: 19,
            commandBuffer: need(queue.makeCommandBuffer(), "completion buffer")), "completion pin")
        let batch = SceneGraphAllocationRecoveryBatch(cache: cache,
            protectedKeys: [.layerGraph(frame.graphPlan.key)])
        let reservations = try need(cache.reserveGraphs(plans: [frame.graphPlan]), "cached reservation")
        external.pin.release() // GPU completion's actual cache mutation, between reservation and preparation.
        var factories = 0
        let allocator = ScenePersistentGraphTargetAllocator(device: device, cache: cache,
            textureFactory: { _, _ in factories += 1; return nil })
        let targets = allocator.prepare(plans: [frame.graphPlan], reservations: reservations,
            recoveryBatch: batch)
        let admitted = targets.flatMap { cache.admitPreparedTargets($0) }
        let final = admitted?.finalize(historyTokensByTarget: [[:]])
        final?.forEach { $0.releaseAll() }
        let preserved = currentGraph(cache, frame.graphPlan).map {
            $0.generation == original.generation && objects($0) == objects(original)
        } ?? false
        let beforeReset = try need(cache.reserveGraphs(plans: [frame.graphPlan]), "reset reservation")
        pool.reset()
        let staleRejected = allocator.prepare(plans: [frame.graphPlan], reservations: beforeReset) == nil
        return ["cachedCompletionAccepted": final?.count == 1,
                "cachedCompletionPreservedTextures": preserved && factories == 0,
                "cachedCompletionRejectsReset": staleRejected]
    }

    static func allocatingCompletion(_ device: MTLDevice, _ queue: MTLCommandQueue,
                                     shared: Bool, beforePrepare: Bool, reset: Bool)
        throws -> [String: Bool] {
        let pool = makePool(device), cache = pool.allocationCache
        let cached = try framePlan(pool, layer: 746, shared: shared)
        let fresh = try framePlan(pool, layer: 747, shared: shared)
        let initial = try need(pool.preparePersistentGraphTargets(framePlans: [cached]), "mixed seed")
        let commits = try need(cache.commitAndPin(try requests(initial)), "mixed seed commit")
        commits.forEach { $0.releaseAll() }
        let original = try need(currentGraph(cache, cached.graphPlan), "mixed cached graph")
        let external = try need(pool.reserveEnvironment(width: 19, height: 19,
            commandBuffer: need(queue.makeCommandBuffer(), "mixed completion buffer")), "mixed pin")
        defer { external.pin.release() }
        let plans = [cached.graphPlan, fresh.graphPlan]
        let batch = SceneGraphAllocationRecoveryBatch(cache: cache,
            protectedKeys: Set(plans.map { .layerGraph($0.key) }))
        let buffer = try need(queue.makeCommandBuffer(), "mixed target buffer")
        let reservations = try need(cache.reserveGraphs(plans: plans,
            orderingContext: .init(commandBuffer: buffer)), "mixed reservations")
        if beforePrepare { external.pin.release() }
        var factories = 0
        let allocator = ScenePersistentGraphTargetAllocator(device: device, cache: cache,
            textureFactory: { descriptor, label in
                factories += 1
                if reset { pool.reset() } else { external.pin.release() }
                return native(device, descriptor, label)
            })
        let targets = allocator.prepare(plans: plans, reservations: reservations, recoveryBatch: batch)
        let unpublished = currentGraph(cache, fresh.graphPlan) == nil
        let final = targets.flatMap { cache.admitPreparedTargets($0) }?
            .finalize(historyTokensByTarget: [[:], [:]], commandBuffer: buffer)
        defer { final?.forEach { $0.releaseAll() } }
        if reset { return ["resetRejected": targets == nil && final == nil && unpublished] }
        let expectedFactories = fresh.graphPlan.slots.count - (shared ? 2 : 0)
        return ["mixedCompletionAccepted": final?.count == 2,
                "allocatedOnce": factories == expectedFactories,
                "prepareUnpublished": unpublished,
                "cachedTexturePreserved": currentGraph(cache, cached.graphPlan).map {
                    $0.generation == original.generation && objects($0) == objects(original)
                } ?? false]
    }

    static func sharedPairCompletion(_ device: MTLDevice, _ queue: MTLCommandQueue,
                                     mutation: String) throws -> [String: Bool] {
        let pool = makePool(device), cache = pool.allocationCache
        let key = Cache.Key.sharedGraphPair(width: 32, height: 32)
        let external = try need(pool.reserveEnvironment(width: 19, height: 19,
            commandBuffer: need(queue.makeCommandBuffer(), "pair completion buffer")), "pair pin")
        defer { external.pin.release() }
        let batch = SceneGraphAllocationRecoveryBatch(cache: cache, protectedKeys: [key])
        let candidate = try need(pool.sharedPairCandidate(width: 32, height: 32,
            recoveryBatch: batch), "pending pair")
        var competingGeneration: UInt64?
        if mutation == "reset" { pool.reset() }
        else if mutation == "replacement" {
            guard pool.ensureSharedPairs([key]) else { throw Failure.setup("competing pair") }
            competingGeneration = cache.allocation(for: key)?.generation
        } else { external.pin.release() }
        let accepted = batch.commitSharedPairs([candidate], requiredKeys: [key])
        if mutation == "reset" { return ["pairResetRejected": !accepted && cache.allocation(for: key) == nil] }
        if mutation == "replacement" {
            return ["pairReplacementRejected": !accepted
                && cache.allocation(for: key)?.generation == competingGeneration]
        }
        return ["pairCompletionAccepted": accepted
            && cache.allocation(for: key)?.generation == candidate.allocation.generation]
    }

    /// Exercises the pool's complete entry point without a factory seam. The
    /// artificial reservation limits the real shared quota; it is not a claim
    /// of physical device OOM. Descriptor charges come from cold native leases.
    static func poolEntryPressure(_ device: MTLDevice, _ queue: MTLCommandQueue,
                                  shared: Bool) throws -> [String: Any] {
        let account = SceneResourceBudget.shared
        let original = account.snapshot.residentBytes
        var row = try autoreleasepool {
            // Keep another actual pool's pinned resource throughout both cold
            // measurement and pressure. Neither accounting nor reclamation may
            // erase this pre-existing resident to make the requested graph fit.
            let protectedPool = makePool(device)
            let protected = try need(protectedPool.reserveEnvironment(width: 7, height: 7,
                commandBuffer: need(queue.makeCommandBuffer(), "protected entry buffer")),
                "protected external pool resident")
            defer { protected.pin.release(); protectedPool.reset() }
            let baseline = account.snapshot.residentBytes
            let protectedGeneration = protected.pin.generation
            var result = try poolEntryPressureWithBaseline(device, queue,
                shared: shared, baseline: baseline)
            result["protectedNativeCharge"] = baseline - original
            result["protectedResidentSurvived"] = protectedPool.allocationCache.allocation(
                for: .environment(width: 7, height: 7))?.generation == protectedGeneration
                && account.snapshot.residentBytes == baseline
            withExtendedLifetime(protected) {}
            return result
        }
        row["originalAccountBytes"] = original
        row["finalAccountBytes"] = account.snapshot.residentBytes
        return row
    }

    static func poolEntryPressureWithBaseline(_ device: MTLDevice, _ queue: MTLCommandQueue,
                                              shared: Bool, baseline: Int)
        throws -> [String: Any] {
        let account = SceneResourceBudget.shared
        let layer = shared ? 751 : 750
        var needed = 0
        try autoreleasepool {
            let cold = makePool(device)
            defer { cold.reset() }
            let frame = try framePlan(cold, layer: layer, shared: shared)
            let prepared = try need(cold.preparePersistentGraphTargets(framePlans: [frame]),
                "cold pool entry prepare")
            let commits = try need(cold.commitAndPinPersistentGraphTargets(prepared,
                historyTokensByTarget: [[:]],
                commandBuffer: need(queue.makeCommandBuffer(), "cold entry buffer")),
                "cold pool entry commit")
            defer { commits.forEach { $0.releaseAll() } }
            needed = account.snapshot.residentBytes - baseline
        }
        guard needed > 0, account.snapshot.residentBytes == baseline else {
            throw Failure.setup("cold measurement did not release native leases")
        }
        var guardBytes = 0
        defer { if guardBytes > 0 { account.release(guardBytes, kind: .gpu) } }
        var row = try autoreleasepool { () throws -> [String: Any] in
            let pool = makePool(device)
            defer { pool.reset() }
            let commandBuffer = try need(queue.makeCommandBuffer(), "warm entry buffer")
            let frame = try framePlan(pool, layer: layer, shared: shared)
            let witness = Witness()
            try autoreleasepool {
                let idle = try need(pool.reserveEnvironment(width: 17, height: 17,
                    commandBuffer: commandBuffer), "warm idle environment")
                witness.texture = idle.texture
                idle.pin.release()
            }
            let idleCharge = account.snapshot.residentBytes - baseline
            // Total room for this cache equals the measured cold graph charge.
            // Its warm idle environment therefore forces a native rejection
            // somewhere in the real shared-pair/graph allocation sequence.
            let reserved = account.maximumBytes - baseline - needed
            guard idleCharge > 0, idleCharge < needed, reserved >= 0,
                  account.reserve(reserved, kind: .gpu) else {
                throw Failure.setup("cannot establish exact cold-charge quota")
            }
            guardBytes = reserved
            let before = account.snapshot
            let prepared = pool.preparePersistentGraphTargets(framePlans: [frame])
            let commits = prepared.flatMap { pool.commitAndPinPersistentGraphTargets($0,
                historyTokensByTarget: [[:]], commandBuffer: commandBuffer) }
            defer { commits?.forEach { $0.releaseAll() } }
            let after = account.snapshot
            let pairPresent: Bool
            if shared, let extent = frame.graphPlan.sharedPairDimensions {
                pairPresent = pool.allocationCache.allocation(for: .sharedGraphPair(
                    width: extent.width, height: extent.height)) != nil
            } else { pairPresent = !shared }
            return [
                "shared": shared,
                "baselineAccountBytes": baseline,
                "coldNativeCharge": needed,
                "idleNativeCharge": idleCharge,
                "reservedQuotaBytes": reserved,
                "availableBeforePrepare": account.maximumBytes - before.residentBytes,
                "nativeQuotaRejections": after.rejectionCount - before.rejectionCount,
                "warmNativeCharge": after.residentBytes - baseline - reserved,
                "prepared": prepared?.count == 1,
                "committed": commits?.count == 1,
                "graphPublished": currentGraph(pool.allocationCache, frame.graphPlan) != nil,
                "sharedPairPresent": pairPresent,
                "idleActuallyReleased": witness.texture == nil,
                "idleCacheEntryRemoved": pool.allocationCache.allocation(
                    for: .environment(width: 17, height: 17)) == nil,
            ]
        }
        row["accountAfterResetWithGuard"] = account.snapshot.residentBytes
        account.release(guardBytes, kind: .gpu)
        guardBytes = 0
        row["accountAfterGuardRelease"] = account.snapshot.residentBytes
        return row
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        var result: [String: Any] = [:]
        for values in [try sharedThenGraph(device, queue), try prefixRecovery(device, queue),
                       try retiredRecovery(device, queue), try externalRevision(device, queue)] {
            for (key, value) in values {
                precondition(result[key] == nil, "duplicate result key")
                result[key] = value
            }
        }
        result["cachedCompletion"] = try [false, true].map {
            try cachedCompletion(device, queue, shared: $0)
        }
        result["allocatingCompletion"] = try [false, true].flatMap { shared in
            try [false, true].map {
                try allocatingCompletion(device, queue, shared: shared, beforePrepare: $0, reset: false)
            } + [try allocatingCompletion(device, queue, shared: shared, beforePrepare: false, reset: true)]
        }
        result["sharedPairCompletion"] = try ["completion", "replacement", "reset"].map {
            try sharedPairCompletion(device, queue, mutation: $0)
        }
        result["poolEntryPressure"] = try [false, true].map {
            try poolEntryPressure(device, queue, shared: $0)
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
