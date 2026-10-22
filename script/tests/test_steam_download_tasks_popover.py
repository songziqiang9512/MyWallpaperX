"""Exercise SK5.2 current and SK5.3 history projections plus AppKit wiring."""
import pathlib
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_transaction import CORE, ROOT, SOURCES
from script.tests.test_steam_library_interactions import method

PROJECTION = CORE / "SteamWorkshopDownloadTaskProjection.swift"
UI = ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopDownloadTasksPopover.swift"
TOOLBAR = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Toolbar"


class SteamDownloadTasksPopoverTests(unittest.TestCase):
    def test_current_projection_is_account_scoped_and_stably_ordered(self):
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
    var displayedDownloads: [SteamWorkshopDownloadRecord] = []
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

        precondition(SteamWorkshopDownloadTaskProjection.currentJobs(
            from: jobs, accountSteamID: nil).isEmpty)
        let visible = SteamWorkshopDownloadTaskProjection.currentJobs(
            from: jobs, accountSteamID: "A")
        precondition(visible.map(\.id) == ["saving", "active", "staged", "failed", "queued-1", "queued-2"])
        precondition(SteamWorkshopDownloadTaskProjection.unfinishedCount(
            in: jobs, accountSteamID: "A") == 6)
        precondition(SteamWorkshopDownloadTaskProjection.jobKey(for: visible[0]) == "saving-1")
        precondition(SteamWorkshopDownloadTaskProjection.jobKey(for: visible[4]) == nil)
        precondition(!SteamWorkshopDownloadTaskProjection.isCancellable(visible[0]))
        precondition(SteamWorkshopDownloadTaskProjection.isCancellable(visible[1]))
        precondition(SteamWorkshopDownloadTaskProjection.isCancellable(visible[4]))

        let accounts: [(String?, Int)] = [(nil, 0), ("", 0), ("A", 6), ("B", 2), (" ", 1), ("missing", 0)]
        for (account, expected) in accounts {
            let count = SteamWorkshopDownloadTaskProjection.unfinishedCount(in: jobs, accountSteamID: account)
            precondition(count == expected)
            precondition(count == SteamWorkshopDownloadTaskProjection.currentJobs(
                from: jobs, accountSteamID: account).count,
                "the toolbar count and current-task panel must admit the same jobs")
            precondition(SteamWorkshopDownloadTaskProjection.unfinishedCount(in: [], accountSteamID: account) == 0)
        }
        precondition(SteamWorkshopDownloadTaskProjection.currentJobs(
            from: Array(jobs.reversed()), accountSteamID: "A") == visible,
            "counting must not change the current-task display order")

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
        precondition(counts.downloadsCount == 4, "ready unknown records belong only to the total")
        precondition(counts.visibleVideoDownloadsCount == 1)
        precondition(counts.visibleWebDownloadsCount == 1)
        precondition(counts.visibleSceneDownloadsCount == 1)
        for record in records {
            precondition((counts.downloadRecord(for: record.id) != nil) == (record.status == .ready))
        }
        precondition(counts.downloadRecord(for: "missing") == nil)
        counts.displayedDownloads = Array(records.suffix(4))
        precondition(counts.downloadsCount == 4, "browse filtering does not alter the library counts")
        precondition(counts.downloads == records, "counting must not mutate or reorder records")
        counts.downloads = []
        precondition(counts.downloadsCount == 0 && counts.visibleVideoDownloadsCount == 0
            && counts.visibleWebDownloadsCount == 0 && counts.visibleSceneDownloadsCount == 0)

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
        precondition(SteamWorkshopDownloadHistoryProjection.summaries(
            from: entries, accountSteamID: nil).isEmpty)
        let summaries = SteamWorkshopDownloadHistoryProjection.summaries(
            from: entries, accountSteamID: "A")
        precondition(summaries.map(\.jobID) == ["retry", "done"])
        precondition(summaries[0].attempts.map(\.attempt) == [2, 1])
        precondition(summaries[0].latestOutcome == .completed)
        precondition(summaries[0].recordID == "item-retry")
        print("Download queries/projections: account isolation, states, first tied failure, ready counts and stable ordering PASS")
    }
}
'''
        job_store = (CORE / "SteamWorkshopJobStore.swift").read_text()
        accessors = (CORE / "SteamWorkshopService+DownloadAccessors.swift").read_text()
        harness = harness.replace("// JOB_QUERIES", "\n".join(method(job_store, signature) for signature in [
            "    func failedJob(", "    var queuedCount:"]))
        harness = harness.replace("// DOWNLOAD_QUERIES", "\n".join(method(accessors, signature) for signature in [
            "    var visibleVideoDownloadsCount:", "    var visibleWebDownloadsCount:",
            "    var visibleSceneDownloadsCount:", "    var downloadsCount:",
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

    def test_popover_uses_existing_owners_and_bounded_observation(self):
        ui = UI.read_text()
        controller = (TOOLBAR / "SteamWorkshopToolbarController.swift").read_text()
        layouts = (TOOLBAR / "SteamWorkshopToolbarController+Layouts.swift").read_text()
        actions = (TOOLBAR / "SteamWorkshopToolbarController+Actions.swift").read_text()
        selection = (CORE / "SteamWorkshopService+DownloadSelection.swift").read_text()

        self.assertIn("private let popover = NSPopover()", ui)
        self.assertIn("popover.behavior = .transient", ui)
        self.assertIn("func startObserving()", ui)
        self.assertIn("func stopObserving()", ui)
        self.assertIn("service.downloadJobStore.$jobs", ui)
        self.assertIn("service.downloadJobStore.$history", ui)
        self.assertIn("service.downloadProgressStore.addObserver", ui)
        self.assertIn("progressBar.setAccessibilityRole(.progressIndicator)", ui)
        self.assertIn('progressBar.setAccessibilityLabel("下载进度：\\(summary.title)")', ui)
        self.assertIn("owner: self", ui)
        self.assertIn("service.downloadProgressStore.removeObserver", ui)
        self.assertIn("SteamWorkshopDownloadHistoryProjection.summaries", ui)
        # 单一队列：无进行中/历史分栏，无查看已下载，无二次确认。
        self.assertNotIn('["进行中", "历史"]', ui)
        self.assertNotIn("查看已下载", ui)
        self.assertNotIn("取消全部下载任务？", ui)
        self.assertNotIn("清空下载历史？", ui)
        self.assertIn("全部清除", ui)
        self.assertIn("不删除已下载文件", ui)
        self.assertIn('clearButton.setAccessibilityLabel("清除：\\(job.title)")', ui)
        self.assertIn('clearButton.setAccessibilityLabel("清除：\\(summary.title)")', ui)
        self.assertIn("removeHistory(forJobID: summary.jobID", ui)
        self.assertNotIn("Timer.scheduledTimer", ui)
        self.assertNotIn("NSMenu()", ui)
        self.assertNotIn("showLoginPanel", ui)

        self.assertIn("var downloadTasksPopoverController", controller)
        self.assertIn("existingDownloadTasksPopoverController?.close()", controller)
        self.assertIn("menuFormRepresentation", controller)
        self.assertIn("downloadTasksButton.window != nil", actions)
        self.assertIn("positioningRect: anchor", actions)
        self.assertIn(".steamDownloadTasks", layouts)
        self.assertIn(".steamDownloadTasks", actions)
        self.assertLess(layouts.index(".steamAccount"), layouts.index(".steamDownloadTasks"))
        downloads_layout = layouts.split("var downloadsIdentifiers", 1)[1]
        self.assertLess(downloads_layout.index(".steamAccount"), downloads_layout.index(".steamDownloadTasks"))


if __name__ == "__main__":
    unittest.main()
