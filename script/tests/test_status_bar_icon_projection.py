"""Exercise the production status icon projection without creating a system item."""
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
}
@MainActor final class Item { var button: Button? = Button() }
@MainActor final class Projection {
    var statusItem: Item? = Item()
    // PRODUCTION_STATE
    // PRODUCTION_UPDATE
    func update() { updateStatusBarIcon() }
}
@main enum Checks {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        let projection = Projection()
        let button = projection.statusItem!.button!
        let monitor = SystemMonitor.shared
        monitor.stats.gpuUsage = nil
        projection.update()
        let initial = button.image
        checks["nilMetricStillProducesInitialZeroIcon"] = initial != nil && button.assignments == 1
            && button.imagePosition == .imageOnly
        for _ in 0..<100 { projection.update() }
        checks["identicalTicksRetainImageWithoutButtonAssignment"] = button.image === initial && button.assignments == 1
        monitor.stats.gpuUsage = 0.004
        projection.update()
        checks["unchangedRoundedMetricReusesImage"] = button.image === initial && button.assignments == 1
        monitor.stats.gpuUsage = 0.006
        projection.update()
        let changed = button.image
        checks["roundedMetricChangePublishesNewImage"] = changed !== initial && button.assignments == 2
        button.effectiveAppearance = NSAppearance(named: .darkAqua)!
        projection.update()
        let dark = button.image
        checks["appearanceChangeRefreshesSamePercentage"] = dark !== changed && button.assignments == 3
        projection.update()
        checks["sameDarkAppearanceReusesNewImage"] = button.image === dark && button.assignments == 3
        monitor.stats.gpuUsage = nil
        projection.update()
        checks["metricBecomingUnavailableKeepsExistingZeroFallback"] = button.assignments == 4
        let detached = Projection()
        let item = detached.statusItem!
        detached.statusItem = nil
        detached.update()
        checks["detachedStatusItemCannotCommitDisplayedState"] = item.button!.assignments == 0
        detached.statusItem = item
        detached.update()
        checks["reattachmentStillReceivesInitialImage"] = item.button!.assignments == 1
        print(String(data: try JSONEncoder().encode(checks), encoding: .utf8)!)
    }
}
'''


class StatusBarIconProjectionTests(unittest.TestCase):
    def test_production_icon_reuses_unchanged_metric_and_refreshes_appearance(self):
        product = (ROOT / "MyWallpaperX/App/StatusBarController.swift").read_text()
        fields = "\n".join(line for line in product.splitlines()
                           if "private var displayedIcon" in line)
        source = HARNESS.replace("// PRODUCTION_STATE", fields).replace(
            "// PRODUCTION_UPDATE", method(product, "    private func updateStatusBarIcon("))
        with tempfile.TemporaryDirectory(prefix="mwx-status-icon-", dir="/private/tmp") as directory:
            work = Path(directory)
            swift = work / "Checks.swift"
            swift.write_text(source)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(swift),
                                    "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertEqual(len(checks), 9)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
