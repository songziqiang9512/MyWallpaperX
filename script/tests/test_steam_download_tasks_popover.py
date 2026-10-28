"""Real local task/history projections; generic AppKit lifecycle has its native gate."""
import pathlib
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_transaction import CORE, ROOT, SOURCES
from script.tests.test_steam_library_interactions import method

PROJECTION = CORE / "SteamWorkshopDownloadTaskProjection.swift"


class SteamDownloadTasksPopoverTests(unittest.TestCase):
    def test_local_projection_keeps_accounts_and_stable_native_queue_order(self):
        harness = r'''
import Foundation

@MainActor final class JobQueryProbe {
    var jobs: [SteamDownloadJob] = []
    // JOB_QUERIES
}

// Only record values are reduced here; all query bodies below come from the
// production accessors, including the ready-record lookup used by consumers.
struct SteamWorkshopDownloadRecord: Equatable {
    enum Status: Equatable { case queued, downloading, ready, failed(String) }
    enum ContentType: Equatable { case video, web, scene, unknown }
    let id: String
    let status: Status
    let contentType: ContentType
}

@MainActor final class DownloadCountProbe {
    var downloads: [SteamWorkshopDownloadRecord] = []
    // DOWNLOAD_QUERIES
}

@main struct Harness {
    @MainActor static func main() {
        let now = Date(timeIntervalSince1970: 100)
        func make(_ id: String, _ state: SteamDownloadJobState, _ ordinal: Int,
                  account: String = "A", attempt: Int = 1,
                  itemID: String? = nil, stamp: TimeInterval = 100) -> SteamDownloadJob {
            SteamDownloadJob(
                id: id,
                workshopItemId: itemID ?? "item-\(id)",
                title: "Title \(id)",
                state: state,
                attempt: attempt,
                queueOrdinal: ordinal,
                accountSteamId: account,
                stagingPath: nil,
                failureMessage: state == .failed ? "network" : nil,
                createdAt: now,
                updatedAt: Date(timeIntervalSince1970: stamp)
            )
        }
        let jobs = [
            make("queued-2", .queued, 20),
            make("other", .running, 1, account: "B"),
            make("other-queued", .queued, 1, account: "B"),
            make("failed", .failed, 5),
            make("completed", .completed, 2),
            make("saving", .committing, 4),
            make("cancelled", .cancelled, 3),
            make("active", .running, 8),
            make("staged", .staged, 9),
            make("queued-1", .queued, 10, attempt: 0),
            make("empty-account", .queued, 0, account: ""),
            make("space-account", .failed, 0, account: " ")
        ]

        let visible = SteamWorkshopDownloadTaskProjection.currentJobs(from: jobs)
        precondition(visible.map(\.id) == ["other", "saving", "active", "staged", "empty-account", "other-queued", "queued-1", "queued-2"],
                     "local reading keeps all account provenance and excludes terminal jobs shown in history")
        precondition(SteamWorkshopDownloadTaskProjection.jobKey(for: visible[1]) == "saving-1")
        precondition(SteamWorkshopDownloadTaskProjection.jobKey(for: visible[6]) == nil)
        precondition(!SteamWorkshopDownloadTaskProjection.isCancellable(visible[1]))
        precondition(SteamWorkshopDownloadTaskProjection.isCancellable(visible[0]))
        precondition(SteamWorkshopDownloadTaskProjection.isCancellable(visible[6]))
        precondition(SteamWorkshopDownloadTaskProjection.currentJobs(from: []).isEmpty)
        precondition(SteamWorkshopDownloadTaskProjection.currentJobs(
            from: Array(jobs.reversed())) == visible,
            "reading must not change the source queue display order")

        let query = JobQueryProbe()
        query.jobs = jobs
        precondition(query.queuedCount == 4, "queuedCount includes queued jobs of every account")
        precondition(query.jobs == jobs, "queries must leave the job snapshot unchanged")
        query.jobs = [
            make("older", .failed, 0, itemID: "target", stamp: 100),
            make("tie-first", .failed, 30, itemID: "target", stamp: 200),
            make("newer-other-account", .failed, 0, account: "B", itemID: "target", stamp: 500),
            make("tie-second", .failed, -10, itemID: "target", stamp: 200),
            make("non-failure", .running, 0, itemID: "target", stamp: 1000),
            make("queued", .queued, 0, itemID: "target", stamp: 1000),
            make("staged", .staged, 0, itemID: "target", stamp: 1000),
            make("committing", .committing, 0, itemID: "target", stamp: 1000),
            make("completed", .completed, 0, itemID: "target", stamp: 1000),
            make("cancelled", .cancelled, 0, itemID: "target", stamp: 1000),
            make("other-item", .failed, 0, itemID: "other", stamp: 1000),
            make("empty-account", .failed, 0, account: "", itemID: "target", stamp: 500),
            make("space-account", .failed, 0, account: " ", itemID: "target", stamp: 500)
        ]
        let beforeQueries = query.jobs
        precondition(query.failedJob(forWorkshopItemId: "target", accountSteamId: "A") == query.jobs[1],
            "equal latest timestamps retain the first input job, independent of id/ordinal")
        precondition(query.failedJob(forWorkshopItemId: "target", accountSteamId: "B")?.id == "newer-other-account")
        precondition(query.failedJob(forWorkshopItemId: "target", accountSteamId: "")?.id == "empty-account")
        precondition(query.failedJob(forWorkshopItemId: "target", accountSteamId: " ")?.id == "space-account")
        precondition(query.failedJob(forWorkshopItemId: "missing", accountSteamId: "A") == nil)
        precondition(query.failedJob(forWorkshopItemId: "target", accountSteamId: "missing") == nil)
        precondition(query.queuedCount == 1)
        precondition(query.jobs == beforeQueries)
        query.jobs.swapAt(1, 3)
        precondition(query.failedJob(forWorkshopItemId: "target", accountSteamId: "A")?.id == "tie-second")
        query.jobs = []
        precondition(query.queuedCount == 0)
        precondition(query.failedJob(forWorkshopItemId: "target", accountSteamId: "A") == nil)

        let counts = DownloadCountProbe()
        let types: [SteamWorkshopDownloadRecord.ContentType] = [.video, .web, .scene, .unknown]
        let statuses: [SteamWorkshopDownloadRecord.Status] = [.ready, .queued, .downloading, .failed("network")]
        for (statusIndex, status) in statuses.enumerated() {
            for (typeIndex, type) in types.enumerated() {
                counts.downloads.append(.init(id: "\(statusIndex)-\(typeIndex)", status: status, contentType: type))
            }
        }
        let records = counts.downloads
        // The retired source UI counters now belong to unified Query/Toolbar.
        // Keep the live record lookup contract across every status/type pair.
        for record in records {
            precondition((counts.downloadRecord(for: record.id) != nil) == (record.status == .ready))
        }
        precondition(counts.downloadRecord(for: "missing") == nil)
        precondition(counts.downloads == records, "lookup must not mutate or reorder records")
        counts.downloads = []
        precondition(counts.downloadRecord(for: "0-0") == nil)

        func history(_ job: String, _ attempt: Int, _ outcome: SteamDownloadHistoryOutcome,
                     _ time: TimeInterval, account: String = "A") -> SteamDownloadHistoryEntry {
            SteamDownloadHistoryEntry(
                jobID: job,
                workshopItemId: "item-\(job)",
                title: "History \(job)",
                accountSteamId: account,
                attempt: attempt,
                outcome: outcome,
                failureMessage: outcome == .failed ? "failed" : nil,
                recordID: outcome == .completed ? "item-\(job)" : nil,
                terminalAt: Date(timeIntervalSince1970: time)
            )
        }
        let entries = [
            history("retry", 1, .failed, 110),
            history("other", 1, .completed, 500, account: "B"),
            history("done", 1, .completed, 150),
            history("retry", 2, .completed, 200)
        ]
        let summaries = SteamWorkshopDownloadHistoryProjection.summaries(from: entries)
        precondition(summaries.map(\.jobID) == ["other", "retry", "done"])
        precondition(summaries[0].accountSteamID == "B" && summaries[1].accountSteamID == "A")
        precondition(summaries[1].attempts.map(\.attempt) == [2, 1] && summaries[1].latestAttempt == 2)
        precondition(summaries[1].latestOutcome == .completed)
        precondition(summaries[1].recordID == "item-retry")
        print("Download queries/projections: account isolation, states, first tied failure, ready record lookup and stable ordering PASS")
    }
}
'''
        job_store = (CORE / "SteamWorkshopJobStore.swift").read_text()
        accessors = (CORE / "SteamWorkshopService+DownloadAccessors.swift").read_text()
        harness = harness.replace("// JOB_QUERIES", "\n".join(method(job_store, signature) for signature in [
            "    func failedJob(", "    var queuedCount:"]))
        harness = harness.replace("// DOWNLOAD_QUERIES", "\n".join(method(accessors, signature) for signature in [
            "    func latestDownloadRecord(", "    func downloadRecord("]))
        with tempfile.TemporaryDirectory(prefix="mwx-steam-task-projection-") as directory:
            root = pathlib.Path(directory)
            source = root / "Harness.swift"
            source.write_text(harness)
            binary = root / "projection"
            subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", *map(str, SOURCES),
                 str(PROJECTION), str(source), "-o", str(binary)],
                check=True,
                timeout=120,
            )
            subprocess.run([str(binary)], check=True, timeout=15)

if __name__ == "__main__":
    unittest.main()
