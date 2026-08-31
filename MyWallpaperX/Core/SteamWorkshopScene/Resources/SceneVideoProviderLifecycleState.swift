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
    private(set) var rate: Double = 1
    private(set) var loop = true

    private var anchorSceneTime: TimeInterval = 0
    private var anchorItemTime: TimeInterval = 0
    private var heldItemTime: TimeInterval = 0
    private var lastPlan: FramePlan?
    private var publishedFrameIndex: UInt64?
    private var isStopped = false
    private var isSuspended = false
    private var needsFrameRefresh = false
    private var lastObservedSceneTime: TimeInterval = 0

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
        lastObservedSceneTime = sceneTime
        isPlaying = true
        lastPlan = nil
        _ = hostTime
    }

    nonisolated mutating func planFrame(
        frameIndex: UInt64,
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) -> FramePlan {
        lastObservedSceneTime = sceneTime
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

        let itemTime = isPlaying && !isSuspended
            ? itemTime(at: sceneTime)
            : heldItemTime
        let plan = FramePlan(
            frameIndex: frameIndex,
            itemTime: itemTime,
            hostTime: hostTime,
            contentGeneration: contentGeneration,
            epoch: epoch,
            shouldDecode: !isStopped && (
                (isPlaying && !isSuspended) || needsFrameRefresh
            )
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
        needsFrameRefresh = false
        return contentGeneration
    }

    nonisolated mutating func pause(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        guard isPlaying, !isStopped else { return }
        heldItemTime = currentTime(at: sceneTime)
        lastObservedSceneTime = sceneTime
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
        lastObservedSceneTime = sceneTime
        isPlaying = true
        lastPlan = nil
        _ = hostTime
    }

    nonisolated mutating func seek(
        to itemTime: TimeInterval,
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        guard !isStopped, itemTime.isFinite, itemTime >= 0 else { return }
        heldItemTime = itemTime
        anchorItemTime = itemTime
        anchorSceneTime = sceneTime
        lastObservedSceneTime = sceneTime
        lastPlan = nil
        needsFrameRefresh = true
        _ = hostTime
    }

    nonisolated mutating func setRate(
        _ value: Double,
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        guard !isStopped, value.isFinite, value > 0, value <= 16 else { return }
        heldItemTime = currentTime(at: sceneTime)
        anchorItemTime = heldItemTime
        anchorSceneTime = sceneTime
        lastObservedSceneTime = sceneTime
        rate = value
        lastPlan = nil
        _ = hostTime
    }

    nonisolated mutating func setLoop(_ value: Bool) {
        guard !isStopped else { return }
        loop = value
    }

    nonisolated mutating func suspend(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        guard !isStopped, !isSuspended else { return }
        if isPlaying { heldItemTime = itemTime(at: sceneTime) }
        lastObservedSceneTime = sceneTime
        isSuspended = true
        lastPlan = nil
        _ = hostTime
    }

    nonisolated mutating func resumeSuspension(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        guard !isStopped, isSuspended else { return }
        isSuspended = false
        anchorItemTime = heldItemTime
        anchorSceneTime = sceneTime
        lastObservedSceneTime = sceneTime
        lastPlan = nil
        _ = hostTime
    }

    nonisolated mutating func didReachEnd(duration: TimeInterval) {
        guard !isStopped, duration.isFinite, duration > 0 else { return }
        if loop {
            heldItemTime = 0
            anchorItemTime = 0
            anchorSceneTime = lastObservedSceneTime
        } else {
            heldItemTime = duration
            anchorItemTime = duration
            isPlaying = false
        }
        lastPlan = nil
        needsFrameRefresh = true
    }

    nonisolated func currentTime(at sceneTime: TimeInterval) -> TimeInterval {
        isPlaying && !isSuspended ? itemTime(at: sceneTime) : heldItemTime
    }

    nonisolated mutating func rebuild(
        sceneTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        if isPlaying {
            heldItemTime = currentTime(at: sceneTime)
        }
        anchorSceneTime = sceneTime
        anchorItemTime = heldItemTime
        lastObservedSceneTime = sceneTime
        lastPlan = nil
        _ = hostTime
    }

    @discardableResult
    nonisolated mutating func stop() -> Bool {
        guard !isStopped else { return false }
        isStopped = true
        isPlaying = false
        isSuspended = false
        lastPlan = nil
        return true
    }

    private nonisolated func itemTime(at sceneTime: TimeInterval) -> TimeInterval {
        anchorItemTime + max(0, sceneTime - anchorSceneTime) * rate
    }
}
