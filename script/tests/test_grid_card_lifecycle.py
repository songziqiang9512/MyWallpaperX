"""Native lifecycle checks for the complete production OnlineLibrary cards.

The temporary copies expose private members for observation. Downloads changes
only the shared thumbnail transport constructor; both cards' completion bodies,
AppKit views, animations, layout methods and model equality are production code.
The controllable cache-image/data transports deliver cancelled and out-of-order
replies. This gate does not exercise HTTP, thumbnail decoding or cache policy, and
does not measure scrolling performance.

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
UI = ROOT / "MyWallpaperX/Modules/OnlineLibrary/UI"
SHARED = ROOT / "MyWallpaperX/Shared/UI"
CARDS = [UI / "AppKitOLBrowserItem.swift", UI / "AppKitOLDownloadsItem.swift"]
DEPENDENCIES = [
    ROOT / "MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryModels.swift",
    SHARED / "AppearanceAwareContainerView.swift",
    SHARED / "NSViewExtensions.swift",
    SHARED / "UIInteractionAnimation.swift",
    SHARED / "WallpaperGridScrollView.swift",
    SHARED / "GridThumbnailDecoder.swift",
]
FIXTURE = ROOT / "script/tests/fixtures/GridCardLifecycleChecks.swift"


def card_copy(source: Path) -> tuple[str, list[str]]:
    text = source.read_text()
    # The two files intentionally have separate file-private olSymbol helpers.
    # Preserve that namespace while exposing stored UI state and complete methods.
    marker = "/* MWX_TEST_KEEP_PRIVATE_IMAGE_EXTENSION */"
    text = text.replace("private extension NSImage", marker + " extension NSImage")
    text = re.sub(r"\bprivate\s+", "", text)
    text = text.replace(marker, "private")
    transforms = ["remove private access except the file-private NSImage extension"]
    if source.name == "AppKitOLDownloadsItem.swift":
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
        originals = CARDS + DEPENDENCIES + [FIXTURE]
        inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in originals}
        copies, transformations = [], {}
        for source in CARDS:
            contents, transformations[str(source)] = card_copy(source)
            copy = cls.work / source.name
            copy.write_text(contents)
            copies.append(copy)
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
        for check, passed in facts["checks"].items():
            with self.subTest(case=name, check=check):
                self.assertIs(passed, True, facts["details"].get(check, ""))

    def test_native_collection_registration_and_actual_item_pool_reuse(self):
        self.check_case("native-pool")

    def test_browser_A_B_A_rejects_old_success_and_failure(self):
        self.check_case("browser-replies")

    def test_downloads_A_B_A_and_memory_hit_reject_old_success_and_failure(self):
        self.check_case("downloads-replies")

    def test_browser_same_id_content_layout_size_and_reuse(self):
        self.check_case("browser-layout")

    def test_downloads_content_placeholder_layout_and_selection_playing(self):
        self.check_case("downloads-layout")

    def test_offscreen_unfinished_restarts_ready_is_retained_and_failure_waits_for_new_epoch(self):
        self.check_case("visibility-requests")

    def test_request_bound_loading_delay_never_covers_ready_or_immediate_failure(self):
        self.check_case("loading-delay")

    def test_real_online_cards_ignore_scroll_hover_events_and_restore_from_current_clip(self):
        self.check_case("real-card-scroll")

    def test_same_size_backing_change_invalidates_real_cards_and_upgrades_thumbnail_request(self):
        self.check_case("backing-scale")

    def test_old_completion_delay_reveal_and_hide_cannot_mutate_reused_badge(self):
        self.check_case("animation-delayed")

    def test_old_move_completion_cannot_fade_reused_badge(self):
        self.check_case("animation-move")

    def test_old_fade_completion_cannot_hide_reused_badge(self):
        self.check_case("animation-fade")


if __name__ == "__main__":
    unittest.main()
