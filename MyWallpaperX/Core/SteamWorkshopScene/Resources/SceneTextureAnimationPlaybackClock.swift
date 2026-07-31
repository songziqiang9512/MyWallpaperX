import Foundation

/// Instance-local, timer-free lifecycle for a bounded texture animation.
///
/// Scene time drives all transitions, so teardown cannot leave callbacks behind.
struct SceneTextureAnimationPlaybackClock {
    private enum State {
        case stopped(until: Float)
        case playing(startedAt: Float)
    }

    private let plan: SceneTextureAnimationPlaybackPlan
    private let frameDurations: [Float]
    private let duration: Float
    private let initialRandomState: UInt64
    private var randomState: UInt64
    private var state: State
    private var lastSceneTime: Float = -.infinity

    init(plan: SceneTextureAnimationPlaybackPlan, frameDurations: [Float]) {
        self.plan = plan
        self.frameDurations = frameDurations.map {
            $0.isFinite && $0 > 0 ? $0 : 1.0 / 60.0
        }
        duration = self.frameDurations.reduce(0, +)
        initialRandomState = Self.seed(layerID: plan.layerID)
        randomState = initialRandomState
        state = .stopped(until: plan.initialDelay)
    }

    mutating func frameIndex(at sceneTime: Float) -> Int {
        guard frameDurations.count > 1, duration > 0 else { return 0 }
        let time = sceneTime.isFinite ? max(sceneTime, 0) : 0
        if time < lastSceneTime {
            reset()
        }
        lastSceneTime = time

        for _ in 0 ..< 1_024 {
            switch state {
            case .stopped(let resumeTime):
                guard time >= resumeTime else { return 0 }
                state = .playing(startedAt: resumeTime)
            case .playing(let startedAt):
                let elapsed = time - startedAt
                guard elapsed >= duration else {
                    return frameIndex(in: max(elapsed, 0))
                }
                let stoppedAt = startedAt + duration
                state = .stopped(until: stoppedAt + nextDelay())
            }
        }

        // Bound extreme scene-time jumps instead of spending an unbounded frame
        // replaying discarded timers.
        state = .playing(startedAt: time)
        return 0
    }

    private mutating func reset() {
        randomState = initialRandomState
        state = .stopped(until: plan.initialDelay)
        lastSceneTime = -.infinity
    }

    private func frameIndex(in elapsed: Float) -> Int {
        var remaining = elapsed
        for (index, frameDuration) in frameDurations.enumerated() {
            if remaining < frameDuration { return index }
            remaining -= frameDuration
        }
        return frameDurations.count - 1
    }

    private mutating func nextDelay() -> Float {
        guard plan.maximumDelay > plan.minimumDelay else { return plan.minimumDelay }
        randomState &+= 0x9e3779b97f4a7c15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        let unit = Double(value >> 11) / 9_007_199_254_740_992.0
        return plan.minimumDelay
            + Float(unit) * (plan.maximumDelay - plan.minimumDelay)
    }

    private static func seed(layerID: Int) -> UInt64 {
        UInt64(bitPattern: Int64(layerID)) ^ 0xd1b54a32d192ed03
    }
}
