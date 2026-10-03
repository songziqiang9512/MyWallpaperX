import Foundation
import Metal

/// A one-use resource transfer, never a claim or a history/publication owner.
/// cancel after take cannot reach the local possession held by prepareFrame.
final class SceneResolvedMaterialFrameResourceBundle {
    struct FrameIdentity {
        let runtimeInstanceIdentity: String
        let executionEpoch: UInt64
        let frameEpoch: UInt64
        let frameIndex: UInt64
    }
    struct Possession {
        let identity: FrameIdentity
        let plans: [SceneResolvedMaterialFrameTargetPlan]
        let pool: SceneOffscreenTexturePool
        let commandBuffer: MTLCommandBuffer
        let targets: [ScenePreparedPersistentGraphTargets]
        let admission: SceneGraphPreparationAdmission

        func isValidForFramePreparation(coordinator: SceneResolvedMaterialSubmissionCoordinator,
                     frame: SceneResolvedMaterialFrameSnapshot,
                     plans actual: [SceneResolvedMaterialFrameTargetPlan],
                     pool actualPool: SceneOffscreenTexturePool?,
                     commandBuffer actualBuffer: MTLCommandBuffer) -> Bool {
            guard identity.runtimeInstanceIdentity == coordinator.runtimeInstanceIdentity,
                  identity.executionEpoch == coordinator.executionEpoch,
                  identity.frameEpoch == frame.textureRegistrySnapshot.frameEpoch,
                  identity.frameIndex == frame.frameIndex,
                  actualPool === pool, actualBuffer === commandBuffer,
                  commandBuffer.status == .notEnqueued,
                  plans.count == actual.count, targets.count == actual.count else { return false }
            return zip(plans, actual).allSatisfy { expected, received in
                expected.token == received.token
                    && expected.allocation.residencyDomainID == pool.residencyDomainID
                    && received.allocation.residencyDomainID == pool.residencyDomainID
                    && expected.allocation.graphPlan == received.allocation.graphPlan
                    && expected.allocation.orderingContext?.commandBuffer
                        === received.allocation.orderingContext?.commandBuffer
                    && (received.allocation.orderingContext?.accepts(commandBuffer) ?? true)
            }
        }
    }

    private let lock = NSLock()
    private var possession: Possession?
    private init(_ value: Possession) { possession = value }

    fileprivate static func prepare(identity: FrameIdentity,
                                    plans: [SceneResolvedMaterialFrameTargetPlan],
                                    pool: SceneOffscreenTexturePool,
                                    commandBuffer: MTLCommandBuffer) -> Self? {
        let allocations = plans.map(\.allocation)
        guard commandBuffer.status == .notEnqueued,
              plans.allSatisfy({ $0.allocation.orderingContext?.accepts(commandBuffer) ?? true }),
              pool.preflightPersistentGraphTargets(allocations) == .ready,
              let targets = pool.preparePreflightedPersistentGraphTargets(framePlans: allocations),
              let admission = pool.allocationCache.admitPreparedTargets(targets) else { return nil }
        return .init(.init(identity: identity, plans: plans, pool: pool,
            commandBuffer: commandBuffer, targets: targets, admission: admission))
    }

    func take() -> Possession? {
        lock.lock()
        defer { lock.unlock() }
        let owned = possession
        possession = nil
        return owned
    }

    func cancel() {
        let owned = take()
        owned?.admission.cancel()
    }
    deinit { cancel() }
}

extension SceneResolvedMaterialSubmissionCoordinator {
    /// Called in the renderer's resource phase. The short lock only captures
    /// this original coordinator/frame identity; actual pool work is outside it.
    /// No capability claim is granted until prepareFrame validates its requests.
    func prepareFrameResourceBundle(
        plans: [SceneResolvedMaterialFrameTargetPlan],
        pool: SceneOffscreenTexturePool,
        commandBuffer: MTLCommandBuffer
    ) -> SceneResolvedMaterialFrameResourceBundle? {
        lock.lock()
        guard terminalFailureReason == nil, frameIsActive, !frameRequiresDrop,
              !frameWaitsForPendingSubmission, frameFailure == nil, let frame,
              !framePreparationComplete, activeTransactions.isEmpty,
              preparedLedgerByLayerID.isEmpty,
              commandBuffer.status == .notEnqueued,
              !plans.isEmpty, plans.count <= Self.maximumTransactionsPerSubmission,
              Set(plans.map { $0.allocation.graphPlan.key.layerID }).count == plans.count,
              Set(plans.map(\.token)).count == plans.count,
              nextTransactionID <= UInt64.max - UInt64(plans.count)
        else { lock.unlock(); return nil }
        let identity = SceneResolvedMaterialFrameResourceBundle.FrameIdentity(
            runtimeInstanceIdentity: runtimeInstanceIdentity, executionEpoch: executionEpoch,
            frameEpoch: frame.textureRegistrySnapshot.frameEpoch, frameIndex: frame.frameIndex)
        lock.unlock()
        return .prepare(identity: identity, plans: plans, pool: pool, commandBuffer: commandBuffer)
    }
}

extension SceneResolvedMaterialSubmissionCoordinator {
    /// Transfer only an explicit ready/unavailable environment atom. A missing
    /// entry means no update; absent/pending/incomplete are not this protocol.
    /// Rejecting an invalid atom leaves the original frozen frame untouched.
    func overlayPreparedSceneEnvironment(from snapshot: SceneFrameTextureRegistrySnapshot) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard frameIsActive, !framePreparationComplete, !frameRequiresDrop,
              frameFailure == nil, let original = frame,
              snapshot.frameEpoch == original.textureRegistrySnapshot.frameEpoch,
              snapshot.frameIndex == original.frameIndex else { return false }
        guard let atom = snapshot.lookup(.sceneEnvironment) else { return true }
        switch atom {
        case .ready(let resource):
            guard Self.isCanonicalPreparedEnvironment(resource, frameEpoch: snapshot.frameEpoch)
            else { return false }
        case .unavailable:
            break
        case .absent, .pending, .incomplete:
            return false
        }
        let frozen = original.textureRegistrySnapshot
        var entries = frozen.entries
        let previous = entries[.sceneEnvironment]
        entries[.sceneEnvironment] = atom
        let replacement = SceneFrameTextureRegistrySnapshot(frameEpoch: frozen.frameEpoch,
            frameIndex: frozen.frameIndex, entries: entries,
            selectionDigest: frozen.selectionDigest.replacing(.sceneEnvironment,
                previous: previous, with: atom))
        guard let overlaid = original.replacingTextureSnapshot(replacement) else { return false }
        frame = overlaid
        return true
    }

    private static func isCanonicalPreparedEnvironment(
        _ resource: SceneFrameTextureResource, frameEpoch: UInt64
    ) -> Bool {
        let value = resource.publication.candidate
        guard case let .provider(.sceneEnvironment(epoch, generation, source)) = value.identity,
              epoch == frameEpoch, generation > 0,
              resource.publication.isComplete,
              let canonical = SceneFrameTextureResource.sameFrameEnvironment(
                frameEpoch: epoch, allocationGeneration: generation,
                texture: value.texture, source: source) else { return false }
        // Compare the actual producer atom with the canonical typed resource;
        // isSameAtom also checks sampling rawFlags and every candidate field.
        return resource.resourceGeneration == canonical.resourceGeneration
            && resource.publication.isSameAtom(as: canonical.publication)
    }
}
