"""Native sidebar input, fixed-UUID menus, selection and constrained outline drag."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibrarySidebarTests(unittest.TestCase):
    def test_native_three_group_sidebar(self):
        paths = ["MyWallpaperX/Models/WallpaperReference.swift", "MyWallpaperX/Models/WallpaperLibraryPage.swift",
                 "MyWallpaperX/Models/WallpaperContent.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsStore.swift",
                 "MyWallpaperX/Core/LibraryCollections/UserCollectionsController.swift",
                 "MyWallpaperX/Shared/Components/SidebarComponents.swift", "MyWallpaperX/Shared/UI/ModalPresentation.swift",
                 "MyWallpaperX/Shared/UI/AppCenteredAlertPresentation.swift",
                 "MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift",
                 "MyWallpaperX/Shared/Components/WallpaperLibrarySymbols.swift",
                 "MyWallpaperX/Shared/Components/WallpaperLibraryControlStyle.swift",
                 "MyWallpaperX/Shared/UI/ListThumbnailTintSource.swift", "MyWallpaperX/Shell/AppKitListBackgroundTint.swift",
                 "MyWallpaperX/Shared/UI/WallpaperArtworkDemandObservation.swift",
                 "MyWallpaperX/Shared/Components/WallpaperLibraryGridMetrics.swift",
                 "MyWallpaperX/Shared/Components/WallpaperCardInteractionView.swift",
                 "MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift", "MyWallpaperX/Shared/UI/BoxSelectionState.swift",
                 "MyWallpaperX/Shared/UI/GridThumbnailPrefetchDemand.swift",
                 "MyWallpaperX/Shell/WallpaperLibraryGridController.swift",
                 "MyWallpaperX/Shell/WallpaperPlaylistEditorController.swift",
                 "MyWallpaperX/Shell/PlaylistOrganizationActions.swift", "MyWallpaperX/Shell/WallpaperLibrarySidebarController.swift",
                 "script/tests/fixtures/NativeAppHarness.swift", "script/tests/fixtures/WallpaperLibrarySidebarHarness.swift"]
        palette = "MyWallpaperX/Shared/UI/InspectorHostViewController.swift"
        observed = paths + [palette, str(Path(__file__).relative_to(ROOT)), "script/tests/test_ui_library_algorithms.py"]
        identities = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in observed}
        with tempfile.TemporaryDirectory(prefix="mwx-library-sidebar-", dir="/private/tmp") as folder:
            work = Path(folder)
            sources = []
            instrumentation = {}
            for path in paths:
                target = work / Path(path).name
                shutil.copy2(ROOT / path, target)
                if path == "MyWallpaperX/Shell/WallpaperLibraryGridController.swift":
                    # Record the actual native session after the production
                    # callback has performed its original cancellation setup.
                    # Keep the controller itself as the real source delegate.
                    original = target.read_text()
                    marker = "        session.animatesToStartingPositionsOnCancelOrFail = false"
                    self.assertEqual(original.count(marker), 1)
                    target.write_text(original.replace(marker, marker + "\n        SidebarGridNativeDragProbe.session = session"))
                    instrumentation[path] = {
                        "original_sha256": identities[path],
                        "test_copy_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                        "purpose": "observe production willBegin native session; original body and delegate retained",
                    }
                sources.append(str(target))
            palette_source = work / "InspectorGlassPalette.swift"
            palette_source.write_text("import AppKit\n" + declaration((ROOT / palette).read_text(), "enum InspectorGlassPalette"))
            sources.append(str(palette_source))
            binary = prepare_native_app(work, "WallpaperLibrarySidebar")
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *sources, "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=40)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                self.assertIs(passed, True, name + "\n" + run.stdout + "\n" + run.stderr)
            print(json.dumps({"testOnlyNativeSessionInstrumentation": instrumentation}, sort_keys=True))
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(identities, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in observed})


if __name__ == "__main__":
    unittest.main()
