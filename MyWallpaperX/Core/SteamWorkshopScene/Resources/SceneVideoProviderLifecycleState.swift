import Foundation

nonisolated struct SceneVideoProviderLifecycleState {
    nonisolated struct FramePlan {
        let frameIndex: UInt64
        let itemTime: TimeInterval
        let hostTime: TimeInterval
        let contentGeneration: UInt64
        let epoch: UInt64
        let shouldDecode: Bool
    }

    private(set) var epoch: UInt64
    private(set) var contentGeneration: UInt64 = 0
    private(set) var isPlaying = false

    private var anchorSceneTime: TimeInterval = 0
    private var anchorItemTime: TimeInterval = 0
    private var heldItemTime: TimeInterval = 0
    private var lastPlan: FramePlan?
    private var publishedFrameIndex: UInt64?
    private var isStopped = false

    nonisolated init(epoch: UInt64) {
        self.epoch = epoch
    }

    nonisolated mutating func start(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        guard !isStopped, !isPlaying else { return }
        anchorSceneTime = sceneTime
        anchorItemTime = heldItemTime
        isPlaying = true
        lastPlan = nil
        _ = hostTime
    }

    nonisolated mutating func planFrame(
        frameIndex: UInt64,
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) -> FramePlan {
        if let lastPlan, lastPlan.frameIndex == frameIndex {
            return FramePlan(
                frameIndex: frameIndex,
                itemTime: lastPlan.itemTime,
                hostTime: lastPlan.hostTime,
                contentGeneration: contentGeneration,
                epoch: epoch,
                shouldDecode: false
            )
        }

        let itemTime = isPlaying
            ? itemTime(at: sceneTime)
            : heldItemTime
        let plan = FramePlan(
            frameIndex: frameIndex,
            itemTime: itemTime,
            hostTime: hostTime,
            contentGeneration: contentGeneration,
            epoch: epoch,
            shouldDecode: isPlaying && !isStopped
        )
        lastPlan = plan
        return plan
    }

    nonisolated mutating func didPublish(frameIndex: UInt64) -> UInt64? {
        guard !isStopped,
              lastPlan?.frameIndex == frameIndex,
              lastPlan?.shouldDecode == true,
              publishedFrameIndex != frameIndex else {
            return nil
        }
        contentGeneration &+= 1
        publishedFrameIndex = frameIndex
        return contentGeneration
    }

    nonisolated mutating func pause(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        guard isPlaying, !isStopped else { return }
        heldItemTime = itemTime(at: sceneTime)
        isPlaying = false
        lastPlan = nil
        _ = hostTime
    }

    nonisolated mutating func resume(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        guard !isPlaying, !isStopped else { return }
        anchorSceneTime = sceneTime
        anchorItemTime = heldItemTime
        isPlaying = true
        lastPlan = nil
        _ = hostTime
    }

    nonisolated mutating func rebuild(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        if isPlaying {
            heldItemTime = itemTime(at: sceneTime)
        }
        anchorSceneTime = sceneTime
        anchorItemTime = heldItemTime
        lastPlan = nil
        _ = hostTime
    }

    @discardableResult
    nonisolated mutating func stop() -> Bool {
        guard !isStopped else { return false }
        isStopped = true
        isPlaying = false
        lastPlan = nil
        return true
    }

    private nonisolated func itemTime(at sceneTime: TimeInterval) -> TimeInterval {
        anchorItemTime + max(0, sceneTime - anchorSceneTime)
    }
}
