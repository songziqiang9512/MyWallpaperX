"""Run real AVPlayer/Metal provider commands; publication envelopes are shims."""
from pathlib import Path
import json
import math
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_initial_video_resource_readiness as readiness

ROOT = Path(__file__).resolve().parents[2]
PROVIDERS = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers"
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


def compile_probe(work):
    compiled = subprocess.run([
        "swiftc", "-parse-as-library", "-default-isolation", "MainActor",
        "-swift-version", "5",
        str(PROVIDERS / "SceneVideoProviderLifecycleState.swift"),
        str(SCENE / "Format/SceneWebMContainer.swift"),
        str(PROVIDERS / "SceneVideoPayloadPreparation.swift"),
        str(PROVIDERS / "SceneVideoOwnedFile.swift"),
        str(SCENE / "Resources/Textures/SceneResourceBudget.swift"),
        str(PROVIDERS / "SceneVideoTextureSource.swift"),
        str(readiness.write_readiness_source(work)),
        str(ROOT / "script/tests/fixtures/SceneVideoRepeatedCommandsHarness.swift"),
        "-module-cache-path", str(work / "module-cache"),
        "-o", str(work / "probe")
    ], capture_output=True, text=True, timeout=120)
    if compiled.returncode:
        raise RuntimeError(compiled.stderr)

class SceneVideoRepeatedCommandsTests(unittest.TestCase):
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
            compile_probe(work)
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
            compile_probe(work)
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
            self.assertTrue(result["pauseHeld"])
            self.assertGreater(result["resumedFrames"], 3)
            self.assertGreater(result["seekFrames"], 3)
            self.assertGreater(result["seekLast"], 0.5)
            self.assertLess(result["seekLast"], 1.2)
            self.assertTrue(result["wrongLayerIgnored"])
            self.assertEqual(result["changedRate"], 2)
            self.assertTrue(result["invalidRateIgnored"])
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
            compile_probe(work)
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
            compile_probe(work)
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
            compile_probe(work)
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
            compile_probe(work)
            result = json.loads(subprocess.run(
                [str(work / "probe"), str(work), "--webm"],
                check=True, capture_output=True, text=True, timeout=20).stdout)
            self.assertTrue(result["initialItemPending"])
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
            self.assertEqual(result["filesAfterStop"], [])
            self.assertTrue(result["cancelStartedPending"])
            self.assertTrue(result["cancelLateFrameAbsent"])
            self.assertTrue(result["cancelLateItemAbsent"])
            self.assertEqual(result["cancelFilesAfterSettle"], [])

if __name__ == "__main__":
    unittest.main()
