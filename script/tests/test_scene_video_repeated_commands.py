"""Run real AVPlayer/Metal provider commands; publication envelopes are shims."""
from pathlib import Path
import hashlib
import json
import math
import os
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_initial_video_resource_readiness as readiness
from script.tests import test_scene_user_property_textures as textures
from script.tests.scene_vector_vm_test_support import (
    C_SOURCES, SWIFT_PREAMBLE, SWIFT_SOURCES, compile_vector_harness,
)
from script.tests.scene_video_segment_delegate_fixture import compile_segment_delegate

ROOT = Path(__file__).resolve().parents[2]
PROVIDERS = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers"
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


def compile_probe(work):
    delegate_arguments = compile_segment_delegate(work)
    readiness_source = readiness.write_readiness_source(work)
    script_types = (SCENE / "Systems/Script/SceneScriptLayerHandleBridge.swift").read_text()
    carriers = "\n".join(readiness.declaration(script_types, f"nonisolated struct {name}:") for name in (
        "SceneScriptVideoPlaybackSnapshot", "SceneScriptMediaPlaybackCommand"))
    readiness_source.write_text("import Foundation\n" + readiness_source.read_text() + "\n" + carriers + "\n")
    compiled = subprocess.run([
        "swiftc", "-parse-as-library", "-default-isolation", "MainActor",
        "-swift-version", "5", *delegate_arguments,
        str(PROVIDERS / "SceneVideoProviderLifecycleState.swift"),
        str(SCENE / "Format/SceneWebMContainer.swift"),
        str(PROVIDERS / "SceneVideoPayloadPreparation.swift"),
        str(SCENE / "Resources/Assets/SceneResourceIndex.swift"),
        str(SCENE / "../SteamWorkshopStorage/ScenePlaybackSource.swift"), str(SCENE / "Format/ScenePkgReader.swift"),
        str(SCENE / "Resources/Assets/SceneResourceIdentity.swift"), str(SCENE / "Resources/Assets/SceneResourceView+Backing.swift"),
        str(SCENE / "Resources/Assets/SceneResourceView.swift"),
        str(PROVIDERS / "SceneVideoOwnedFile.swift"),
        str(SCENE / "Resources/Textures/SceneResourceBudget.swift"),
        str(PROVIDERS / "SceneVideoTextureSource.swift"),
        str(readiness_source),
        str(ROOT / "script/tests/fixtures/SceneVideoRepeatedCommandsHarness.swift"),
        "-module-cache-path", str(work / "module-cache"),
        "-o", str(work / "probe")
    ], capture_output=True, text=True, timeout=120)
    if compiled.returncode:
        raise RuntimeError(compiled.stderr)

class SceneVideoRepeatedCommandsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if any(not shutil.which(tool) for tool in ("swiftc", "ffmpeg")):
            raise unittest.SkipTest("Swift and ffmpeg are required for real AVPlayer/Metal evidence")
        cls.probe_directory = tempfile.TemporaryDirectory(prefix="mwx-video-shared-probe-")
        cls.probe = Path(cls.probe_directory.name) / "probe"
        try:
            compile_probe(cls.probe.parent)
        except BaseException:
            cls.probe_directory.cleanup()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.probe_directory.cleanup()

    def test_playing_seek_first_pixels_and_discarded_retry_match_latest_target(self):
        if not shutil.which("swiftc") or not shutil.which("ffmpeg"):
            self.skipTest("Swift and ffmpeg are required for real seek pixel evidence")
        with tempfile.TemporaryDirectory(prefix="mwx-video-seek-pixels-") as tmp:
            work = Path(tmp)
            subprocess.run([
                "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "color=c=red:s=320x180:r=30:d=4", "-f", "lavfi", "-i",
                "color=c=blue:s=320x180:r=30:d=6", "-filter_complex",
                "[0:v][1:v]concat=n=2:v=1:a=0[v]", "-map", "[v]", "-an",
                "-c:v", "libx264", "-g", "300", "-keyint_min", "300",
                "-sc_threshold", "0", "-pix_fmt", "yuv420p", str(work / "clip.mp4")
            ], check=True, capture_output=True, timeout=30)
            for second, expected in ((0.5, "red"), (6.5, "blue")):
                pixel = subprocess.run([
                    "ffmpeg", "-v", "error", "-ss", str(second), "-i",
                    str(work / "clip.mp4"), "-frames:v", "1", "-vf", "scale=1:1",
                    "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"
                ], check=True, capture_output=True, timeout=10).stdout
                self.assertEqual(len(pixel), 3)
                channel = 0 if expected == "red" else 2
                self.assertGreater(pixel[channel], 127)
                self.assertTrue(all(value < 127 for i, value in enumerate(pixel) if i != channel))
            (work / "probe").symlink_to(self.probe)
            expected = [("seek6", "blue"), ("seek2", "red"),
                        ("same-inflight6", "blue"), ("repeat-until-ready6", "blue"),
                        ("latest6-2-6", "blue"),
                        ("discard-before", "blue"), ("discard-after", "blue"),
                        ("ordinary-drop", "red"), ("paused-discard-after", "blue")]
            for name, color in expected:
                with self.subTest(case=name):
                    completed = subprocess.run([
                        str(work / "probe"), str(work), "--seek-pixels", name
                    ], capture_output=True, text=True, timeout=12)
                    self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
                    result = json.loads(completed.stdout)
                    self.assertEqual(result["controls"], [[0, 0, 0], [255, 255, 255]])
                    self.assertGreater(result["initialRGB"][0], 127)
                    self.assertTrue(all(v < 127 for v in result["initialRGB"][1:]))
                    if name == "seek2":
                        setup = result["setupSeek6"]["firstTexture"]["centerMeanRGB"]
                        self.assertGreater(setup[2], 127)
                        self.assertTrue(all(v < 127 for v in setup[:2]))
                    row = result["row"]
                    self.assertEqual(row["case"], name)
                    self.assertEqual(row["firstCandidateGeneration"], row["baselineGeneration"] + 1)
                    self.assertEqual(row["candidateGeneration"], row["baselineGeneration"] + 1)
                    self.assertEqual(row["publishedBeforeCommit"], row["baselineGeneration"])
                    self.assertEqual(row["publishedAfterCommit"], row["candidateGeneration"])
                    self.assertTrue(row["heldTextureBeforeCommit"])
                    self.assertTrue(row["committedCandidateTexture"])
                    self.assertEqual(row["candidateSize"], [320, 180])
                    rgb = row["firstTexture"]["centerMeanRGB"]
                    channel = 0 if color == "red" else 2
                    self.assertGreater(rgb[channel], 127)
                    self.assertTrue(all(value < 127 for i, value in enumerate(rgb) if i != channel))
                    if name == "ordinary-drop":
                        self.assertEqual(row["commands"], [])
                        self.assertGreater(row["rateImmediatelyAfterDiscard"], 0)
                        self.assertEqual(row["publishedAfterDiscard"], row["baselineGeneration"])
                        self.assertEqual(row["publishedAfterIdle"], row["baselineGeneration"])
                        self.assertTrue(row["heldTextureAfterDiscard"])
                        self.assertTrue(row["heldTextureAfterIdle"])
                        self.assertGreaterEqual(row["idleElapsed"], 0.19)
                        self.assertGreater(row["backendAfterIdle"] - row["backendBeforeIdle"], 0.1)
                        self.assertGreater(row["typedAfterIdle"] - row["typedBeforeIdle"], 0.1)
                    else:
                        self.assertGreaterEqual(row["requested"], row["target"] - 0.001)
                        self.assertLess(row["requested"], row["target"] + 2)
                    if name in ("discard-before", "discard-after", "paused-discard-after", "same-inflight6"):
                        self.assertEqual(set(row["retryFrameIndices"]), {row["retryFrameIndex"]})
                        self.assertGreaterEqual(len(row["retryFrameIndices"]), 2)
                        self.assertEqual(row["publishedAfterDiscard"], row["baselineGeneration"])
                        self.assertTrue(row["heldTextureAfterDiscard"])
                    if name == "same-inflight6" and row["earlyCandidateTexture"] is not None:
                        early = row["earlyCandidateTexture"]["centerMeanRGB"]
                        self.assertGreater(early[2], 127)
                        self.assertTrue(all(v < 127 for v in early[:2]))
                    if name in ("discard-after", "paused-discard-after"):
                        retried = row["retryTexture"]["centerMeanRGB"]
                        self.assertGreater(retried[2], 127)
                        self.assertTrue(all(v < 127 for v in retried[:2]))
                        self.assertTrue(row["retrySameTexture"])
                        self.assertEqual(row["discardPhase"], "ready-candidate-not-callback")
                    if name == "paused-discard-after":
                        self.assertFalse(row["playingAfterRetry"])
                        self.assertEqual(row["rateAfterRetry"], 0)
                        self.assertAlmostEqual(row["heldTimeBeforeDiscard"], 6, places=6)
                        self.assertAlmostEqual(row["heldTimeAfterRetry"], 6, places=6)
                    if name == "latest6-2-6":
                        self.assertEqual(row["commands"], [6, 2, 6])
                    if name == "repeat-until-ready6":
                        self.assertEqual(row["repeatedSeekCommands"], len(row["retryFrameIndices"]))
                        self.assertGreaterEqual(row["repeatedSeekCommands"], 2)
            # Reuse the same compiled provider; only replace its owned input clip.
            subprocess.run([
                "ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                "color=c=red:s=320x180:r=30:d=2", "-an", "-c:v", "libx264",
                "-pix_fmt", "yuv420p", str(work / "clip.mp4")
            ], check=True, capture_output=True, timeout=30)
            for looping in (True, False):
                with self.subTest(drop_before_natural_end=True, looping=looping):
                    args = [str(work / "probe"), str(work), "--eof-discard", "--drop-before-end"]
                    if not looping:
                        args.append("--no-loop")
                    completed = subprocess.run(args, capture_output=True, text=True, timeout=8)
                    self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
                    row = json.loads(completed.stdout)
                    self.assertGreater(row["before"], 0)
                    self.assertEqual(row["afterDiscard"], row["before"])
                    self.assertEqual(row["afterIdle"], row["before"])
                    self.assertTrue(row["heldTextureAfterIdle"])
                    self.assertGreater(row["timeAtDrop"], 0.5)
                    self.assertLess(row["timeAtDrop"], row["duration"] - 0.05)
                    self.assertGreater(row["rateImmediatelyAfterDiscard"], 0)
                    self.assertEqual(row["endsBefore"], 0)
                    self.assertEqual(row["rawEndCount"], 1)
                    self.assertEqual(row["endedAfterIdle"], 1)
                    self.assertEqual(row["playingAfterIdle"], looping)

    def test_repeated_commands_preserve_playback_and_real_transitions_work(self):
        if not shutil.which("swiftc") or not shutil.which("ffmpeg"):
            self.skipTest("Swift and ffmpeg are required for real AVPlayer evidence")
        with tempfile.TemporaryDirectory(prefix="mwx-video-repeat-") as tmp:
            work = Path(tmp)
            subprocess.run([
                "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=size=320x180:rate=30:duration=12", "-c:v", "libx264",
                "-pix_fmt", "yuv420p", str(work / "clip.mp4")
            ], check=True, capture_output=True, timeout=30)
            (work / "probe").symlink_to(self.probe)
            run = subprocess.run([str(work / "probe"), str(work)],
                                 check=True, capture_output=True, text=True, timeout=30)
            result = json.loads(run.stdout)
            self.assertEqual(result["beforeRate"], 1)
            self.assertEqual(result["afterRepeatedPlayRate"], 1,
                             "play while playing must not pause AVPlayer")
            self.assertEqual(result["afterUnchangedRate"], 1,
                             "an unchanged playback rate must not pause AVPlayer")
            self.assertGreater(result["repeatedPlayFrames"], 10)
            # These are provider plan timestamps, not decoded presentation timestamps.
            times = result["repeatedPlayTimes"]
            self.assertGreater(times[-1] - times[0], 1)
            self.assertTrue(all(b > a for a, b in zip(times, times[1:])))
            decoded = result["repeatedDecodedTimes"]
            self.assertGreater(len(decoded), 20)
            # AVPlayer returns display deadlines, not compressed-source PTS.
            self.assertTrue(all(math.isfinite(t) for t in decoded))
            self.assertTrue(all(b > a for a, b in zip(decoded, decoded[1:])))
            self.assertGreater(decoded[-1] - decoded[0], 1)
            self.assertTrue(result["sharedFrameProjectsConsumerIdentity"])
            self.assertTrue(result["pauseHeld"])
            self.assertGreater(result["resumedFrames"], 3)
            self.assertGreater(result["seekFrames"], 3)
            self.assertGreater(result["seekLast"], 0.5)
            self.assertLess(result["seekLast"], 1.2)
            self.assertEqual(result["changedRate"], 2)
            self.assertEqual(result["recoveredRate"], 2)
            self.assertGreater(result["recoveredFrames"], 3)
            self.assertEqual(result["retryRate"], 2)
            self.assertGreater(result["retriedFrames"], 3)
            self.assertGreater(result["fasterTimes"][-1] - result["fasterTimes"][1], 0.4)

    def test_paused_seek_publishes_completed_target_and_ignores_obsolete_completion(self):
        with tempfile.TemporaryDirectory(prefix="mwx-video-paused-seek-") as tmp:
            work = Path(tmp)
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=size=320x180:rate=30:duration=10", "-c:v", "libx264",
                "-pix_fmt", "yuv420p", str(work / "clip.mp4")], check=True, capture_output=True)
            (work / "probe").symlink_to(self.probe)
            run = subprocess.run([str(work / "probe"), str(work), "--paused-seek"],
                check=True, capture_output=True, text=True, timeout=20)
            result = json.loads(run.stdout)
            for phase, target in [("paused", 6), ("replaced", 2), ("stopped", 0)]:
                self.assertTrue(result[phase], phase)
                for requested, decoded in result[phase]:
                    self.assertAlmostEqual(requested, target, places=3)
                    self.assertAlmostEqual(decoded, target, delta=1 / 30)
            self.assertEqual(result["held"], [])
            for phase, target in [("loopOff", result["duration"]), ("loopOn", 0)]:
                self.assertTrue(result[phase], phase)
                for requested, decoded in result[phase]:
                    self.assertAlmostEqual(requested, target, places=3)
                    self.assertAlmostEqual(decoded, target, delta=1 / 30 + 0.001)

    def test_actual_loop_requests_preserve_scene_clock_phase(self):
        if not shutil.which("swiftc") or not shutil.which("ffmpeg"):
            self.skipTest("Swift and ffmpeg are required for real AVPlayer evidence")
        with tempfile.TemporaryDirectory(prefix="mwx-video-loop-phase-") as tmp:
            work = Path(tmp)
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=size=320x180:rate=30:duration=2", "-c:v", "libx264",
                "-pix_fmt", "yuv420p", str(work / "clip.mp4")],
                check=True, capture_output=True, timeout=30)
            (work / "probe").symlink_to(self.probe)
            run = subprocess.run([str(work / "probe"), str(work), "--loop-phase"],
                check=True, capture_output=True, text=True, timeout=20)
            result = json.loads(run.stdout)
            rows = result["rows"]
            self.assertGreaterEqual(result["ends"], 3)
            self.assertGreater(len(rows), 150)
            duration = result["duration"]
            self.assertGreater(result["requestTimescale"], 0)
            errors = [abs((requested - scene % duration + duration / 2)
                          % duration - duration / 2)
                      for scene, requested, decoded in rows]
            self.assertLess(max(errors), 1.01 / result["requestTimescale"],
                            "EOF must not replace the scene clock origin")
            wraps = sum(b[2] < a[2] for a, b in zip(rows, rows[1:]))
            self.assertGreaterEqual(wraps, 3)

    def test_confirmed_end_survives_frame_discard_and_retry(self):
        if not shutil.which("swiftc") or not shutil.which("ffmpeg"):
            self.skipTest("Swift and ffmpeg are required for real AVPlayer evidence")
        with tempfile.TemporaryDirectory(prefix="mwx-video-eof-discard-") as tmp:
            work = Path(tmp)
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=size=320x180:rate=30:duration=2", "-c:v", "libx264",
                "-pix_fmt", "yuv420p", str(work / "clip.mp4")],
                check=True, capture_output=True, timeout=30)
            (work / "probe").symlink_to(self.probe)
            for looping in (True, False):
                with self.subTest(looping=looping):
                    args = [str(work / "probe"), str(work), "--eof-discard"]
                    if not looping:
                        args.append("--no-loop")
                    run = subprocess.run(args, check=True, capture_output=True, text=True, timeout=15)
                    result = json.loads(run.stdout)
                    self.assertGreater(result["before"], 0)
                    self.assertEqual(result["afterDiscard"], result["before"])
                    self.assertLessEqual(result["afterRetry"], result["before"] + 1)
                    self.assertEqual(result["endsBefore"], 1)
                    self.assertEqual(result["endsAfter"], 1)
                    self.assertEqual(result["finalEnds"], 1)
                    if looping:
                        self.assertTrue(result["playing"])
                        self.assertTrue(result["finalPlaying"])
                        self.assertAlmostEqual(result["time"], result["scene"] - 2, places=6)
                        rows = result["rows"]
                        self.assertGreater(len(rows), 5)
                        self.assertLess(max(abs(requested - (scene - 2))
                            for scene, requested, decoded, generation in rows), 0.00101)
                        self.assertGreater(rows[-1][2], rows[0][2])
                        self.assertLess(rows[-1][2], 1.5)
                        generations = [result["afterRetry"]] + [r[3] for r in rows]
                        self.assertTrue(all(b == a + 1 for a, b in zip(generations, generations[1:])))
                    else:
                        self.assertFalse(result["playing"])
                        self.assertFalse(result["finalPlaying"])
                        self.assertAlmostEqual(result["time"], 2)
                        self.assertAlmostEqual(result["finalTime"], 2)

    def test_webm_preparation_uses_real_player_frames_and_stop_cancels_publication(self):
        if any(not shutil.which(tool) for tool in ("swiftc", "ffmpeg")):
            self.skipTest("Swift and ffmpeg are required for real WebM evidence")
        with tempfile.TemporaryDirectory(prefix="mwx-video-webm-") as tmp:
            work = Path(tmp)
            subprocess.run([
                "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=size=320x180:rate=30:duration=2", "-c:v", "libvpx-vp9",
                "-deadline", "realtime", "-cpu-used", "8", "-g", "30",
                "-pix_fmt", "yuv420p", str(work / "clip.webm")
            ], check=True, capture_output=True, timeout=30)
            (work / "probe").symlink_to(self.probe)
            result = json.loads(subprocess.run(
                [str(work / "probe"), str(work), "--webm"],
                check=True, capture_output=True, text=True, timeout=20).stdout)
            self.assertTrue(result["initialItemPending"])
            self.assertTrue(result["metadataPendingBeforeInstall"])
            self.assertTrue(result["snapshotAbsentBeforeInstall"])
            self.assertTrue(result["metadataReadyAtFirstPublication"])
            self.assertTrue(result["pendingCommandsHeld"])
            self.assertTrue(result["preparedFilePresent"])
            self.assertAlmostEqual(result["duration"], 2, delta=0.002)
            self.assertTrue(result["initialRows"])
            self.assertAlmostEqual(result["initialRows"][0][1], 0.7, delta=1 / 30)
            self.assertGreater(len(result["playingRows"]), 5)
            self.assertTrue(result["pauseHeld"])
            self.assertEqual(result["pausedRefreshRows"], [])
            self.assertTrue(result["seekRows"])
            self.assertTrue(all(abs(row[1] - 0.3) < 1 / 30 for row in result["seekRows"]))
            self.assertGreaterEqual(result["ends"], 2)
            self.assertGreaterEqual(result["displayWraps"], 2)
            rows = sum((result[phase] for phase in
                        ("initialRows", "playingRows", "seekRows", "loopRows")), [])
            self.assertGreater(len(rows), 50)
            self.assertTrue(all(row[3:6] == [320, 180, True] for row in rows))
            self.assertLess(result["firstTexture"]["rgbRange"][0],
                            result["firstTexture"]["rgbRange"][1])
            self.assertNotEqual(result["firstTexture"]["sha256"],
                                result["playingTexture"]["sha256"])
            # itemTimeForDisplay is a display deadline, not source packet PTS.
            # Every acquired buffer counts, including those around seek/EOF.
            loop_spans = [[]]
            previous_display = None
            for row in result["loopRows"]:
                if previous_display is not None and row[1] < previous_display:
                    loop_spans.append([])
                previous_display = row[1]
                loop_spans[-1].append(row)
            self.assertGreaterEqual(sum(len(span) >= 5 for span in loop_spans), 2,
                                    "publication must continue across display timeline wraps")
            generations = [row[2] for row in rows]
            self.assertTrue(all(b == a + 1 for a, b in zip(generations, generations[1:])))
            self.assertTrue(result["stoppedFrameAbsent"])
            self.assertTrue(result["stoppedItemAbsent"])
            self.assertTrue(result["filesAfterStop"], "the explicitly borrowed asset must pin its payload")
            self.assertTrue(result["stoppedSourceAliveAtReleaseCheck"])
            self.assertTrue(result["stoppedAssetReleased"])
            self.assertTrue(result["stoppedOwnedFileReleased"])
            self.assertTrue(result["stoppedPayloadAbsent"])
            self.assertEqual(result["filesAfterBorrowerRelease"], [])
            self.assertTrue(result["cancelStartedPending"])
            self.assertTrue(result["cancelLateFrameAbsent"])
            self.assertTrue(result["cancelLateItemAbsent"])
            self.assertEqual(result["cancelFilesAfterSettle"], [])

METADATA_VM = r'''
import AVFoundation
import Metal
import QuartzCore

@main @MainActor enum MetadataVM {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let empty = SceneVideoTextureSourceRegistry(epoch: 1)
        let emptyPending = empty.pendingSceneScriptMetadataSources.isEmpty
        empty.completeSceneScriptMetadataPreparation()
        let noVideo = empty.sceneScriptSnapshots(sceneTime: 0)
        empty.stop()
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
        var rows: [[String: Any]] = []
        for (index, names) in [("clip.mp4", "primary-video"), ("renamed.mp4", "another video")].enumerated() {
            rows.append(try await exercise(root, device, filename: names.0, name: names.1,
                layerID: 17 + index * 301, model: "models/carrier-\(index)"))
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: [
            "emptyRegistryHasNoPreparation": emptyPending && noVideo.sources.isEmpty && noVideo.layerBindings.isEmpty,
            "rows": rows,
        ], options: [.sortedKeys]), as: UTF8.self))
    }

    static func exercise(_ root: URL, _ device: MTLDevice, filename: String,
                         name: String, layerID: Int, model: String) async throws -> [String: Any] {
        let registry = SceneVideoTextureSourceRegistry(epoch: 40)
        defer { registry.stop() }
        let cache = root.appendingPathComponent("cache-\(layerID)")
        let goodInput = SceneResourceView.FileInput.externalFile(root.appendingPathComponent(filename))
        let badInput = SceneResourceView.FileInput.externalFile(root.appendingPathComponent("invalid.mp4"))
        let goodKey = try goodInput.currentIdentity(), badKey = try badInput.currentIdentity()
        let goodFile = try SceneVideoOwnedFile.snapshot(payload: Data(contentsOf: root.appendingPathComponent(filename)), cacheDirectory: cache)
        let badFile = try SceneVideoOwnedFile.snapshot(payload: Data(contentsOf: root.appendingPathComponent("invalid.mp4")), cacheDirectory: cache)
        // The failed row precedes the healthy one, so the real C publication
        // must accept an unbound unavailable slot without losing its peer.
        let badID = layerID + 1
        guard let bad = try registry.source(sourceKey: badKey, preparedFile: badFile,
                owner: .ordinary, layerID: badID, device: device),
              let good = try registry.source(sourceKey: goodKey, preparedFile: goodFile,
                owner: .ordinary, layerID: layerID, device: device) else { fatalError("Source construction failed") }
        let resources: [String: ScenePreparedDynamicImageResource] = [
            model: .init(product: .video(source: goodKey, file: goodFile, sizeWH: [32, 24])),
            model + "-bad": .init(product: .video(source: badKey, file: badFile, sizeWH: [32, 24])),
        ]
        try registry.prepareDynamicVideoSources(resources: resources, modelPaths: Set(resources.keys), device: device)
        let pending = registry.pendingSceneScriptMetadataSources
        let unpublished = registry.sceneScriptSnapshots(sceneTime: 0).sources.compactMap { $0 }.isEmpty
        for source in pending { _ = await source.preparePlaybackMetadata() }
        registry.completeSceneScriptMetadataPreparation()
        registry.bindPreparedVideoConsumers([layerID: model, badID: model + "-bad"])
        let snapshot = registry.sceneScriptSnapshots(sceneTime: 0)
        guard let index = snapshot.layerBindings[layerID], let prepared = snapshot.sources[index] else {
            fatalError("healthy metadata unavailable")
        }
        let again = try registry.source(sourceKey: badKey, preparedFile: badFile,
            owner: .ordinary, layerID: badID, device: device)
        let terminalBadReused = again === bad && !bad.isPreparingItem && !bad.hasPlaybackMetadata

        let source = """
        let initialDuration = -1;
        let end = -1;
        export function init(value) {
            const video = thisScene.getLayer("\(name)").getVideoTexture();
            initialDuration = video.duration;
            end = video.duration;
            video.loop = false;
            video.setCurrentTime(end / 4);
            return value;
        }
        export function update(value) {
            const video = thisScene.getLayer("\(name)").getVideoTexture();
            if (video.getCurrentTime() >= end) video.stop();
            else video.play();
            return new Vec3(initialDuration, video.duration, video.getCurrentTime());
        }
        """
        let badSource = "export function update(value) { return new Vec3(thisLayer.getVideoTexture().duration, 0, 0); }"
        let descriptor = SceneRenderDescriptor(layers: [layerID, badID].enumerated().map { i, id in
            .init(id: id, layerIndex: i, name: i == 0 ? name : "unavailable-\(name)", visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: [])
        })
        let bindings = [source, badSource].enumerated().map { i, text in
            SceneScriptBindingIR(source: text,
                owner: .init(kind: .object, objectIndex: i, objectID: i == 0 ? layerID : badID,
                    effectIndex: nil, effectID: nil, passIndex: nil, passID: nil),
                targetPath: [.key("objects"), .index(i), .key("origin")], properties: [:],
                authoredValue: .string("0 0 0"), valueType: .string, wrapperKeys: ["script", "value"])
        }
        let target = SceneDynamicTarget.layer(layerID: layerID, field: .origin)
        let badTarget = SceneDynamicTarget.layer(layerID: badID, field: .origin)
        let domain = try SceneScriptQuickJSDomain()
        try domain.configureLayerCatalog(descriptor)
        let program = SceneScriptVectorProgram.compile(domain: domain, descriptor: descriptor,
            scriptBindings: bindings, userPropertyDefinitions: [], generation: 1)
        let clock = CACurrentMediaTime()
        var frame: UInt64 = 0
        func timing(_ scene: Double) -> SceneFrameTiming {
            frame += 1
            return .init(wallDate: Date(timeIntervalSince1970: 0), simulationFrameTime: 1 / 60,
                sceneTime: scene, frameIndex: frame, hostTime: CACurrentMediaTime())
        }
        func evaluate(_ videos: SceneScriptVideoFrameSnapshot, _ time: SceneFrameTiming) throws -> SceneScriptVectorFrameResult {
            try domain.publishLayerSnapshot(SceneDynamicSnapshotResolver().resolve(
                frameIndex: time.frameIndex, generation: time.frameIndex, definitions: []).snapshot,
                descriptor: descriptor, videoSnapshots: videos)
            return program.evaluate(inputs: [target: .vector3(0, 0, 0), badTarget: .vector3(0, 0, 0)],
                effectivePropertyValues: [:], frame: .init(timing: time))
        }
        func ordered(_ result: SceneScriptVectorFrameResult) -> [SceneScriptMediaPlaybackCommand] {
            SceneScriptMediaPlaybackCommandBridge.orderedCommands(in: result.ownerEffects)
        }
        func commit(_ result: SceneScriptVectorFrameResult, _ time: SceneFrameTiming) throws {
            let commands = ordered(result)
            try registry.validate(commands, timing: time).get()
            for command in commands { registry.applyAdmitted(command, timing: time) }
            program.finalizeLayerMutations(committing: true, rejectedOwnerTargets: Set(result.failures.keys))
        }
        func vector(_ result: SceneScriptVectorFrameResult) -> [Double] {
            if case let .vector3(x, y, z)? = result.values[target] { return [x, y, z] }
            return []
        }
        let firstTime = timing(0), first = try evaluate(snapshot, firstTime)
        let firstCommands = ordered(first)
        let seeks = firstCommands.compactMap { command -> Double? in
            if case let .setCurrentTime(value) = command.action { return value }; return nil
        }
        try commit(first, firstTime)
        let afterSeek = good.playbackSnapshot(sceneTime: 0)!
        registry.beginSurfaceRebuild(sceneTime: 0, hostTime: CACurrentMediaTime())
        try registry.prepareDynamicVideoSources(resources: resources, modelPaths: Set(resources.keys), device: device)
        registry.bindPreparedVideoConsumers([layerID: model, badID: model + "-bad"])
        let rebuilt = try registry.source(sourceKey: goodKey, preparedFile: goodFile,
            owner: .ordinary, layerID: layerID, device: device)
        registry.completeSurfaceRebuild()
        let reused = rebuilt === good && registry.pendingSceneScriptMetadataSources.isEmpty
            && good.hasPlaybackMetadata && registry.preparedVideoSourceReferences[model] == index
        let secondTime = timing(0.01)
        let second = try evaluate(registry.sceneScriptSnapshots(sceneTime: 0.01), secondTime)
        try commit(second, secondTime)

        let deadline = CACurrentMediaTime() + 5
        while good.playbackSnapshot(sceneTime: CACurrentMediaTime() - clock)!.endedGeneration == 0,
              CACurrentMediaTime() < deadline {
            _ = good.currentFrame(for: timing(CACurrentMediaTime() - clock))
            try await Task.sleep(for: .milliseconds(8))
        }
        let eofTime = timing(CACurrentMediaTime() - clock)
        let eofSnapshot = good.playbackSnapshot(sceneTime: eofTime.sceneTime)!
        let eof = try evaluate(registry.sceneScriptSnapshots(sceneTime: eofTime.sceneTime), eofTime)
        let eofCommands = ordered(eof)
        try commit(eof, eofTime)

        guard let cancelled = SceneVideoTextureSource(owner: .ordinary, preparedFile: goodFile, device: device),
              let shared = SceneVideoTextureSource(owner: .ordinary, preparedFile: goodFile, device: device) else {
            fatalError("cancellation Source unavailable")
        }
        let cancellationStartedPending = cancelled.isPreparingItem && cancelled.playbackSnapshot(sceneTime: 0) == nil
        cancelled.stop()
        let cancelledReady = await cancelled.preparePlaybackMetadata()
        let waiter = Task { await shared.preparePlaybackMetadata() }
        waiter.cancel()
        _ = await waiter.value
        let sharedReady = await shared.preparePlaybackMetadata()
        try await Task.sleep(for: .milliseconds(20))
        let player = Mirror(reflecting: cancelled).children.compactMap { $0.value as? AVPlayer }.first!
        let cancelledStayedUnavailable = !cancelledReady && !cancelled.hasPlaybackMetadata
            && !cancelled.isPreparingItem && cancelled.playbackSnapshot(sceneTime: 0) == nil && player.currentItem == nil
        shared.stop()
        return [
            "name": name, "layerID": layerID, "duration": prepared.duration,
            "pendingSources": pending.count, "noUnpreparedNumericSnapshot": unpublished,
            "pendingAfterPreparation": registry.pendingSceneScriptMetadataSources.count,
            "failedSnapshotAbsent": bad.playbackSnapshot(sceneTime: 0) == nil,
            "failedBindingAbsent": snapshot.layerBindings[badID] == nil,
            "unavailableRowRetained": snapshot.sources.contains { $0 == nil },
            "failedPreparedReferenceAbsent": registry.preparedVideoSourceReferences[model + "-bad"] == nil,
            "failedSourceReusedWithoutRetry": terminalBadReused,
            "initialVector": vector(first), "firstSeekCommands": seeks,
            "healthyFailure": first.failures[target]?.code ?? "none",
            "failedOwnerFailure": first.failures[badTarget]?.code ?? "none",
            "firstStopCommands": firstCommands.filter { $0.action == .stop }.count,
            "seekPosition": afterSeek.currentTime, "sourceReusedAcrossRebuild": reused,
            "secondVector": vector(second), "rebuildSeekCommands": ordered(second).filter {
                if case .setCurrentTime = $0.action { return true }; return false
            }.count,
            "realEOFGeneration": eofSnapshot.endedGeneration, "eofPosition": eofSnapshot.currentTime,
            "eofStopCommands": eofCommands.filter { $0.action == .stop }.count,
            "cancellationStartedPending": cancellationStartedPending,
            "cancelledSourceCannotPublishLate": cancelledStayedUnavailable,
            "cancelledWaiterKeepsSharedPreparation": waiter.isCancelled && sharedReady,
        ]
    }
}
'''


class SceneVideoScriptMetadataTests(unittest.TestCase):
    def test_real_source_registry_metadata_reaches_first_vm_callbacks_and_isolates_failure(self):
        if any(not shutil.which(tool) for tool in ("swiftc", "ffmpeg")):
            self.skipTest("Swift and ffmpeg are required")
        evidence = Path(os.environ["MWX_VIDEO_METADATA_EVIDENCE"]) if os.environ.get("MWX_VIDEO_METADATA_EVIDENCE") else None
        if evidence:
            evidence.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="mwx-video-metadata-vm-") as tmp:
            work = Path(tmp)
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=size=32x24:rate=20:duration=1.2", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                str(work / "clip.mp4")], check=True, capture_output=True, timeout=30)
            shutil.copyfile(work / "clip.mp4", work / "renamed.mp4")
            (work / "invalid.mp4").write_bytes(b"not a media container")
            delegate = compile_segment_delegate(work, evidence_directory=evidence)
            header = work / "VideoAndVM.h"
            header.write_text(f'#include "{SCENE / "Systems/Script/SceneQuickJS.h"}"\n#include "{delegate[1]}"\n')
            product_input = SCENE / "Runtime/Session/ScenePreparedDeviceResources.swift"
            product = readiness.declaration(product_input.read_text(), "    nonisolated enum Product {")
            carrier = work / "VideoMetadataCarriers.swift"
            carrier.write_text("import Foundation\nstruct ScenePreparedDynamicImageResource {\n" + product
                + "\nlet product: Product\n}\n" + readiness.write_readiness_source(work).read_text())
            timing = readiness.declaration(SWIFT_PREAMBLE, "struct SceneFrameTiming {")
            preamble = SWIFT_PREAMBLE.replace(timing, timing.replace("\n}",
                "\n    var frameIndex: UInt64 = 0\n    var hostTime: Double = 0\n}"))
            extras = tuple(dict.fromkeys([*textures.SWIFT_SOURCES,
                PROVIDERS / "SceneVideoProviderLifecycleState.swift", PROVIDERS / "SceneVideoTextureSource.swift",
                PROVIDERS / "SceneVideoTextureSourceRegistry.swift", carrier]))
            inputs = list(dict.fromkeys([*SWIFT_SOURCES, *C_SOURCES, *extras, product_input,
                SCENE / "Systems/Script/SceneQuickJS.h", Path(delegate[1]),
                PROVIDERS / "SceneVideoSegmentDelegate.m", Path(__file__),
                Path(compile_vector_harness.__code__.co_filename), Path(textures.__file__), Path(readiness.__file__),
                Path(compile_segment_delegate.__code__.co_filename)]))
            hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
            if evidence:
                (evidence / "inputs-before.json").write_text(json.dumps(hashes, indent=2) + "\n")
            try:
                binary = compile_vector_harness(work, METADATA_VM, "video-metadata-vm",
                    extra_swift_sources=extras, preamble=preamble, whole_module_optimization=True,
                    bridging_header=header, extra_link_objects=(Path(delegate[2]),))
            except BaseException as error:
                if evidence:
                    (evidence / "compile-failure.txt").write_text(str(error))
                raise
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=20)
            if evidence:
                (evidence / "stdout.json").write_text(run.stdout)
                (evidence / "stderr.txt").write_text(run.stderr)
                (evidence / "generated-inputs.json").write_text(json.dumps({
                    str(p.name): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in (header, Path(delegate[2]), binary, work / "clip.mp4", work / "renamed.mp4")
                }, indent=2) + "\n")
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            result = json.loads(run.stdout)
            self.assertTrue(result["emptyRegistryHasNoPreparation"])
            self.assertEqual(len(result["rows"]), 2)
            for row in result["rows"]:
                with self.subTest(name=row["name"], layerID=row["layerID"]):
                    self.assertAlmostEqual(row["duration"], 1.2, delta=0.05)
                    self.assertEqual(row["pendingSources"], 2)
                    self.assertEqual(row["pendingAfterPreparation"], 0)
                    for key in ("noUnpreparedNumericSnapshot", "failedSnapshotAbsent", "failedBindingAbsent",
                                "unavailableRowRetained", "failedPreparedReferenceAbsent", "failedSourceReusedWithoutRetry",
                                "sourceReusedAcrossRebuild", "cancellationStartedPending", "cancelledSourceCannotPublishLate",
                                "cancelledWaiterKeepsSharedPreparation"):
                        self.assertTrue(row[key], (key, row))
                    self.assertEqual(row["healthyFailure"], "none")
                    self.assertEqual(row["failedOwnerFailure"], "exception")
                    self.assertEqual(row["initialVector"], [row["duration"], row["duration"], 0])
                    self.assertEqual(row["firstSeekCommands"], [row["duration"] / 4])
                    self.assertEqual(row["firstStopCommands"], 0)
                    self.assertAlmostEqual(row["seekPosition"], row["duration"] / 4, delta=0.001)
                    self.assertEqual(row["rebuildSeekCommands"], 0)
                    self.assertEqual(row["secondVector"][:2], [row["duration"], row["duration"]])
                    self.assertGreater(row["realEOFGeneration"], 0)
                    self.assertAlmostEqual(row["eofPosition"], row["duration"], delta=0.05)
                    self.assertEqual(row["eofStopCommands"], 1)
            after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
            if evidence:
                (evidence / "inputs-after.json").write_text(json.dumps(after, indent=2) + "\n")
            self.assertEqual(after, hashes, "source inputs changed during compilation/run")


if __name__ == "__main__":
    unittest.main()
