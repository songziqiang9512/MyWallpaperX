import Foundation

/// Test-only suspension at the real executor's original asynchronous cleanup
/// boundary. The product method still performs the descriptor-bound deletion.
@MainActor final class SteamDownloadCleanupBarrier {
    var heldJobID: String?
    private(set) var enteredJob: SteamDownloadJob?
    private var continuation: CheckedContinuation<Void, Never>?

    func wait(for job: SteamDownloadJob) async {
        guard job.id == heldJobID else { return }
        enteredJob = job
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        heldJobID = nil
        continuation?.resume()
        continuation = nil
    }
}

extension SteamWorkshopService {
    func runLateCleanupFixtureIfNeeded(mode: String, transport: Transport) async throws -> Bool {
        guard mode.hasPrefix("late-cleanup-") else { return false }
        let sameAttemptOwner = mode == "late-cleanup-new-attempt"
        let changeAccount = mode == "late-cleanup-new-account"
        func wait(_ predicate: () -> Bool) async throws {
            for _ in 0..<100_000 {
                if predicate() { return }
                await Task.yield()
            }
            throw SteamWorkshopLibraryTransaction.Failure(message: "late-cleanup fixture boundary timed out")
        }
        downloadWorkshopItem(id: "123456", pageTitle: "A original")
        try await wait {
            transport.observedPersistedIdentityBeforeAcknowledgement
                && self.downloadJobStore.activeJob(forWorkshopItemId: "123456")?.stagingPath != nil
        }
        let original = downloadJobStore.activeJob(forWorkshopItemId: "123456")!
        let originalKey = "\(original.id)-\(original.attempt)"
        let originalPath = original.stagingPath!
        stagingCleanupBarrier.heldJobID = original.id
        cancelDownloadImmediately(itemID: "123456", showFeedback: false)
        try await wait {
            transport.commands.contains { $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == originalKey }
        }
        transport.finishHeldCancellation(jobId: originalKey)
        try await wait { self.stagingCleanupBarrier.enteredJob != nil }
        precondition(stagingCleanupBarrier.enteredJob?.stagingLeaseIdentity == original.stagingLeaseIdentity)
        precondition(FileManager.default.fileExists(atPath: originalPath), "captured lease must still exist while cleanup is held")

        if sameAttemptOwner {
            // A legitimate JobStore transition can invalidate an old recovery
            // lease and admit a new attempt while the captured physical cleanup
            // is suspended. The old attempt's terminal history remains durable.
            precondition(downloadJobStore.apply(.recoveryInvalidated, toID: original.id) != nil)
            precondition(downloadJobStore.apply(.failed("old attempt settled externally"), toID: original.id) != nil)
        } else {
            precondition(downloadJobStore.apply(.cancelled, toID: original.id) != nil)
        }
        if changeAccount {
            steamAuth.steamId = "76561198000000001"
            steamServiceClient.accountEpoch &+= 1
        }
        transport.receipt["stagingPath"] = transport.receipt["secondStagingPath"]
        transport.receipt["stagingDevice"] = transport.receipt["secondStagingDevice"]
        transport.receipt["stagingInode"] = transport.receipt["secondStagingInode"]
        transport.receipt["stagingBirthSeconds"] = transport.receipt["secondStagingBirthSeconds"]
        transport.receipt["stagingBirthNanoseconds"] = transport.receipt["secondStagingBirthNanoseconds"]
        transport.receipt["accountSteamId"] = steamAuth.steamId!
        downloadWorkshopItem(id: "123456", pageTitle: "B replacement")
        try await wait {
            guard let current = self.downloadJobStore.activeJob(forWorkshopItemId: "123456") else { return false }
            return current.stagingPath == transport.receipt["stagingPath"] as? String
                && self.activeDownloadJobKeysByItemID["123456"] != originalKey
        }
        let replacement = downloadJobStore.activeJob(forWorkshopItemId: "123456")!
        let replacementKey = "\(replacement.id)-\(replacement.attempt)"
        precondition(replacementKey != originalKey && replacement.state == .running)
        precondition(sameAttemptOwner ? replacement.id == original.id && replacement.attempt > original.attempt : replacement.id != original.id)
        let before = downloads.first { $0.id == "123456" }!
        let progressBefore = downloadProgressStore.snapshot(for: "123456")
        let reloadsBefore = reloads
        statusMessage = "B current status"
        downloadError = "B current diagnostic"
        stagingCleanupBarrier.release()
        try await wait { self.activeDownloadTasks[originalKey] == nil }
        let after = downloads.first { $0.id == "123456" }
        precondition(after?.title == before.title && after?.status == before.status && after?.sizeText == before.sizeText,
            "old cleanup may not remove or overwrite the replacement row")
        precondition(statusMessage == "B current status" && downloadError == "B current diagnostic" && reloads == reloadsBefore)
        precondition(activeDownloadJobKeysByItemID["123456"] == replacementKey && activeDownloadTasks[replacementKey] != nil)
        precondition(downloadProgressStore.snapshot(for: "123456") == progressBefore)
        let stillCurrent = downloadJobStore.job(id: replacement.id)!
        precondition(stillCurrent.state == .running && stillCurrent.attempt == replacement.attempt
            && stillCurrent.stagingPath == replacement.stagingPath && stillCurrent.stagingLeaseIdentity == replacement.stagingLeaseIdentity,
            "old terminal/recoveryInvalidated writes may not settle the replacement attempt")
        precondition(!FileManager.default.fileExists(atPath: originalPath), "original captured lease still needs physical cleanup")
        precondition(FileManager.default.fileExists(atPath: replacement.stagingPath!), "replacement lease must remain intact")
        let oldOutcome: SteamDownloadHistoryOutcome = sameAttemptOwner ? .failed : .cancelled
        precondition(downloadJobStore.history.contains { $0.jobID == original.id && $0.attempt == original.attempt && $0.outcome == oldOutcome },
            "stale UI receipts do not roll back the old attempt's durable settlement")
        if !sameAttemptOwner { precondition(downloadJobStore.job(id: original.id)?.state == .cancelled) }

        cancelDownloadImmediately(itemID: "123456", showFeedback: false)
        try await wait {
            transport.commands.contains { $0["command"] as? String == "cancelDownload" && $0["jobId"] as? String == replacementKey }
        }
        transport.finishHeldCancellation(jobId: replacementKey)
        try await wait { self.activeDownloadTasks.isEmpty && self.terminalDownloadCleanupTask == nil }
        await steamServiceClient.stop(shutdownTimeout: 0)
        print("EXECUTION PASS: \(mode)")
        return true
    }
}
