import Foundation

actor PreviewOperationGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var entries = 0
    func wait() async {
        entries += 1
        await withCheckedContinuation { continuations.append($0) }
    }
    func releaseAll() { let values = continuations; continuations.removeAll(); values.forEach { $0.resume() } }
}

extension SteamWorkshopPreviewRequestScheduler {
    func snapshot() -> (Int, Int, Int, Int) {
        (activeUserRequests, activeVisibleRequests, activePrefetchRequests, waiting.count)
    }
}

@main struct SteamPreviewSchedulingChecks {
    static func main() async throws {
        var checks: [String: Bool] = [:]
        func settle(_ condition: () async -> Bool) async -> Bool {
            for _ in 0..<500 {
                if await condition() { return true }
                try? await Task.sleep(for: .milliseconds(2))
            }
            return await condition()
        }
        let scheduler = SteamWorkshopPreviewRequestScheduler()
        let active = PreviewOperationGate()
        let first = Task { await scheduler.run(priority: .prefetch) { await active.wait() } }
        let second = Task { await scheduler.run(priority: .prefetch) { await active.wait() } }
        checks["existingPrefetchBoundRemainsTwo"] = await settle { await active.entries == 2 }
        let promoted = PreviewOperationGate()
        let target = Task { await scheduler.run(priority: .prefetch, key: "promoted") { await promoted.wait() } }
        checks["thirdPrefetchWaitsWithoutTakingSlot"] = await settle { await scheduler.snapshot().3 == 1 }
        await scheduler.promoteVisible(key: "promoted")
        checks["visibleJoinPromotesRegisteredPrefetch"] = await settle { await promoted.entries == 1 }
        let promotedState = await scheduler.snapshot()
        checks["promotionAccountsForVisibleInsteadOfPrefetchSlot"] = promotedState.1 == 1 && promotedState.2 == 2
        let beforeRegistration = PreviewOperationGate()
        let alreadyVisible = Task {
            await scheduler.run(priority: .prefetch, key: "early", priorityProvider: { .visible }) {
                await beforeRegistration.wait()
            }
        }
        checks["earlyPromotionProviderReadAtRegistration"] = await settle { await beforeRegistration.entries == 1 }
        await promoted.releaseAll(); await beforeRegistration.releaseAll(); await target.value; await alreadyVisible.value
        let cancelled = Task { await scheduler.run(priority: .prefetch, key: "cancelled") { Task.isCancelled } }
        _ = await settle { await scheduler.snapshot().3 == 1 }
        cancelled.cancel()
        checks["cancelledWaiterSettlesBeforeActiveRequestsComplete"] = await cancelled.value
        checks["cancelledWaiterReleasesQueuedState"] = await scheduler.snapshot().3 == 0
        await active.releaseAll(); await first.value; await second.value
        let final = await scheduler.snapshot()
        checks["allAcquiredSlotsSettleExactlyOnce"] = final.0 == 0 && final.1 == 0 && final.2 == 0 && final.3 == 0
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
