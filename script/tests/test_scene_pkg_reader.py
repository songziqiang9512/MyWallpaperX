"""Execute the real PKG FD/table reader; fixtures never enter the product App."""
from __future__ import annotations

import base64
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from script.tests.scene_pkg_fixture import make_package

READER = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift"
HARNESS = r'''
import Foundation
import Darwin

nonisolated final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [String] = []
    func fail(_ message: String) { lock.lock(); failures.append(message); lock.unlock() }
    var passed: Bool { lock.lock(); defer { lock.unlock() }; return failures.isEmpty }
}

@main enum Harness {
    nonisolated static func bytes(_ package: ScenePkgReader.OpenPackage, _ entry: ScenePkgIndex.Entry,
                                  checkCancellation: (() throws -> Void)? = nil) throws -> Data {
        var value = Data()
        try package.readEntryChunks(entry, checkCancellation: checkCancellation) { value.append($0) }
        return value
    }
    nonisolated static func expected(_ entry: ScenePkgIndex.Entry, in original: Data,
                                    index: ScenePkgIndex) -> Data {
        let start = original.startIndex + index.dataStartOffset + Int(entry.offset)
        return Data(original[start..<(start + Int(entry.size))])
    }
    static func rejects(_ operation: () throws -> Void,
                        matching: (Error) -> Bool = { _ in true }) -> Bool {
        do { try operation(); return false } catch { return matching(error) }
    }
    static func descriptorCount() -> Int {
        (0..<1_024).filter { fcntl(Int32($0), F_GETFD) >= 0 }.count
    }
    static func main() throws {
        let mode = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
        let reader = ScenePkgReader()
        if mode == "index" || mode == "compatibility-index" {
            do {
                let value = try reader.openPackage(packageURL: url,
                    limits: mode == "index" ? .bounded : .compatibility).index
                print("accepted:\(value.entries.count)")
            } catch {
                print("rejected:\(error)")
            }
            return
        }
        if mode == "fd-lifetime" {
            let malformed = url.deletingLastPathComponent().appendingPathComponent("malformed.pkg")
            try Data("bad".utf8).write(to: malformed)
            let before = descriptorCount()
            var released = true
            var cancelledAfterOpen = true
            for _ in 0..<64 {
                var owned: ScenePkgReader.OpenPackage? = try reader.openPackage(packageURL: url)
                weak var borrower = owned
                _ = try bytes(owned!, owned!.index.entries[0])
                owned = nil
                released = released && borrower == nil
                _ = rejects({ _ = try reader.openPackage(packageURL: malformed) })
                var calls = 0
                let rejected = rejects({
                    _ = try reader.openPackage(packageURL: url, checkCancellation: {
                        calls += 1
                        if calls == 2 { throw CancellationError() }
                    })
                }, matching: { $0 is CancellationError })
                cancelledAfterOpen = cancelledAfterOpen && rejected && calls == 2
            }
            let result = ["ownerReleased": released, "cancelledAfterOpen": cancelledAfterOpen,
                          "descriptorsReleasedOnSuccessFailureAndCancel": descriptorCount() == before]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
            return
        }
        let package = try reader.openPackage(packageURL: url)
        let index = package.index
        let original = try Data(contentsOf: url)
        let entry = index.entries[0]
        let reference = expected(entry, in: original, index: index)
        var result: [String: Any] = [:]
        switch mode {
        case "duplicate-fd":
            let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
            guard descriptor >= 0 else { throw POSIXError(.EIO) }
            var duplicate: ScenePkgReader.OpenPackage?
            do { duplicate = try reader.openPackage(duplicatingFileDescriptor: descriptor) }
            catch { close(descriptor); throw error }
            close(descriptor)
            result["duplicateOutlivesCallerDescriptor"] = try bytes(duplicate!, duplicate!.index.entries[0]) == reference
                && duplicate!.fileRevision == package.fileRevision
            weak var borrower = duplicate
            duplicate = nil
            result["duplicateHasIndependentLifetime"] = borrower == nil
            let count = descriptorCount()
            result["invalidCallerDescriptorFailsWithoutLeak"] = rejects({
                _ = try reader.openPackage(duplicatingFileDescriptor: -1)
            }) && descriptorCount() == count
        case "equivalence":
            let second = try reader.openPackage(packageURL: url)
            result["newFDParsesSameTableAndRevision"] = second.index == index
                && second.fileRevision == package.fileRevision
            result["actualFileSize"] = index.fileSize == original.count
            result["paths"] = index.entries.map(\.path)
            result["payloads"] = try index.entries.map { try bytes(package, $0).base64EncodedString() }
            result["allEntriesEqual"] = try index.entries.allSatisfy {
                try bytes(package, $0) == expected($0, in: original, index: index)
            }
        case "verification":
            result["selectedBytes"] = try bytes(package, entry) == reference
            try package.validateCurrentSource()
            result["openedSourceIsCurrent"] = true
            result["cancelledReadRejected"] = rejects({
                _ = try bytes(package, entry,
                    checkCancellation: { throw CancellationError() })
            }, matching: { $0 is CancellationError })
            result["cancelledOpenRejected"] = rejects({
                _ = try reader.openPackage(packageURL: url, checkCancellation: { throw CancellationError() })
            }, matching: { $0 is CancellationError })
            if let empty = index.entries.first(where: { $0.size == 0 }) {
                var chunks = 0
                try package.readEntryChunks(empty) { _ in chunks += 1 }
                result["emptyReadHasNoPayloadChunks"] = try bytes(package, empty).isEmpty && chunks == 0
            }
        case "mutation":
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let file = try FileHandle(forWritingTo: url)
            try file.seek(toOffset: UInt64(index.dataStartOffset + Int(entry.offset)))
            try file.write(contentsOf: Data(repeating: 0x58, count: reference.count))
            try file.close()
            try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!],
                                                   ofItemAtPath: url.path)
            result["openedSourceChangeRejected"] = rejects({ _ = try bytes(package, entry) },
                matching: { if case ScenePkgReader.ReadError.sourceChanged = $0 { return true }; return false })
            result["staleCurrentSourceRejected"] = rejects({ try package.validateCurrentSource() },
                matching: { if case ScenePkgReader.ReadError.sourceChanged = $0 { return true }; return false })
            let reopened = try reader.openPackage(packageURL: url)
            result["newRevisionReadsCurrentBytes"] = try bytes(reopened, reopened.index.entries[0])
                == Data(repeating: 0x58, count: reference.count)
            result["newRevisionGetsNewCacheKey"] = reopened.fileRevision != package.fileRevision

        case "truncate":
            let file = try FileHandle(forWritingTo: url)
            try file.truncate(atOffset: UInt64(index.fileSize - 1)); try file.close()
            result["currentSourceRejected"] = rejects({ try package.validateCurrentSource() },
                matching: { if case ScenePkgReader.ReadError.sourceChanged = $0 { return true }; return false })
            result["entryRejected"] = rejects({ _ = try bytes(package, entry) },
                matching: { if case ScenePkgReader.ReadError.sourceChanged = $0 { return true }; return false })
        case "replace":
            var replacement = original
            let start = index.dataStartOffset + Int(entry.offset)
            replacement.replaceSubrange(start..<(start + reference.count),
                                         with: Data(repeating: 0x59, count: reference.count))
            try replacement.write(to: url, options: .atomic)
            do {
                result["neverReturnsReplacement"] = try bytes(package, entry) == reference
            } catch ScenePkgReader.ReadError.sourceChanged { result["neverReturnsReplacement"] = true }
            let reopened = try reader.openPackage(packageURL: url)
            result["newFDReadsCurrentRevision"] = try bytes(reopened, reopened.index.entries[0])
                == Data(repeating: 0x59, count: reference.count)
            result["replacementHasDifferentCacheIdentity"] = reopened.fileRevision != package.fileRevision

        case "during-read":
            var chunks = 0
            result["inFlightChangeRejected"] = rejects({
                try package.readEntryChunks(entry) { _ in
                        chunks += 1
                        if chunks == 1 {
                            let file = try FileHandle(forWritingTo: url)
                            try file.seek(toOffset: UInt64(index.dataStartOffset))
                            try file.write(contentsOf: Data([0x5a])); try file.close()
                        }
                    }
            }, matching: { if case ScenePkgReader.ReadError.sourceChanged = $0 { return true }; return false })
            result["mutationReachedActualChunkConsumer"] = chunks > 0
        case "parallel":
            let results = Results()
            DispatchQueue.concurrentPerform(iterations: 64) { number in
                let entry = index.entries[number % index.entries.count]
                do {
                    if try bytes(package, entry) != expected(entry, in: original, index: index) {
                        results.fail("wrong bytes")
                    }
                } catch { results.fail(String(describing: error)) }
            }
            result["parallelReadsExact"] = results.passed
        case "cancel-during-read":
            var chunks = 0
            result["cancelledAfterFirstChunk"] = rejects({
                try package.readEntryChunks(entry,
                    checkCancellation: { if chunks > 0 { throw CancellationError() } }) { _ in chunks += 1 }
            }, matching: { $0 is CancellationError })
            result["exactlyOneChunkReachedConsumerBeforeCancel"] = chunks == 1
            result["canRetryAfterCancel"] = try bytes(package, entry) == reference
        default: fatalError("unknown mode")
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class ScenePkgReaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-pkg-reader-")
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS)
        cls.binary = root / "reader"
        result = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                                 "-parse-as-library",
                                 str(READER), str(harness), "-o", str(cls.binary)],
                                capture_output=True, text=True, timeout=90)
        if result.returncode:
            cls.temporary.cleanup()
            raise AssertionError(result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_case(self, mode, entries=None, data=None):
        with tempfile.TemporaryDirectory(prefix="mwx-pkg-input-") as temporary:
            package = Path(temporary) / "scene.pkg"
            package.write_bytes(data if data is not None else make_package(entries or [
                ("scene.json", b"original-scene"), ("images/empty.png", b""),
                ("sounds/track.ogg", b"sound-bytes")]))
            completed = subprocess.run([str(self.binary), mode, str(package)],
                                       capture_output=True, text=True, timeout=20)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            return completed.stdout.strip() if mode.endswith("index") else json.loads(completed.stdout)

    def assert_case(self, mode, **kwargs):
        result = self.run_case(mode, **kwargs)
        self.assertTrue(all(result.values()), result)

    def test_current_fd_retains_exact_table_order_raw_names_and_payload_ranges(self):
        entries = [("Scene.json", b"uppercase"), ("scene.json", b"lowercase"),
                   ("textures/e\u0301.tex", b"decomposed"), ("textures/é.tex", b"composed"),
                   ("materials\\space .tex", b"backslash"), ("images/empty.png", b"")]
        result = self.run_case("equivalence", entries=entries)
        self.assertEqual(result.pop("paths"), [path for path, _ in entries])
        self.assertEqual(result.pop("payloads"), [base64.b64encode(payload).decode() for _, payload in entries])
        self.assertTrue(all(result.values()), result)

    def test_current_fd_zero_length_and_cancellation(self):
        self.assert_case("verification")

    def test_same_size_restored_mtime_rejects_stale_and_new_revision_reads_current_bytes(self):
        self.assert_case("mutation")

    def test_truncation_after_open_never_returns_partial_data(self):
        self.assert_case("truncate")

    def test_atomic_path_replacement_never_reopens_as_old_entry(self):
        self.assert_case("replace")

    def test_mutation_during_chunked_read_is_rejected(self):
        self.assert_case("during-read", entries=[("images/large.png", b"a" * (256 * 1024))])

    def test_cancellation_after_one_chunk_does_not_poison_retry(self):
        self.assert_case("cancel-during-read", entries=[("images/large.png", b"a" * (256 * 1024))])

    def test_shared_fd_has_no_seek_cursor_race(self):
        self.assert_case("parallel", entries=[("images/a.png", b"a" * 70001),
                                              ("images/b.png", b"b" * 80003)])

    def test_fd_owner_releases_on_success_failed_parse_and_cancellation(self):
        self.assert_case("fd-lifetime")

    def test_duplicate_fd_outlives_caller_and_has_independent_lifetime(self):
        self.assert_case("duplicate-fd")

    def test_index_budget_boundaries_and_explicit_compatibility_policy(self):
        # These are caller budgets, not PKGV format limits. Playback's explicit
        # compatibility policy still accepts the same structurally valid tables.
        def magic_table(length):
            return struct.pack("<I", length) + b"PKGV" + b"0" * (length - 4) + struct.pack("<I", 0)

        def table_of_size(size):
            remaining = size - 15  # PKGV001 header and count
            paths = []
            while remaining > 65536 + 12:
                length = min(65536, remaining - 25)  # leave at least one valid final record
                paths.append(("p" * length, b""))
                remaining -= length + 12
            paths.append(("p" * (remaining - 12), b""))
            data = make_package(paths)
            self.assertEqual(len(data), size)
            return data, len(paths)

        at_table, table_count = table_of_size(16 * 1024 * 1024)
        over_table, over_count = table_of_size(16 * 1024 * 1024 + 1)
        cases = [(magic_table(64), magic_table(65), 0, 0),
                 (make_package([("p" * 65536, b"")]), make_package([("p" * 65537, b"")]), 1, 1),
                 (make_package([("p", b"")] * 100000), make_package([("p", b"")] * 100001), 100000, 100001),
                 (at_table, over_table, table_count, over_count)]
        for at_limit, over_limit, count, over_count in cases:
            with self.subTest(boundary_bytes=len(at_limit)):
                self.assertEqual(self.run_case("index", data=at_limit), f"accepted:{count}")
                self.assertTrue(self.run_case("index", data=over_limit).startswith("rejected:limitExceeded"))
                self.assertEqual(self.run_case("compatibility-index", data=over_limit), f"accepted:{over_count}")

    def test_malformed_table_structure_fails_even_without_policy_caps(self):
        header = struct.pack("<I", 7) + b"PKGV001" + struct.pack("<I", 1)
        malformed = [b"short", struct.pack("<I", 7) + b"INVALID" + struct.pack("<I", 0) + b"x",
                     struct.pack("<I", 0) + b"x" * 16,
                     struct.pack("<I", 7) + b"PKGV001" + struct.pack("<I", 0xFFFFFFFF) + b"x",
                     header + struct.pack("<I", 0) + struct.pack("<II", 0, 0),
                     header + struct.pack("<I", 1) + b"\xff" + struct.pack("<II", 0, 0),
                     header + struct.pack("<I", 50) + b"short"]
        for data in malformed:
            with self.subTest(bytes=len(data)):
                for mode in ("index", "compatibility-index"):
                    self.assertTrue(self.run_case(mode, data=data).startswith("rejected:"))

    def test_index_preserves_unavailable_payload_metadata_without_consuming_raw_entries(self):
        header = struct.pack("<I", 7) + b"PKGV001" + struct.pack("<I", 1)
        # These have complete tables but unavailable payload ranges. Reader only
        # parses metadata; the Root projection owns omission before any consumer.
        cases = [make_package([("scene.json", b"payload")])[:-1],
                 header + struct.pack("<I", 1) + b"p" + struct.pack("<II", 0xFFFFFFFF, 1) + b"x",
                 header + struct.pack("<I", 1) + b"p" + struct.pack("<II", 0, 0xFFFFFFFF) + b"x",
                 header + struct.pack("<I", 1) + b"p" + struct.pack("<II", 2, 0) + b"x"]
        for data in cases:
            for mode in ("index", "compatibility-index"):
                with self.subTest(mode=mode, bytes=len(data)):
                    self.assertEqual(self.run_case(mode, data=data), "accepted:1")
        # Never pass these raw out-of-range Entry values to readEntryChunks.

    def test_sparse_file_index_uses_metadata_without_loading_payload(self):
        with tempfile.TemporaryDirectory(prefix="mwx-pkg-sparse-") as temporary:
            path = Path(temporary) / "scene.pkg"
            table = make_package([("images/large.png", b"")])
            table = table[:-4] + struct.pack("<I", 256 * 1024 * 1024)
            with path.open("wb") as file:
                file.write(table)
                file.truncate(len(table) + 256 * 1024 * 1024)
            result = subprocess.run([str(self.binary), "index", str(path)],
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "accepted:1")


if __name__ == "__main__":
    unittest.main()
