// Compiled in the same file as the unchanged production scheduler actors.
// These extensions add no product API or alternate scheduling implementation.
nonisolated private struct SchedulerAuditState: Equatable, Sendable {
    let primary: Int
    let secondary: Int
    let waitingPrimary: Int
    let waitingSecondary: Int

    static let idle = Self(primary: 0, secondary: 0, waitingPrimary: 0, waitingSecondary: 0)
}

extension OLThumbnailRequestScheduler {
    fileprivate func stateForAudit() -> SchedulerAuditState {
        SchedulerAuditState(primary: activeVisibleRequests, secondary: activePrefetchRequests,
            waitingPrimary: waitingVisibleRequests.count, waitingSecondary: waitingPrefetchRequests.count)
    }

    fileprivate func acquireForAudit(_ priority: OLThumbnailRequestPriority) async {
        await acquire(priority: priority)
    }

    fileprivate func releaseForAudit(_ priority: OLThumbnailRequestPriority) -> SchedulerAuditState {
        release(priority: priority)
        return stateForAudit()
    }
}

extension SteamWorkshopDetailRequestScheduler {
    fileprivate func stateForAudit() -> SchedulerAuditState {
        SchedulerAuditState(primary: activeUserRequests, secondary: activeBackgroundRequests,
            waitingPrimary: waitingUserRequests.count, waitingSecondary: waitingBackgroundRequests.count)
    }

    fileprivate func acquireForAudit(_ priority: SteamWorkshopDetailRequestPriority) async {
        await acquire(priority: priority)
    }

    fileprivate func releaseForAudit(_ priority: SteamWorkshopDetailRequestPriority) -> SchedulerAuditState {
        release(priority: priority)
        return stateForAudit()
    }
}

private actor AuditGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private enum HarnessFailure: Error {
    case assertion(String)
    case expected
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw HarnessFailure.assertion(message) }
}

private func eventually(_ condition: @Sendable () async -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))
    while !(await condition()) {
        try expect(clock.now < deadline, "scheduler did not reach the expected state")
        try await Task.sleep(nanoseconds: 1_000_000)
    }
}

@main private struct UIRequestSchedulerHarness {
    static func onlineBoundedHandoffAndPriority() async throws {
        let scheduler = OLThumbnailRequestScheduler()
        await scheduler.acquireForAudit(.visible)
        await scheduler.acquireForAudit(.visible)
        let visible = (0..<10).map { _ in Task { await scheduler.acquireForAudit(.visible) } }
        let prefetch = (0..<3).map { _ in Task { await scheduler.acquireForAudit(.prefetch) } }
        try await eventually {
            await scheduler.stateForAudit() == SchedulerAuditState(
                primary: 2, secondary: 0, waitingPrimary: 10, waitingSecondary: 3)
        }
        let first = await scheduler.releaseForAudit(.visible)
        try expect(first == SchedulerAuditState(primary: 2, secondary: 0, waitingPrimary: 9, waitingSecondary: 3),
            "one visible completion must hand off one permit without waking the other nine")
        for remaining in stride(from: 8, through: 0, by: -1) {
            let state = await scheduler.releaseForAudit(.visible)
            try expect(state == SchedulerAuditState(primary: 2, secondary: 0,
                waitingPrimary: remaining, waitingSecondary: 3), "visible concurrency or priority changed")
        }
        let penultimate = await scheduler.releaseForAudit(.visible)
        try expect(penultimate == SchedulerAuditState(primary: 1, secondary: 0,
            waitingPrimary: 0, waitingSecondary: 3), "prefetch must wait for active visible requests")
        let firstPrefetch = await scheduler.releaseForAudit(.visible)
        try expect(firstPrefetch == SchedulerAuditState(primary: 0, secondary: 1,
            waitingPrimary: 0, waitingSecondary: 2), "only one prefetch permit may be handed off")
        for remaining in stride(from: 1, through: 0, by: -1) {
            let state = await scheduler.releaseForAudit(.prefetch)
            try expect(state == SchedulerAuditState(primary: 0, secondary: 1,
                waitingPrimary: 0, waitingSecondary: remaining), "prefetch concurrency exceeded one")
        }
        _ = await scheduler.releaseForAudit(.prefetch)
        for task in visible + prefetch { await task.value }
        try expect(await scheduler.stateForAudit() == .idle, "online permits did not drain")
    }

    static func onlineExistingPrefetchAndVisibleLimits() async throws {
        let scheduler = OLThumbnailRequestScheduler()
        await scheduler.acquireForAudit(.prefetch)
        // A prefetch already in flight has never blocked newly visible work.
        await scheduler.acquireForAudit(.visible)
        await scheduler.acquireForAudit(.visible)
        let visible = Task { await scheduler.acquireForAudit(.visible) }
        let prefetch = Task { await scheduler.acquireForAudit(.prefetch) }
        try await eventually {
            await scheduler.stateForAudit() == SchedulerAuditState(
                primary: 2, secondary: 1, waitingPrimary: 1, waitingSecondary: 1)
        }
        let state = await scheduler.releaseForAudit(.visible)
        try expect(state == SchedulerAuditState(primary: 2, secondary: 1,
            waitingPrimary: 0, waitingSecondary: 1), "existing prefetch must not reduce visible capacity")
        await visible.value
        _ = await scheduler.releaseForAudit(.visible)
        _ = await scheduler.releaseForAudit(.visible)
        let next = await scheduler.releaseForAudit(.prefetch)
        try expect(next == SchedulerAuditState(primary: 0, secondary: 1,
            waitingPrimary: 0, waitingSecondary: 0), "prefetch queue did not resume")
        await prefetch.value
        _ = await scheduler.releaseForAudit(.prefetch)
        try expect(await scheduler.stateForAudit() == .idle, "mixed online permits did not drain")
    }

    static func steamBoundedHandoffAndPriority() async throws {
        let scheduler = SteamWorkshopDetailRequestScheduler()
        await scheduler.acquireForAudit(.background)
        await scheduler.acquireForAudit(.background)
        let background = (0..<8).map { _ in Task { await scheduler.acquireForAudit(.background) } }
        let user = (0..<2).map { _ in Task { await scheduler.acquireForAudit(.userInitiated) } }
        try await eventually {
            await scheduler.stateForAudit() == SchedulerAuditState(
                primary: 0, secondary: 2, waitingPrimary: 2, waitingSecondary: 8)
        }
        let first = await scheduler.releaseForAudit(.background)
        try expect(first == SchedulerAuditState(primary: 1, secondary: 1, waitingPrimary: 1, waitingSecondary: 8),
            "user request must receive the freed permit before background work")
        let second = await scheduler.releaseForAudit(.background)
        try expect(second == SchedulerAuditState(primary: 1, secondary: 0, waitingPrimary: 1, waitingSecondary: 8),
            "background must remain suspended while a user request is active")
        let nextUser = await scheduler.releaseForAudit(.userInitiated)
        try expect(nextUser == SchedulerAuditState(primary: 1, secondary: 0, waitingPrimary: 0, waitingSecondary: 8),
            "user handoff must reserve its permit before considering background work")
        let nextBackground = await scheduler.releaseForAudit(.userInitiated)
        try expect(nextBackground == SchedulerAuditState(primary: 0, secondary: 2,
            waitingPrimary: 0, waitingSecondary: 6), "two free slots must wake exactly two background waiters")
        for remaining in stride(from: 5, through: 0, by: -1) {
            let state = await scheduler.releaseForAudit(.background)
            try expect(state == SchedulerAuditState(primary: 0, secondary: 2,
                waitingPrimary: 0, waitingSecondary: remaining), "background handoff exceeded available capacity")
        }
        _ = await scheduler.releaseForAudit(.background)
        _ = await scheduler.releaseForAudit(.background)
        for task in background + user { await task.value }
        try expect(await scheduler.stateForAudit() == .idle, "Steam permits did not drain")
    }

    static func onlineNormalAndCancelledRelease() async throws {
        let scheduler = OLThumbnailRequestScheduler()
        let normal = await scheduler.run(priority: .visible) { 7 }
        let normalState = await scheduler.stateForAudit()
        try expect(normal == 7 && normalState == .idle, "normal online return leaked a permit")
        await scheduler.acquireForAudit(.visible)
        await scheduler.acquireForAudit(.visible)
        let cancelled = Task {
            await scheduler.run(priority: .visible) { Task.isCancelled }
        }
        try await eventually { await scheduler.stateForAudit().waitingPrimary == 1 }
        cancelled.cancel()
        _ = await scheduler.releaseForAudit(.visible)
        try expect(await cancelled.value, "queued online operation lost its cancellation state")
        try expect(await scheduler.stateForAudit() == SchedulerAuditState(primary: 1, secondary: 0,
            waitingPrimary: 0, waitingSecondary: 0), "cancelled online operation leaked its handed-off permit")
        _ = await scheduler.releaseForAudit(.visible)
        let recovered = await scheduler.run(priority: .prefetch) { 9 }
        let recoveredState = await scheduler.stateForAudit()
        try expect(recovered == 9 && recoveredState == .idle,
            "online scheduler could not recover after cancellation")
    }

    static func steamNormalThrowAndCancelledRelease() async throws {
        let scheduler = SteamWorkshopDetailRequestScheduler()
        let normal = await scheduler.run(priority: .background) { 7 }
        let normalState = await scheduler.stateForAudit()
        try expect(normal == 7 && normalState == .idle, "normal Steam return leaked a permit")
        do {
            _ = try await scheduler.run(priority: .userInitiated) { () async throws -> Int in
                throw HarnessFailure.expected
            }
            throw HarnessFailure.assertion("throwing Steam operation returned successfully")
        } catch HarnessFailure.expected {}
        try expect(await scheduler.stateForAudit() == .idle, "throwing Steam operation leaked a permit")

        await scheduler.acquireForAudit(.background)
        await scheduler.acquireForAudit(.background)
        let cancelled = Task {
            try await scheduler.run(priority: .userInitiated) { () async throws -> Int in
                try Task.checkCancellation()
                return -1
            }
        }
        let following = Task { await scheduler.run(priority: .background) { 11 } }
        try await eventually {
            await scheduler.stateForAudit() == SchedulerAuditState(
                primary: 0, secondary: 2, waitingPrimary: 1, waitingSecondary: 1)
        }
        cancelled.cancel()
        _ = await scheduler.releaseForAudit(.background)
        switch await cancelled.result {
        case .failure(let error): try expect(error is CancellationError, "unexpected queued cancellation error")
        case .success: throw HarnessFailure.assertion("cancelled Steam operation returned successfully")
        }
        try expect(await following.value == 11, "queued cancellation did not release its user permit")
        _ = await scheduler.releaseForAudit(.background)
        try expect(await scheduler.stateForAudit() == .idle, "queued Steam cancellation leaked a permit")

        let started = AuditGate()
        let running = Task {
            try await scheduler.run(priority: .userInitiated) {
                await started.open()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return 13
            }
        }
        await started.wait()
        running.cancel()
        switch await running.result {
        case .failure(let error): try expect(error is CancellationError, "unexpected active cancellation error")
        case .success: throw HarnessFailure.assertion("active cancellation was not observed")
        }
        let recovered = await scheduler.run(priority: .background) { 17 }
        let recoveredState = await scheduler.stateForAudit()
        try expect(recovered == 17 && recoveredState == .idle,
            "active cancellation leaked a permit or blocked later work")
    }

    static func main() async throws {
        try await onlineBoundedHandoffAndPriority()
        try await onlineExistingPrefetchAndVisibleLimits()
        try await steamBoundedHandoffAndPriority()
        try await onlineNormalAndCancelledRelease()
        try await steamNormalThrowAndCancelledRelease()
        let facts = ["onlineBoundedHandoffAndPriority": true, "onlineExistingPrefetchAndVisibleLimits": true,
            "steamBoundedHandoffAndPriority": true, "onlineNormalAndCancelledRelease": true,
            "steamNormalThrowAndCancelledRelease": true]
        print(String(data: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
