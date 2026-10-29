"""Exercise update reminders and the production status icon without network or a system item."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method


ROOT = Path(__file__).resolve().parents[2]
HARNESS = r'''
import AppKit
import Foundation

// Sparkle transport leaves: the complete product controller owns reminder state.
@MainActor protocol SPUStandardUserDriverDelegate: AnyObject {}
struct SUAppcastItem { let displayVersionString: String }
struct SPUUserUpdateState { let userInitiated: Bool }
@MainActor final class SPUStandardUpdaterController {
    static var instances = 0
    static var latest: SPUStandardUpdaterController!
    let started: Bool
    weak var delegate: (any SPUStandardUserDriverDelegate)?
    var checkCalls = 0
    var lastSender: Any?
    let updater = UpdateAvailability()
    final class UpdateAvailability { var canCheckForUpdates = true }
    init(startingUpdater: Bool, updaterDelegate: AnyObject?, userDriverDelegate: any SPUStandardUserDriverDelegate) {
        started = startingUpdater; delegate = userDriverDelegate
        Self.instances += 1; Self.latest = self
    }
    func checkForUpdates(_ sender: Any?) { checkCalls += 1; lastSender = sender }
}
@MainActor var presentedAlerts = 0
@MainActor func makeAppAlert(title: String, message: String, buttons: [String]) -> NSAlert { NSAlert() }
@MainActor func appModalHostWindow() -> NSWindow? { nil }
@MainActor func presentAppAlert(_ alert: NSAlert, in window: NSWindow?) { presentedAlerts += 1 }
// PRODUCT_UPDATE_OWNER

@MainActor final class SystemMonitor {
    struct Stats { var gpuUsage: Double? }
    static let shared = SystemMonitor()
    var stats = Stats()
}
@MainActor final class Button {
    var effectiveAppearance = NSAppearance(named: .aqua)!
    var assignments = 0
    var image: NSImage? { didSet { assignments += 1 } }
    var imagePosition = NSControl.ImagePosition.noImage
    var toolTip: String?
}
@MainActor final class Item { var button: Button? = Button() }
@MainActor final class Projection {
    var statusItem: Item? = Item()
    // PRODUCTION_STATE
    // PRODUCTION_UPDATE
    var label: String? { displayedIconLabel }
    func update() { updateStatusBarIcon() }
}
@main enum Checks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks: [String: Bool] = [:]
        let projection = Projection()
        let button = projection.statusItem!.button!
        let monitor = SystemMonitor.shared
        monitor.stats.gpuUsage = nil
        projection.update()
        let initial = button.image
        checks["nilMetricProducesUnavailableIcon"] = initial != nil && projection.label == "—" && button.assignments == 1
            && button.imagePosition == .imageOnly
        for _ in 0..<100 { projection.update() }
        checks["identicalTicksRetainImageWithoutButtonAssignment"] = button.image === initial && button.assignments == 1
        monitor.stats.gpuUsage = 0.004
        projection.update()
        let zero = button.image
        checks["realZeroDiffersFromUnavailable"] = zero !== initial && projection.label == "0%" && button.assignments == 2
        projection.update()
        checks["unchangedRoundedMetricReusesImage"] = button.image === zero && button.assignments == 2
        monitor.stats.gpuUsage = 0.006
        projection.update()
        let changed = button.image
        checks["roundedMetricChangePublishesNewImage"] = changed !== zero && button.assignments == 3
        button.effectiveAppearance = NSAppearance(named: .darkAqua)!
        projection.update()
        let dark = button.image
        checks["appearanceChangeRefreshesSamePercentage"] = dark !== changed && button.assignments == 4
        projection.update()
        checks["sameDarkAppearanceReusesNewImage"] = button.image === dark && button.assignments == 4
        monitor.stats.gpuUsage = nil
        projection.update()
        checks["metricBecomingUnavailableUsesDash"] = projection.label == "—" && button.assignments == 5
        let detached = Projection()
        let item = detached.statusItem!
        detached.statusItem = nil
        detached.update()
        checks["detachedStatusItemCannotCommitDisplayedState"] = item.button!.assignments == 0
        detached.statusItem = item
        detached.update()
        checks["reattachmentStillReceivesInitialImage"] = item.button!.assignments == 1
        let updates = AppUpdateController.shared
        let transport = SPUStandardUpdaterController.latest!
        checks["oneUpdaterRetainsTheRealReminderDelegate"] = SPUStandardUpdaterController.instances == 1
            && transport.delegate === updates && updates.supportsGentleScheduledUpdateReminders
        #if DEBUG
        checks["configuredStartPolicy"] = !transport.started
        #else
        checks["configuredStartPolicy"] = transport.started
        #endif
        let update = SUAppcastItem(displayVersionString: "9.1")
        let menu = NSMenuItem(title: "检查更新…", action: #selector(AppUpdateController.checkForUpdates(_:)), keyEquivalent: "")
        transport.updater.canCheckForUpdates = false
        #if DEBUG
        checks["menuKeepsDebugNoticeAvailable"] = updates.validateMenuItem(menu)
        #else
        checks["menuRejectsBusyBackgroundUpdate"] = !updates.validateMenuItem(menu)
        #endif
        transport.updater.canCheckForUpdates = true
        updates.standardUserDriverWillHandleShowingUpdate(true, forUpdate: update, state: .init(userInitiated: false))
        projection.update()
        checks["scheduledUpdateHasVisibleMenuAndIconReminder"] = updates.validateMenuItem(menu)
            && menu.title == "发现新版本 9.1…" && projection.label == "↑ —"
            && button.toolTip?.contains("有可用更新") == true
        let reminderImage = button.image, reminderAssignments = button.assignments
        for _ in 0..<100 { projection.update() }
        checks["unchangedReminderDoesNotRebuildIcon"] = button.image === reminderImage && button.assignments == reminderAssignments
        updates.standardUserDriverWillHandleShowingUpdate(true, forUpdate: .init(displayVersionString: "9.2"), state: .init(userInitiated: false))
        projection.update()
        checks["versionOnlyChangeUpdatesMenuWithoutRebuildingSameHint"] = updates.validateMenuItem(menu)
            && menu.title == "发现新版本 9.2…" && button.image === reminderImage
        updates.standardUserDriverDidReceiveUserAttention(forUpdate: update)
        projection.update()
        checks["userAttentionRetiresBothReminderSurfaces"] = updates.validateMenuItem(menu)
            && menu.title == "检查更新…" && projection.label == "—" && button.toolTip == "MyWallpaperX · 壁纸控制"
        updates.standardUserDriverWillHandleShowingUpdate(true, forUpdate: update, state: .init(userInitiated: false))
        updates.standardUserDriverWillFinishUpdateSession()
        projection.update()
        checks["sessionEndRetiresReminder"] = updates.availableUpdateVersion == nil && projection.label == "—"
        updates.standardUserDriverWillHandleShowingUpdate(true, forUpdate: update, state: .init(userInitiated: true))
        checks["manualUpdateDoesNotCreateBackgroundReminder"] = updates.availableUpdateVersion == nil
        let sender = NSObject()
        updates.checkForUpdates(sender)
        #if DEBUG
        checks["originalCheckActionPolicy"] = transport.checkCalls == 0 && presentedAlerts == 1
        #else
        checks["originalCheckActionPolicy"] = transport.checkCalls == 1 && (transport.lastSender as? NSObject) === sender && presentedAlerts == 0
        #endif
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
'''


class StatusBarIconProjectionTests(unittest.TestCase):
    def test_production_icon_reuses_unchanged_metric_and_refreshes_appearance(self):
        product = (ROOT / "MyWallpaperX/App/StatusBarController.swift").read_text()
        updater = (ROOT / "MyWallpaperX/App/AppUpdateController.swift").read_text()
        fields = "\n".join(line for line in product.splitlines()
                           if "private var displayedIcon" in line)
        source = HARNESS.replace("// PRODUCTION_STATE", fields).replace(
            "// PRODUCTION_UPDATE", method(product, "    private func updateStatusBarIcon(")).replace(
            "// PRODUCT_UPDATE_OWNER", updater.replace("import Sparkle\n", ""))
        with tempfile.TemporaryDirectory(prefix="mwx-status-icon-", dir="/private/tmp") as directory:
            work = Path(directory)
            swift = work / "Checks.swift"
            swift.write_text(source)
            for mode, flags in [("debug", ["-D", "DEBUG"]), ("release", [])]:
                binary = work / mode
                build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *flags, str(swift),
                                        "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                                       capture_output=True, text=True, timeout=120)
                self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
                run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                checks = json.loads(run.stdout)
                self.assertEqual(len(checks), 20)
                for name, passed in checks.items():
                    with self.subTest(mode=mode, name=name):
                        self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
