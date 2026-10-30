"""Exercise real SQLite transactions and the product manager's bounded save owner."""
import hashlib
import json
import os
import shutil
import sqlite3
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

from script.tests.test_ui_library_algorithms import declaration


ROOT = Path(__file__).resolve().parents[2]
def prepare_asset_path_publication_sources(tree, work, cache_assets_override=None, fixture_tree=None, *, published_assets=True):
    """Same real storage assembly; optional actual Combine/cache publication mode.

    Overrides select only the source-under-test, never replace its algorithm.
    All generated files belong to the caller's explicit work directory.
    """
    tree, work = Path(tree), Path(work)
    fixture_tree = Path(fixture_tree) if fixture_tree is not None else tree
    core = tree / "MyWallpaperX/Modules/VideoLibrary/Core"
    persistence = (core / "WallpaperManager+Persistence.swift").read_text()
    manager = (core / "WallpaperManager.swift").read_text()
    store = (core / "WallpaperIndexStore.swift").read_text()
    startup = (tree / "MyWallpaperX/Models/WallpaperIndexStartupChanges.swift").read_text() + "\n" + (core / "WallpaperManager+InitialIndexLoad.swift").read_text()
    fixture_path = fixture_tree / "script/tests/fixtures/VideoIndexOrderedSaveHarness.swift"
    fixture = fixture_path.read_text()
    fields = "\n".join(next(line for line in manager.splitlines() if name in line) for name in [
        "var wallpaperIndexSaveRevision:", "var wallpaperIndexSaveEpoch:",
        "var didFinishInitialIndexLoad", "var initialIndexChanges =", "var initialIndexLoadGeneration:",
        "var initialIndexLoadInFlight", "var initialIndexBootstrapInProgress", "var initialIndexSeedWallpapers:",
        "var initialIndexInternalPublication", "var initialIndexGlobalMutationDepth",
        "var wallpaperIndexSaveInFlight:", "var pendingWallpaperIndexSave:",
    ])
    state = declaration(manager, "    struct WallpaperIndexSaveSnapshot") + "\n" + fields
    observer = declaration(manager, "    @Published var wallpapers:")
    if not published_assets:
        observer = observer.replace("@Published ", "")
    state += "\n" + observer
    methods = "\n".join(declaration(persistence, signature) for signature in [
        "    var defaults:", "    private var wallpaperIndexStore:",
        "    func saveWallpapers(", "    private func submitPendingWallpaperIndexSave(",
        "    private func applyWallpaperIndexSaveResult(", "    private func flushWallpaperIndex(",
        "    func persistWallpaperIndexNow(",
        "    private func invalidateWallpaperIndexPersistence(", "    func flushPersistentState(",
        "    func loadWallpapers(", "    func deduplicatedWallpapersByPath(",
        "    private func loadCodableValue<", "    func saveCodableValue<",
        "    private func decode<", "    private func encode<",
    ])
    imports = (core / "WallpaperManager+ImportProcessing.swift").read_text()
    bundled = (core / "WallpaperManager+BundledVideos.swift").read_text()
    fixture = fixture.replace("// PRODUCTION_BUNDLED_COPY", declaration(bundled, "    func migratedBundledVideoWallpaper("))
    presentation = (core / "WallpaperManager+ImportPresentation.swift").read_text()
    for signature in ["    private struct ImportCounters", "    private struct PreparedImportEntry",
                      "    private struct ImportPreparationResult", "    private func applyPreparedImportResult(",
                      "    private func makePreparedWallpaper(", "    private func makeImportedWallpaper(", "    private func appendWallpapersInBatches(",
                      "    private func makeImportSummary("]:
        methods += "\n" + declaration(imports, signature)
    methods += "\n" + declaration(presentation, "    func importFailureBreakdown(")
    methods += "\n" + declaration(manager, "    private func mergeWallpaper(")
    support = (core / "WallpaperLibrarySupport.swift").read_text()
    import_types = declaration(support, "struct ImportSummary") + "\n" + declaration(support, "enum ImportContext")
    playback = tree / "MyWallpaperX/Core/PlaybackControl"
    import_types += "\n" + (playback / "PlaybackResourceLifetime.swift").read_text()
    import_types += "\n" + (tree / "MyWallpaperX/Models/WallpaperReference.swift").read_text()
    import_types += "\n" + (tree / "MyWallpaperX/Models/WallpaperContent.swift").read_text()
    import_types += "\n" + (tree / "MyWallpaperX/Models/WallpaperSourceImportResult.swift").read_text()
    for name in ["WallpaperRuntimeSwitch.swift", "PlaybackSwitchTransaction.swift", "ImportedVideoPlaybackAdmission.swift", "ImportedVideoAutoplayGate.swift"]:
        import_types += "\n" + (playback / name).read_text()
    # Isolate the filesystem and CFPreferences leaves explicitly; HOME alone
    # does not define a macOS application's preferences domain.
    methods = methods.replace("var defaults: UserDefaults { .standard }",
                              'var defaults: UserDefaults { UserDefaults(suiteName: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_DOMAIN"]!)! }')
    store = store.replace(declaration(store, "    private init("),
                          '    private init() { migrationReadOnly = Self.startupMigrationReadOnly; dbURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWX_VIDEO_INDEX_TEST_ROOT"]!).appendingPathComponent("index.sqlite3") }')
    # Observe transaction entry and control only the storage queue / SQLite
    # connection in the test copy. The production transaction body is intact.
    marker = "    private func saveWallpapersInternal(_ wallpapers: [VideoWallpaper]) throws {"
    if store.count(marker) != 1:
        raise AssertionError("one actual SQLite transaction entry required")
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
    if reset.index("invalidateWallpaperIndexPersistence()") >= reset.index("wallpapers.removeAll()"):
        raise AssertionError("reset must revoke persistence before clearing rows")
    if reset.index("resetStore()") >= reset.index("flushPersistentState()"):
        raise AssertionError("reset must retire storage before flush")
    report = declaration(startup, "    func reportUnreadableInitialIndexChanges(")
    startup = startup.replace(report, "    func reportUnreadableInitialIndexChanges() { unreadableRecoveryCount += 1 }")
    asset_path = Path(cache_assets_override) if cache_assets_override is not None else core / "WallpaperManager+CacheAssets.swift"
    if published_assets:
        size_receipt = "                guard let self, self.wallpaperIndexSaveEpoch == epoch else { return }"
        if startup.count(size_receipt) != 1:
            raise AssertionError("one initial size callback receipt required")
        startup = startup.replace(size_receipt, "                defer { self?.auditInitialSizeCallbacks += 1 }\n" + size_receipt, 1)
        fixture = fixture.replace("@MainActor final class WallpaperManager {", "@MainActor final class WallpaperManager: ObservableObject {")
        current_field = next(line for line in manager.splitlines() if "    @Published var currentWallpaper:" in line)
        fixture = fixture.replace("    var currentWallpaper: VideoWallpaper?", current_field)
        fixture = fixture.replace(declaration(fixture, "    func normalizedPath("), declaration(manager, "    func normalizedPath("))
        sink_start = manager.index("        $wallpapers\n")
        sink_end = manager.index(".store(in: &cancellables)", sink_start) + len(".store(in: &cancellables)")
        actual_sink = manager[sink_start:sink_end]
        fixture = fixture.replace("// ACTUAL_ASSET_SINK", actual_sink)
        methods += "\n" + declaration(persistence, "    func scheduleWallpapersAutoPersist(")
        methods += "\n" + "\n".join(declaration(asset_path.read_text(), marker) for marker in (
            "    func updateWallpaperAssetPaths(", "    private func applyAssetPaths("))
        methods = methods.replace("    func scheduleWallpapersAutoPersist() {", "    func scheduleWallpapersAutoPersist() {\n        auditScheduleEntries += 1")
    source = startup.replace("import AppKit\n", "") + "\n" + import_types + "\n" + fixture.replace("// PRODUCTION_STATE", state).replace("// PRODUCTION_METHODS", methods)
    swift = work / "Checks.swift"
    actual_store = work / "WallpaperIndexStore.swift"
    swift.write_text(source)
    actual_store.write_text(store)
    model = tree / "MyWallpaperX/Models/VideoWallpaper.swift"
    inputs = [core / name for name in (
        "WallpaperManager+Persistence.swift", "WallpaperManager.swift", "WallpaperIndexStore.swift",
        "WallpaperManager+InitialIndexLoad.swift", "WallpaperManager+ImportProcessing.swift",
        "WallpaperManager+BundledVideos.swift", "WallpaperManager+ImportPresentation.swift", "WallpaperLibrarySupport.swift")]
    inputs += [Path(__file__).resolve(), fixture_path, model, tree / "MyWallpaperX/Models/WallpaperIndexStartupChanges.swift",
        tree / "MyWallpaperX/Models/WallpaperReference.swift", tree / "MyWallpaperX/Models/WallpaperContent.swift",
        tree / "MyWallpaperX/Models/WallpaperSourceImportResult.swift"]
    inputs += [playback / name for name in (
        "PlaybackResourceLifetime.swift", "WallpaperRuntimeSwitch.swift", "PlaybackSwitchTransaction.swift",
        "ImportedVideoPlaybackAdmission.swift", "ImportedVideoAutoplayGate.swift")]
    if published_assets:
        inputs.append(asset_path)
    return [actual_store, model, swift], {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}


class VideoIndexOrderedSaveTests(unittest.TestCase):
    def test_ordered_snapshots_fallback_flush_reset_and_process_restart(self):
        with tempfile.TemporaryDirectory(prefix="mwx-video-index-", dir="/private/tmp") as directory:
            work = Path(directory)
            sources, _ = prepare_asset_path_publication_sources(ROOT, work, published_assets=False)
            actual_store, _, swift = sources
            binary = work / "checks"
            if evidence := os.environ.get("MWX_VIDEO_INDEX_EVIDENCE"):
                retained = Path(evidence)
                retained.mkdir(parents=True, exist_ok=True)
                (retained / "Checks.swift").write_bytes(swift.read_bytes())
                (retained / "WallpaperIndexStore.swift").write_bytes(actual_store.read_bytes())
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(actual_store),
                                    str(ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"), str(swift),
                                    "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            for modes in [["startup"], ["bounded"], ["callbacks"], ["fallback-write", "fallback-read"],
                          ["empty-write", "empty-read"], ["bad-fallback"], ["startup-merge"],
                          ["startup-failure-write", "startup-failure-read"], ["startup-retry"],
                          ["startup-empty"], ["startup-global"], ["startup-import-context"], ["startup-size"], ["startup-corrupt"], ["read-interrupt"],
                          ["migration-readonly"], ["migration-legacy-index"], ["migration-missing-index"],
                          ["first-indexed"], ["first-indexed-sql-write", "first-indexed-sql-read"],
                          ["first-indexed-fallback-write", "first-indexed-fallback-read"], ["first-indexed-legacy"]]:
                home = work / modes[0]
                home.mkdir()
                if modes[0] in ["migration-readonly", "migration-legacy-index", "first-indexed-legacy"]:
                    with sqlite3.connect(home / "index.sqlite3") as db:
                        db.executescript("""CREATE TABLE wallpapers(sort_index INTEGER,id TEXT PRIMARY KEY,title TEXT,path TEXT,
                            thumbnail_path TEXT,static_frame_path TEXT,is_favorite INTEGER,last_used REAL,tags_json TEXT,
                            file_size INTEGER,duration REAL,resolution TEXT);CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT);
                            INSERT INTO meta VALUES('library_initialized','1');
                            INSERT INTO wallpapers VALUES(0,'A','A','/fixture/A.mp4',NULL,NULL,0,0,'[]',1,NULL,NULL);
                            INSERT INTO wallpapers VALUES(1,'B','B','/fixture/B.mp4',NULL,NULL,0,0,'[]',1,NULL,NULL);""")
                        if modes[0] == "migration-legacy-index":
                            db.executescript("ALTER TABLE wallpapers DROP COLUMN file_size;ALTER TABLE wallpapers DROP COLUMN duration;"
                                             "ALTER TABLE wallpapers DROP COLUMN resolution;DROP TABLE meta;")
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

    def test_actual_combine_asset_publication_and_sqlite_save(self):
        results = []
        expected = {
            "sameValue": (0, 0, 0, 0), "nilInputs": (0, 0, 0, 0),
            "changedBatch": (2, 2, 2, 1), "pendingThenNoop": (1, 1, 1, 1),
            "currentOnly": (0, 1, 0, 0), "absentRowCurrent": (0, 1, 0, 0),
            "removedBeforeCallback": (1, 0, 1, 1), "aliasFirstMatch": (1, 1, 1, 1),
            "emptyString": (1, 1, 1, 1), "initialLoad": (2, 2, 2, 2), "readOnly": (1, 1, 1, 0),
            "initialSizeBatch": (1, 0, 1, 1), "initialSizeCurrentRows": (1, 0, 1, 1),
            "initialSizeMetadataWins": (0, 0, 0, 0), "initialSizeRemoved": (0, 0, 0, 0),
            "initialSizeRevoked": (0, 0, 0, 0),
        }
        with tempfile.TemporaryDirectory(prefix="mwx-video-assets-", dir="/private/tmp") as directory:
            root = Path(directory)
            # Both configurations use identical absolute source and database paths.
            runtime = root / "runtime"
            for configuration, flags in [("debug", ["-D", "DEBUG"]),
                                          ("release", ["-O", "-whole-module-optimization"])]:
                work = root / configuration
                work.mkdir()
                sources, inputs = prepare_asset_path_publication_sources(ROOT, work)
                binary = work / "checks"
                build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-D", "VIDEO_INDEX_ASSET_PUBLICATION",
                    *flags, *map(str, sources), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                    capture_output=True, text=True, timeout=120)
                retained = None
                if evidence := os.environ.get("MWX_VIDEO_INDEX_EVIDENCE"):
                    retained = Path(evidence) / "asset-publication" / configuration
                    retained.mkdir(parents=True, exist_ok=True)
                    for source in sources:
                        (retained / source.name).write_bytes(source.read_bytes())
                    (retained / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
                    (retained / "compile.stdout").write_text(build.stdout)
                    (retained / "compile.stderr").write_text(build.stderr)
                self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
                runtime.mkdir()
                env = dict(os.environ, HOME=str(runtime), CFFIXED_USER_HOME=str(runtime),
                    MWX_VIDEO_INDEX_TEST_ROOT=str(runtime), MWX_VIDEO_INDEX_TEST_DOMAIN="MWX.VideoAssets.Test." + uuid.uuid4().hex,
                    MWX_VIDEO_INDEX_TEST_CLEANUP="1")
                run = subprocess.run([str(binary), "asset-publication"], env=env,
                    capture_output=True, text=True, timeout=30)
                if retained:
                    (retained / "runtime.stdout").write_text(run.stdout)
                    (retained / "runtime.stderr").write_text(run.stderr)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                result = json.loads(run.stdout)
                self.assertEqual(set(result), {"functional", "work"})
                self.assertEqual(set(result["functional"]), set(expected))
                self.assertEqual(set(result["work"]), set(expected))
                for phase, counters in expected.items():
                    for name, passed in result["functional"][phase]["checks"].items():
                        with self.subTest(configuration=configuration, phase=phase, check=name):
                            self.assertIs(passed, True, run.stdout)
                    actual = result["work"][phase]
                    self.assertEqual(tuple(actual[key] for key in (
                        "publications", "currentPublications", "scheduleEntries", "saveEntries")), counters, phase + run.stdout)
                self.assertEqual(result["work"]["pendingThenNoop"]["retainedPendingTimer"], 1)
                self.assertEqual(inputs, {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in inputs})
                results.append(result)
                print(json.dumps({"configuration": configuration, **result}, sort_keys=True))
                exit_run = subprocess.run([str(binary), "exit-index"], env=env,
                                          capture_output=True, text=True, timeout=30)
                self.assertEqual(exit_run.returncode, 0, exit_run.stdout + exit_run.stderr)
                exit_result = json.loads(exit_run.stdout)
                print(json.dumps({"configuration": configuration, "exitIndex": exit_result}, sort_keys=True))
                for name, passed in exit_result["checks"].items():
                    with self.subTest(configuration=configuration, exitCheck=name):
                        self.assertIs(passed, True)
                self.assertEqual(exit_result["writes"], {
                    "clean": 0, "debounced": 1, "afterOrdinarySave": 0, "retryFailure": 1, "reset": 1})
                # Runtime is wholly test-owned; neither user media nor standard prefs are used.
                shutil.rmtree(runtime)
        self.assertEqual(results[0], results[1])


if __name__ == "__main__":
    unittest.main()
