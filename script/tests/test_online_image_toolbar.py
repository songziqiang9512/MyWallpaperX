"""Actual online toolbar/query/menu commands and native popover geometry.

Browser/network orchestration and capsule styling are recording leaves. The
toolbar, typed query values, overflow menu items, modal permission and shared
scrolling popover compile unchanged. This opens only an isolated fixture App.
"""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "script/tests/fixtures/OnlineImageToolbarHarness.swift"


@unittest.skipUnless(sys.platform == "darwin", "requires native macOS AppKit")
class OnlineImageToolbarTests(unittest.TestCase):
    def test_live_queries_overflow_modal_and_native_scrolling(self):
        relative = [
            "Models/WallpaperReference.swift", "Models/WallpaperContent.swift",
            "Models/WallpaperLibraryPage.swift", "Core/OnlineImages/OnlineImageModels.swift",
            "Modules/Wallhaven/Core/WallhavenQuery.swift", "Modules/Pixiv/Core/PixivQuery.swift",
            "App/OnlineImageToolbarController.swift", "Shared/UI/ToolbarMenuPopover.swift",
            "Shared/UI/WallpaperLibrarySheetPresentation.swift", "Shared/Components/ActionMenuItem.swift",
        ]
        sources = [ROOT / "MyWallpaperX" / name for name in relative]
        sources += [ROOT / "script/tests/fixtures/NativeAppHarness.swift", FIXTURE]
        observed = [*sources, Path(__file__), ROOT / "script/tests/native_app_harness.py"]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        proof = None
        if value := os.environ.get("MWX_ONLINE_IMAGE_TOOLBAR_PROOF_DIR"):
            proof = Path(value); proof.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="mwx-online-image-toolbar-", dir="/private/tmp") as directory:
            work = Path(directory)
            copied = []
            for path in sources:
                target = work / path.name
                shutil.copy2(path, target)
                copied.append(str(target))
            binary = prepare_native_app(work, "OnlineImageToolbarChecks")
            home = work / "home"; home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            command = ["xcrun", "--sdk", "macosx", "swiftc", "-swift-version", "5",
                       "-default-isolation", "MainActor", "-warnings-as-errors", "-parse-as-library",
                       "-target", platform.machine() + "-apple-macos26.0",
                       *copied, "-module-cache-path", str(work / "modules"),
                       "-framework", "AppKit", "-o", str(binary)]
            build = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=120)
            if proof:
                (proof / "compile.log").write_text(build.stdout + build.stderr)
                (proof / "inputs.json").write_text(json.dumps(hashes, indent=2) + "\n")
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=35)
            if proof:
                (proof / "stdout.json").write_text(run.stdout)
                (proof / "runtime.log").write_text(run.stderr)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            self.assertTrue(run.stdout.strip(), run.stderr)
            facts = json.loads(run.stdout)
            self.assertNotIn("error", facts, run.stdout + run.stderr)
            self.assertTrue(facts["checks"])
            for name, passed in facts["checks"].items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, facts.get("details", {}).get(name, "") + run.stderr)
            print(json.dumps(facts, sort_keys=True))
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == "__main__":
    unittest.main()
