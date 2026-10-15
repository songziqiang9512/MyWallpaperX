#!/usr/bin/env python3
"""Real owned-file I/O and ARC lifetime, with OS read observation (no renderer)."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneVideoOwnedFile.swift"
CHUNK = 1_024 * 1_024

HARNESS = r'''
import CryptoKit
import Darwin
import Foundation

nonisolated private enum IdentityFailure: Error { case identityProbe }

@main
enum Harness {
    static func main() throws {
        let mode = CommandLine.arguments[1]
        let source = URL(fileURLWithPath: CommandLine.arguments[2])
        let cache = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let maximum = Int(CommandLine.arguments[4])!
        let fm = FileManager.default
        let directory = cache.appendingPathComponent(".mywallpaperx-scene-video-payloads")
        var facts: [String: Any] = ["mode": mode]
        var identityChecks = 0
        var mutated = false
        var mutationFailure: String?
        func hasCopiedChunk() -> Bool {
            guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
                  let file = files.first,
                  let attributes = try? fm.attributesOfItem(atPath: file.path),
                  let count = attributes[.size] as? NSNumber else { return false }
            return count.intValue >= 1_024 * 1_024
        }
        do {
            var lease: SceneVideoOwnedFile?
            if mode == "allocate" {
                lease = try SceneVideoOwnedFile.allocate(cacheDirectory: cache, fileExtension: "mov")
                facts["absentBeforePayloadWrite"] = !fm.fileExists(atPath: lease!.url.path)
                facts["allocatedExtension"] = lease!.url.pathExtension
                try Data([7, 11, 13]).write(to: lease!.url)
            } else {
                lease = try SceneVideoOwnedFile.snapshot(from: source, cacheDirectory: cache,
                    maximumBytes: maximum, isCancelled: {
                        if mode == "cancel-before" { return true }
                        if mode == "cancel-during" { return hasCopiedChunk() }
                        if (mode == "grow" || mode == "shrink"), !mutated, hasCopiedChunk() {
                            do {
                                let handle = try FileHandle(forWritingTo: source)
                                defer { try? handle.close() }
                                if mode == "grow" {
                                    try handle.seekToEnd()
                                    try handle.write(contentsOf: Data([29]))
                                } else { try handle.truncate(atOffset: 1_024 * 1_024) }
                                mutated = true
                            } catch { mutationFailure = String(describing: error); return true }
                        }
                        return false
                    }, isSourceCurrent: {
                        identityChecks += 1
                        if mode == "deadline" { Thread.sleep(forTimeInterval: 30.05) }
                        if mode == "identity-throws", identityChecks == 2 {
                            throw IdentityFailure.identityProbe
                        }
                        return mode != "stale-before" && !(mode == "stale-after" && identityChecks == 2)
                    })
            }
            let url = lease!.url
            facts["url"] = url.path
            facts["sha256"] = SHA256.hash(data: try Data(contentsOf: url))
                .map { String(format: "%02x", $0) }.joined()
            facts["byteCount"] = (try fm.attributesOfItem(atPath: url.path)[.size] as! NSNumber).intValue
            var retained = lease
            lease = nil
            facts["retainedURLMatches"] = retained?.url == url
            facts["existsWithLastLease"] = fm.fileExists(atPath: url.path)
            withExtendedLifetime(retained) {}
            retained = nil
            facts["removedAfterLastLease"] = !fm.fileExists(atPath: url.path)
            facts["outcome"] = "success"
        } catch let failure as SceneVideoOwnedFile.Failure {
            facts["outcome"] = "failure"
            switch failure {
            case let .io(operation, code):
                facts["failure"] = "io"; facts["operation"] = operation.rawValue; facts["errno"] = code
            case let .directoryCreation(domain, code):
                facts["failure"] = "directoryCreation"; facts["domain"] = domain; facts["code"] = code
            default: facts["failure"] = String(describing: failure)
            }
        } catch IdentityFailure.identityProbe {
            facts["outcome"] = "identity-error-preserved"
        }
        facts["identityChecks"] = identityChecks
        facts["mutated"] = mutated
        facts["mutationFailure"] = mutationFailure ?? ""
        facts["remainingOwnedFiles"] = fm.fileExists(atPath: directory.path)
            ? try fm.contentsOfDirectory(atPath: directory.path).count : 0
        facts["sourceStillExists"] = fm.fileExists(atPath: source.path)
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

# Dyld observes actual OS read requests for the source inode. It does not
# replace any product API, alter results, or inspect product source shape.
READ_OBSERVER = r'''
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
static dev_t target_dev;
static ino_t target_ino;
static int enabled;
static const char *trace_path;
static _Atomic uint64_t calls, bytes, largest;
static ssize_t observed_read(int fd, void *buffer, size_t count) {
    struct stat value;
    int matches = enabled && fstat(fd, &value) == 0 && value.st_dev == target_dev && value.st_ino == target_ino;
    if (matches) {
        atomic_fetch_add(&calls, 1);
        uint64_t previous = atomic_load(&largest);
        while (previous < count && !atomic_compare_exchange_weak(&largest, &previous, count)) {}
    }
    ssize_t result = read(fd, buffer, count);
    if (matches && result > 0) atomic_fetch_add(&bytes, result);
    return result;
}
__attribute__((used)) static struct { const void *replacement, *original; }
interpose_read __attribute__((section("__DATA,__interpose"))) = { (const void *)observed_read, (const void *)read };
static void finish_trace(void) {
    if (!trace_path) return;
    char result[256];
    int count = snprintf(result, sizeof result, "{\"calls\":%llu,\"bytes\":%llu,\"largestRequest\":%llu}\n",
        (unsigned long long)atomic_load(&calls), (unsigned long long)atomic_load(&bytes),
        (unsigned long long)atomic_load(&largest));
    int output = open(trace_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (output >= 0) { (void)write(output, result, count); (void)close(output); }
}
__attribute__((constructor)) static void begin_trace(void) {
    const char *path = getenv("MWX_OWNED_FILE_OBSERVED_SOURCE");
    trace_path = getenv("MWX_OWNED_FILE_READ_TRACE");
    struct stat value;
    if (path && stat(path, &value) == 0) { target_dev = value.st_dev; target_ino = value.st_ino; enabled = 1; }
    atexit(finish_trace);
}
'''


@unittest.skipUnless(shutil.which("swiftc") and shutil.which("xcrun"), "macOS Swift and clang required")
class SceneVideoOwnedFileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-video-owned-file-")
        cls.work = Path(cls.temporary.name)
        cls.binary = cls.work / "owned-file-probe"
        cls.observer = cls.work / "read-observer.dylib"
        cls.proof = Path(os.environ["MWX_VIDEO_OWNED_FILE_PROOF"]) if os.environ.get("MWX_VIDEO_OWNED_FILE_PROOF") else None
        if cls.proof:
            cls.proof.mkdir(parents=True, exist_ok=True)
        harness, observer = cls.work / "Harness.swift", cls.work / "read-observer.c"
        harness.write_text(HARNESS)
        observer.write_text(READ_OBSERVER)
        commands = [
            ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-strict-concurrency=complete",
             "-warnings-as-errors", "-default-isolation", "MainActor", str(SOURCE), str(harness),
             "-module-cache-path", str(cls.work / "module-cache"), "-o", str(cls.binary)],
            ["xcrun", "--sdk", "macosx", "clang", "-dynamiclib", "-Wall", "-Werror", str(observer), "-o", str(cls.observer)],
        ]
        for index, command in enumerate(commands):
            completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90)
            if cls.proof:
                (cls.proof / f"compile-{index}.json").write_text(json.dumps({"argv": command, "exit": completed.returncode,
                    "stdout": completed.stdout, "stderr": completed.stderr}, indent=2) + "\n")
            if completed.returncode:
                cls.temporary.cleanup()
                raise AssertionError(completed.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_case(self, mode="snapshot", maximum=1_024 * CHUNK, source_kind="file"):
        directory = self.work / self._testMethodName
        directory.mkdir()
        source, cache, trace = directory / "external.mov", directory / "cache", directory / "read-trace.json"
        payload = bytes(range(256)) * (3 * CHUNK // 256) + bytes(range(251))
        if source_kind == "directory":
            source.mkdir()
        elif source_kind == "fifo":
            os.mkfifo(source)
        else:
            source.write_bytes(payload)
        environment = {**os.environ, "MWX_OWNED_FILE_OBSERVED_SOURCE": str(source), "MWX_OWNED_FILE_READ_TRACE": str(trace)}
        command = ["/usr/bin/env", f"DYLD_INSERT_LIBRARIES={self.observer}", str(self.binary), mode, str(source), str(cache), str(maximum)]
        completed = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=45)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        facts, observed = json.loads(completed.stdout), json.loads(trace.read_text())
        if self.proof:
            (self.proof / f"{self._testMethodName}.json").write_text(json.dumps({"facts": facts, "readObservation": observed}, indent=2) + "\n")
        self.assertEqual(facts["remainingOwnedFiles"], 0, facts)
        self.assertTrue(facts["sourceStillExists"], facts)
        self.assertEqual(facts["mutationFailure"], "", facts)
        self.assertLessEqual(observed["largestRequest"], CHUNK, observed)
        return facts, observed, payload

    def test_snapshot_bytes_single_pass_read_bound_and_final_lease(self):
        facts, observed, payload = self.run_case()
        self.assertEqual(facts["outcome"], "success")
        self.assertEqual(facts["sha256"], hashlib.sha256(payload).hexdigest())
        self.assertEqual(facts["byteCount"], len(payload))
        self.assertEqual(observed["bytes"], len(payload))
        self.assertEqual(observed["largestRequest"], CHUNK)
        self.assertGreaterEqual(observed["calls"], 4)
        self.assertEqual(facts["identityChecks"], 2)
        self.assertTrue(facts["retainedURLMatches"] and facts["existsWithLastLease"] and facts["removedAfterLastLease"])

    def test_allocate_leaves_destination_absent_for_existing_payload_writers(self):
        facts, _, _ = self.run_case("allocate")
        self.assertTrue(facts["absentBeforePayloadWrite"])
        self.assertEqual(facts["allocatedExtension"], "mov")
        self.assertTrue(facts["existsWithLastLease"] and facts["removedAfterLastLease"])

    def test_oversized_source_is_rejected_before_reading(self):
        facts, observed, _ = self.run_case(maximum=CHUNK)
        self.assertEqual(facts["failure"], "byteLimitExceeded")
        self.assertEqual(observed["calls"], 0)

    def test_actual_growth_cannot_exceed_byte_budget(self):
        facts, _, _ = self.run_case("grow", maximum=3 * CHUNK + 251)
        self.assertTrue(facts["mutated"])
        self.assertEqual(facts["failure"], "byteLimitExceeded")

    def test_shorter_source_fails_initial_size_contract(self):
        facts, _, _ = self.run_case("shrink")
        self.assertTrue(facts["mutated"])
        self.assertEqual(facts["failure"], "sourceChanged")

    def test_cancellation_before_io(self):
        facts, observed, _ = self.run_case("cancel-before")
        self.assertEqual(facts["failure"], "cancelled")
        self.assertEqual(observed["calls"], 0)

    def test_cancellation_during_stream_cleans_partial_file(self):
        facts, observed, _ = self.run_case("cancel-during")
        self.assertEqual(facts["failure"], "cancelled")
        self.assertEqual(observed["bytes"], CHUNK)

    def test_stale_source_before_io(self):
        facts, observed, _ = self.run_case("stale-before")
        self.assertEqual(facts["failure"], "sourceChanged")
        self.assertEqual(observed["calls"], 0)

    def test_stale_source_after_copy_cleans_candidate(self):
        facts, observed, payload = self.run_case("stale-after")
        self.assertEqual(facts["failure"], "sourceChanged")
        self.assertEqual(observed["bytes"], len(payload))

    def test_identity_check_error_is_preserved(self):
        facts, _, _ = self.run_case("identity-throws")
        self.assertEqual(facts["outcome"], "identity-error-preserved")

    def test_directory_rejected_as_nonregular(self):
        facts, observed, _ = self.run_case(source_kind="directory")
        self.assertEqual(facts["failure"], "sourceNotRegularFile")
        self.assertEqual(observed["calls"], 0)

    def test_fifo_rejected_without_blocking_open(self):
        facts, observed, _ = self.run_case(source_kind="fifo")
        self.assertEqual(facts["failure"], "sourceNotRegularFile")
        self.assertEqual(observed["calls"], 0)

    def test_deadline_is_checked_after_blocking_work_returns(self):
        facts, observed, _ = self.run_case("deadline")
        self.assertEqual(facts["failure"], "deadlineExceeded")
        self.assertEqual(observed["calls"], 0)


if __name__ == "__main__":
    unittest.main()
