"""Real AppKit local-grid events using the production controller and value DTOs."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryGridTests(unittest.TestCase):
    def test_native_selection_navigation_layout_and_drop_receipts(self):
        named_modes = {"continuous-drag": ("--continuous-drag",),
                       "topology-transitions": ("--topology-transitions",),
                       "legacy": ()}
        requested_mode = os.environ.get("MWX_GRID_MODE")
        if requested_mode is not None:
            self.assertIn(requested_mode, named_modes, "Unsupported MWX_GRID_MODE")
        paths = ["MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperContent.swift",
                 "MyWallpaperX/Models/WallpaperLibraryPage.swift",
                 "MyWallpaperX/Shared/Components/WallpaperLibraryControlStyle.swift",
                 "MyWallpaperX/Shared/Components/WallpaperLibraryGridMetrics.swift",
                 "MyWallpaperX/Shared/Components/WallpaperLibrarySymbols.swift",
                 "MyWallpaperX/Shared/Components/WallpaperCardInteractionView.swift",
                 "MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift", "MyWallpaperX/Shared/UI/BoxSelectionState.swift",
                 "MyWallpaperX/Shared/UI/GridThumbnailPrefetchDemand.swift",
                 "MyWallpaperX/Shell/WallpaperLibraryGridController.swift",
                 "MyWallpaperX/Shell/WallpaperLibraryPageChrome.swift",
                 "script/tests/fixtures/NativeAppHarness.swift", "script/tests/fixtures/WallpaperLibraryGridHarness.swift",
                 "script/tests/fixtures/WallpaperLibraryGridDragChecks.swift",
                 "script/tests/fixtures/WallpaperPlaylistHeaderChecks.swift"]
        hashes = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-library-grid-", dir="/private/tmp") as directory:
            work = Path(directory)
            for path in paths:
                shutil.copy2(ROOT / path, work / Path(path).name)
            proof = None
            if destination := os.environ.get("MWX_GRID_PROOF_DIR"):
                Path(destination).mkdir(parents=True, exist_ok=True)
                proof = Path(tempfile.mkdtemp(prefix="grid-", dir=destination))
                (proof / "inputs.json").write_text(json.dumps(hashes, indent=2, sort_keys=True))
            binary = prepare_native_app(work, "WallpaperLibraryGrid")
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *[str(work / Path(p).name) for p in paths], "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            if proof:
                (proof / "compile.log").write_text(build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            # Drag admission and pending-layout transitions have isolated native
            # processes, so settled legacy geometry cannot mask either failure.
            modes = [("--continuous-drag",), ("--topology-transitions",), ()]
            if requested_mode is not None:
                modes = [named_modes[requested_mode]]
            elif os.environ.get("MWX_GRID_ONLY_CONTINUOUS_DRAG") == "1":
                modes = [("--continuous-drag",)]
            for arguments in modes:
                mode = arguments[0].removeprefix("--") if arguments else "legacy"
                try:
                    run = run_native_app(binary, arguments, timeout=50)
                except subprocess.TimeoutExpired:
                    # The runner has already stopped only its exact owned PID.
                    # Preserve App output before TemporaryDirectory removes it.
                    if proof:
                        for stream in ("stdout", "stderr"):
                            captured = work / ("native-app." + stream)
                            (proof / f"{mode}.{stream}.log").write_text(captured.read_text() if captured.exists() else "")
                        (proof / f"{mode}.result.json").write_text(json.dumps({
                            "arguments": arguments, "timeoutSeconds": 50, "timedOut": True,
                            "launchReturncode": None,
                            "inputsAfter": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}}, indent=2))
                    raise
                if proof:
                    (proof / f"{mode}.stdout.log").write_text(run.stdout)
                    (proof / f"{mode}.stderr.log").write_text(run.stderr)
                    (proof / f"{mode}.result.json").write_text(json.dumps({
                        "arguments": arguments, "timeoutSeconds": 50, "timedOut": False,
                        "launchReturncode": run.launch_returncode,
                        "inputsAfter": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}}, indent=2))
                diagnostic = (f"mode={arguments or ('legacy',)}\n"
                              f"LaunchServices status={run.launch_returncode} (not the App process exit status)\n"
                              f"native stdout:\n{run.stdout}\nnative stderr:\n{run.stderr}")
                self.assertEqual(run.launch_returncode, 0, diagnostic)
                self.assertTrue(run.stdout.strip(), "Native fixture ended without its checks JSON.\n" + diagnostic)
                try:
                    checks = json.loads(run.stdout)
                except json.JSONDecodeError as error:
                    self.fail("Native fixture did not reach a valid checks result: " + str(error) + "\n" + diagnostic)
                self.assertTrue(checks)
                print(json.dumps(checks, sort_keys=True))
                for name, passed in checks.items():
                    self.assertIs(passed, True, name + "\n" + diagnostic)
        self.assertEqual(hashes, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths})


if __name__ == "__main__":
    unittest.main()
