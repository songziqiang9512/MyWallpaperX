"""Run the production AppKit panel, preview lifetime, and committed-state projection."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_steam_library_interactions import method

ROOT = Path(__file__).resolve().parents[2]


class StatusBarPanelTests(unittest.TestCase):
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
