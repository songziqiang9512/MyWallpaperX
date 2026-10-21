"""Exercise both production grid timer owners with real AppKit windows."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration


ROOT = Path(__file__).resolve().parents[2]
GRID = r'''
@MainActor private final class CLASS: NSView, ProbeAudit {
    let collectionView = Collection()
    let wallpaperManager = ProbeManager()
    var orderedIDs = ["a"]
    var wallpapersByID = ["a": Record(id: "a", path: "/fixture/a")]
    var lifecycleUpdates = 0
    var thumbnailWindowObservation: NSKeyValueObservation?
    var thumbnailWindowVisibilityObservation: NSKeyValueObservation?
    // PRODUCTION_STATE
    init() { super.init(frame: NSRect(x: 0, y: 0, width: 80, height: 80)) }
    required init?(coder: NSCoder) { nil }
    deinit {
        TIMER?.cancel()
        missingPathWindowObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    var view: NSView { self }
    var timerIdentity: ObjectIdentifier? { TIMER.map { ObjectIdentifier($0 as AnyObject) } }
    var observerCount: Int { missingPathWindowObservers.count }
    var inFlight: Bool { isMissingPathProbeInFlight }
    var pendingResume: Bool { needsMissingPathProbeAfterFlight }
    var reloadCount: Int { collectionView.reloadCount }
    func fire() { PROBE() }
    func synchronize() { updateMissingPathProbeTimer() }
    func scheduleRestingScrollOriginCapture() {}
    // Prefetch is an unrelated leaf in this source-existence timer gate.
    func scheduleThumbnailPrefetch() {}
    func cancelThumbnailPrefetch() {}
    func scheduleViewportPrefetch() {}
    func cancelViewportPrefetch() {}
    func updateVisibleThumbnailDemand() {}
    func reloadVisibleItems(forIDs ids: Set<String>) { if !ids.isEmpty { collectionView.reloadCount += 1 } }
    // PRODUCTION_METHODS
}
'''


class UIPathProbeWindowLifecycleTests(unittest.TestCase):
    def test_native_window_timer_leases_and_bounded_resume(self):
        template = (ROOT / "script/tests/fixtures/UIPathProbeWindowLifecycleHarness.swift").read_text()
        grids = []
        for name, relative, timer, start, probe in [
            ("VideoGrid", "VideoLibrary/UI/AppKitLibraryGridView.swift", "missingPathProbeTimer",
             "startMissingPathProbeTimer", "probeVisibleMissingWallpapers"),
            ("SILGrid", "StaticImageLibrary/UI/SILGridContainerView.swift", "missingPathTimer",
             "startMissingPathTimer", "probeMissingPaths"),
        ]:
            product = (ROOT / "MyWallpaperX/Modules" / relative).read_text()
            fields = ["private var " + field for field in [
                timer, "isMissingPathProbeInFlight", "missingPathWindowObservers", "needsMissingPathProbeAfterFlight",
            ]]
            if name == "VideoGrid":
                fields.append("private var visibleMissingWallpaperIDs")
            state = "\n".join(next(line for line in product.splitlines() if field in line) for field in fields)
            methods = "\n".join(declaration(product, signature) for signature in [
                "    override func viewDidMoveToWindow(", "    private var canProbeMissingPaths:",
                "    private func updateMissingPathProbeTimer(", "    private func " + start + "(",
                "    private func " + probe + "(",
            ])
            if name == "SILGrid":
                self.assertEqual(methods.count("FileManager.default"), 1)
                methods = methods.replace("FileManager.default", "ProbeFiles.shared")
            # Count real lease callbacks without changing their admission or timer body.
            methods = methods.replace("private func updateMissingPathProbeTimer() {",
                                      "private func updateMissingPathProbeTimer() { lifecycleUpdates += 1")
            source = GRID.replace("CLASS", name).replace("TIMER", timer).replace("PROBE()", probe + "()")
            grids.append(source.replace("// PRODUCTION_STATE", state).replace("// PRODUCTION_METHODS", methods))
        source = template.replace("// PRODUCTION_GRIDS", "\n".join(grids))
        with tempfile.TemporaryDirectory(prefix="mwx-grid-window-probe-", dir="/private/tmp") as folder:
            work = Path(folder)
            swift = work / "Checks.swift"
            swift.write_text(source)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(swift),
                                    "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                                 capture_output=True, text=True, timeout=90)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 30)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed, run.stderr)


if __name__ == "__main__":
    unittest.main()
