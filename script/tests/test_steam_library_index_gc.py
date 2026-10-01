"""Download metadata index GC must never delete a concurrently (re)published entry.

Behavioral coverage driven from real product sources: the GC scan decision, the
candidate identity, and the main-actor delete phase are spliced verbatim from
SteamWorkshopService+LibraryReclamation.swift and executed against the real
transaction layer (scan/publish/remove primitives) on an isolated library
fixture — no Steam, no user library, /private/tmp only.
"""
import json
import os
import pathlib
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_transaction import SOURCES, CORE, ROOT


def method(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 0
    for index in range(opening, len(source)):
        depth += (source[index] == '{') - (source[index] == '}')
        if depth == 0:
            return source[start:index + 1]
    raise AssertionError(signature)


def orphan_commit(item_id):
    return {
        'version': 3, 'workshopId': item_id, 'jobId': 'job-1', 'attempt': 1,
        'directoryName': item_id, 'manifestId': 'm1', 'contentDigest': 'd1',
        'contentType': 'web', 'entryPath': 'index.html', 'committedAt': 0,
        'removed': False, 'generation': '11111111-1111-4111-8111-111111111111',
    }


def write_entry(root, item_id, aged=True):
    """Install a metadata index entry whose referenced content is absent."""
    index = root / 'library' / '.mywallpaperx-steam-metadata'
    index.mkdir(parents=True, exist_ok=True)
    entry = index / f'{item_id}.json'
    snapshot = {
        'fetchedAt': 0, 'item': {'id': item_id}, 'commit': orphan_commit(item_id),
        'legacyFolderURL': None, 'exportedVideoURL': None,
    }
    entry.write_text(json.dumps(snapshot))
    if aged:
        old = 1_600_000_000
        os.utime(entry, (old, old))
    return entry


HARNESS_HEAD = r'''
import Foundation
struct SteamWorkshopBrowserItem: Codable { let id: String }
struct SteamWorkshopDownloadMetadataSnapshot: Codable {
    let fetchedAt: Date
    var item: SteamWorkshopBrowserItem
    var legacyFolderURL: URL? = nil
    var exportedVideoURL: URL? = nil
    var commit: SteamWorkshopLibraryCommit? = nil
}
@MainActor final class SteamWorkshopService {
    let downloadJobStore: SteamDownloadJobStore
    var removingDownloadIDs: Set<String> = []
    // 调度路径（scheduleLibraryVersionReclamation 拼接体）所需的最小成员。
    let libraryRoot: URL
    var libraryVersionReclamationTask: Task<Void, Never>? = nil
    let steamLibraryVersionLeaseRegistry = SteamWorkshopLibraryVersionLeaseRegistry()
    var steamDownloadLibraryRootURL: URL { libraryRoot }
    init(_ root: URL) {
        downloadJobStore = SteamDownloadJobStore(persistenceURL: root.appendingPathComponent("jobs.json"))
        libraryRoot = root.appendingPathComponent("library", isDirectory: true)
    }
    func loadManagedDownloadSnapshots(
        requireComplete: Bool
    ) throws -> [String: SteamWorkshopDownloadMetadataSnapshot] { [:] }
    func referencedLibraryStorageIdentities() -> Set<String> { [] }
'''


HARNESS_MAIN = r'''
}
@main struct Harness {
    @MainActor static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let mode = CommandLine.arguments[2]
        let library = base.appendingPathComponent("library", isDirectory: true)
        let indexDir = library.appendingPathComponent(".mywallpaperx-steam-metadata", isDirectory: true)
        func entry(_ id: String) -> URL { indexDir.appendingPathComponent(id + ".json") }
        let exists = { FileManager.default.fileExists(atPath: entry("123456").path) }
        let service = SteamWorkshopService(base)

        if mode == "gc-aged-orphan" {
            let candidates = SteamWorkshopService.scanOrphanedMetadataEntries(
                libraryRoot: library, minimumAge: 3_600)
            precondition(candidates.count == 1 && candidates[0].itemID == "123456",
                "only the aged entry becomes a candidate (got \(candidates.map(\.itemID)))")
            let removed = service.removeOrphanedMetadataEntries(candidates, libraryRoot: library)
            precondition(removed == 1, "aged orphan must be reclaimed (removed=\(removed))")
            precondition(!exists(), "aged orphan entry must be gone")
            precondition(FileManager.default.fileExists(atPath: entry("654321").path),
                "young entry must be kept")
            print("AGED ORPHAN REMOVED")
            return
        }
        if mode == "gc-replaced-during-scan" {
            // Controlled interleaving: GC scan has judged both entries orphans,
            // then a publish lands before the GC delete phase — item 123456 gets
            // its content directory installed plus the real publish() rename
            // replacement; item 234567 gets only the content install (the
            // window inside finishPublication between directory exchange and
            // metadata rename).
            let candidates = SteamWorkshopService.scanOrphanedMetadataEntries(
                libraryRoot: library, minimumAge: 3_600)
            precondition(candidates.count == 2, "expected two aged candidates")
            let content = library.appendingPathComponent("Web", isDirectory: true)
            for id in ["123456", "234567"] {
                let directory = content.appendingPathComponent(id, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data("<h1>new</h1>".utf8).write(to: directory.appendingPathComponent("index.html"))
            }
            let fresh = SteamWorkshopDownloadMetadataSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                item: SteamWorkshopBrowserItem(id: "123456"),
                legacyFolderURL: nil, exportedVideoURL: nil, commit: nil)
            try SteamWorkshopLibraryTransaction.publish(
                metadata: JSONEncoder().encode(fresh), itemID: "123456", libraryRoot: library)
            let removed = service.removeOrphanedMetadataEntries(candidates, libraryRoot: library)
            precondition(removed == 0, "entries replaced/re-fed after the scan must be kept (removed=\(removed))")
            let kept = try JSONDecoder().decode(
                SteamWorkshopDownloadMetadataSnapshot.self, from: try Data(contentsOf: entry("123456")))
            precondition(kept.fetchedAt.timeIntervalSince1970 == 1_700_000_000,
                "the freshly published index must be the one that survived")
            precondition(FileManager.default.fileExists(
                atPath: content.appendingPathComponent("123456/index.html").path),
                "freshly published content must survive")
            precondition(FileManager.default.fileExists(atPath: entry("234567").path),
                "an entry whose content reappeared must be kept")
            print("REPLACED DURING SCAN KEPT")
            return
        }
        if mode == "gc-active-after-scan" {
            let candidates = SteamWorkshopService.scanOrphanedMetadataEntries(
                libraryRoot: library, minimumAge: 3_600)
            precondition(candidates.count == 1)
            let job = service.downloadJobStore.enqueue(
                workshopItemId: "123456", title: "t", accountSteamId: "76561198000000000").job
            precondition(service.downloadJobStore.apply(.started, toID: job.id) != nil)
            var removed = service.removeOrphanedMetadataEntries(candidates, libraryRoot: library)
            precondition(removed == 0, "an item whose job started after the scan must be kept (removed=\(removed))")
            precondition(exists())
            service.removingDownloadIDs = ["123456"]
            removed = service.removeOrphanedMetadataEntries(candidates, libraryRoot: library)
            precondition(removed == 0 && exists(), "an item pending removal must be kept")
            // The guard is activity, not a blanket no-op: with no live job and no
            // pending removal the same candidate is reclaimed.
            try FileManager.default.createDirectory(
                at: base.appendingPathComponent("clean", isDirectory: true), withIntermediateDirectories: true)
            let idle = SteamWorkshopService(base.appendingPathComponent("clean", isDirectory: true))
            removed = idle.removeOrphanedMetadataEntries(candidates, libraryRoot: library)
            precondition(removed == 1 && !exists(), "an idle orphan must still be reclaimed")
            print("ACTIVE AFTER SCAN KEPT")
            return
        }
        if mode == "gc-scheduled" {
            // End-to-end scheduling: detached scan → main-actor delete phase,
            // exactly as the production reclamation task drives it.
            service.scheduleLibraryVersionReclamation()
            while service.libraryVersionReclamationTask != nil { await Task.yield() }
            precondition(!exists(), "scheduled GC must reclaim the aged orphan")
            precondition(FileManager.default.fileExists(atPath: entry("654321").path),
                "scheduled GC must keep the young entry")
            print("SCHEDULED GC RECLAIMED")
            return
        }
        fatalError("unknown mode \(mode)")
    }
}
'''


class SteamLibraryIndexGCTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        reclamation = (CORE / 'SteamWorkshopService+LibraryReclamation.swift').read_text()
        cls.candidate_type = method(
            reclamation, '    struct OrphanedMetadataEntryCandidate: Sendable {')
        cls.scan = method(
            reclamation, '    nonisolated static func scanOrphanedMetadataEntries(')
        cls.delete = method(
            reclamation, '    func removeOrphanedMetadataEntries(')
        cls.schedule = method(
            reclamation, '    func scheduleLibraryVersionReclamation(')
        cls.retire = method(
            reclamation, '    nonisolated static func retireLegacyVersionsRoot(')
        cls.build = tempfile.TemporaryDirectory(prefix='mwx-steam-index-gc-', dir='/private/tmp')
        folder = pathlib.Path(cls.build.name)
        source = folder / 'Harness.swift'
        source.write_text(HARNESS_HEAD + cls.candidate_type + '\n' + cls.scan + '\n'
                          + cls.delete + '\n' + cls.retire + '\n'
                          + cls.schedule + HARNESS_MAIN)
        cls.binary = folder / 'index-gc'
        result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, SOURCES), str(source),
                                 '-o', str(cls.binary)], capture_output=True, text=True, timeout=180)
        cls.compile_output = result.stdout + result.stderr
        if result.returncode != 0:
            raise AssertionError(cls.compile_output)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def run_mode(self, mode, fixtures, verify):
        with tempfile.TemporaryDirectory(prefix='mwx-index-gc-run-', dir='/private/tmp') as temporary:
            root = pathlib.Path(temporary)
            for item_id, aged in fixtures:
                write_entry(root, item_id, aged=aged)
            result = subprocess.run([str(self.binary), str(root), mode],
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertIn({
                'gc-aged-orphan': 'AGED ORPHAN REMOVED',
                'gc-replaced-during-scan': 'REPLACED DURING SCAN KEPT',
                'gc-active-after-scan': 'ACTIVE AFTER SCAN KEPT',
                'gc-scheduled': 'SCHEDULED GC RECLAIMED',
            }[mode], result.stdout)
            verify(root)

    def test_index_gc_removes_aged_orphan_without_content(self):
        def verify(root):
            self.assertFalse((root / 'library/.mywallpaperx-steam-metadata/123456.json').exists())
            self.assertTrue((root / 'library/.mywallpaperx-steam-metadata/654321.json').exists())
        self.run_mode('gc-aged-orphan', [('123456', True), ('654321', False)], verify)

    def test_scheduled_reclamation_runs_detached_scan_then_main_actor_delete(self):
        def verify(root):
            self.assertFalse((root / 'library/.mywallpaperx-steam-metadata/123456.json').exists())
            self.assertTrue((root / 'library/.mywallpaperx-steam-metadata/654321.json').exists())
        self.run_mode('gc-scheduled', [('123456', True), ('654321', False)], verify)

    def test_index_gc_keeps_entry_replaced_during_scan(self):
        def verify(root):
            kept = root / 'library/.mywallpaperx-steam-metadata/123456.json'
            self.assertTrue(kept.exists())
            # JSONEncoder's deferred date strategy counts from the 2001
            # reference date; the Swift side pinned the same instant.
            self.assertEqual(json.loads(kept.read_text())['fetchedAt'],
                             1_700_000_000 - 978_307_200)
            self.assertTrue((root / 'library/Web/123456/index.html').exists())
            self.assertTrue((root / 'library/Web/234567/index.html').exists())
            self.assertTrue((root / 'library/.mywallpaperx-steam-metadata/234567.json').exists())
        self.run_mode('gc-replaced-during-scan', [('123456', True), ('234567', True)], verify)

    def test_index_gc_skips_item_with_job_started_after_scan(self):
        def verify(root):
            # The harness's last step proves the guard is activity, not a
            # blanket no-op: the same candidate is reclaimed once no job or
            # removal is live.
            self.assertFalse((root / 'library/.mywallpaperx-steam-metadata/123456.json').exists())
        self.run_mode('gc-active-after-scan', [('123456', True)], verify)


if __name__ == '__main__':
    unittest.main()
