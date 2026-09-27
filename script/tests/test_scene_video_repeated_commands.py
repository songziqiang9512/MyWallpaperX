"""Run real AVPlayer/Metal provider commands; publication envelopes are shims."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROVIDERS = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers"

class SceneVideoRepeatedCommandsTests(unittest.TestCase):
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
            subprocess.run([
                "swiftc", "-parse-as-library",
                str(PROVIDERS / "SceneVideoProviderLifecycleState.swift"),
                str(PROVIDERS / "SceneVideoTextureSource.swift"),
                str(ROOT / "script/tests/fixtures/SceneVideoRepeatedCommandsHarness.swift"),
                "-module-cache-path", str(work / "module-cache"),
                "-o", str(work / "probe")
            ], check=True, capture_output=True, timeout=120)
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
            requested = result["repeatedRequestedTimes"]
            self.assertGreater(len(decoded), 20)
            # During steady playback the 30 fps output lies on the frame grid.
            # Seek/re-anchor output can have a different first display timestamp;
            # requests occur at host callback times and must not masquerade as PTS.
            self.assertTrue(all(abs(t * 30 - round(t * 30)) < 0.001 for t in decoded))
            self.assertTrue(any(abs(a - b) > 0.002 for a, b in zip(decoded, requested)))
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

    def test_actual_loop_requests_preserve_scene_clock_phase(self):
        if not shutil.which("swiftc") or not shutil.which("ffmpeg"):
            self.skipTest("Swift and ffmpeg are required for real AVPlayer evidence")
        with tempfile.TemporaryDirectory(prefix="mwx-video-loop-phase-") as tmp:
            work = Path(tmp)
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
                "testsrc2=size=320x180:rate=30:duration=2", "-c:v", "libx264",
                "-pix_fmt", "yuv420p", str(work / "clip.mp4")],
                check=True, capture_output=True, timeout=30)
            subprocess.run(["swiftc", "-parse-as-library",
                str(PROVIDERS / "SceneVideoProviderLifecycleState.swift"),
                str(PROVIDERS / "SceneVideoTextureSource.swift"),
                str(ROOT / "script/tests/fixtures/SceneVideoRepeatedCommandsHarness.swift"),
                "-module-cache-path", str(work / "module-cache"), "-o", str(work / "probe")],
                check=True, capture_output=True, timeout=120)
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
            subprocess.run(["swiftc", "-parse-as-library",
                str(PROVIDERS / "SceneVideoProviderLifecycleState.swift"),
                str(PROVIDERS / "SceneVideoTextureSource.swift"),
                str(ROOT / "script/tests/fixtures/SceneVideoRepeatedCommandsHarness.swift"),
                "-module-cache-path", str(work / "module-cache"), "-o", str(work / "probe")],
                check=True, capture_output=True, timeout=120)
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

if __name__ == "__main__":
    unittest.main()
