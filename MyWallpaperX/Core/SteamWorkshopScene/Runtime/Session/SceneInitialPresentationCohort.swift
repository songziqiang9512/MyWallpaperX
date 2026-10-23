/// Session-local success coordination for one initial-presentation submission.
///
/// The caller supplies content qualification and actual submission together.
/// Source readiness, GPU failures and Host promotion remain with their existing
/// owners. Invalidate before replacing surface objects or releasing the candidate.
nonisolated struct SceneInitialPresentationCohort {
    nonisolated struct AttemptToken: Hashable, Sendable {
        let rawValue: UInt64

        fileprivate init(rawValue: UInt64) {
            self.rawValue = rawValue
        }
    }

    private struct Attempt {
        let token: AttemptToken
        let members: [UInt32: ObjectIdentifier]
        var completed: Set<UInt32> = []
        var isHeld = false
        var delivered = false
    }

    private var lastAttemptID: UInt64 = 0
    private var attempt: Attempt?

    /// Remains held after delivery until Host promotion/cancellation releases it.
    var isHeld: Bool { attempt?.isHeld == true }

    /// Host already received this cohort; invalidation must preserve its outcome
    /// ownership rather than silently rendering a replacement candidate.
    var hasDelivered: Bool { attempt?.delivered == true }

    /// Paused retries get distinct tokens even when they reuse one frameIndex.
    /// A held drawable cannot be silently superseded by a newer render attempt.
    mutating func beginAttempt(members: [UInt32: ObjectIdentifier]) -> AttemptToken? {
        guard !isHeld, lastAttemptID < UInt64.max else { return nil }
        lastAttemptID += 1
        let token = AttemptToken(rawValue: lastAttemptID)
        attempt = Attempt(token: token, members: members)
        return token
    }

    /// Seal only an exact, nonempty set of qualified and actually submitted
    /// surface objects. Incomplete submissions cannot contribute to a later one.
    /// Call takeCompletedCohort after sealing to cover synchronous completions.
    @discardableResult
    mutating func finishAttempt(
        token: AttemptToken,
        qualifiedSubmitted: [UInt32: ObjectIdentifier]
    ) -> Bool {
        guard var current = attempt, current.token == token else { return false }
        if current.isHeld { return true }
        guard !current.members.isEmpty, qualifiedSubmitted == current.members else {
            attempt = nil
            return false
        }
        current.isHeld = true
        attempt = current
        return true
    }

    /// Record successes only. Callers must still forward every GPU failure to
    /// the existing Host path, including while delivered and awaiting promotion.
    mutating func complete(
        token: AttemptToken,
        surface: UInt32,
        identity: ObjectIdentifier
    ) -> [UInt32]? {
        guard var current = attempt, current.token == token,
              current.members[surface] == identity else { return nil }
        current.completed.insert(surface)
        attempt = current
        return takeCompletedCohort()
    }

    /// Also drains successes that arrived before finishAttempt established hold.
    /// Delivery does not release hold: an external parent may defer Host commit.
    mutating func takeCompletedCohort() -> [UInt32]? {
        guard var current = attempt, current.isHeld, !current.delivered,
              current.completed.count == current.members.count else { return nil }
        current.delivered = true
        attempt = current
        return current.members.keys.sorted()
    }

    /// Revoke pending callbacks without ever reusing their attempt token.
    mutating func invalidate() {
        attempt = nil
    }

    /// Used by promotion, stop and teardown; does not reset the token sequence.
    mutating func reset() {
        invalidate()
    }
}
