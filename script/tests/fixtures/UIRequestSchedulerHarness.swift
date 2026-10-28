// Compiled in the same file as the unchanged production thumbnail scheduler.
// This extension adds no product API or alternate scheduling implementation.
nonisolated private struct SchedulerAuditState: Equatable, Sendable {
    let primary: Int
    let secondary: Int
    let waitingPrimary: Int
    let waitingSecondary: Int

    static let idle = Self(primary: 0, secondary: 0, waitingPrimary: 0, waitingSecondary: 0)
}

extension OnlineImageThumbnailRequestScheduler {
    fileprivate func stateForAudit() -> SchedulerAuditState {
        SchedulerAuditState(primary: active.values.filter { $0 == .visible }.count,
            secondary: active.values.filter { $0 == .prefetch }.count,
            waitingPrimary: waiting.filter { $0.priority == .visible }.count,
            waitingSecondary: waiting.filter { $0.priority == .prefetch }.count)
    }

    fileprivate func acquireForAudit(_ priority: OnlineImageThumbnailRequestPriority) async {
        _ = await acquire(id: UUID(), priority: priority)
    }

    fileprivate func releaseForAudit(_ priority: OnlineImageThumbnailRequestPriority) -> SchedulerAuditState {
        if let id = active.first(where: { $0.value == priority })?.key { release(id: id) }
        return stateForAudit()
    }
}

private enum HarnessFailure: Error {
    case assertion(String)
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
    static func pixabayBoundedHandoffAndPriority() async throws {
        let scheduler = OnlineImageThumbnailRequestScheduler()
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
        try expect(penultimate == SchedulerAuditState(primary: 1, secondary: 1,
            waitingPrimary: 0, waitingSecondary: 2), "one free slot should serve one neighbor after queued visible work drains")
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

    static func pixabayExistingPrefetchAndVisibleLimits() async throws {
        let scheduler = OnlineImageThumbnailRequestScheduler()
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

    static func pixabayNormalAndCancelledRelease() async throws {
        let scheduler = OnlineImageThumbnailRequestScheduler()
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
        try expect(await cancelled.value == nil, "cancelled queued online operation must not execute")
        try expect(await scheduler.stateForAudit() == SchedulerAuditState(primary: 1, secondary: 0,
            waitingPrimary: 0, waitingSecondary: 0), "cancelled online operation leaked its handed-off permit")
        _ = await scheduler.releaseForAudit(.visible)
        let recovered = await scheduler.run(priority: .prefetch) { 9 }
        let recoveredState = await scheduler.stateForAudit()
        try expect(recovered == 9 && recoveredState == .idle,
            "online scheduler could not recover after cancellation")
    }

    static func main() async throws {
        try await pixabayBoundedHandoffAndPriority()
        try await pixabayExistingPrefetchAndVisibleLimits()
        try await pixabayNormalAndCancelledRelease()
        let facts = ["onlineBoundedHandoffAndPriority": true, "onlineExistingPrefetchAndVisibleLimits": true,
            "onlineNormalAndCancelledRelease": true]
        print(String(data: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
