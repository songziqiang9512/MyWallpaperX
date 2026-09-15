"""Exercise SK5.2 current and SK5.3 history projections plus AppKit wiring."""
import pathlib
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_transaction import CORE, ROOT, SOURCES

PROJECTION = CORE / "SteamWorkshopDownloadTaskProjection.swift"
UI = ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopDownloadTasksPopover.swift"
TOOLBAR = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Toolbar"


class SteamDownloadTasksPopoverTests(unittest.TestCase):
    def test_current_projection_is_account_scoped_and_stably_ordered(self):
        harness = r'''
import Foundation

@main struct Harness {
    @MainActor static func main() {
        let now = Date(timeIntervalSince1970: 100)
        func make(_ id: String, _ state: SteamDownloadJobState, _ ordinal: Int,
                  account: String = "A", attempt: Int = 1) -> SteamDownloadJob {
            SteamDownloadJob(
                id: id,
                workshopItemId: "item-\(id)",
                title: "Title \(id)",
                state: state,
                attempt: attempt,
                queueOrdinal: ordinal,
                accountSteamId: account,
                stagingPath: nil,
                failureMessage: state == .failed ? "network" : nil,
                createdAt: now,
                updatedAt: now
            )
        }
        let jobs = [
            make("queued-2", .queued, 20),
            make("other", .running, 1, account: "B"),
            make("failed", .failed, 5),
            make("completed", .completed, 2),
            make("saving", .committing, 4),
            make("cancelled", .cancelled, 3),
            make("active", .running, 8),
            make("queued-1", .queued, 10, attempt: 0)
        ]

        precondition(SteamWorkshopDownloadTaskProjection.currentJobs(
            from: jobs, accountSteamID: nil).isEmpty)
        let visible = SteamWorkshopDownloadTaskProjection.currentJobs(
            from: jobs, accountSteamID: "A")
        precondition(visible.map(\.id) == ["saving", "active", "failed", "queued-1", "queued-2"])
        precondition(SteamWorkshopDownloadTaskProjection.unfinishedCount(
            in: jobs, accountSteamID: "A") == 5)
        precondition(SteamWorkshopDownloadTaskProjection.jobKey(for: visible[0]) == "saving-1")
        precondition(SteamWorkshopDownloadTaskProjection.jobKey(for: visible[3]) == nil)
        precondition(!SteamWorkshopDownloadTaskProjection.isCancellable(visible[0]))
        precondition(SteamWorkshopDownloadTaskProjection.isCancellable(visible[1]))
        precondition(SteamWorkshopDownloadTaskProjection.isCancellable(visible[3]))

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
        print("Download task/history projection: account isolation, stable ordering and attempt grouping PASS")
    }
}
'''
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
        self.assertIn("func requestInitialFocus()", ui)
        self.assertIn("view.window?.makeFirstResponder(modeControl)", ui)
        self.assertIn("guard let self, self.popover.isShown else { return }", ui)
        self.assertIn("service.downloadJobStore.$jobs", ui)
        self.assertIn("service.downloadJobStore.$history", ui)
        self.assertIn("service.steamAuth.$expired", ui)
        self.assertIn("请使用工具栏重新登录", ui)
        self.assertIn("service.downloadProgressStore.addObserver", ui)
        self.assertIn("private let progressBar = SteamWorkshopGlassBarView()", ui)
        self.assertIn("progressBar.setAccessibilityRole(.progressIndicator)", ui)
        self.assertIn('progressBar.setAccessibilityLabel("下载进度：\\(job.title)")', ui)
        self.assertIn("let bucket = percent.map { $0 / 10 }", ui)
        self.assertIn("NSAccessibility.post(element: progressBar, notification: .valueChanged)", ui)
        self.assertIn('cancelButton.setAccessibilityLabel("取消：\\(job.title)")', ui)
        self.assertIn('retryButton.setAccessibilityLabel("重试：\\(job.title)")', ui)
        self.assertIn('detailButton.setAccessibilityLabel("详情：\\(job.title)")', ui)
        self.assertIn('detailButton.setAccessibilityLabel("\\(detailButton.title)：\\(summary.title)")', ui)
        self.assertIn("owner: self", ui)
        self.assertIn("service.downloadProgressStore.removeObserver", ui)
        self.assertIn("Keep existing rows fixed", ui)
        self.assertIn("取消全部下载任务？", ui)
        self.assertIn("已下载文件不会被删除", ui)
        self.assertIn('["进行中", "历史"]', ui)
        self.assertIn("SteamWorkshopDownloadHistoryProjection.summaries", ui)
        self.assertIn("清空下载历史？", ui)
        self.assertIn("不会取消任务，也不会删除已下载文件", ui)
        self.assertIn("已下载文件不存在", ui)
        self.assertIn("availableDownloadRecord(forHistoryRecordID: recordID)", ui)
        self.assertIn("service.focusDownloadRecordFromHistory(itemID: recordID)", ui)
        self.assertIn("func focusDownloadRecordFromHistory", selection)
        focus = selection.split("func focusDownloadRecordFromHistory", 1)[1].split("\n    }", 1)[0]
        self.assertIn("downloadsDisplayMode = .all", focus)
        self.assertIn('downloadsQuery = ""', focus)
        self.assertIn("selectDownload(itemID: itemID)", focus)
        self.assertIn('"selectedItem": "steamDownloads"', ui)
        self.assertNotIn("Timer.scheduledTimer", ui)
        self.assertNotIn("NSMenu()", ui)
        self.assertNotIn("showLoginPanel", ui)

        self.assertIn("var downloadTasksPopoverController", controller)
        self.assertIn("existingDownloadTasksPopoverController?.close()", controller)
        self.assertIn("menuFormRepresentation", controller)
        self.assertIn("downloadTasksButtonView.button.window != nil", actions)
        self.assertIn("positioningRect: anchor", actions)
        self.assertIn("下载任务，\\(safeCount) 项", ui)
        self.assertIn(".steamDownloadTasks", layouts)
        self.assertIn(".steamDownloadTasks", actions)
        self.assertLess(layouts.index(".steamAccount"), layouts.index(".steamDownloadTasks"))
        downloads_layout = layouts.split("var downloadsIdentifiers", 1)[1]
        self.assertLess(downloads_layout.index(".steamAccount"), downloads_layout.index(".steamDownloadTasks"))


if __name__ == "__main__":
    unittest.main()
