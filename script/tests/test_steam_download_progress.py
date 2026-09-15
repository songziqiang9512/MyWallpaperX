"""Exercise the item-scoped App progress projection without AppKit or Steam I/O."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopDownloadProgress.swift"


class SteamDownloadProgressTests(unittest.TestCase):
    def test_progress_is_attempt_scoped_monotonic_and_bounded(self):
        harness = r'''
import Foundation

@main struct Harness {
    @MainActor static func main() {
        let store = SteamWorkshopDownloadProgressStore()
        var itemAEvents: [SteamWorkshopDownloadProgressSnapshot?] = []
        var itemBEvents = 0
        let observerA = store.addObserver(for: "A") { itemAEvents.append($0) }
        _ = store.addObserver(for: "B") { _ in itemBEvents += 1 }
        precondition(itemAEvents.count == 1 && itemAEvents[0] == nil)
        precondition(itemBEvents == 1)

        store.begin(itemID: "A", jobKey: "job-1", attempt: 1)
        precondition(store.snapshot(for: "A")?.phase == .connecting)
        precondition(store.snapshot(for: "A")?.fraction == nil)
        precondition(itemBEvents == 1, "A updates must not notify B")

        func publish(_ sequence: Int, verified: Int64, total: Int64 = 100) -> Bool {
            store.receiveHelperEvent(itemID: "A", jobKey: "job-1", attempt: 1,
                sequence: sequence, stage: "chunks", totalBytes: total, verifiedBytes: verified)
        }
        precondition(publish(1, verified: 0))
        precondition(store.snapshot(for: "A")?.percent == 0)
        precondition(publish(2, verified: 1))
        precondition(store.snapshot(for: "A")?.percent == 1)
        precondition(publish(3, verified: 50))
        precondition(store.snapshot(for: "A")?.percent == 50)
        precondition(store.snapshot(for: "A")?.statusText(compact: true) == "50%")
        precondition(store.snapshot(for: "A")?.statusText().contains("50%") == true)
        precondition(!publish(3, verified: 60), "duplicate sequence must be ignored")
        precondition(!publish(4, verified: 49), "verified bytes must be monotonic")
        precondition(!publish(4, verified: 101), "verified bytes cannot exceed total")
        precondition(!publish(4, verified: 1, total: 8 * 1024 * 1024 * 1024 + 1),
            "total must stay within the per-item admission cap")
        precondition(publish(4, verified: 100))
        precondition(store.snapshot(for: "A")?.percent == 100)

        store.markSaving(itemID: "A", jobKey: "job-1")
        precondition(store.snapshot(for: "A")?.phase == .saving)
        precondition(store.snapshot(for: "A")?.percent == 100)
        precondition(!store.receiveHelperEvent(itemID: "A", jobKey: "job-1", attempt: 1,
            sequence: 99, stage: "chunks", totalBytes: 100, verifiedBytes: 100),
            "late helper events cannot regress the saving phase")
        store.fail(itemID: "A", jobKey: "job-1", message: "disk full")
        precondition(store.snapshot(for: "A")?.phase == .failed)
        precondition(store.snapshot(for: "A")?.fraction == 1)
        precondition(store.snapshot(for: "A")?.failureMessage == "disk full")

        store.begin(itemID: "A", jobKey: "job-2", attempt: 2)
        precondition(store.snapshot(for: "A")?.jobKey == "job-2")
        precondition(store.snapshot(for: "A")?.verifiedBytes == 0)
        precondition(!store.receiveHelperEvent(itemID: "A", jobKey: "job-1", attempt: 1,
            sequence: 99, stage: "chunks", totalBytes: 100, verifiedBytes: 99))
        store.clear(itemID: "A", jobKey: "job-1")
        precondition(store.snapshot(for: "A")?.jobKey == "job-2",
            "an old completion cannot clear a newer attempt")
        precondition(store.receiveHelperEvent(itemID: "A", jobKey: "job-2", attempt: 2,
            sequence: 1, stage: "preparing", totalBytes: nil, verifiedBytes: nil))
        precondition(store.snapshot(for: "A")?.statusText() == "正在获取文件信息")

        let countBeforeRemoval = itemAEvents.count
        store.removeObserver(observerA)
        store.markWaiting(itemID: "A", jobKey: "job-2")
        precondition(store.snapshot(for: "A")?.phase == .waiting)
        precondition(store.snapshot(for: "A")?.statusText() == "等待重连")
        precondition(itemAEvents.count == countBeforeRemoval)

        final class Owner {}
        var owner: Owner? = Owner()
        var ownedEvents = 0
        _ = store.addObserver(for: "B", owner: owner!) { _ in ownedEvents += 1 }
        precondition(ownedEvents == 1)
        owner = nil
        store.begin(itemID: "B", jobKey: "job-b", attempt: 1)
        precondition(ownedEvents == 1, "released view owners must not receive or retain observations")
        store.removeAll()
        precondition(store.snapshot(for: "A") == nil)
        print("Download progress: scoped observer, 0/1/50/100 boundaries, retry identity and terminal retention PASS")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="mwx-steam-progress-") as directory:
            root = pathlib.Path(directory)
            source = root / "Harness.swift"
            source.write_text(harness)
            binary = root / "progress"
            subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(SOURCE), str(source),
                            "-o", str(binary)], check=True, timeout=120)
            subprocess.run([str(binary)], check=True, timeout=15)

    def test_ui_projection_does_not_publish_or_reload_the_grid(self):
        progress = SOURCE.read_text()
        downloads = (ROOT / "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift").read_text()
        cell = (ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserItem.swift").read_text()
        support = (ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserItemSupportViews.swift").read_text()
        self.assertNotRegex(progress, r"final class SteamWorkshopDownloadProgressStore\s*:\s*ObservableObject")
        self.assertNotIn("@Published", progress)
        observer_body = downloads.split("let observer = steamServiceClient.addEventObserver", 1)[1].split("let task = Task", 1)[0]
        self.assertNotIn("statusMessage =", observer_body)
        self.assertIn("unbindDownloadProgress()", cell.split("override func prepareForReuse", 1)[1].split("func configure(", 1)[0])
        self.assertIn("fillClipLayer", support)
        self.assertNotIn("setScanAnimationEnabled", support)
        self.assertNotIn("steam.bar.scan", support)


if __name__ == "__main__":
    unittest.main()
