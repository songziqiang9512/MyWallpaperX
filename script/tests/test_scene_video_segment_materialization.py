#!/usr/bin/env python3
"""Owned-file disk accounting and real VP9 fragmented-MP4 CPU/AV consumers.

No Scene surface, Metal device, user media, or App process is started.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from .test_scene_sound_resource_input import CARRIERS
from script.tests.scene_video_segment_delegate_fixture import compile_segment_delegate


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    ROOT / "MyWallpaperX/Core/SteamWorkshopStorage/ScenePlaybackSource.swift",
    *[SCENE / path for path in (
        "Format/ScenePkgReader.swift", "Format/SceneWebMContainer.swift",
        "Resources/Assets/SceneResourceIdentity.swift", "Resources/Assets/SceneResourceView+Backing.swift",
        "Resources/Assets/SceneResourceIndex.swift", "Resources/Assets/SceneResourceView.swift",
        "Resources/Providers/SceneVideoOwnedFile.swift",
        "Resources/Providers/SceneVideoPayloadPreparation.swift",
        "Systems/Media/SceneSoundPlaybackProgram.swift",
    )],
]

HARNESS = r'''
import AVFoundation
import CoreVideo
import Foundation

@main
enum Harness {
    static let fm = FileManager.default

    static func ledger(_ base: URL) throws -> [String: Bool] {
        let budget = SceneVideoOwnedFile.DiskBudget(maximumBytes: 131_072)
        var first: SceneVideoOwnedFile.Writer? = try SceneVideoOwnedFile.makeWriter(
            cacheDirectory: base, expectedBytes: 65_536, diskBudget: budget)
        let reservedBeforeWrite = budget.reservedBytes == 65_536
        try first!.append(Data(repeating: 7, count: 65_536))
        var file: SceneVideoOwnedFile? = try first!.finish()
        first = nil
        let second = try SceneVideoOwnedFile.makeWriter(cacheDirectory: base, diskBudget: budget)
        try second.append(Data(repeating: 9, count: 65_536))
        let partialCharged = budget.reservedBytes == 131_072
        var rejected = false
        do { try second.append(Data([11])) }
        catch SceneVideoOwnedFile.Failure.aggregateDiskBudgetExceeded { rejected = true }
        let partialSize = (try fm.attributesOfItem(atPath: second.file.url.path)[.size] as! NSNumber).intValue
        second.abort()
        let partialRemovedWhileFileAlive = !fm.fileExists(atPath: second.file.url.path)
            && budget.reservedBytes == 65_536
        let path = file!.url.path
        var asset: AVURLAsset?
        autoreleasepool {
            asset = AVURLAsset(url: file!.url)
            file!.retainForLifetime(of: asset!)
            file = nil
        }
        let actualAssetKeepsReservation = fm.fileExists(atPath: path)
            && budget.reservedBytes == 65_536
        autoreleasepool { asset = nil }
        return ["knownBytesReservedBeforeWrite": reservedBeforeWrite,
            "publishedPlusPartialCharged": partialCharged,
            "wholeSegmentRejectedBeforeWrite": rejected && partialSize == 65_536,
            "partialRemovedBeforeFileObjectDies": partialRemovedWhileFileAlive,
            "actualAssetKeepsDiskReservation": actualAssetKeepsReservation,
            "lastAssetUnlinksAndReleases": !fm.fileExists(atPath: path) && budget.reservedBytes == 0]
    }

    static func failedWrites(_ base: URL) throws -> [String: Bool] {
        let budget = SceneVideoOwnedFile.DiskBudget(maximumBytes: 262_144)
        let writer = try SceneVideoOwnedFile.makeWriter(cacheDirectory: base,
            expectedBytes: 196_608, diskBudget: budget)
        var checks = 0
        var cancelled = false
        do {
            try writer.append(Data(repeating: 13, count: 196_608), checkCancellation: {
                checks += 1
                if checks == 3 { throw CancellationError() }
            })
        } catch is CancellationError { cancelled = true }
        let attributes = try fm.attributesOfItem(atPath: writer.file.url.path)
        let partial = (attributes[.size] as! NSNumber).intValue
        let chargedUntilWorkerAbort = budget.reservedBytes == 196_608 && partial == 65_536
        writer.abort()
        let released = budget.reservedBytes == 0 && !fm.fileExists(atPath: writer.file.url.path)
        var escaped = false
        do { try writer.append(Data([17])) }
        catch SceneVideoOwnedFile.Failure.io { escaped = true }
        return ["cancelErrorPreserved": cancelled,
            "partialKeepsReservationUntilWriterTerminal": chargedUntilWorkerAbort,
            "abortUnlinksAndReleases": released, "lateAppendCannotReopenOutput": escaped]
    }

    static func handleQuota(_ base: URL) throws -> [String: Bool] {
        let author = base.appendingPathComponent("author", isDirectory: true)
        try fm.createDirectory(at: author, withIntermediateDirectories: true)
        let url = author.appendingPathComponent("audio.wav")
        try Data(repeating: 23, count: 8_192).write(to: url)
        let root = SceneResourceView.Root(source: .loose, url: author)
        let handle = root.handle(relativePath: "audio.wav")!
        let cache = base.appendingPathComponent("cache", isDirectory: true)
        let budget = SceneVideoOwnedFile.DiskBudget(maximumBytes: 4_096)
        var rejected = false
        do {
            _ = try SceneVideoOwnedFile.snapshot(from: handle, cacheDirectory: cache,
                fileExtension: "wav", diskBudget: budget)
        } catch SceneVideoOwnedFile.Failure.aggregateDiskBudgetExceeded { rejected = true }
        var mp4Rejected = false
        do {
            _ = try SceneVideoOwnedFile.snapshot(payload: Data(repeating: 29, count: 8_192),
                cacheDirectory: cache, diskBudget: budget)
        } catch SceneVideoOwnedFile.Failure.aggregateDiskBudgetExceeded { mp4Rejected = true }
        return ["handleExactLengthRejectsBeforeOutputCreation": rejected && !fm.fileExists(atPath: cache.path),
            "mp4ExactLengthRejectsBeforeOutputCreation": mp4Rejected && !fm.fileExists(atPath: cache.path),
            "failedReservationDoesNotCharge": budget.reservedBytes == 0,
            "authorSourceUnchanged": try Data(contentsOf: url) == Data(repeating: 23, count: 8_192)]
    }

    static func soundQuota(_ base: URL) throws -> [String: Bool] {
        let author = base.appendingPathComponent("author", isDirectory: true)
        try fm.createDirectory(at: author, withIntermediateDirectories: true)
        for path in ["selected.wav", "later.wav"] {
            try Data(repeating: 31, count: 8_192).write(to: author.appendingPathComponent(path))
        }
        let view = SceneResourceView(projectRootURL: author, packageRootURL: nil, stockAssetsRootURL: nil)
        // This separate test process reserves capacity without writing 8 GiB.
        // Actual small-capacity accounting is exercised by the other modes.
        let blocker = try SceneVideoOwnedFile.makeWriter(cacheDirectory: base,
            expectedBytes: SceneVideoOwnedFile.DiskBudget.shared.maximumBytes)
        defer { blocker.abort() }
        let sound = SceneDocument.SceneSoundLayerDefinition(
            paths: ["selected.wav", "later.wav"], authoredPathCount: 2,
            playbackMode: "loop", startsSilent: false, muteInEditor: false,
            volume: 0, volumePropertyKey: nil, minimumTime: nil, maximumTime: nil,
            spatialization: nil, attenuation: nil, minimumDistance: nil)
        let plan = try SceneSoundPlaybackProgram.compile(
            document: .init(objects: [.init(id: 1, sound: sound)]), resourceView: view,
            privateCacheDirectory: base.appendingPathComponent("sound-cache"))
        let resource = plan.bindings.first?.resources.first
        return ["actualSoundCompileRetainsUnavailableSelectedSlot": plan.bindings.count == 1
            && plan.bindings[0].resources.count == 1 && resource?.file == nil,
            "quotaDoesNotSwitchAuthoredPath": resource?.displayPath.hasSuffix("selected.wav") == true,
            "quotaIsObservable": plan.diagnostics.contains { $0.reason == .resourceUnavailable },
            "noSoundOutputCreatedOnRejectedReservation": !fm.fileExists(atPath: base.appendingPathComponent("sound-cache").path)]
    }

    static func webm(_ base: URL, payload: Data, quota: Bool, cancel: Bool) async throws -> [String: Bool] {
        let parsed = try SceneWebMContainer.parse(payload)
        let budget = SceneVideoOwnedFile.DiskBudget(maximumBytes: quota ? 32 : 8 * 1_024 * 1_024)
        let writer = try SceneVideoOwnedFile.makeWriter(cacheDirectory: base, diskBudget: budget)
        let work = Task { try await SceneVideoPayloadPreparation.writeWebM(payload, to: writer) }
        if cancel { work.cancel() }
        do { try await work.value }
        catch SceneVideoOwnedFile.Failure.aggregateDiskBudgetExceeded {
            return ["actualSegmentQuotaErrorPreserved": quota,
                "failedNativeWorkerClearsPartialAndCharge": budget.reservedBytes == 0
                    && !fm.fileExists(atPath: writer.file.url.path)]
        } catch is CancellationError {
            return ["cancelledNativeWorkerPreservesCancellation": cancel,
                "cancelledWorkerClearsPartialAndCharge": budget.reservedBytes == 0
                    && !fm.fileExists(atPath: writer.file.url.path)]
        }
        guard !quota, !cancel else { return ["expectedNativeFailure": false] }
        let file = writer.file
        let count = (try fm.attributesOfItem(atPath: file.url.path)[.size] as! NSNumber).uint64Value
        let asset = AVURLAsset(url: file.url)
        let playable = try await asset.load(.isPlayable)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { return ["actualVideoTrack": false] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw reader.error! }
        var times: [Double] = []
        var imagesValid = true
        while let sample = output.copyNextSampleBuffer() {
            times.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)))
            imagesValid = imagesValid && CMSampleBufferGetImageBuffer(sample).map {
                CVPixelBufferGetWidth($0) == parsed.track.width
                    && CVPixelBufferGetHeight($0) == parsed.track.height
            } == true
        }
        let expectedTimes = parsed.packets.map { Double($0.presentationTimeNanoseconds) / 1e9 }
        let expectedDurations = parsed.packets.map { Double($0.durationNanoseconds) / 1e9 }
        let timesMatch = times.count == expectedTimes.count && zip(times, expectedTimes).allSatisfy { abs($0 - $1) < 0.000001 }
        // Decoded BGRA buffers need not expose encoded packet durations. Read
        // per-sample timing from the same track's compressed representation.
        let timingReader = try AVAssetReader(asset: asset)
        let timingOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        timingReader.add(timingOutput)
        guard timingReader.startReading() else { throw timingReader.error! }
        var durations: [Double] = []
        while let sample = timingOutput.copyNextSampleBuffer() {
            for index in 0..<CMSampleBufferGetNumSamples(sample) {
                var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
                guard CMSampleBufferGetSampleTimingInfo(sample, at: index, timingInfoOut: &timing) == noErr else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                durations.append(CMTimeGetSeconds(timing.duration))
            }
        }
        let assetDuration = CMTimeGetSeconds(try await asset.load(.duration))
        let expectedEnd = Double(parsed.packets.last!.presentationTimeNanoseconds
            + parsed.packets.last!.durationNanoseconds) / 1e9
        let durationsMatch = durations.count == expectedDurations.count
            && zip(durations, expectedDurations).allSatisfy { abs($0 - $1) < 0.000001 }
            && timingReader.status == .completed && abs(assetDuration - expectedEnd) < 0.000001
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var seeksMatch = true
        for index in [parsed.packets.count - 3, 5, parsed.packets.count / 2] {
            let target = CMTime(value: parsed.packets[index].presentationTimeNanoseconds, timescale: 1_000_000_000)
            let result = try await generator.image(at: target)
            seeksMatch = seeksMatch && result.image.width == parsed.track.width
                && result.image.height == parsed.track.height
                && abs(CMTimeGetSeconds(result.actualTime) - CMTimeGetSeconds(target)) < 0.000001
        }
        let encoded = try Data(contentsOf: file.url)
        let fragmentCount = encoded.indices.dropLast(3).filter {
            encoded[$0] == 0x6d && encoded[$0 + 1] == 0x6f && encoded[$0 + 2] == 0x6f && encoded[$0 + 3] == 0x66
        }.count
        return ["actualFragmentedVP9Playable": playable && fragmentCount >= 2,
            "allFramesDecodeThroughAVAssetReader": imagesValid && reader.status == .completed && timesMatch,
            "nanosecondPacketDurationsPreserved": durationsMatch,
            "reverseThenForwardExactNativeSeek": seeksMatch,
            "allActualOutputBytesCharged": count > 0 && budget.reservedBytes == count]
    }

    static func main() async throws {
        let mode = CommandLine.arguments[1]
        let base = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let facts: [String: Bool]
        switch mode {
        case "ledger": facts = try ledger(base)
        case "partial": facts = try failedWrites(base)
        case "handle": facts = try handleQuota(base)
        case "sound": facts = try soundQuota(base)
        default:
            let payload = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
            facts = try await webm(base, payload: payload, quota: mode == "quota", cancel: mode == "cancel")
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc") and shutil.which("ffmpeg"), "macOS Swift and ffmpeg required")
class SceneVideoSegmentMaterializationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-media-disk-segment-")
        cls.work = Path(cls.temporary.name)
        harness = cls.work / "Harness.swift"
        harness.write_text(HARNESS)
        carriers = cls.work / "SoundCarriers.swift"
        carriers.write_text(CARRIERS)
        cls.binary = cls.work / "probe"
        cls.proof = Path(os.environ["MWX_MEDIA_SEGMENT_PROOF"]) if os.environ.get("MWX_MEDIA_SEGMENT_PROOF") else None
        if cls.proof:
            cls.proof.mkdir(parents=True, exist_ok=True)
        delegate_arguments = compile_segment_delegate(cls.work,
            target="arm64-apple-macos26.0", evidence_directory=cls.proof)
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            "-strict-concurrency=complete", "-warnings-as-errors", "-default-isolation", "MainActor",
            "-target", "arm64-apple-macos26.0",
            *delegate_arguments, *map(str, SOURCES), str(carriers), str(harness), "-module-cache-path", str(cls.work / "module-cache"), "-o", str(cls.binary)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
        if cls.proof:
            (cls.proof / "compile.json").write_text(json.dumps({"argv": command, "exit": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr}, indent=2) + "\n")
        if result.returncode:
            cls.temporary.cleanup()
            raise AssertionError(result.stderr)
        cls.webm = cls.work / "vp9.webm"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            "testsrc2=size=320x180:rate=1000/17", "-frames:v", "130", "-c:v", "libvpx-vp9",
            "-g", "30", "-deadline", "realtime", "-cpu-used", "8", "-pix_fmt", "yuv420p", "-an", str(cls.webm)],
            check=True, capture_output=True, timeout=30)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_mode(self, mode):
        command = [str(self.binary), mode, str(self.work / mode), str(self.webm)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=20)
        if self.proof:
            (self.proof / f"{mode}.json").write_text(json.dumps({"argv": command, "exit": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr}, indent=2) + "\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        facts = json.loads(result.stdout)
        self.assertTrue(facts, result.stdout)
        self.assertTrue(all(facts.values()), facts)

    def test_published_partial_and_last_asset_share_one_disk_ledger(self):
        self.run_mode("ledger")

    def test_partial_cancellation_cleans_only_after_writer_terminal(self):
        self.run_mode("partial")

    def test_handle_and_mp4_known_length_reserve_before_output(self):
        self.run_mode("handle")

    def test_real_vp9_fragments_decode_preserve_timing_and_seek(self):
        self.run_mode("webm")

    def test_actual_sound_quota_preserves_selected_slot_and_local_failure(self):
        self.run_mode("sound")

    def test_actual_segment_output_rejects_quota_before_write(self):
        self.run_mode("quota")

    def test_cancelled_remux_cleans_partial_and_reservation(self):
        self.run_mode("cancel")


if __name__ == "__main__":
    unittest.main()
