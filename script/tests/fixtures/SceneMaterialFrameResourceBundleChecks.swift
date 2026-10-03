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
        let bundle = s.coordinator.prepareFrameResourceBundle(plans: mode == "duplicatePlans" ? [s.target, s.target] : [s.target],
            pool: s.pool, commandBuffer: s.buffer)
        if mode == "duplicatePlans" {
            checks["duplicatePlansRejectedBeforeAllocation"] = bundle == nil && s.pool.residentByteCost == 0
            continue
        }
        guard let bundle else { fatalError("negative bundle allocation failed") }
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
    let bundle = s.coordinator.prepareFrameResourceBundle(plans: [s.target], pool: s.pool, commandBuffer: s.buffer)
    let delta = SceneResourceBudget.shared.snapshot.residentBytes - nativeBefore
    return ["rejectedBeforeAllocation": bundle == nil && s.pool.residentByteCost == 0 && delta == 0,
        "actualResidentBytes": s.pool.residentByteCost, "actualNativeDelta": delta,
        "graphOwnBytes": s.target.allocation.graphPlan.residentByteCost]
}

func phaseOverlayChecks(device: MTLDevice, queue: MTLCommandQueue,
    source: MTLTexture, pipeline: SceneImageLayerPipeline) -> [String: Any] {
    let s = makePhaseProbeState(device: device, queue: queue, source: source, pipeline: pipeline)
    defer { _ = s.coordinator.endFrame(); s.pool.reset() }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 4, mipmapped: true)
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
        "incrementalDigestExact": current().selectionDigest == SceneFrameTextureSelectionDigest(current().entries),
        "wrongEpochRejectedWithoutMutation": wrongEpochRejected]
}
