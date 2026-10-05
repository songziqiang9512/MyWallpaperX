#!/usr/bin/env python3
"""Exercise the real JSON endpoint and its fixed Perl/XS pipe using owned input."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneSystemMediaSource.swift"
FRAMING = ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift"

FIXTURE = r'''
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

XS(mwx_scene_media_run) {
    const char *path = getenv("MWX_TRANSPORT_TEST_PID");
    FILE *p = fopen(path, "a");
    if (p) { fprintf(p, "%d\n", getpid()); fclose(p); }
    const char *mode = getenv("MWX_TRANSPORT_TEST_MODE");
    if (strcmp(mode, "partial") == 0) {
        fputs("{\"version\":1", stdout); fflush(stdout); _exit(0);
    }
    if (strcmp(mode, "closed") == 0) { close(1); sleep(600); _exit(0); }
    if (strcmp(mode, "bad") == 0) {
        fputs("{\"version\":true,\"status\":\"noSession\"}\n", stdout); fflush(stdout);
    } else if (strcmp(mode, "emit") == 0) {
        const char *title = strcmp(getenv("MWX_TRANSPORT_TEST_TITLE"), "NEW") == 0 ? "NEW" : "OLD";
        fprintf(stdout, "{\"version\":1,\"status\":\"snapshot\",\"source\":\"fixture\",\"identity\":\"A\",\"title\":\"%s\",\"artworkChanged\":true}\n", title);
        fflush(stdout);
    }
    sleep(600);
    _exit(0);
}
'''

HARNESS = r'''
import Darwin
import Foundation

typealias Endpoint = SceneSystemMediaSource
typealias Failure = Endpoint.Failure

@main
@MainActor
struct SystemMediaHarness {
    nonisolated static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    nonisolated static func decoderCases() throws -> String {
        var checks = 0
        func check(_ condition: Bool) { precondition(condition); checks += 1 }
        func reject(_ expected: Failure, _ body: () throws -> Void) {
            do { try body(); preconditionFailure("accepted invalid wire") }
            catch let error as Failure { check(error == expected) }
            catch { preconditionFailure("unexpected error") }
        }
        let good: [String: Any] = ["version": 1, "status": "snapshot", "source": "fixture",
            "identity": "A", "title": "Owned", "artist": "Artist", "album": "Album",
            "playbackState": 1, "position": 3.5, "duration": 180, "artworkIdentifier": "artA",
            "artworkChanged": true, "artworkData": Data([1, 2, 3]).base64EncodedString()]
        var decoder = Endpoint.Decoder()
        if case .snapshot(let value) = try decoder.decode(json(good)) {
            check(value.source == "fixture" && value.identity == "A")
            check(value.title == "Owned" && value.artist == "Artist" && value.album == "Album")
            check(value.playbackState == 1 && value.position == 3.5 && value.duration == 180)
            check(value.artworkChanged && value.artworkIdentifier == "artA")
            check(value.artworkData == Data([1, 2, 3]) && value.artworkFailure == nil)
        } else { preconditionFailure("expected snapshot") }
        var inherited = good
        inherited.removeValue(forKey: "artworkData")
        inherited["artworkChanged"] = false
        if case .snapshot(let value) = try decoder.decode(json(inherited)) {
            check(!value.artworkChanged && value.artworkData == nil)
        } else { preconditionFailure("expected unchanged art") }
        for (key, value) in [("identity", "B"), ("source", "other"), ("artworkIdentifier", "artB")] {
            var changed = inherited; changed[key] = value
            reject(.inheritedArtworkWithoutMatchingTrack) { _ = try decoder.decode(json(changed)) }
        }
        var falseWithData = good; falseWithData["artworkChanged"] = false
        reject(.inheritedArtworkWithoutMatchingTrack) { _ = try decoder.decode(json(falseWithData)) }
        var fresh = Endpoint.Decoder()
        reject(.inheritedArtworkWithoutMatchingTrack) { _ = try fresh.decode(json(inherited)) }
        for status in ["noSession", "unavailable"] {
            _ = try decoder.decode(json(good))
            let value = try decoder.decode(json(["version": 1, "status": status]))
            if status == "noSession" {
                if case .noSession = value { check(true) } else { preconditionFailure("wrong status") }
            } else {
                if case .unavailable(.helperUnavailable) = value { check(true) } else { preconditionFailure("wrong status") }
            }
            reject(.inheritedArtworkWithoutMatchingTrack) { _ = try decoder.decode(json(inherited)) }
        }
        let cases: [(String, Any, Failure)] = [
            ("version", 2, .unsupportedVersion), ("version", true, .invalidJSON),
            ("status", "other", .invalidFields), ("source", "", .invalidFields),
            ("identity", "", .invalidFields), ("title", "a\nb", .invalidFields),
            ("artist", String(repeating: "a", count: 4097), .invalidFields),
            ("album", 1, .invalidJSON), ("playbackState", 3, .invalidFields),
            ("playbackState", true, .invalidJSON), ("position", -1, .invalidFields),
            ("duration", "180", .invalidJSON), ("duration", -1, .invalidFields),
            ("artworkChanged", 1, .invalidJSON), ("artworkData", [], .invalidJSON)
        ]
        for (key, value, error) in cases {
            var invalid = good; invalid[key] = value
            reject(error) { _ = try decoder.decode(json(invalid)) }
        }
        for key in ["source", "identity", "artworkChanged"] {
            var invalid = good; invalid.removeValue(forKey: key)
            reject(.invalidFields) { _ = try decoder.decode(json(invalid)) }
        }
        reject(.invalidJSON) { _ = try decoder.decode(Data("[]".utf8)) }
        reject(.invalidJSON) { _ = try decoder.decode(Data("{\"version\":1,\"status\":\"snapshot\",\"position\":1e400}".utf8)) }
        var optional = good
        for key in ["title", "artist", "album", "playbackState", "position", "duration", "artworkData", "artworkIdentifier"] {
            optional[key] = NSNull()
        }
        if case .snapshot(let value) = try decoder.decode(json(optional)) {
            check(value.title == nil && value.artist == nil && value.album == nil)
            check(value.playbackState == nil && value.position == nil && value.duration == nil)
            check(value.artworkChanged && value.artworkData == nil && value.artworkFailure == nil)
        } else { preconditionFailure("nullable fields must clear") }
        for (encoded, expected) in [("!!bad!!", Failure.invalidArtwork),
                                   (Data(count: Endpoint.maximumArtworkByteCount + 1).base64EncodedString(), .artworkByteLimit)] {
            var badArt = good; badArt["artworkData"] = encoded
            if case .snapshot(let value) = try decoder.decode(json(badArt)) {
                check(value.title == "Owned" && value.artworkChanged)
                check(value.artworkData == nil && value.artworkFailure == expected)
            } else { preconditionFailure("optional art failure must stay local") }
        }
        var boundary = good
        boundary["title"] = String(repeating: "a", count: 4096)
        boundary["artworkData"] = Data(count: Endpoint.maximumArtworkByteCount).base64EncodedString()
        if case .snapshot(let value) = try decoder.decode(json(boundary)) {
            check(value.title?.utf8.count == 4096 && value.artworkData?.count == Endpoint.maximumArtworkByteCount)
        } else { preconditionFailure("valid byte limit rejected") }
        var stream = Endpoint.StreamDecoder()
        var frame = try json(good); frame.append(10)
        check(try stream.append(frame.prefix(17)).isEmpty)
        check(stream.hasIncompleteFrame)
        let result = try stream.append(frame.dropFirst(17))
        check(result.count == 1 && !stream.hasIncompleteFrame)
        check(try stream.append(Data([10, 10])).isEmpty)
        var limited = Endpoint.StreamDecoder()
        check(try limited.append(Data(repeating: 32, count: Endpoint.maximumLineByteCount)).isEmpty)
        reject(.lineByteLimit) { _ = try limited.append(Data([32])) }
        reject(.lineByteLimit) { _ = try decoder.decode(Data(count: Endpoint.maximumLineByteCount + 1)) }
        check(Endpoint.heartbeatTimeout == 12)
        return "{\"checks\":\(checks),\"result\":\"PASS\",\"nativeMediaQueries\":0}"
    }

    static func wait(_ condition: () -> Bool, seconds: Double) async {
        let end = ProcessInfo.processInfo.systemUptime + seconds
        while !condition() && ProcessInfo.processInfo.systemUptime < end {
            try? await Task.sleep(for: .milliseconds(20))
        }
        precondition(condition(), "transport did not reach expected state")
    }

    static func pids(_ path: String) -> [Int32] {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { Int32($0) }
    }

    nonisolated static func blockBriefly() { Thread.sleep(forTimeInterval: 0.1) }

    static func main() async throws {
        if CommandLine.arguments[1] == "decoder" {
            print(try await Task.detached { try decoderCases() }.value)
            return
        }
        let mode = CommandLine.arguments[1], bundlePath = CommandLine.arguments[2]
        let pidPath = CommandLine.arguments[3]
        setenv("MWX_TRANSPORT_TEST_PID", pidPath, 1)
        setenv("MWX_TRANSPORT_TEST_MODE", ["lifecycle", "heartbeat"].contains(mode) ? "emit" : mode, 1)
        setenv("MWX_TRANSPORT_TEST_TITLE", "OLD", 1)
        let source = Endpoint(bundle: Bundle(path: bundlePath)!)
        var events: [Endpoint.Result] = []
        source.start { events.append($0) }
        if mode == "lifecycle" {
            // Keep the actor occupied until old output is queued, then restart
            // before that callback can run. The worker remains independent.
            let end = ProcessInfo.processInfo.systemUptime + 2
            while pids(pidPath).isEmpty && ProcessInfo.processInfo.systemUptime < end { blockBriefly() }
            precondition(!pids(pidPath).isEmpty)
            blockBriefly()
            source.stop()
            setenv("MWX_TRANSPORT_TEST_TITLE", "NEW", 1)
            source.start { events.append($0) }
            source.start { _ in preconditionFailure("start spawned twice") }
            await wait({ events.contains { if case .snapshot(let s) = $0 { return s.title == "NEW" }; return false } }, seconds: 4)
            precondition(!events.contains { if case .snapshot(let s) = $0 { return s.title == "OLD" }; return false })
        } else {
            await wait({ events.contains { if case .unavailable = $0 { return true }; return false } }, seconds: 16)
            guard case .unavailable(let failure) = events.last! else { preconditionFailure() }
            if mode == "bad" { precondition(failure == .invalidJSON) }
            if mode == "partial" { precondition(failure == .incompleteFrame) }
            if mode == "wait" || mode == "heartbeat" { precondition(failure == .heartbeatTimeout) }
            if mode == "heartbeat" {
                precondition(events.contains { if case .snapshot = $0 { return true }; return false })
            }
            if mode == "closed" {
                guard case .processExited = failure else { preconditionFailure("EOF did not stop child") }
            }
        }
        source.stop()
        source.stop()
        await wait({ !pids(pidPath).isEmpty && pids(pidPath).allSatisfy { Darwin.kill($0, 0) == -1 && errno == ESRCH } }, seconds: 3)
        precondition(pids(pidPath).count == (mode == "lifecycle" ? 2 : 1))
        print("{\"result\":\"PASS\",\"mode\":\"\(mode)\",\"childrenReaped\":true,\"callbacks\":\(events.count)}")
    }
}
'''


class SceneSystemMediaSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None or shutil.which("xcrun") is None:
            raise unittest.SkipTest("macOS Swift/SDK are unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-system-media-source-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
        archlib = subprocess.check_output(["/usr/bin/perl", "-MConfig", "-e", "print $Config{archlib}"], text=True)
        headers = Path(sdk) / archlib.lstrip("/") / "CORE"
        if not (headers / "perl.h").is_file():
            raise unittest.SkipTest("public Perl XS SDK headers are unavailable")
        cls.bundle = root / "OwnedMedia.bundle"
        resources = cls.bundle / "Contents/Resources/SceneMediaObserver"
        resources.mkdir(parents=True)
        (cls.bundle / "Contents/Info.plist").write_text(
            '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key>'
            '<string>com.mywallpaperx.tests.mediafixture</string><key>CFBundlePackageType</key>'
            '<string>BNDL</string></dict></plist>', encoding="utf-8")
        fixture = root / "fixture.c"
        fixture.write_text(FIXTURE, encoding="utf-8")
        subprocess.run(["xcrun", "clang", "-dynamiclib", "-I", str(headers), str(fixture),
                        "-undefined", "dynamic_lookup", "-o", str(resources / "SceneMediaObserver.dylib")],
                       capture_output=True, text=True, check=True)
        harness = root / "harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "media-source"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        subprocess.run(["swiftc", "-swift-version", "6", "-default-isolation", "MainActor",
                        "-module-cache-path", str(root / "swift-cache"), str(FRAMING), str(SOURCE),
                        str(harness), "-o", str(cls.binary)], capture_output=True, text=True,
                       env=environment, check=True, cwd=ROOT)

    def run_mode(self, mode):
        pid_path = Path(self.temporary.name) / f"{mode}-pids"
        try:
            executed = subprocess.run([str(self.binary), mode, str(self.bundle), str(pid_path)],
                                      capture_output=True, text=True, timeout=24)
            if executed.returncode:
                self.fail(executed.stderr)
        finally:
            # A failing harness must not orphan its own fixture child.
            if pid_path.is_file():
                for raw in pid_path.read_text().splitlines():
                    command = subprocess.run(["ps", "-p", raw, "-o", "command="],
                                             capture_output=True, text=True).stdout
                    if str(self.bundle) not in command:
                        continue
                    try:
                        os.kill(int(raw), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
        result = json.loads(executed.stdout)
        self.assertEqual(result["result"], "PASS")
        if mode != "decoder":
            self.assertTrue(result["childrenReaped"])
        return result

    def test_real_decoder_and_shared_frame_limits(self):
        result = self.run_mode("decoder")
        self.assertGreaterEqual(result["checks"], 45)
        self.assertEqual(result["nativeMediaQueries"], 0)

    def test_stop_restart_rejects_old_callback_and_does_not_spawn_twice(self):
        self.run_mode("lifecycle")

    def test_invalid_wire_and_partial_eof_stop_owned_process(self):
        self.run_mode("bad")
        self.run_mode("partial")

    def test_closed_stdout_reaps_live_child(self):
        self.run_mode("closed")

    def test_startup_without_complete_record_times_out(self):
        self.run_mode("wait")

    def test_valid_snapshot_followed_by_silence_times_out(self):
        self.run_mode("heartbeat")


if __name__ == "__main__":
    unittest.main()
