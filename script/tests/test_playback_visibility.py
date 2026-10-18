"""Native visibility/media gates and real Video activation/rollback counterexamples."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "script/tests/fixtures/playback-lifecycle"
PROBE = ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackSurfaceVisibility.swift"

class PlaybackVisibilityTests(unittest.TestCase):
    def run_harness(self, sources, name, timeout):
        with tempfile.TemporaryDirectory(prefix="mwx-playback-visibility-") as temporary:
            folder = Path(temporary)
            binary = folder / "harness"
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                str(FIXTURES / name), "-o", str(binary)], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary), str(folder / "generated.mov")],
                capture_output=True, text=True, timeout=timeout)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_window_and_latest_native_media_gates(self):
        self.run_harness([PROBE, ROOT / "MyWallpaperX/Core/SteamWorkshopWeb/Host/WebMediaPlaybackGate.swift"],
            "ProbeGateHarness.swift", 20)

    def test_real_video_visibility_and_rollback(self):
        sources = sorted((ROOT / "WallpaperDaemonSources/Daemon").rglob("*.swift"))
        sources += [PROBE, ROOT / "MyWallpaperX/Core/Playback/DaemonProtocol.swift",
            ROOT / "MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift",
            ROOT / "MyWallpaperX/Core/DaemonKit/DaemonParentLifetime.swift"]
        self.run_harness(sources, "VideoHarness.swift", 30)
