"""Exercise real SQLite transactions and the product manager's bounded save owner."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "MyWallpaperX/Modules/VideoLibrary/Core"


class VideoIndexOrderedSaveTests(unittest.TestCase):
    def test_ordered_snapshots_fallback_flush_reset_and_process_restart(self):
        persistence = (CORE / "WallpaperManager+Persistence.swift").read_text()
        manager = (CORE / "WallpaperManager.swift").read_text()
        store = (CORE / "WallpaperIndexStore.swift").read_text()
        fixture = (ROOT / "script/tests/fixtures/VideoIndexOrderedSaveHarness.swift").read_text()
        fields = "\n".join(next(line for line in manager.splitlines() if name in line) for name in [
            "var wallpaperIndexSaveRevision:", "var wallpaperIndexSaveEpoch:",
            "var didFinishInitialIndexLoad",
            "var wallpaperIndexSaveInFlight:", "var pendingWallpaperIndexSave:",
        ])
        state = declaration(manager, "    struct WallpaperIndexSaveSnapshot") + "\n" + fields
        methods = "\n".join(declaration(persistence, signature) for signature in [
            "    var defaults:", "    private var wallpaperIndexStore:",
            "    func saveWallpapers(", "    private func submitPendingWallpaperIndexSave(",
            "    private func applyWallpaperIndexSaveResult(", "    private func flushWallpaperIndex(",
            "    private func invalidateWallpaperIndexPersistence(", "    func flushPersistentState(",
            "    func loadWallpapers(", "    func deduplicatedWallpapersByPath(",
            "    func migrateLegacyWallpaperIndexToSQLite(",
            "    private func loadCodableValue<", "    func saveCodableValue<",
            "    private func decode<", "    private func encode<",
        ])
        # Observe transaction entry and control only the storage queue / SQLite
        # connection in the test copy. The production transaction body is intact.
        marker = "    private func saveWallpapersInternal(_ wallpapers: [VideoWallpaper]) throws {"
        self.assertEqual(store.count(marker), 1)
        store = store.replace("    private var db: OpaquePointer?", "    private var db: OpaquePointer?\n    private var auditSaves: [[String]] = []")
        store = store.replace(marker, marker + "\n        auditSaves.append(wallpapers.map(\\.id))")
        store += r'''
extension WallpaperIndexStore {
    func holdQueueForAudit(entered: DispatchSemaphore, release: DispatchSemaphore) {
        queue.async { entered.signal(); release.wait() }
    }
    func setReadOnlyForAudit(_ enabled: Bool) throws {
        try queue.sync { try exec("PRAGMA query_only=" + (enabled ? "ON" : "OFF") + ";") }
    }
    func savedIDsForAudit() -> [[String]] { queue.sync { auditSaves } }
    func clearAudit() { queue.sync { auditSaves = [] } }
}
'''
        reset = declaration(persistence, "    func resetToFreshInstallState(")
        self.assertLess(reset.index("invalidateWallpaperIndexPersistence()"), reset.index("wallpapers.removeAll()"))
        self.assertLess(reset.index("resetStore()"), reset.index("flushPersistentState()"))
        source = fixture.replace("// PRODUCTION_STATE", state).replace("// PRODUCTION_METHODS", methods)
        with tempfile.TemporaryDirectory(prefix="mwx-video-index-", dir="/private/tmp") as directory:
            work = Path(directory)
            swift = work / "Checks.swift"
            swift.write_text(source)
            actual_store = work / "WallpaperIndexStore.swift"
            actual_store.write_text(store)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(actual_store),
                                    str(ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"), str(swift),
                                    "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            for modes in [["startup"], ["bounded"], ["callbacks"], ["fallback-write", "fallback-read"],
                          ["empty-write", "empty-read"], ["bad-fallback"]]:
                home = work / modes[0]
                home.mkdir()
                env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
                for mode in modes:
                    run = subprocess.run([str(binary), mode], env=env,
                                         capture_output=True, text=True, timeout=30)
                    self.assertEqual(run.returncode, 0, mode + "\n" + run.stdout + run.stderr)
                    checks = json.loads(run.stdout)
                    self.assertTrue(checks)
                    for name, passed in checks.items():
                        with self.subTest(mode=mode, name=name):
                            self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
