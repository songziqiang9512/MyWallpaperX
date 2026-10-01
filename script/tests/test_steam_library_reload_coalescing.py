"""Real reloadInstalledItems scan protocol: one scan in flight, coalesced catch-up, final projection kept.

Drives the production reload entry against a real metadata index (real
loadManagedDownloadSnapshots pipeline) with an instrumented scan body that can
be held in flight and counted. Asserts the observable contract: overlapping
reloads never run concurrent whole-library scans, every coalesced request is
answered by exactly one catch-up scan launched from the newest state, stale
results never overwrite it, and interleaved deletions are not lost.
"""
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_transaction import CORE, ROOT, SOURCES

COALESCING_MEMBERS = (
    '    private func startInstalledLibraryScan(',
    '    private func finishInstalledLibraryScan(',
    '    private var installedLibraryScanFlight: SteamWorkshopInstalledLibraryScanFlight {',
)


def extract(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError('unterminated Swift member: ' + signature)


class SteamLibraryReloadCoalescingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix='mwx-reload-coalescing-build-')
        folder = pathlib.Path(cls.build.name)
        source = (CORE / 'SteamWorkshopService+DownloadLibrarySync.swift').read_text()
        members = []
        for signature in (
            '    func reloadInstalledItems() {',
            '    func managedDownloadSnapshots() ->',
            '    func loadManagedDownloadSnapshots(',
            '    private func applyInstalledLibraryRecords(',
        ):
            members.append(extract(source, signature))
        # Post-fix the reload protocol routes through dedicated scan members and a
        # per-instance flight holder; extract them so the harness runs the real
        # implementations rather than stand-ins.
        for signature in COALESCING_MEMBERS:
            if signature in source:
                members.append(extract(source, signature))
            else:
                members.append('// member absent in this revision: ' + signature.strip())
        flight_type = extract(source, 'private final class SteamWorkshopInstalledLibraryScanFlight {') \
            if 'private final class SteamWorkshopInstalledLibraryScanFlight {' in source else ''
        harness = r'''
import Foundation

''' + (flight_type + '\n' if flight_type else '') + r'''
struct SteamWorkshopBrowserItem: Codable { let id: String; let title: String }
struct SteamWorkshopDownloadRecord: Identifiable, Equatable {
    enum Status: Equatable { case queued, downloading, ready, failed(String) }
    let id: String; let title: String; let sizeText: String; let status: Status
}
struct SteamWorkshopDownloadMetadataSnapshot: Codable {
    let fetchedAt: Date; let item: SteamWorkshopBrowserItem; let sourceVideoRelativePath: String?
    let previewRelativePath: String?; let exportedVideoURL: URL?; let legacyFolderURL: URL?
    var legacyRemoved: Bool? = nil
    var commit: SteamWorkshopLibraryCommit? = nil
}
struct SteamWorkshopInstalledLibraryScanContext: Sendable { let libraryRoot: URL }

/// Instrumented scan body: counts entries, tracks peak concurrency, holds while
/// the gate is closed and reports the managed snapshot it was launched with.
enum ScanGate {
    static let lock = NSLock()
    static var hold = true
    static var started = 0
    static var inFlight = 0
    static var peakInFlight = 0
    static var seenManagedCounts: [Int] = []
    static func gate<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}

@MainActor final class SteamWorkshopService {
    var statusMessage = ""
    let steamDownloadLibraryRootURL: URL
    var installedLibraryScanGeneration = 0
    var downloads: [SteamWorkshopDownloadRecord] = []
    var selectedDownloadID: String?
    var selectedDownloadIDs: Set<String> = []
    init(libraryRoot: URL) { steamDownloadLibraryRootURL = libraryRoot }
    func referencedLibraryStorageIdentities() -> Set<String> { [] }
    func scheduleLegacyLibraryPublicationMigration(from snapshots: [String: SteamWorkshopDownloadMetadataSnapshot]) {}
    func reconcileDownloadCommits(_ snapshots: [String: SteamWorkshopDownloadMetadataSnapshot]) {}
    func scheduleTerminalDownloadCleanup() {}
    func installedLibraryScanContext() -> SteamWorkshopInstalledLibraryScanContext {
        SteamWorkshopInstalledLibraryScanContext(libraryRoot: steamDownloadLibraryRootURL)
    }
    func preloadWebRuntimeCaches(for records: [SteamWorkshopDownloadRecord]) {}
    func publishDownloadSelectionState(primaryID: String?, selectedIDs: Set<String>, deferPublishing: Bool) {}
    func scheduleLibraryVersionReclamation() {}
    nonisolated static func scanInstalledLibraryRecords(
        managed: [String: SteamWorkshopDownloadMetadataSnapshot],
        context: SteamWorkshopInstalledLibraryScanContext
    ) -> [SteamWorkshopDownloadRecord] {
        ScanGate.gate {
            ScanGate.started &+= 1
            ScanGate.inFlight &+= 1
            ScanGate.peakInFlight = max(ScanGate.peakInFlight, ScanGate.inFlight)
            ScanGate.seenManagedCounts.append(managed.count)
        }
        while ScanGate.gate({ ScanGate.hold }) {
            Thread.sleep(forTimeInterval: 0.002)
        }
        ScanGate.gate { ScanGate.inFlight -= 1 }
        return managed.values
            .sorted { $0.item.id < $1.item.id }
            .map { SteamWorkshopDownloadRecord(id: $0.item.id, title: $0.item.title, sizeText: "1 KB", status: .ready) }
    }
''' + '\n'.join(members) + r'''
}
@main struct Harness {
    @MainActor static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let library = base.appendingPathComponent("library", isDirectory: true)
        let service = SteamWorkshopService(libraryRoot: library)
        func waitUntil(_ label: String, deadlineSeconds: Double = 5, _ condition: @MainActor () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(deadlineSeconds)
            while Date() < deadline {
                if condition() { return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            fatalError("timed out waiting for: " + label
                + " [started=\(ScanGate.gate { ScanGate.started }) inFlight=\(ScanGate.gate { ScanGate.inFlight })"
                + " hold=\(ScanGate.gate { ScanGate.hold }) seen=\(ScanGate.gate { ScanGate.seenManagedCounts })"
                + " generation=\(service.installedLibraryScanGeneration) downloads=\(service.downloads.count)]")
        }
        func publish(_ id: String, _ title: String) throws {
            let generation = UUID().uuidString
            var commit = SteamWorkshopLibraryCommit(
                version: 3, workshopId: id, jobId: "job-" + id, attempt: 1,
                directoryName: id, manifestId: "m-" + id,
                contentDigest: String(repeating: "a", count: 64),
                contentType: "web", entryPath: "index.html",
                committedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            commit.generation = generation
            // Canonical v3 layout (see canonicalCommit): the public content
            // directory is the workshop ID itself; `generation` only names the
            // retired public generation it replaced.
            let content = library.appendingPathComponent("Web", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: content.appendingPathComponent("project.json"))
            try Data("<html>".utf8).write(to: content.appendingPathComponent("index.html"))
            var snapshot = SteamWorkshopDownloadMetadataSnapshot(
                fetchedAt: Date(), item: SteamWorkshopBrowserItem(id: id, title: title),
                sourceVideoRelativePath: nil, previewRelativePath: nil,
                exportedVideoURL: nil, legacyFolderURL: content
            )
            snapshot.commit = commit
            try SteamWorkshopLibraryTransaction.publish(
                metadata: JSONEncoder().encode(snapshot), itemID: id, libraryRoot: library
            )
        }
        func removeItem(_ id: String) throws {
            let index = library.appendingPathComponent(
                SteamWorkshopLibraryTransaction.metadataName, isDirectory: true
            )
            try? FileManager.default.removeItem(at: index.appendingPathComponent("\(id).json"))
            let webRoot = library.appendingPathComponent("Web", isDirectory: true)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: webRoot.path)) ?? []
            where name == id || name.hasPrefix(id + "-") {
                try? FileManager.default.removeItem(at: webRoot.appendingPathComponent(name))
            }
        }

        // --- Scenario 1: continuous refresh while a scan is in flight. ---
        try publish("100001", "alpha-v1")
        service.reloadInstalledItems()
        try await waitUntil("first scan started") { ScanGate.gate { ScanGate.started == 1 } }
        for index in 2...6 {
            try publish(String(100_000 + index), "item-\(index)")
        }
        for _ in 0..<5 { service.reloadInstalledItems() }
        precondition(service.installedLibraryScanGeneration == 6,
            "every reload must still advance the result generation")
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(ScanGate.gate { ScanGate.started == 1 && ScanGate.peakInFlight == 1 },
            "reloads arriving while a scan is in flight must not start additional whole-library scans"
            + " (started=\(ScanGate.gate { ScanGate.started }), peak=\(ScanGate.gate { ScanGate.peakInFlight }))")
        ScanGate.gate { ScanGate.hold = false }
        try await waitUntil("coalesced catch-up applied") {
            service.downloads.count == 6 && ScanGate.gate { ScanGate.started == 2 }
        }
        precondition(ScanGate.gate { ScanGate.seenManagedCounts == [1, 6] },
            "the coalesced catch-up must scan the newest managed state exactly once: "
            + "\(ScanGate.gate { ScanGate.seenManagedCounts })")
        precondition(service.downloads.map(\.title).sorted() ==
            ["alpha-v1", "item-2", "item-3", "item-4", "item-5", "item-6"].sorted(),
            "the stale first scan must never overwrite the newest projection: "
            + "\(service.downloads.map(\.title))")
        precondition(ScanGate.gate { ScanGate.peakInFlight == 1 },
            "scans must never execute concurrently (peak=\(ScanGate.gate { ScanGate.peakInFlight }))")

        // --- Scenario 2: deletion interleaved with an in-flight scan. ---
        ScanGate.gate { ScanGate.hold = true }
        for index in 2...6 { try removeItem(String(100_000 + index)) }
        service.reloadInstalledItems()
        try await waitUntil("post-deletion scan started") { ScanGate.gate { ScanGate.started == 3 } }
        service.reloadInstalledItems()
        precondition(service.installedLibraryScanGeneration == 8)
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(ScanGate.gate { ScanGate.started == 3 },
            "a reload during an in-flight scan must coalesce, not start a concurrent scan")
        ScanGate.gate { ScanGate.hold = false }
        try await waitUntil("deletion projected") {
            service.downloads.count == 1 && ScanGate.gate { ScanGate.started == 4 }
        }
        precondition(service.downloads.map(\.title) == ["alpha-v1"],
            "the interleaved deletion must not be lost: \(service.downloads.map(\.title))")
        precondition(ScanGate.gate { ScanGate.seenManagedCounts == [1, 6, 1, 1] },
            "scan sequence must be initial, catch-up(newest), post-deletion, catch-up(newest): "
            + "\(ScanGate.gate { ScanGate.seenManagedCounts })")
        precondition(ScanGate.gate { ScanGate.peakInFlight == 1 })
        print("RELOAD COALESCING PASS: scans=\(ScanGate.gate { ScanGate.started })"
            + " peakConcurrent=\(ScanGate.gate { ScanGate.peakInFlight })")
    }
}
'''
        harness_path = folder / 'Harness.swift'
        harness_path.write_text(harness)
        cls.binary = folder / 'coalescing'
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, SOURCES), str(harness_path),
                        '-o', str(cls.binary)], check=True, timeout=120)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def test_overlapping_reloads_coalesce_into_one_catch_up_scan(self):
        with tempfile.TemporaryDirectory(prefix='mwx-reload-coalescing-', dir='/private/tmp') as directory:
            result = subprocess.run([str(self.binary), directory], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('RELOAD COALESCING PASS: scans=', result.stdout)


if __name__ == '__main__':
    unittest.main()
