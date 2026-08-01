import Foundation

/// Instance-local, timer-free lifecycle for a bounded texture animation.
///
/// Scene time drives all transitions, so teardown cannot leave callbacks behind.
struct SceneTextureAnimationPlaybackClock {
    private enum DelayedState {
        case stopped(until: Float)
        case playing(startedAt: Float)
    }

    private let plan: SceneTextureAnimationPlaybackPlan
    private let frameDurations: [Float]
    private let duration: Float
    private let initialRandomState: UInt64
    private var randomState: UInt64
    private var delayedState: DelayedState
    private var lastTimeOfDayState: SceneTimeOfDaySchedule.State?
    private var selectedTimeOfDayFrame = 0
    private var lastSceneTime: Float = -.infinity

    init(plan: SceneTextureAnimationPlaybackPlan, frameDurations: [Float]) {
        self.plan = plan
        self.frameDurations = frameDurations.map {
            $0.isFinite && $0 > 0 ? $0 : 1.0 / 60.0
        }
        duration = self.frameDurations.reduce(0, +)
        initialRandomState = Self.seed(layerID: plan.layerID)
        randomState = initialRandomState
        delayedState = .stopped(until: Self.initialDelay(for: plan.mode))
    }

    mutating func frameIndex(
        at sceneTime: Float,
        wallDate: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Int {
        guard frameDurations.count > 1, duration > 0 else { return 0 }
        let time = sceneTime.isFinite ? max(sceneTime, 0) : 0
        if time < lastSceneTime {
            reset()
        }
        lastSceneTime = time

        switch plan.mode {
        case let .delayedLoop(initialDelay, minimumDelay, maximumDelay):
            return delayedFrameIndex(
                at: time,
                initialDelay: initialDelay,
                minimumDelay: minimumDelay,
                maximumDelay: maximumDelay
            )
        case .timeOfDay(let schedule):
            guard frameDurations.count >= 3,
                  let currentState = schedule.state(at: wallDate, timeZone: timeZone) else {
                return 0
            }
            guard let previousState = lastTimeOfDayState else {
                lastTimeOfDayState = currentState
                selectedTimeOfDayFrame = 0
                return 0
            }
            if currentState != previousState {
                lastTimeOfDayState = currentState
                selectedTimeOfDayFrame = currentState == .day ? 1 : 2
            }
            return selectedTimeOfDayFrame
        }
    }

    mutating func frameIndex(at sceneTime: Float) -> Int {
        frameIndex(
            at: sceneTime,
            wallDate: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    private mutating func delayedFrameIndex(
        at time: Float,
        initialDelay: Float,
        minimumDelay: Float,
        maximumDelay: Float
    ) -> Int {
        for _ in 0 ..< 1_024 {
            switch delayedState {
            case .stopped(let resumeTime):
                guard time >= resumeTime else { return 0 }
                delayedState = .playing(startedAt: resumeTime)
            case .playing(let startedAt):
                let elapsed = time - startedAt
                guard elapsed >= duration else {
                    return frameIndex(in: max(elapsed, 0))
                }
                let stoppedAt = startedAt + duration
                delayedState = .stopped(
                    until: stoppedAt + nextDelay(
                        minimumDelay: minimumDelay,
                        maximumDelay: maximumDelay
                    )
                )
            }
        }

        // Bound extreme scene-time jumps instead of spending an unbounded frame
        // replaying discarded timers.
        delayedState = .playing(startedAt: time)
        return 0
    }

    private mutating func reset() {
        randomState = initialRandomState
        delayedState = .stopped(until: Self.initialDelay(for: plan.mode))
        lastTimeOfDayState = nil
        selectedTimeOfDayFrame = 0
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

    private mutating func nextDelay(minimumDelay: Float, maximumDelay: Float) -> Float {
        guard maximumDelay > minimumDelay else { return minimumDelay }
        randomState &+= 0x9e3779b97f4a7c15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        let unit = Double(value >> 11) / 9_007_199_254_740_992.0
        return minimumDelay + Float(unit) * (maximumDelay - minimumDelay)
    }

    private static func initialDelay(for mode: SceneTextureAnimationPlaybackPlan.Mode) -> Float {
        guard case .delayedLoop(let initialDelay, _, _) = mode else { return 0 }
        return initialDelay
    }

    private static func seed(layerID: Int) -> UInt64 {
        UInt64(bitPattern: Int64(layerID)) ^ 0xd1b54a32d192ed03
    }
}
