import Foundation
import Metal

extension SceneResolvedMaterialSubmissionCoordinator {
    typealias SceneColorIntent = SceneOffscreenTexturePool.SceneColorIntent

    /// Optional completed snapshots retain only identity. The pool may evict
    /// their allocation before the next frame admits its mandatory resources.
    struct CompletedSceneColor {
        let pool: SceneOffscreenTexturePool
        let key: SceneOffscreenTexturePool.CacheKey
        let member: Int
        let producerReceipt: SceneCompletedColorSourceIdentity
        let persistenceReservation: SceneColorReservation?

        var frameIndex: UInt64 { producerReceipt.frameIndex }
        var displayMapped: Bool? { persistenceReservation?.displayMapped }
    }

    /// A terminal frame payload, not a second history owner. Its retained raw
    /// member becomes readable to later frames only in drainCompletedLocked.
    struct SceneColorReservation {
        let lease: SceneOffscreenTexturePool.SceneColorLease
        let pool: SceneOffscreenTexturePool
        let epoch: UInt64
        let frameIndex: UInt64
        let member: Int
        let previous: MTLTexture?
        let previousReceipt: SceneCompletedColorSourceIdentity?
        let producerReceipt: SceneCompletedColorSourceIdentity
        let requiresDraw: Bool
        let commandBufferID: ObjectIdentifier
        var displayMapped: Bool? = nil
        var snapshotCopied = false
        /// Detached candidates never publish, but their pins stay in the
        /// existing pending submission until the buffer reaches terminal.
        var snapshotPublicationDetached = false

        var raw: MTLTexture { lease.targets.raw(member) }
        var display: MTLTexture? { lease.targets.display }
        var intent: SceneColorIntent { lease.targets.intent }
        var terminalOutputMarked: Bool {
            switch intent {
            case .persistence: displayMapped != nil
            case .snapshot: snapshotCopied || snapshotPublicationDetached
            }
        }
        var matchesCurrentEpoch: Bool {
            pool.sceneColorResetEpoch == lease.resetEpoch
        }
    }

    func reserveDisplayScratch(pool: SceneOffscreenTexturePool, width: Int, height: Int,
                               commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        guard frameIsActive, preparedDisplayScratch == nil,
              preparedSceneColor.map({ $0.intent == .snapshot
                  && $0.commandBufferID == ObjectIdentifier(commandBuffer) }) != false,
              commandBuffer.status == .notEnqueued,
              submissionQueueAcceptsFrameLocked(),
              let lease = pool.reserveDisplayScratch(width: width, height: height, commandBuffer: commandBuffer)
        else { return nil }
        guard observeCommandBufferLocked(commandBuffer) else {
            lease.pin.release()
            return nil
        }
        preparedDisplayScratch = (ObjectIdentifier(commandBuffer), lease.pin)
        return lease.texture
    }

    func reserveSceneColor(
        pool: SceneOffscreenTexturePool, width: Int, height: Int,
        frameIndex: UInt64, commandBuffer: MTLCommandBuffer,
        intent: SceneColorIntent = .persistence
    ) -> SceneColorReservation? {
        lock.lock()
        defer { lock.unlock() }
        guard frameIsActive, let frame, frame.frameIndex == frameIndex,
              preparedSceneColor == nil, submissionQueueAcceptsFrameLocked(),
              preparedDisplayScratch.map({ $0.commandBufferID == ObjectIdentifier(commandBuffer)
                  && intent == .snapshot }) != false,
              commandBuffer.status == .notEnqueued,
              let lease = pool.reserveSceneColor(width: width, height: height, intent: intent)
        else { return nil }
        guard observeCommandBufferLocked(commandBuffer) else {
            lease.release()
            return nil
        }
        let prior = completedSceneColor.flatMap { value -> CompletedSceneColor? in
            guard value.pool === pool, value.key == lease.key,
                  value.producerReceipt.executionEpoch == executionEpoch,
                  value.producerReceipt.resetEpoch == lease.resetEpoch,
                  pool.sceneColorResetEpoch == lease.resetEpoch,
                  value.producerReceipt.allocationGeneration == lease.targets.identity.generation,
                  lease.targets.first.width == width, lease.targets.first.height == height,
                  lease.targets.first.pixelFormat == pool.pixelFormat
            else { return nil }
            return value
        }
        let draws = intent == .snapshot || prior == nil || prior?.frameIndex != frameIndex
        let member = prior.map { draws ? 1 - $0.member : $0.member } ?? 0
        let receipt = !draws ? prior!.producerReceipt : SceneCompletedColorSourceIdentity(
            frameIndex: frameIndex, frameEpoch: frame.textureRegistrySnapshot.frameEpoch,
            executionEpoch: executionEpoch,
            commandBufferObservationID: commandBufferRecords[ObjectIdentifier(commandBuffer)]!.sourceObservationID,
            allocationGeneration: lease.targets.identity.generation, resetEpoch: lease.resetEpoch)
        let value = SceneColorReservation(lease: lease, pool: pool, epoch: executionEpoch,
            frameIndex: frameIndex, member: member,
            previous: prior.map { lease.targets.raw($0.member) },
            previousReceipt: prior?.producerReceipt, producerReceipt: receipt,
            requiresDraw: draws, commandBufferID: ObjectIdentifier(commandBuffer))
        preparedSceneColor = value
        return value
    }

    func markSceneColorOutput(on commandBuffer: MTLCommandBuffer, mapped: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard commandBuffer.status == .notEnqueued,
              preparedSceneColor?.commandBufferID == ObjectIdentifier(commandBuffer),
              preparedSceneColor?.intent == .persistence,
              preparedSceneColor?.displayMapped == nil else { return false }
        preparedSceneColor?.displayMapped = mapped
        return true
    }

    func markSceneColorSnapshot(on commandBuffer: MTLCommandBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard commandBuffer.status == .notEnqueued,
              preparedSceneColor?.commandBufferID == ObjectIdentifier(commandBuffer),
              preparedSceneColor?.intent == .snapshot,
              preparedSceneColor?.snapshotCopied == false,
              preparedSceneColor?.snapshotPublicationDetached == false else { return false }
        preparedSceneColor?.snapshotCopied = true
        return true
    }

    @discardableResult
    func detachPreparedSceneColorSnapshot(on commandBuffer: MTLCommandBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard commandBuffer.status == .notEnqueued,
              preparedSceneColor?.commandBufferID == ObjectIdentifier(commandBuffer),
              preparedSceneColor?.intent == .snapshot else { return false }
        preparedSceneColor?.snapshotPublicationDetached = true
        return true
    }

    func cancelPreparedSceneColorLocked() {
        preparedSceneColor?.lease.release()
        preparedSceneColor = nil
        preparedDisplayScratch?.pin.release()
        preparedDisplayScratch = nil
    }

    @discardableResult
    func completeSceneColorLocked(_ value: SceneColorReservation, succeeded: Bool) -> Bool {
        if succeeded, value.epoch == executionEpoch, value.matchesCurrentEpoch,
           !value.snapshotPublicationDetached {
            completedSceneColor?.persistenceReservation?.lease.retention.release()
            completedSceneColor = .init(pool: value.pool, key: value.lease.key,
                member: value.member, producerReceipt: value.producerReceipt,
                persistenceReservation: value.intent == .persistence ? value : nil)
            if value.intent == .persistence { value.lease.submission.release() }
            else { value.lease.release() }
            return true
        } else {
            value.lease.release()
            return false
        }
    }
}
