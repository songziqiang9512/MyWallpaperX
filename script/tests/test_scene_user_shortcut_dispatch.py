"""Exercise the production Session action policy with an independently chosen native result."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SceneUserShortcutDispatchTests(unittest.TestCase):
    def test_control_plane_reentry_and_stale_acknowledgements(self):
        with tempfile.TemporaryDirectory(prefix="mwx-shortcut-control-") as temporary:
            binary = Path(temporary) / "control"
            sources = [
                "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
                "MyWallpaperX/Core/PlaybackControl/ScenePlaybackShortcut.swift",
                "MyWallpaperX/Core/PlaybackControl/WallpaperEngineCommand.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonProtocol+UserShortcuts.swift",
                "MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonClient+UserShortcuts.swift",
                "script/tests/fixtures/SceneUserShortcutControlHarness.swift",
            ]
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                *[str(ROOT / path) for path in sources], "-module-cache-path",
                str(Path(temporary) / "module-cache"), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            execution = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(execution.returncode, 0, execution.stderr)
            self.assertIn("shortcut-control-pass", execution.stdout)

    def test_native_results_and_irreversible_input_budget(self):
        with tempfile.TemporaryDirectory(prefix="mwx-shortcut-policy-") as temporary:
            binary = Path(temporary) / "policy"
            result = subprocess.run([
                "xcrun", "swiftc", "-parse-as-library",
                str(ROOT / "MyWallpaperX/Core/PlaybackControl/ScenePlaybackShortcut.swift"),
                str(ROOT / "MyWallpaperX/Core/PlaybackControl/PlaybackDesktopInputAdmission.swift"),
                str(ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+UserShortcuts.swift"),
                str(ROOT / "script/tests/fixtures/SceneUserShortcutDispatchHarness.swift"),
                "-module-cache-path", str(Path(temporary) / "module-cache"), "-o", str(binary),
            ], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            execution = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(execution.returncode, 0, execution.stderr)
            self.assertIn("shortcut-dispatch-pass native-calls=2", execution.stdout)
