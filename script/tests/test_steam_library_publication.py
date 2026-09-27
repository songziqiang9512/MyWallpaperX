"""Exercise clean-ID publication, recovery and local deletion against isolated disk trees."""
import pathlib
import subprocess
import tempfile
import unittest
from script.tests.test_steam_library_transaction import SOURCES

HARNESS = r'''
import Foundation
import Darwin
@main struct Harness {
    @MainActor static func main() async throws {
        let library = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let mode = CommandLine.arguments[2]
        typealias T = SteamWorkshopLibraryTransaction
        func prepare(_ payload: String) throws -> SteamWorkshopLibraryCommit {
            let commit = SteamWorkshopLibraryCommit(version: 2, workshopId: "123456", jobId: payload,
                attempt: 1, directoryName: "123456-" + UUID().uuidString.lowercased(), manifestId: "123",
                contentDigest: String(repeating: "a", count: 64), contentType: "web", entryPath: "index.html",
                committedAt: Date())
            let url = try T.contentURL(for: commit, libraryRoot: library)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(#"{"type":"web","file":"index.html"}"#.utf8).write(to: url.appendingPathComponent("project.json"))
            try Data(payload.utf8).write(to: url.appendingPathComponent("index.html"))
            try JSONEncoder().encode(commit).write(to: url.appendingPathComponent(T.ownershipMarkerName))
            return commit
        }
        func data(_ commit: SteamWorkshopLibraryCommit) throws -> Data {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(commit)
        }
        func current() throws -> Data? { try T.publishedMetadata(libraryRoot: library, requireComplete: true)["123456"] }
        let first = try prepare("first")
        let canonical = try T.canonicalCommit(first)
        let target = try T.contentURL(for: canonical, libraryRoot: library)
        if mode == "foreign" {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try Data("user".utf8).write(to: target.appendingPathComponent("sentinel"))
            do { try T.publishCanonical(first, metadata: data(canonical), libraryRoot: library); fatalError("overwrote user content") }
            catch { precondition(FileManager.default.fileExists(atPath: target.appendingPathComponent("sentinel").path)) }
            return
        }
        try T.publishCanonical(first, metadata: data(canonical), libraryRoot: library)
        precondition(target.lastPathComponent == "123456" && T.isAvailable(canonical, libraryRoot: library))
        precondition(!T.isAvailable(first, libraryRoot: library))
        let firstIndex = try current()
        let expectedFirst = try data(canonical)
        precondition(firstIndex == expectedFirst)
        let second = try prepare("second")
        let next = try T.canonicalCommit(second)
        let nextData = try data(next)
        var expectedData = nextData
        let preparedURL = try T.contentURL(for: second, libraryRoot: library)
        if mode == "rollback" {
            let index = library.appendingPathComponent(T.metadataName)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: index.path)
            do { try T.publishCanonical(second, metadata: nextData, libraryRoot: library); fatalError("read-only index published") }
            catch {}
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: index.path)
            let retained = try current()
            precondition(retained == firstIndex && T.isAvailable(canonical, libraryRoot: library))
            precondition(T.isAvailable(second, libraryRoot: library))
        } else if mode.hasPrefix("recover") {
            struct Intent: Encodable {
                let prepared: SteamWorkshopLibraryCommit
                let current: SteamWorkshopLibraryCommit
                let metadata: Data
                let previousMetadata: Data?
                let previous: SteamWorkshopLibraryCommit?
            }
            let journal = library.appendingPathComponent(".mywallpaperx-steam-publications")
            try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
            let intent = Intent(prepared: second, current: next, metadata: nextData,
                previousMetadata: firstIndex, previous: canonical)
            try JSONEncoder().encode(intent).write(to: journal.appendingPathComponent("123456.json"))
            if ["recover-after", "recover-indexed", "recover-enriched", "recover-retired-marker", "recover-retired-directory", "recover-deleted"].contains(mode) {
                try nextData.write(to: preparedURL.appendingPathComponent(T.ownershipMarkerName))
                precondition(renamex_np(preparedURL.path, target.path, UInt32(RENAME_SWAP)) == 0)
            }
            if mode == "recover-deleted" {
                struct Metadata: Encodable { let commit: SteamWorkshopLibraryCommit }
                var removed = next; removed.removed = true
                try T.publish(metadata: JSONEncoder().encode(Metadata(commit: removed)), itemID: "123456", libraryRoot: library)
                try T.removeContent(at: target, itemID: "123456", libraryRoot: library, expectedCommit: next)
                try T.recoverPublications(libraryRoot: library)
                precondition(!FileManager.default.fileExists(atPath: target.path), "recovery resurrected deleted content")
                let third = try prepare("third")
                try T.publishCanonical(third, metadata: data(T.canonicalCommit(third)), libraryRoot: library)
                print("PASS: " + mode)
                return
            }
            if mode.hasPrefix("recover-retired") {
                try T.publish(metadata: nextData, itemID: "123456", libraryRoot: library)
                try data(first).write(to: preparedURL.appendingPathComponent(T.ownershipMarkerName))
                if mode == "recover-retired-directory" {
                    let retiredURL = target.deletingLastPathComponent().appendingPathComponent(T.retiredPrefix + first.directoryName)
                    precondition(renamex_np(preparedURL.path, retiredURL.path, UInt32(RENAME_EXCL)) == 0)
                }
            }
            if mode == "recover-indexed" { try T.publish(metadata: nextData, itemID: "123456", libraryRoot: library) }
            if mode == "recover-enriched" {
                struct Metadata: Encodable { let commit: SteamWorkshopLibraryCommit; let title: String }
                expectedData = try JSONEncoder().encode(Metadata(commit: next, title: "refreshed author metadata"))
                try T.publish(metadata: expectedData, itemID: "123456", libraryRoot: library)
            }
            if mode == "recover-protected" {
                try T.recoverPublications(libraryRoot: library, retaining: [T.storageIdentity(for: canonical)!])
                let stillIndexed = try current()
                precondition(stillIndexed == firstIndex && T.isAvailable(canonical, libraryRoot: library))
            }
            try T.recoverPublications(libraryRoot: library)
            try T.recoverPublications(libraryRoot: library)
        } else {
            try T.publishCanonical(second, metadata: nextData, libraryRoot: library)
        }
        if mode != "rollback" {
            let indexed = try current()
            precondition(indexed == expectedData && T.isAvailable(next, libraryRoot: library))
            precondition(!T.isAvailable(canonical, libraryRoot: library))
            precondition(!FileManager.default.fileExists(atPath: preparedURL.path))
            precondition(T.storageIdentity(for: next) != T.storageIdentity(for: canonical))
            let payload = try String(contentsOf: target.appendingPathComponent("index.html"), encoding: .utf8)
            precondition(payload == "second")
            let retiredURL = target.deletingLastPathComponent().appendingPathComponent(T.retiredPrefix + first.directoryName)
            precondition(FileManager.default.fileExists(atPath: retiredURL.appendingPathComponent("index.html").path),
                "publication must leave old payload to GC")
            let visible = try FileManager.default.contentsOfDirectory(at: target.deletingLastPathComponent(),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            precondition(visible.map(\.lastPathComponent) == ["123456"], "only the clean ID should be visible")
            if mode == "cleanup-delete-redownload" {
                // Recursive deletion fails, but publication/recovery and the next
                // user mutation must not depend on that cleanup succeeding.
                try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: retiredURL.path)
                do {
                    _ = try await T.reclaimVersions(libraryRoot: library,
                        retaining: [T.storageIdentity(for: next)!], minimumAge: 0)
                    fatalError("read-only old payload should fail reclamation")
                } catch {}
                var removed = next; removed.removed = true
                try T.publish(metadata: data(removed), itemID: "123456", libraryRoot: library)
                try T.removeContent(at: target, itemID: "123456", libraryRoot: library, expectedCommit: next)
                try T.recoverPublications(libraryRoot: library)
                let third = try prepare("third")
                let thirdCurrent = try T.canonicalCommit(third)
                try T.publishCanonical(third, metadata: data(thirdCurrent), libraryRoot: library)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: retiredURL.path)
                let gc = try await T.reclaimVersions(libraryRoot: library,
                    retaining: [T.storageIdentity(for: thirdCurrent)!], minimumAge: 0)
                precondition(gc.removedStorageIdentities.contains(T.storageIdentity(for: first)!))
                precondition(T.isAvailable(thirdCurrent, libraryRoot: library))
            }
            if mode == "delete" {
                do { try T.removeContent(at: target, itemID: "123456", libraryRoot: library, expectedCommit: canonical)
                    fatalError("stale identity deleted current content") } catch {}
                precondition(T.isAvailable(next, libraryRoot: library))
                try T.removeContent(at: target, itemID: "123456", libraryRoot: library, expectedCommit: next)
                precondition(!FileManager.default.fileExists(atPath: target.path))
            }
        }
        print("PASS: " + mode)
    }
}
'''

class SteamLibraryPublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix='mwx-publication-build-')
        root = pathlib.Path(cls.build.name)
        source = root / 'Harness.swift'
        source.write_text(HARNESS)
        cls.binary = root / 'test'
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', *map(str, SOURCES), str(source), '-o', str(cls.binary)], check=True, timeout=120)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def run_case(self, mode):
        with tempfile.TemporaryDirectory(prefix='mwx-publication-', dir='/private/tmp') as root:
            result = subprocess.run([str(self.binary), root, mode], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_clean_id_first_publication_and_replacement(self): self.run_case('replace')
    def test_failed_index_write_restores_old_directory(self): self.run_case('rollback')
    def test_recover_intent_before_directory_swap(self): self.run_case('recover-before')
    def test_recover_after_directory_swap(self): self.run_case('recover-after')
    def test_recover_after_index_commit_is_idempotent(self): self.run_case('recover-indexed')
    def test_recovery_waits_for_playback_lease(self): self.run_case('recover-protected')
    def test_cleanup_recovery_preserves_refreshed_metadata(self): self.run_case('recover-enriched')
    def test_unknown_numeric_directory_is_preserved(self): self.run_case('foreign')
    def test_delete_requires_current_identity_and_removes_files(self): self.run_case('delete')

    def test_recovery_after_old_marker_rewrite(self): self.run_case('recover-retired-marker')
    def test_recovery_after_old_generation_rename(self): self.run_case('recover-retired-directory')
    def test_failed_background_cleanup_does_not_block_delete_or_redownload(self): self.run_case('cleanup-delete-redownload')

    def test_legacy_cleanup_journal_respects_later_deletion(self): self.run_case('recover-deleted')
