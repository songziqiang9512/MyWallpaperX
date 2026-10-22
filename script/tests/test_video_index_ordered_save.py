"""Exercise real SQLite transactions and the product manager's bounded save owner."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

from script.tests.test_ui_library_algorithms import declaration


ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "MyWallpaperX/Modules/VideoLibrary/Core"


class VideoIndexOrderedSaveTests(unittest.TestCase):
    def test_ordered_snapshots_fallback_flush_reset_and_process_restart(self):
        persistence = (CORE / "WallpaperManager+Persistence.swift").read_text()
        manager = (CORE / "WallpaperManager.swift").read_text()
        store = (CORE / "WallpaperIndexStore.swift").read_text()
        startup = (CORE / "WallpaperManager+InitialIndexLoad.swift").read_text()
        fixture = (ROOT / "script/tests/fixtures/VideoIndexOrderedSaveHarness.swift").read_text()
        fields = "\n".join(next(line for line in manager.splitlines() if name in line) for name in [
            "var wallpaperIndexSaveRevision:", "var wallpaperIndexSaveEpoch:",
            "var didFinishInitialIndexLoad", "var initialIndexChanges =", "var initialIndexLoadGeneration:",
            "var initialIndexLoadInFlight", "var initialIndexBootstrapInProgress", "var initialIndexSeedWallpapers:",
            "var initialIndexInternalPublication", "var initialIndexGlobalMutationDepth",
            "var wallpaperIndexSaveInFlight:", "var pendingWallpaperIndexSave:",
        ])
        state = declaration(manager, "    struct WallpaperIndexSaveSnapshot") + "\n" + fields
        observer = declaration(manager, "    @Published var wallpapers:").replace("@Published ", "")
        state += "\n" + observer + "\n" + declaration(manager, "    func normalizeRecentWallpapers(")
        state += "\n" + declaration(manager, "    func constrainRecentWallpapersToLibrary(")
        selection = (CORE / "WallpaperManager+Selection.swift").read_text()
        state += "\n" + declaration(selection, "    func syncSelectedWallpaperInspectorIfNeeded(")
        methods = "\n".join(declaration(persistence, signature) for signature in [
            "    var defaults:", "    private var wallpaperIndexStore:",
            "    func saveWallpapers(", "    private func submitPendingWallpaperIndexSave(",
            "    private func applyWallpaperIndexSaveResult(", "    private func flushWallpaperIndex(",
            "    private func invalidateWallpaperIndexPersistence(", "    func flushPersistentState(",
            "    func loadWallpapers(", "    func deduplicatedWallpapersByPath(",
            "    func loadRecentWallpapers(",
            "    func saveRecentWallpapers(",
            "    private func loadCodableValue<", "    func saveCodableValue<",
            "    private func decode<", "    private func encode<",
        ])
        imports = (CORE / "WallpaperManager+ImportProcessing.swift").read_text()
        presentation = (CORE / "WallpaperManager+ImportPresentation.swift").read_text()
        for signature in ["    private struct ImportCounters", "    private struct PreparedImportEntry",
                          "    private struct ImportPreparationResult", "    private func applyPreparedImportResult(",
                          "    private func recordInitialIndexImportContext(", "    private func applyContextMetadataIfNeeded(",
                          "    private func makePreparedWallpaper(", "    private func appendWallpapersInBatches(",
                          "    private func makeImportSummary("]:
            methods += "\n" + declaration(imports, signature)
        methods += "\n" + declaration(presentation, "    func importFailureBreakdown(")
        support = (CORE / "WallpaperLibrarySupport.swift").read_text()
        import_types = declaration(support, "struct ImportSummary") + "\n" + declaration(support, "enum ImportContext")
        playback = ROOT / "MyWallpaperX/Core/PlaybackControl"
        import_types += "\n" + (playback / "PlaybackResourceLifetime.swift").read_text()
        import_types += "\n" + (playback / "ImportedVideoAutoplayGate.swift").read_text()
        # Isolate the filesystem and CFPreferences leaves explicitly; HOME alone
        # does not define a macOS application's preferences domain.
        methods = methods.replace("var defaults: UserDefaults { .standard }",
                                  'var defaults: UserDefaults { UserDefaults(suiteName: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_DOMAIN"]!)! }')
        store = store.replace(declaration(store, "    private init("),
                              '    private init() { dbURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_ROOT"]!).appendingPathComponent("index.sqlite3") }')
        # Observe transaction entry and control only the storage queue / SQLite
        # connection in the test copy. The production transaction body is intact.
        marker = "    private func saveWallpapersInternal(_ wallpapers: [VideoWallpaper]) throws {"
        self.assertEqual(store.count(marker), 1)
        store = store.replace("    private var db: OpaquePointer?", "    private var db: OpaquePointer?\n    private var auditSaves: [[String]] = []")
        store = store.replace(marker, marker + "\n        auditSaves.append(wallpapers.map(\\.id))")
        store = store.replace("    private var auditSaves:", "    private var auditReadRows = 0\n    private var auditSelectDenied = false\n    private var auditProgressTicks = 0\n    private var auditProgressLimit = 0\n    private var auditSaves:")
        store = store.replace("        while step == SQLITE_ROW {", "        while step == SQLITE_ROW {\n            auditReadRows += 1")
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
    func denySelectForAudit(_ denied: Bool) throws {
        try queue.sync {
            try openIfNeeded()
            auditSelectDenied = denied
            sqlite3_set_authorizer(db, { raw, action, _, _, _, _ in
                let store = Unmanaged<WallpaperIndexStore>.fromOpaque(raw!).takeUnretainedValue()
                return store.auditSelectDenied && action == SQLITE_SELECT ? SQLITE_DENY : SQLITE_OK
            }, Unmanaged.passUnretained(self).toOpaque())
        }
    }
    func interruptReadForAudit(after ticks: Int) {
        queue.sync {
            auditReadRows = 0; auditProgressTicks = 0; auditProgressLimit = ticks
            sqlite3_progress_handler(db, ticks == 0 ? 0 : 1, { raw in
                let store = Unmanaged<WallpaperIndexStore>.fromOpaque(raw!).takeUnretainedValue()
                store.auditProgressTicks += 1
                return store.auditProgressTicks > store.auditProgressLimit ? 1 : 0
            }, Unmanaged.passUnretained(self).toOpaque())
        }
    }
    func readRowsForAudit() -> Int { queue.sync { auditReadRows } }
}
'''
        reset = declaration(persistence, "    func resetToFreshInstallState(")
        self.assertLess(reset.index("invalidateWallpaperIndexPersistence()"), reset.index("wallpapers.removeAll()"))
        self.assertLess(reset.index("resetStore()"), reset.index("flushPersistentState()"))
        report = declaration(startup, "    func reportUnreadableInitialIndexChanges(")
        startup = startup.replace(report, "    func reportUnreadableInitialIndexChanges() { unreadableRecoveryCount += 1 }")
        source = startup.replace("import AppKit\n", "") + "\n" + import_types + "\n" + fixture.replace("// PRODUCTION_STATE", state).replace("// PRODUCTION_METHODS", methods)
        with tempfile.TemporaryDirectory(prefix="mwx-video-index-", dir="/private/tmp") as directory:
            work = Path(directory)
            swift = work / "Checks.swift"
            swift.write_text(source)
            actual_store = work / "WallpaperIndexStore.swift"
            actual_store.write_text(store)
            binary = work / "checks"
            if evidence := os.environ.get("MWX_VIDEO_INDEX_EVIDENCE"):
                retained = Path(evidence)
                retained.mkdir(parents=True, exist_ok=True)
                (retained / "Checks.swift").write_text(source)
                (retained / "WallpaperIndexStore.swift").write_text(store)
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(actual_store),
                                    str(ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"), str(swift),
                                    "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            for modes in [["startup"], ["bounded"], ["callbacks"], ["fallback-write", "fallback-read"],
                          ["empty-write", "empty-read"], ["bad-fallback"], ["startup-merge"],
                          ["startup-failure-write", "startup-failure-read"], ["startup-retry"],
                          ["startup-empty"], ["startup-global"], ["startup-import-context"], ["startup-size"], ["startup-corrupt"], ["read-interrupt"]]:
                home = work / modes[0]
                home.mkdir()
                env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home),
                           MWX_VIDEO_INDEX_TEST_ROOT=str(home), MWX_VIDEO_INDEX_TEST_DOMAIN="MWX.VideoIndex.Test." + uuid.uuid4().hex)
                for mode in modes:
                    env["MWX_VIDEO_INDEX_TEST_CLEANUP"] = "1" if mode == modes[-1] else "0"
                    run = subprocess.run([str(binary), mode], env=env,
                                         capture_output=True, text=True, timeout=30)
                    self.assertEqual(run.returncode, 0, mode + "\n" + run.stdout + run.stderr)
                    checks = json.loads(run.stdout)
                    self.assertTrue(checks)
                    print(json.dumps({"mode": mode, "checks": checks}, sort_keys=True))
                    for name, passed in checks.items():
                        with self.subTest(mode=mode, name=name):
                            self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
