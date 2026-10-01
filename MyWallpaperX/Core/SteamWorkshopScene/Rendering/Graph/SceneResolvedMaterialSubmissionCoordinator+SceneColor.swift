import Foundation
import Metal

extension SceneResolvedMaterialSubmissionCoordinator {
    /// A terminal frame payload, not a second history owner. Its retained raw
    /// member becomes readable to later frames only in drainCompletedLocked.
    struct SceneColorReservation {
        let lease: SceneOffscreenTexturePool.SceneColorLease
        let pool: SceneOffscreenTexturePool
        let epoch: UInt64
        let frameIndex: UInt64
        let member: Int
        let previous: MTLTexture?
        let requiresDraw: Bool
        let commandBufferID: ObjectIdentifier
        var displayMapped: Bool? = nil

        var raw: MTLTexture { lease.targets.raw(member) }
        var display: MTLTexture { lease.targets.display }
        var matchesCurrentEpoch: Bool {
            pool.sceneColorResetEpoch == lease.resetEpoch
        }
    }

    func reserveDisplayScratch(pool: SceneOffscreenTexturePool, width: Int, height: Int,
                               commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        guard frameIsActive, preparedDisplayScratch == nil,
              preparedSceneColor == nil, commandBuffer.status == .notEnqueued,
              submissionQueueAcceptsFrameLocked(),
              let lease = pool.reserveDisplayScratch(width: width, height: height)
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
        frameIndex: UInt64, commandBuffer: MTLCommandBuffer
    ) -> SceneColorReservation? {
        lock.lock()
        defer { lock.unlock() }
        guard frameIsActive, frame?.frameIndex == frameIndex,
              preparedSceneColor == nil, submissionQueueAcceptsFrameLocked(),
              commandBuffer.status == .notEnqueued,
              let lease = pool.reserveSceneColor(width: width, height: height)
        else { return nil }
        guard observeCommandBufferLocked(commandBuffer) else {
            lease.release()
            return nil
        }
        let prior = completedSceneColor.flatMap { value -> SceneColorReservation? in
            guard value.pool === pool, value.matchesCurrentEpoch,
                  value.raw.width == width, value.raw.height == height,
                  value.raw.pixelFormat == lease.targets.first.pixelFormat,
                  value.lease.targets.identity.generation == lease.targets.identity.generation
            else { return nil }
            return value
        }
        let draws = prior == nil || prior?.frameIndex != frameIndex
        let member = prior.map { draws ? 1 - $0.member : $0.member } ?? 0
        let value = SceneColorReservation(lease: lease, pool: pool, epoch: executionEpoch,
            frameIndex: frameIndex, member: member, previous: prior?.raw,
            requiresDraw: draws, commandBufferID: ObjectIdentifier(commandBuffer))
        preparedSceneColor = value
        return value
    }

    func markSceneColorOutput(on commandBuffer: MTLCommandBuffer, mapped: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard commandBuffer.status == .notEnqueued,
              preparedSceneColor?.commandBufferID == ObjectIdentifier(commandBuffer),
              preparedSceneColor?.displayMapped == nil else { return false }
        preparedSceneColor?.displayMapped = mapped
        return true
    }

    func cancelPreparedSceneColorLocked() {
        preparedSceneColor?.lease.release()
        preparedSceneColor = nil
        preparedDisplayScratch?.pin.release()
        preparedDisplayScratch = nil
    }

    func completeSceneColorLocked(_ value: SceneColorReservation, succeeded: Bool) {
        if succeeded, value.epoch == executionEpoch, value.matchesCurrentEpoch {
            completedSceneColor?.lease.retention.release()
            completedSceneColor = value
            value.lease.submission.release()
        } else {
            value.lease.release()
        }
    }
}
