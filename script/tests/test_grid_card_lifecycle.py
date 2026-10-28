"""Native lifecycle checks for the complete production Pixabay cards.

The temporary copies expose private members for observation. Downloads changes
only the shared thumbnail transport constructor; both cards' completion bodies,
AppKit views, animations, layout methods and model equality are production code.
The controllable cache-image/data transports deliver cancelled and out-of-order
replies. This gate does not exercise HTTP, thumbnail decoding or cache policy, and
does not measure scrolling performance.

The Downloads click case compiles the complete shared production GridController
and the real card. It dispatches real window mouse events across the native
button and its neighbors; only application actions are recording leaves.

Window pointer and backing scale are controlled inputs on a real NSWindow.
Activation/visibility remain actual AppKit state; no real display migration is
claimed by the injected 1x-to-2x backing callback case.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
UI = ROOT / "MyWallpaperX/Modules/Pixabay/UI"
SHARED = ROOT / "MyWallpaperX/Shared/UI"
CARDS = [UI / "AppKitPixabayBrowserItem.swift", UI / "AppKitPixabayDownloadsItem.swift",
         SHARED / "OnlineImageGridItem.swift"]
BROWSER = Path(os.environ.get("MWX_ONLINE_BROWSER_GRID_SOURCE", UI / "AppKitPixabayBrowserGridView.swift"))
DEPENDENCIES = [
    ROOT / "MyWallpaperX/Modules/Pixabay/Core/PixabayDownloadedContent.swift",
    ROOT / "MyWallpaperX/Modules/Pixabay/Core/PixabayModels.swift",
    SHARED / "AppearanceAwareContainerView.swift",
    SHARED / "NSViewExtensions.swift",
    SHARED / "UIInteractionAnimation.swift",
    SHARED / "WallpaperGridScrollView.swift",
    SHARED / "WallpaperOpenWithMenu.swift",
    SHARED / "GridThumbnailDecoder.swift",
    SHARED / "ModuleFocusable.swift",
    SHARED / "ListThumbnailTintSource.swift",
    ROOT / "MyWallpaperX/Shared/Components/WallpaperCardInteractionView.swift",
    ROOT / "MyWallpaperX/Shared/Components/WallpaperCardSupportViews.swift",
    ROOT / "MyWallpaperX/Shared/Components/WallpaperCardControlsView.swift",
    ROOT / "MyWallpaperX/Shared/Components/ActionMenuItem.swift",
    ROOT / "MyWallpaperX/Shared/Components/WallpaperLibrarySymbols.swift",
    SHARED / "WallpaperInspectorActions.swift",
    SHARED / "WallpaperLibrarySheetPresentation.swift",
    ROOT / "script/tests/fixtures/GridCardInteractionChecks.swift",
    ROOT / "script/tests/fixtures/WallpaperLibraryGridCardReflowChecks.swift",
    ROOT / "script/tests/fixtures/PixabayCardPresentationChecks.swift",
    ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopKeyboardCollectionView.swift",
    ROOT / "MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopGridKeyboardNavigation.swift",
]
FIXTURE = ROOT / "script/tests/fixtures/GridCardLifecycleChecks.swift"
CLICK_SOURCES = [ROOT / "MyWallpaperX" / name for name in (
    "Models/WallpaperReference.swift", "Models/WallpaperContent.swift", "Models/WallpaperLibraryPage.swift",
    "Shared/Components/WallpaperLibraryGridMetrics.swift", "Shared/UI/BoxSelectionState.swift",
    "Shared/UI/GridThumbnailPrefetchDemand.swift",
    "Shell/WallpaperLibraryGridController.swift")]
DEPENDENCIES += CLICK_SOURCES


def card_copy(source: Path) -> tuple[str, list[str]]:
    text = source.read_text()
    # Expose presentation state while retaining every production method.
    text = re.sub(r"\bprivate\s+", "", text)
    transforms = ["remove private access for presentation observation"]
    if source.name == "AppKitPixabayBrowserItem.swift":
        external_open = "NSWorkspace.shared.open(url)"
        if text.count(external_open) != 1:
            raise AssertionError("Browser webpage-opening leaf is no longer unique")
        text = text.replace(external_open, "PixabayMenuWorkspace.open(url)")
        transforms.append("record the external NSWorkspace webpage-open leaf only")
    if source.name == "AppKitPixabayDownloadsItem.swift":
        old = "static let sharedCache = ThumbnailCache("
        if text.count(old) != 1:
            raise AssertionError("Downloads thumbnail constructor injection is no longer unique")
        text = text.replace(old, "static let sharedCache = CardThumbnailTransport(")
        transforms.append("replace shared thumbnail transport constructor only")
    return text, transforms


@unittest.skipUnless(sys.platform == "darwin", "native AppKit requires macOS")
class GridCardLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("Xcode Swift toolchain is unavailable")
        temporary = tempfile.TemporaryDirectory(prefix="mwx-grid-cards-", dir="/private/tmp")
        cls.addClassCleanup(temporary.cleanup)
        cls.work = Path(temporary.name)
        contents = cls.work / "GridCardChecks.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        cls.binary = contents / "MacOS/GridCardChecks"
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.mywallpaperx.tests." + cls.work.name,
            "CFBundleName": "Grid Card Checks",
            "CFBundleExecutable": cls.binary.name,
            "CFBundlePackageType": "APPL",
            "NSPrincipalClass": "NSApplication",
            "LSMinimumSystemVersion": "15.0",
        }))
        cls.environment = os.environ.copy()
        cls.environment.update(
            HOME=str(cls.work / "home"),
            CFFIXED_USER_HOME=str(cls.work / "home"),
            TMPDIR=str(cls.work / "tmp") + "/",
            CLANG_MODULE_CACHE_PATH=str(cls.work / "clang-modules"),
            SWIFT_MODULECACHE_PATH=str(cls.work / "swift-modules"),
        )
        for name in ("home", "tmp"):
            (cls.work / name).mkdir()
        originals = CARDS + [BROWSER] + DEPENDENCIES + [FIXTURE] + CLICK_SOURCES
        inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in originals}
        copies, transformations = [], {}
        for source in CARDS:
            contents, transformations[str(source)] = card_copy(source)
            copy = cls.work / source.name
            copy.write_text(contents)
            copies.append(copy)
        browser = cls.work / "AppKitPixabayBrowserGridView.swift"
        browser.write_text(BROWSER.read_text().replace("private ", ""))
        copies.append(browser)
        transformations[str(BROWSER)] = ["expose private container state for native publication observations"]
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                   "-default-isolation", "MainActor",
                   *map(str, DEPENDENCIES + copies + [FIXTURE]),
                   "-module-cache-path", str(cls.work / "swift-modules"),
                   "-framework", "AppKit", "-framework", "AVFoundation",
                   "-framework", "QuartzCore", "-o", str(cls.binary)]
        build = subprocess.run(command, capture_output=True, text=True,
                               env=cls.environment, cwd=ROOT, timeout=150)
        cls.proof = None
        if directory := os.environ.get("MWX_GRID_CARD_PROOF_DIR"):
            parent = Path(directory)
            parent.mkdir(parents=True, exist_ok=True)
            cls.proof = Path(tempfile.mkdtemp(prefix="grid-card-", dir=parent))
            (cls.proof / "compile.log").write_text(build.stdout + build.stderr)
            (cls.proof / "inputs.json").write_text(json.dumps({
                "inputs": inputs, "transformations": transformations, "command": command,
                "scope": "complete AppKit card lifecycle; controlled thumbnail transport only",
                "excluded": ["network", "thumbnail decode", "cache policy", "frame rate", "full App"],
            }, indent=2) + "\n")
        if build.returncode:
            raise AssertionError(build.stdout + build.stderr)
        if inputs != {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in originals}:
            raise AssertionError("a compiled input changed during the native harness build")

    def check_case(self, name: str) -> None:
        stdout, stderr, pid_file = [self.work / (name + suffix) for suffix in (".stdout", ".stderr", ".pid")]
        stdout.touch()
        stderr.touch()
        command = ["/usr/bin/open", "-n", "-W", "--stdout", str(stdout), "--stderr", str(stderr)]
        for key in ("HOME", "CFFIXED_USER_HOME", "TMPDIR", "CLANG_MODULE_CACHE_PATH", "SWIFT_MODULECACHE_PATH"):
            command += ["--env", key + "=" + self.environment[key]]
        command += ["--env", "MWX_GRID_NATIVE_PID_PATH=" + str(pid_file),
                    str(self.binary.parents[2]), "--args", name]
        try:
            run = subprocess.run(command, capture_output=True, text=True,
                                 env=self.environment, cwd=self.work, timeout=25)
        except subprocess.TimeoutExpired:
            if pid_file.exists():
                pid = int(pid_file.read_text())
                owner = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="],
                                       capture_output=True, text=True).stdout.strip()
                if Path(owner).resolve() == self.binary.resolve():
                    os.kill(pid, signal.SIGKILL)
            raise
        output, errors = stdout.read_text(), stderr.read_text()
        if self.proof:
            (self.proof / (name + ".stdout")).write_text(output)
            (self.proof / (name + ".stderr")).write_text(errors + run.stderr)
        self.assertEqual(run.returncode, 0, output + errors + run.stderr)
        self.assertTrue(output, "native App did not produce its completed result: " + errors)
        facts = json.loads(output)
        self.assertTrue(facts["checks"], "native checks must not be empty")
        if name == "card-reflow":
            self.assertEqual(len(facts["checks"]), 17)
        for check, passed in facts["checks"].items():
            with self.subTest(case=name, check=check):
                self.assertIs(passed, True, facts["details"].get(check, ""))

    def test_pixabay_shared_square_controls_real_hit_testing_and_reuse(self):
        self.check_case("pixabay-square-controls")

    def test_pixabay_native_square_geometry_resize_and_visible_queries(self):
        self.check_case("pixabay-square-layout")

    def test_downloads_native_buttons_are_the_only_primary_action_hit_owner(self):
        self.check_case("pixabay-native-click-owner")

    def test_native_collection_registration_and_actual_item_pool_reuse(self):
        self.check_case("native-pool")

    def test_browser_A_B_A_rejects_old_success_and_failure(self):
        self.check_case("browser-replies")

    def test_downloads_A_B_A_and_memory_hit_reject_old_success_and_failure(self):
        self.check_case("downloads-replies")

    def test_browser_same_id_content_layout_size_and_reuse(self):
        self.check_case("browser-layout")

    def test_browser_container_updates_mounted_same_id_metadata_and_fixed_actions(self):
        self.check_case("browser-container-metadata")

    def test_downloads_content_placeholder_layout_and_selection_playing(self):
        self.check_case("downloads-layout")

    def test_offscreen_unfinished_restarts_ready_is_retained_and_failure_waits_for_new_epoch(self):
        self.check_case("visibility-requests")

    def test_request_bound_loading_delay_never_covers_ready_or_immediate_failure(self):
        self.check_case("loading-delay")

    def test_real_online_cards_ignore_scroll_hover_events_and_restore_from_current_clip(self):
        self.check_case("real-card-scroll")

    def test_active_whole_cards_keep_size_and_white_outline_across_hover_exit_restore_and_card_responder_click(self):
        self.check_case("card-interactions")

    def test_downloaded_cards_recompute_hover_after_native_three_four_five_column_reflow(self):
        self.check_case("card-reflow")

    def test_same_size_backing_change_invalidates_real_cards_and_upgrades_thumbnail_request(self):
        self.check_case("backing-scale")

    def test_completion_immediately_restores_current_primary_without_an_overlay_or_reuse_delay(self):
        self.check_case("completion-feedback")


if __name__ == "__main__":
    unittest.main()
