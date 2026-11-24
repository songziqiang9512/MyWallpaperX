"""Native visibility/media gates and real Video activation/rollback counterexamples."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "script/tests/fixtures/playback-lifecycle"
PROBE = ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackSurfaceVisibility.swift"

class PlaybackVisibilityTests(unittest.TestCase):
    def run_harness(self, sources, name, timeout, input_video=None):
        with tempfile.TemporaryDirectory(prefix="mwx-playback-visibility-") as temporary:
            folder = Path(temporary)
            binary = folder / "harness"
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                str(FIXTURES / name), "-o", str(binary)], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            command = [str(binary), str(folder / "generated.mov")]
            if input_video is not None:
                command.append(str(input_video))
            result = subprocess.run(command,
                capture_output=True, text=True, timeout=timeout)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout

    def test_window_and_latest_native_media_gates(self):
        self.run_harness([PROBE, ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/WebMediaPlaybackGate.swift"],
            "ProbeGateHarness.swift", 20)

    def run_video_harness(self, input_video=None):
        sources = sorted((ROOT / "WallpaperDaemonSources/Daemon").rglob("*.swift"))
        sources += [PROBE, ROOT / "MyWallpaperX/Core/Playback/DaemonProtocol.swift",
            ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift",
            ROOT / "MyWallpaperX/Core/DaemonKit/DaemonParentLifetime.swift"]
        return self.run_harness(sources, "VideoHarness.swift", 30, input_video)

    def test_real_video_visibility_and_rollback(self):
        self.run_video_harness()

    def test_downloaded_quality_file_loops_in_the_real_video_daemon(self):
        selected = os.environ.get("MWX_SELECTED_VIDEO_QUALITY_FIXTURE")
        if not selected:
            self.skipTest("requires the isolated marked clip from the Pixabay transfer gate")
        output = self.run_video_harness(Path(selected).resolve(strict=True))
        self.assertIn("selected-video-playback loops=2", output)
        print(next(line for line in output.splitlines() if line.startswith("selected-video-playback ")))
