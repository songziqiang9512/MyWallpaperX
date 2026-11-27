import Foundation

/// Admits player callbacks only for the playback anchor that is still current.
/// AVPlayerItem end notifications do not carry the command generation that
/// produced them, so the source also supplies the observed item time. A seek,
/// rate change, pause, resume or rollback invalidates the old anchor before an
/// asynchronous callback is allowed to mutate the typed provider lifecycle.
nonisolated struct SceneVideoPlayerEventState: Equatable {
    private(set) var commandGeneration: UInt64 = 0
    private(set) var anchoredGeneration: UInt64?

    nonisolated mutating func invalidateAnchor() {
        commandGeneration &+= 1
        anchoredGeneration = nil
    }

    nonisolated mutating func didAnchorPlayback() {
        anchoredGeneration = commandGeneration
    }

    nonisolated func acceptsEndEvent(
        observedItemTime: TimeInterval,
        duration: TimeInterval,
        tolerance: TimeInterval
    ) -> Bool {
        guard let anchoredGeneration,
              anchoredGeneration == commandGeneration,
              observedItemTime.isFinite,
              duration.isFinite,
              tolerance.isFinite,
              duration > 0,
              tolerance >= 0 else {
            return false
        }
        // AVPlayer may report a valid terminal timestamp a few container
        // ticks past the nominal duration. Only the lower boundary separates
        // a current EOF from a stale callback delivered after a restart.
        return observedItemTime >= max(0, duration - tolerance)
    }
}

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

    private var anchorHostTime: TimeInterval = 0
    private var anchorItemTime: TimeInterval = 0
    private var heldItemTime: TimeInterval = 0
    private var lastPlan: FramePlan?
    private var publishedFrameIndex: UInt64?
    private var isStopped = false
    private var isSuspended = false
    private(set) var needsFrameRefresh = false
    private var lastObservedHostTime: TimeInterval = 0

    /// User playback intent survives a global Scene pause. Backend playback
    /// may advance only while that intent is not globally suspended.
    nonisolated var isAdvancingPlayback: Bool {
        !isStopped && isPlaying && !isSuspended
    }

    nonisolated init(epoch: UInt64) {
        self.epoch = epoch
    }

    nonisolated mutating func start(
        hostTime: TimeInterval
    ) {
        guard !isStopped, !isPlaying else { return }
        anchorHostTime = hostTime
        anchorItemTime = heldItemTime
        lastObservedHostTime = hostTime
        isPlaying = true
        lastPlan = nil
        needsFrameRefresh = true
    }

    nonisolated mutating func planFrame(
        frameIndex: UInt64,
        hostTime: TimeInterval
    ) -> FramePlan {
        lastObservedHostTime = hostTime
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

        let itemTime = isAdvancingPlayback
            ? itemTime(at: hostTime)
            : heldItemTime
        let plan = FramePlan(
            frameIndex: frameIndex,
            itemTime: itemTime,
            hostTime: hostTime,
            contentGeneration: contentGeneration,
            epoch: epoch,
            shouldDecode: !isStopped && (
                isAdvancingPlayback || needsFrameRefresh
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

    nonisolated mutating func requireFrameRefresh() {
        needsFrameRefresh = true
    }

    nonisolated mutating func discardPlannedFrame(frameIndex: UInt64) {
        guard lastPlan?.frameIndex == frameIndex else { return }
        lastPlan = nil
    }

    nonisolated func hasPlannedFrame(frameIndex: UInt64) -> Bool {
        lastPlan?.frameIndex == frameIndex
    }

    nonisolated mutating func pause(
        hostTime: TimeInterval
    ) {
        guard isPlaying, !isStopped else { return }
        heldItemTime = currentTime(at: hostTime)
        lastObservedHostTime = hostTime
        isPlaying = false
        lastPlan = nil
    }

    nonisolated mutating func resume(
        hostTime: TimeInterval
    ) {
        guard !isPlaying, !isStopped else { return }
        anchorHostTime = hostTime
        anchorItemTime = heldItemTime
        lastObservedHostTime = hostTime
        isPlaying = true
        lastPlan = nil
    }

    nonisolated mutating func seek(
        to itemTime: TimeInterval,
        hostTime: TimeInterval
    ) {
        guard !isStopped, itemTime.isFinite, itemTime >= 0 else { return }
        heldItemTime = itemTime
        anchorItemTime = itemTime
        anchorHostTime = hostTime
        lastObservedHostTime = hostTime
        lastPlan = nil
        needsFrameRefresh = true
    }

    nonisolated mutating func setRate(
        _ value: Double,
        hostTime: TimeInterval
    ) {
        guard !isStopped, value.isFinite, value > 0, value <= 16 else { return }
        heldItemTime = currentTime(at: hostTime)
        anchorItemTime = heldItemTime
        anchorHostTime = hostTime
        lastObservedHostTime = hostTime
        rate = value
        lastPlan = nil
    }

    nonisolated mutating func setLoop(_ value: Bool) {
        guard !isStopped else { return }
        loop = value
    }

    nonisolated mutating func requestFrameRefresh() {
        guard !isStopped else { return }
        lastPlan = nil
        needsFrameRefresh = true
    }

    nonisolated mutating func suspend(
        hostTime: TimeInterval
    ) {
        guard !isStopped, !isSuspended else { return }
        if isPlaying { heldItemTime = itemTime(at: hostTime) }
        lastObservedHostTime = hostTime
        isSuspended = true
        lastPlan = nil
    }

    nonisolated mutating func resumeSuspension(
        hostTime: TimeInterval
    ) {
        guard !isStopped, isSuspended else { return }
        isSuspended = false
        anchorItemTime = heldItemTime
        anchorHostTime = hostTime
        lastObservedHostTime = hostTime
        lastPlan = nil
    }

    nonisolated mutating func didReachEnd(duration: TimeInterval) {
        guard !isStopped, duration.isFinite, duration > 0 else { return }
        if loop {
            // EOF is an asynchronous backend observation, not a new clock
            // origin. Carry the elapsed phase across the duration boundary.
            // A last observation just before EOF can produce a small negative
            // anchor; the next frame then crosses zero at the right time.
            heldItemTime = currentTime(at: lastObservedHostTime) - duration
            anchorItemTime = heldItemTime
            anchorHostTime = lastObservedHostTime
        } else {
            heldItemTime = duration
            anchorItemTime = duration
            isPlaying = false
        }
        lastPlan = nil
        needsFrameRefresh = true
    }

    nonisolated func currentTime(at hostTime: TimeInterval) -> TimeInterval {
        isAdvancingPlayback ? itemTime(at: hostTime) : heldItemTime
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

    private nonisolated func itemTime(at hostTime: TimeInterval) -> TimeInterval {
        anchorItemTime + max(0, hostTime - anchorHostTime) * rate
    }
}
