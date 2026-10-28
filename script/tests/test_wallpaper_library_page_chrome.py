"""Native all-page feedback using the real Chrome, detail host and Inspector overlay.

The composition feedback function is copied intact. Source services, persistence
and navigation are recording leaves; this gate does not scan or play media.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class WallpaperLibraryPageChromeTests(unittest.TestCase):
    def test_all_page_feedback_current_actions_and_native_viewport(self):
        paths = [ROOT / "MyWallpaperX" / name for name in (
            "Models/WallpaperReference.swift", "Shared/UI/WallpaperPlaylistArtwork.swift", "Models/WallpaperContent.swift", "Models/WallpaperLibraryPage.swift",
            "Core/LibraryCollections/WallpaperLibraryQuery.swift",
            "Shared/Components/WallpaperLibraryControlStyle.swift", "Shared/Components/WallpaperLibraryGridMetrics.swift", "Shared/Components/WallpaperLibrarySymbols.swift",
            "Shared/Components/WallpaperCardInteractionView.swift", "Shared/UI/BoxSelectionState.swift",
            "Shared/UI/WallpaperLibrarySheetPresentation.swift", "Shared/UI/WallpaperGridNoticeView.swift",
            "Shared/UI/GridThumbnailPrefetchDemand.swift", "Shared/UI/WallpaperGridScrollView.swift",
            "Shared/UI/WallpaperArtworkDemandObservation.swift", "Shell/WallpaperLibraryGridController.swift",
            "Shell/AppKitPlaylistDirectoryController.swift", "Shell/AppKitDetailHostViewController.swift",
            "Shell/WallpaperLibraryPageChrome.swift")]
        fixture = ROOT / "script/tests/fixtures/WallpaperLibraryPageChromeHarness.swift"
        initialization = ROOT / "script/tests/fixtures/NativeAppHarness.swift"
        composition = ROOT / "MyWallpaperX/App/WallpaperLibraryWindowComposition.swift"
        split = ROOT / "MyWallpaperX/Shell/AppKitMainSplitView.swift"
        tint = ROOT / "MyWallpaperX/Shell/AppKitListBackgroundTint.swift"
        presentation = ROOT / "MyWallpaperX/Shell/WallpaperLibraryPresentation.swift"
        actions = ROOT / "MyWallpaperX/Shell/PlaylistOrganizationActions.swift"
        observed = [*paths, fixture, initialization, composition, split, tint, presentation, actions, Path(__file__),
                    ROOT / "script/tests/native_app_harness.py", ROOT / "script/tests/test_ui_library_algorithms.py",
                    ROOT / "script/tests/test_video_thumbnail_prefetch.py"]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed}
        self.assertNotIn("grid.scrollView.onRefresh", composition.read_text())
        template = fixture.read_text()
        substitutions = {
            "// ACTUAL_PRESENTATION_VALUE": declaration(presentation.read_text(), "nonisolated struct WallpaperLibraryPresentationState:"),
            "// ACTUAL_DIRECTORY_ACTION": declaration(actions.read_text(), "nonisolated enum PlaylistOrganizationAction:"),
            "// ACTUAL_FEEDBACK": declaration(composition.read_text(), "    private func updatePageChrome("),
            "// ACTUAL_HEADER_UPDATE": declaration(composition.read_text(), "    private func updateHeader("),
            "// ACTUAL_INPUT_PERMISSION": declaration(composition.read_text(), "    private var permitsInput:"),
            "// ACTUAL_INSPECTOR_HOST": "\n".join(declaration(split.read_text(), marker) for marker in (
                "private final class InspectorDetailContainerViewController:", "private final class InspectorOverlayPassthroughView:")),
            "// ACTUAL_TINT_SURFACE": declaration(tint.read_text(), "final class AppKitListTintSurface:"),
        }
        for marker, source in substitutions.items():
            self.assertEqual(template.count(marker), 1)
            template = template.replace(marker, source)
        with tempfile.TemporaryDirectory(prefix="mwx-page-chrome-", dir="/private/tmp") as directory:
            work = Path(directory)
            copies = []
            for path in [*paths, initialization]:
                copied = work / path.name
                shutil.copy2(path, copied)
                copies.append(str(copied))
            harness = work / "Checks.swift"
            harness.write_text(template)
            proof = Path(output) if (output := os.environ.get("MWX_PAGE_CHROME_PROOF_DIR")) else None
            if proof is not None:
                proof.mkdir(parents=True, exist_ok=True)
                (proof / "inputs.json").write_text(json.dumps(hashes, indent=2) + "\n")
            binary = prepare_native_app(work, "WallpaperLibraryPageChrome")
            built = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *copies, str(harness), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = run_native_app(binary, timeout=45)
            if proof is not None:
                (proof / "native.stdout").write_text(ran.stdout)
                (proof / "native.stderr").write_text(ran.stderr)
                (proof / "run.json").write_text(json.dumps({"launchServicesReturnCode": ran.launch_returncode}) + "\n")
            diagnostic = f"LaunchServices={ran.launch_returncode}\n{ran.stdout}\n{ran.stderr}"
            self.assertEqual(ran.launch_returncode, 0, diagnostic)
            self.assertTrue(ran.stdout.strip(), diagnostic)
            checks = json.loads(ran.stdout)
            self.assertTrue(checks, diagnostic)
            print(json.dumps(checks, sort_keys=True))
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, diagnostic)
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in observed})


if __name__ == "__main__":
    unittest.main()
