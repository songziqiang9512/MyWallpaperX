"""Run the production AppKit panel, preview lifetime, and committed-state projection."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_steam_library_interactions import method
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class StatusBarPanelTests(unittest.TestCase):
    def test_quit_confirmed_without_main_window_can_finish_async_termination(self):
        controller = (ROOT / "MyWallpaperX/App/StatusBarController.swift").read_text()
        fixture = (ROOT / "script/tests/fixtures/StatusBarQuitHarness.swift").read_text()
        fixture = fixture.replace("    // PRODUCTION_CLOSE", method(controller, "    private func closeThen("))
        fixture = fixture.replace("    // PRODUCTION_QUIT", method(controller, "    @objc private func quitApp("))
        with tempfile.TemporaryDirectory(prefix="mwx-status-quit-", dir="/private/tmp") as folder:
            work = Path(folder)
            source = work / "Checks.swift"
            source.write_text(fixture)
            binary = prepare_native_app(work, "StatusBarQuit")
            sources = [ROOT / name for name in (
                "MyWallpaperX/Shared/UI/ModalPresentation.swift",
                "MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift",
                "script/tests/fixtures/NativeAppHarness.swift")]
            built = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors",
                                    "-parse-as-library", *map(str, sources), str(source),
                                    "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            for mode in ("closed", "open", "closed-cancel"):
                with self.subTest(mode=mode):
                    ran = run_native_app(binary, [mode], timeout=15)
                    output = ran.stdout + ran.stderr
                    print(f"status-quit-{mode}: {ran.stdout.strip()}")
                    self.assertEqual(ran.launch_returncode, 0, output)
                    self.assertNotIn("status-quit-timeout", output)
                    self.assertIn("cancel-preserved-running-app" if mode == "closed-cancel"
                                  else "confirmed-quit-completed", output)
                    if mode == "closed-cancel":
                        self.assertNotIn("async-cleanup-started", output)
                    else:
                        self.assertIn("async-cleanup-started", output)

    def test_native_layout_state_actions_and_preview_lifetime(self):
        with tempfile.TemporaryDirectory(prefix="mwx-status-panel-", dir="/private/tmp") as folder:
            work = Path(folder)
            binary = work / "checks"
            harness = work / "Checks.swift"
            controller = (ROOT / "MyWallpaperX/App/StatusBarController.swift").read_text()
            template = (ROOT / "script/tests/fixtures/StatusBarPanelHarness.swift").read_text()
            for marker, signature in [
                ("PRODUCTION_CAPTURE", "    private func capturePresentation("),
                ("PRODUCTION_TOGGLE", "    private func togglePlayback("),
                ("PRODUCTION_MODE", "    private func cyclePlaybackMode("),
                ("PRODUCTION_FAVORITE", "    private func toggleFavorite(")]:
                template = template.replace("    // " + marker, method(controller, signature))
            harness.write_text(template)
            sources = [ROOT / "MyWallpaperX/App" / name for name in [
                "StatusBarPanelPresentation.swift", "StatusBarPanelControls.swift",
                "StatusBarPanelView.swift", "StatusBarPanelViewController.swift"]]
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                                    "-module-cache-path", str(work / "modules"),
                                    *map(str, sources),
                                    str(harness),
                                    "-o", str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                                 capture_output=True, text=True, timeout=60)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("status-panel-checks-passed", run.stdout)


if __name__ == "__main__":
    unittest.main()
