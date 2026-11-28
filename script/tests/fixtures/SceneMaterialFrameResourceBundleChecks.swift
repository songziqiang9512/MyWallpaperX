import Foundation
import Metal

struct PhaseProbeState {
    let coordinator: SceneResolvedMaterialSubmissionCoordinator
    let pool: SceneOffscreenTexturePool
    let buffer: MTLCommandBuffer
    let target: SceneResolvedMaterialFrameTargetPlan
    let request: SceneResolvedMaterialRuntimeBridge.FramePreparationRequest
}

func coordinatorBundleIdentityChecks(device: MTLDevice, queue: MTLCommandQueue,
    source: MTLTexture, pipeline: SceneImageLayerPipeline) -> [String: Any] {
    var checks: [String: Any] = [:]
    for mode in ["wrongBuffer", "wrongPool", "emptyRequests", "duplicatePlans", "cancel"] {
        let s = makePhaseProbeState(device: device, queue: queue, source: source, pipeline: pipeline)
        let otherPool = SceneOffscreenTexturePool(device: device, residentByteBudget: 1_048_576)
        defer { _ = s.coordinator.endFrame(); s.pool.reset(); otherPool.reset() }
        let preparation = s.coordinator.prepareFrameResourceBundle(plans: mode == "duplicatePlans" ? [s.target, s.target] : [s.target],
            pool: s.pool, commandBuffer: s.buffer)
        if mode == "duplicatePlans" {
            let rejected: Bool
            if case .rejected = preparation { rejected = true } else { rejected = false }
            checks["duplicatePlansRejectedBeforeAllocation"] = rejected && s.pool.residentByteCost == 0
            continue
        }
        guard case let .ready(bundle) = preparation else { fatalError("negative bundle allocation failed") }
        let cache = s.pool.allocationCache
        let shared = cache.locked { cache.residents.values.compactMap { entry -> (UInt64, MTLTexture, MTLTexture, Int)? in
            guard case let .sharedGraphPair(pair, identity) = entry.allocation else { return nil }
            return (identity.generation, pair.first, pair.second, entry.byteCost)
        } }
        if mode == "cancel" { bundle.cancel() }
        let result = s.coordinator.prepareFrame(mode == "emptyRequests" ? [] : [s.request],
            pool: mode == "wrongPool" ? otherPool : s.pool,
            commandBuffer: mode == "wrongBuffer" ? queue.makeCommandBuffer()! : s.buffer, resourceBundle: bundle)
        let clean = cache.locked { cache.residents.count == shared.count && cache.residents.values.allSatisfy { entry in
            guard !entry.isPinned, case let .sharedGraphPair(pair, identity) = entry.allocation else { return false }
            return shared.contains { $0.0 == identity.generation && $0.1 === pair.first && $0.2 === pair.second && $0.3 == entry.byteCost }
        } }
        let rejected: Bool
        if case .rejected = result { rejected = true } else { rejected = false }
        checks[mode] = ["rejectedAndCancelled": rejected && clean && shared.count == 1
            && s.pool.residentByteCost == shared.reduce(0) { $0 + $1.3 }
            && s.coordinator.activeTransactions.isEmpty && s.coordinator.committedTails.isEmpty
            && s.coordinator.scheduledTails.isEmpty, "legitimateIdleSharedPairBytes": s.pool.residentByteCost]
    }
    return checks
}

func phaseCapacityCheck(device: MTLDevice, queue: MTLCommandQueue,
    source: MTLTexture, pipeline: SceneImageLayerPipeline) -> [String: Any] {
    let s = makePhaseProbeState(device: device, queue: queue, source: source, pipeline: pipeline, budget: 96)
    defer { _ = s.coordinator.endFrame(); s.pool.reset() }
    let nativeBefore = SceneResourceBudget.shared.snapshot.residentBytes
    let preparation = s.coordinator.prepareFrameResourceBundle(plans: [s.target], pool: s.pool, commandBuffer: s.buffer)
    let delta = SceneResourceBudget.shared.snapshot.residentBytes - nativeBefore
    let rejected: Bool
    if case .rejected = preparation { rejected = true } else { rejected = false }
    return ["rejectedBeforeAllocation": rejected && s.pool.residentByteCost == 0 && delta == 0,
        "actualResidentBytes": s.pool.residentByteCost, "actualNativeDelta": delta,
        "graphOwnBytes": s.target.allocation.graphPlan.residentByteCost,
        "olderFramePressure": phaseBusyCompletionCheck(
            device: device, queue: queue, source: source, pipeline: pipeline)]
}

private func phaseBusyCompletionCheck(device: MTLDevice, queue: MTLCommandQueue,
    source: MTLTexture, pipeline: SceneImageLayerPipeline) -> [String: Bool] {
    let sizing = makePhaseProbeState(device: device, queue: queue, source: source, pipeline: pipeline)
    let shape = sizing.target.allocation.graphPlan.sharedPairDimensions!
    let budget = sizing.target.allocation.graphPlan.residentByteCost
        + sizing.pool.byteCost(width: shape.width, height: shape.height, textureCount: 2)!
    _ = sizing.coordinator.endFrame()
    let s = makePhaseProbeState(device: device, queue: queue,
        source: source, pipeline: pipeline, budget: budget)
    defer { _ = s.coordinator.endFrame(); s.pool.reset() }
    let older = queue.makeCommandBuffer()!
    let blocker = s.pool.reserveCompositionTargets(
        dimensions: [(shape.width, shape.height)], commandBuffer: older)![0]
    let event = device.makeSharedEvent()!
    defer { event.signaledValue = 1 }
    older.encodeWaitForEvent(event, value: 1)
    let descriptor = MTLRenderPassDescriptor()
    descriptor.colorAttachments[0].texture = blocker.texture
    descriptor.colorAttachments[0].loadAction = .clear
    descriptor.colorAttachments[0].storeAction = .store
    descriptor.colorAttachments[0].clearColor = .init(red: 0, green: 0, blue: 1, alpha: 1)
    let encoder = older.makeRenderCommandEncoder(descriptor: descriptor)!
    encoder.endEncoding()
    let completed = DispatchSemaphore(value: 0)
    older.addCompletedHandler { _ in blocker.pin.release(); completed.signal() }
    older.commit()
    let blocked = s.coordinator.prepareFrameResourceBundle(plans: [s.target],
        pool: s.pool, commandBuffer: s.buffer)
    let temporarilyBlocked: Bool
    if case .temporarilyBlocked = blocked { temporarilyBlocked = true } else { temporarilyBlocked = false }
    let noPartialGraph = s.pool.allocationCache.locked {
        s.pool.allocationCache.residents.values.allSatisfy { entry in
            if case .composition = entry.allocation { return entry.preparationPins.isEmpty }
            return false
        }
    } && s.coordinator.activeTransactions.isEmpty
    event.signaledValue = 1
    older.waitUntilCompleted()
    let observed = completed.wait(timeout: .now() + 10) == .success
    let recovered = s.coordinator.prepareFrameResourceBundle(plans: [s.target],
        pool: s.pool, commandBuffer: s.buffer)
    let ready: Bool
    if case let .ready(bundle) = recovered { ready = true; bundle.cancel() }
    else { ready = false }
    let cancelled = s.pool.allocationCache.locked {
        s.pool.allocationCache.residents.values.allSatisfy { $0.preparationPins.isEmpty && !$0.isPinned }
    }
    return ["typedBusyWithoutPartialGraph": temporarilyBlocked && noPartialGraph,
        "completionThenReadyWithSameRequest": observed && older.status == .completed
            && older.error == nil && ready,
        "recoveredBundleCancelLeavesNoPinsOrLedger": cancelled
            && s.coordinator.activeTransactions.isEmpty && s.coordinator.committedTails.isEmpty]
}

func phaseOverlayChecks(device: MTLDevice, queue: MTLCommandQueue,
    source: MTLTexture, pipeline: SceneImageLayerPipeline) -> [String: Any] {
    let s = makePhaseProbeState(device: device, queue: queue, source: source, pipeline: pipeline)
    defer { _ = s.coordinator.endFrame(); s.pool.reset() }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 4, mipmapped: false)
    descriptor.usage = [.shaderRead, .renderTarget]
    let texture = device.makeTexture(descriptor: descriptor)!
    // Synthetic API input receipt; this probe does not prove GPU completion provenance.
    let receipt = SceneCompletedColorSourceIdentity(frameIndex: 9, frameEpoch: 9, executionEpoch: 1,
        commandBufferObservationID: UUID(), allocationGeneration: 77, resetEpoch: UUID())
    let canonical = SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 10, allocationGeneration: 88,
        texture: texture, source: receipt)!
    func snapshot(_ atom: SceneFrameTextureLookupStatus, epoch: UInt64 = 10) -> SceneFrameTextureRegistrySnapshot {
        .init(frameEpoch: epoch, frameIndex: 10, entries: [.sceneEnvironment: atom, .sceneBackground(123): .unavailable])
    }
    func current() -> SceneFrameTextureRegistrySnapshot { s.coordinator.frame!.textureRegistrySnapshot }
    let ready = s.coordinator.overlayPreparedSceneEnvironment(from: snapshot(.ready(canonical)))
    let exact = current().resource(for: .sceneEnvironment)?.publication.isSameAtom(as: canonical.publication) == true
    let v = canonical.publication.candidate
    let poison = SceneFrameTextureResource(publication: .init(requestIdentity: .sceneEnvironment,
        candidate: .init(texture: texture, identity: v.identity, generation: v.generation,
            purpose: .preservedChannels, content: .data, physicalSize: v.physicalSize,
            mappedSize: v.mappedSize, uvTransform: v.uvTransform, sampling: v.sampling), contentGeneration: 10),
        resourceGeneration: canonical.resourceGeneration)
    let poisonAccepted = s.coordinator.overlayPreparedSceneEnvironment(from: snapshot(.ready(poison)))
    let preserved = current().resource(for: .sceneEnvironment)?.publication.isSameAtom(as: canonical.publication) == true
    _ = s.coordinator.overlayPreparedSceneEnvironment(from: snapshot(.ready(canonical)))
    let wrongEpochRejected = !s.coordinator.overlayPreparedSceneEnvironment(from: snapshot(.unavailable, epoch: 11))
        && current().resource(for: .sceneEnvironment) != nil
    let unavailableAccepted = s.coordinator.overlayPreparedSceneEnvironment(from: snapshot(.unavailable))
    let isUnavailable: Bool
    if case .unavailable? = current().lookup(.sceneEnvironment) { isUnavailable = true } else { isUnavailable = false }
    return ["canonicalReadyAndReceiptPreserved": ready && exact,
        "poisonIsGenericComplete": poison.publication.isComplete,
        "nonCanonicalAtomRejectedWithoutMutation": !poisonAccepted && preserved,
        "explicitUnavailableClearsReady": unavailableAccepted && isUnavailable && current().resource(for: .sceneEnvironment) == nil,
        "otherEntriesNotImported": current().lookup(.sceneBackground(123)) == nil,
        "incrementalDigestExact": current().selectionDigest == SceneFrameTextureSelectionDigest([
            .sceneEnvironment: .unavailable]),
        "wrongEpochRejectedWithoutMutation": wrongEpochRejected,
        "endedFrameRetiresAtLastExternalView": phaseOverlayRetirementCheck(
            device: device, queue: queue, source: source, pipeline: pipeline, stop: false),
        "surfaceStopRetiresAtLastExternalView": phaseOverlayRetirementCheck(
            device: device, queue: queue, source: source, pipeline: pipeline, stop: true)]
}

private func phaseOverlayRetirementCheck(device: MTLDevice, queue: MTLCommandQueue,
    source: MTLTexture, pipeline: SceneImageLayerPipeline, stop: Bool) -> Bool {
    let s = makePhaseProbeState(device: device, queue: queue, source: source, pipeline: pipeline)
    defer { _ = s.coordinator.endFrame(); s.pool.reset() }
    weak var observed: MTLTexture?
    var external: SceneFrameTextureRegistrySnapshot?
    let ended = autoreleasepool {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: 7, height: 5, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        let texture = device.makeTexture(descriptor: descriptor)!
        observed = texture
        let receipt = SceneCompletedColorSourceIdentity(frameIndex: 9, frameEpoch: 9,
            executionEpoch: 1, commandBufferObservationID: UUID(),
            allocationGeneration: 77, resetEpoch: UUID())
        let atom = SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 10,
            allocationGeneration: 88, texture: texture, source: receipt)!
        let incoming = SceneFrameTextureRegistrySnapshot(frameEpoch: 10, frameIndex: 10,
            entries: [.sceneEnvironment: .ready(atom)])
        guard s.coordinator.overlayPreparedSceneEnvironment(from: incoming) else { return false }
        external = s.coordinator.frame!.textureRegistrySnapshot
        if stop {
            s.coordinator.invalidate(reason: .surfaceStop)
        } else {
            _ = s.coordinator.endFrame()
        }
        return s.coordinator.frame == nil
    }
    let retained = withExtendedLifetime(external) { observed != nil }
    external = nil
    return ended && retained && observed == nil
}
