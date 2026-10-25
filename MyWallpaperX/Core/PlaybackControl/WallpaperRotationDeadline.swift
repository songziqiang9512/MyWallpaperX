import Foundation

/// Monotonic timing values only. The Manager schedules/cancels the one timer
/// and validates the sequence's rotationGeneration before calling takeDue.
/// Effective user OR system pause arrives from the existing policy authority.
nonisolated struct WallpaperRotationDeadline: Equatable, Sendable {
    private(set) var deadline: TimeInterval?
    private(set) var remaining: TimeInterval?
    private(set) var interval: TimeInterval = 1
    private(set) var hasCommittedSession = false
    private(set) var isEligible = false
    private(set) var isPaused = false
    private(set) var isPreparing = false

    var isRunning: Bool { deadline != nil }

    /// Only a real new selection success starts a full new display interval.
    /// Internal recovery/settings rebuild must not call this method.
    mutating func commitSuccess(now: TimeInterval, interval: TimeInterval, eligible: Bool) {
        guard valid(now), validInterval(interval) else { return }
        self.interval = interval
        hasCommittedSession = true
        isEligible = eligible
        isPreparing = false
        remaining = interval
        arm(now: now)
    }

    /// Changing settings preserves elapsed display time; disabling freezes it.
    /// Enabling/resuming after Stop never creates a new session or deadline.
    mutating func configure(now: TimeInterval, interval: TimeInterval, eligible: Bool) {
        guard valid(now), validInterval(interval) else { return }
        guard self.interval != interval || isEligible != eligible else { return }
        captureRemaining(now: now)
        if let remaining {
            let elapsed = max(0, self.interval - remaining)
            self.remaining = max(0, interval - elapsed)
        }
        self.interval = interval
        isEligible = eligible
        arm(now: now)
    }

    mutating func setPause(effective: Bool, now: TimeInterval) {
        guard valid(now), effective != isPaused else { return }
        captureRemaining(now: now)
        isPaused = effective
        arm(now: now)
    }

    /// One pending target freezes the old display budget. Failure/cancel uses
    /// this same remaining value; preparing time does not consume the next item.
    mutating func freezeForPreparation(now: TimeInterval) {
        guard valid(now), !isPreparing else { return }
        captureRemaining(now: now)
        isPreparing = true
        deadline = nil
    }

    mutating func preparationFailed(now: TimeInterval) {
        guard valid(now), isPreparing else { return }
        isPreparing = false
        arm(now: now)
    }

    /// The scheduled deadline must still be exact. The caller additionally
    /// checks its captured sequence generation, so Stop/restart at the same
    /// numeric monotonic instant cannot give an old callback new authority.
    @discardableResult
    mutating func takeDue(now: TimeInterval, scheduledDeadline: TimeInterval) -> Bool {
        guard valid(now), hasCommittedSession, isEligible, !isPaused, !isPreparing,
              let deadline, deadline == scheduledDeadline, now >= deadline else { return false }
        remaining = 0
        self.deadline = nil
        isPreparing = true
        return true
    }

    mutating func stop() {
        hasCommittedSession = false
        isPreparing = false
        deadline = nil
        remaining = nil
    }

    private mutating func captureRemaining(now: TimeInterval) {
        if let deadline { remaining = max(0, deadline - now) }
        deadline = nil
    }

    private mutating func arm(now: TimeInterval) {
        guard hasCommittedSession, isEligible, !isPaused, !isPreparing, let remaining,
              (now + remaining).isFinite else { deadline = nil; return }
        deadline = now + remaining
    }

    private func valid(_ now: TimeInterval) -> Bool { now.isFinite && now >= 0 }
    private func validInterval(_ value: TimeInterval) -> Bool { value.isFinite && value > 0 }
}
