"""Reusable main-window lifecycle: close hides a live window, reopen resumes it.

The dead-window regression came from tearing down the composition while the
AppKit window stayed registered and was later revived by the coordinator. This
gate compiles the real coordinator with a controller/window stub and runs the
extracted suspend/resume methods against recording leaves.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.support.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "MyWallpaperX"


class LibraryWindowLifecycleTests(unittest.TestCase):
    def test_window_close_keeps_live_composition_and_reopen_resumes_rendering(self):
        coordinator = APP / "App/MainWindowCoordinator.swift"
        controller = APP / "App/MainWindowController.swift"
        composition = APP / "App/WallpaperLibraryWindowComposition.swift"
        fixture = ROOT / "script/tests/fixtures/LibraryWindowLifecycleHarness.swift"
        coordinator_text = coordinator.read_text()
        controller_text = controller.read_text()
        composition_text = composition.read_text()
        self.assertNotIn("NSApp.windows.first", coordinator_text)
        self.assertEqual(controller_text.count("composition.suspendForWindowClose()"), 1)
        self.assertEqual(controller_text.count("composition.resumeAfterWindowOpen()"), 1)
        self.assertEqual(composition_text.count("guard !isSuspended else { return }"), 1)
        suspend = declaration(composition_text, "    func suspendForWindowClose()")
        self.assertNotIn("subscriptions.removeAll", suspend)
        self.assertNotIn("windowObservers.forEach", suspend)
        self.assertNotIn("windowVisibility = nil", suspend)
        inputs = [coordinator, controller, composition, fixture, Path(__file__).resolve()]
        hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        with tempfile.TemporaryDirectory(prefix="mwx-window-lifecycle-", dir="/private/tmp") as directory:
            work = Path(directory)
            copied = work / coordinator.name
            shutil.copy2(coordinator, copied)
            harness = work / "Checks.swift"
            harness.write_text(fixture.read_text().replace(
                "    // EXTRACTED_LIFECYCLE_METHODS",
                "\n\n".join((suspend, declaration(composition_text, "    func resumeAfterWindowOpen()"))),
            ))
            binary = prepare_native_app(work, "LibraryWindowLifecycle")
            built = subprocess.run(
                ["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                 str(copied), str(harness), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            try:
                ran = run_native_app(binary, [str(work)], timeout=35)
            finally:
                if output := os.environ.get("MWX_WINDOW_LIFECYCLE_PROOF_DIR"):
                    proof = Path(output)
                    proof.mkdir(parents=True, exist_ok=True)
                    for name in ("native-app.stdout", "native-app.stderr", "native-app.pid"):
                        if (work / name).exists():
                            shutil.copy2(work / name, proof / name)
                    (proof / "inputs.json").write_text(json.dumps(hashes, indent=2))
            self.assertEqual(ran.launch_returncode, 0, ran.stdout + ran.stderr)
            checks = json.loads(ran.stdout)
            self.assertGreaterEqual(len(checks), 5)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, ran.stdout + ran.stderr)
            self.assertEqual(hashes, {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})


if __name__ == "__main__":
    unittest.main()
