"""Native AppKit behavior of the production per-grid hover scrolling gate."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import shutil
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]
PRODUCTION = ROOT / "MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift"
FIXTURE = ROOT / "script/tests/fixtures/GridScrollInteractionChecks.swift"
MENU_FIXTURE = ROOT / "script/tests/fixtures/GridContextMenuHoverChecks.swift"
NATIVE_MENU_FIXTURE = ROOT / "script/tests/fixtures/GridContextMenuNativeInputChecks.swift"
COLLECTION = ROOT / "MyWallpaperX/Shell/WallpaperLibraryGridController.swift"
CARD_INTERACTION = ROOT / "MyWallpaperX/Shared/Components/WallpaperCardInteractionView.swift"


@unittest.skipUnless(sys.platform == "darwin", "native AppKit requires macOS")
class GridScrollInteractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("Xcode Swift toolchain is unavailable")
        temporary = tempfile.TemporaryDirectory(prefix="mwx-grid-scroll-", dir="/private/tmp")
        cls.addClassCleanup(temporary.cleanup)
        cls.work = Path(temporary.name)
        contents = cls.work / "GridScrollChecks.app/Contents"
        (contents / "MacOS").mkdir(parents=True)
        cls.binary = contents / "MacOS/GridScrollChecks"
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.mywallpaperx.tests." + cls.work.name,
            "CFBundleName": "Grid Scroll Checks",
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
        paths = (PRODUCTION, FIXTURE, MENU_FIXTURE, NATIVE_MENU_FIXTURE, COLLECTION, CARD_INTERACTION, Path(__file__),
                 ROOT / "script/tests/test_ui_library_algorithms.py")
        inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        original = PRODUCTION.read_text()
        marker = "    private func observeLiveScroll() {\n"
        if original.count(marker) != 1:
            raise AssertionError("the production observer installation marker must be unique")
        instrumented = original.replace(marker, marker + """        // Geometry-only fixture injection before the original observers attach.
        if GridScrollClipProbe.usesControlledGeometry {
            contentView = GridScrollGeometryClip(frame: contentView.frame)
        }
""")
        for signature, label in [
            ("    func beginContextMenu(at point: NSPoint)", "scroll.begin"),
            ("    func endContextMenu()", "scroll.end"),
        ]:
            marker = signature + " {"
            if instrumented.count(marker) != 1:
                raise AssertionError("the production native-input trace marker must be unique: " + signature)
            event = "event" if label.startswith("tracking.") else "nil"
            instrumented = instrumented.replace(marker, marker + f'''
        GridContextMenuInputTrace.record("{label}.before", event: {event})
        defer {{ GridContextMenuInputTrace.record("{label}.after", event: {event}) }}
''', 1)
        production_copy = cls.work / PRODUCTION.name
        production_copy.write_text(instrumented)
        collection = declaration(COLLECTION.read_text(), "@MainActor final class WallpaperLibraryCollectionView:")
        card = CARD_INTERACTION.read_text()
        native_sources = []
        for source, target_name, label in [(collection, "NativeCollection.swift", "collection"),
                                           (card, CARD_INTERACTION.name, "card")]:
            callbacks = [("    override func rightMouseDown(with event: NSEvent)", "rightDown", "nil")]
            if label == "collection":
                callbacks.append(("    override func menu(for event: NSEvent) -> NSMenu?", "menu", "nil"))
            for signature, callback, menu in callbacks:
                marker = signature + " {"
                if source.count(marker) != 1:
                    raise AssertionError("the actual native view callback must be unique: " + signature)
                if callback == "menu":
                    # Instrumentation makes the original single-expression
                    # getter a multi-statement body; retain its return value.
                    expression = "\n        contextMenuProvider?("
                    if source.count(expression) != 1:
                        raise AssertionError("the actual menu expression must be unique")
                    source = source.replace(expression, "\n        return contextMenuProvider?(", 1)
                source = source.replace(marker, marker + f'''
        GridContextMenuInputTrace.record("{label}.{callback}", event: event, menu: {menu})
''', 1)
            # Observe AppKit's native lifecycle, retaining the inherited body.
            # These added overrides log and call super; they own no menu state.
            source = source.rstrip()[:-1] + f'''
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {{
        GridContextMenuInputTrace.record("{label}.willOpen", event: event, menu: menu)
        super.willOpenMenu(menu, with: event)
    }}
    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {{
        GridContextMenuInputTrace.record("{label}.didClose", event: event, menu: menu)
        super.didCloseMenu(menu, with: event)
    }}
}}
'''
            target = cls.work / target_name
            target.write_text("import AppKit\n" + source)
            native_sources.append(str(target))
        fixture_copy = cls.work / FIXTURE.name
        fixture = FIXTURE.read_text()
        for callback in ("Exited", "Moved"):
            marker = f"    override func mouse{callback}(with event: NSEvent) {{"
            if fixture.count(marker) != 1:
                raise AssertionError("the native hover observation leaf must be unique")
            fixture = fixture.replace(marker, marker + f' GridContextMenuInputTrace.record("item.mouse{callback}", event: event);', 1)
        fixture_copy.write_text(fixture + "\n" + MENU_FIXTURE.read_text() + "\n" + NATIVE_MENU_FIXTURE.read_text())
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                   "-default-isolation", "MainActor", str(production_copy), *native_sources, str(fixture_copy),
                   "-module-cache-path", str(cls.work / "swift-modules"),
                   "-framework", "AppKit", "-o", str(cls.binary)]
        build = subprocess.run(command, capture_output=True, text=True,
                               env=cls.environment, cwd=ROOT, timeout=120)
        cls.proof = None
        if directory := os.environ.get("MWX_GRID_SCROLL_PROOF_DIR"):
            parent = Path(directory)
            parent.mkdir(parents=True, exist_ok=True)
            cls.proof = Path(tempfile.mkdtemp(prefix="grid-scroll-", dir=parent))
            (cls.proof / "compile.log").write_text(build.stdout + build.stderr)
            (cls.proof / "inputs.json").write_text(json.dumps({
                "inputs": inputs, "command": command,
                "productionCopySHA256": hashlib.sha256(instrumented.encode()).hexdigest(),
                "instrumentation": "Geometry-only clip leaf; original collection/card/scroll bodies gain observation-only trace calls, disabled outside the native context input case. Added view lifecycle observers only call super. Tracking areas keep the real NSResponder owner. Commands/SQLite are replaced by a fixed menu; rightDown/up enter through NSApplication.sendEvent with no fixture popUp call.",
                "scope": "standalone AppKit interaction; no frame-rate or App-wide claim",
            }, indent=2) + "\n")
        if build.returncode:
            raise AssertionError(build.stdout + build.stderr)
        if inputs != {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}:
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
            if name == "responsive":
                run = subprocess.run([str(self.binary), name], capture_output=True, text=True,
                                     env=self.environment, cwd=self.work, timeout=25)
                stdout.write_text(run.stdout)
                stderr.write_text(run.stderr)
            else:
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
        if name == "pull-count-native-input":
            self.assertEqual(facts["hardwareAcceptance"], "not-verified")
            self.assertIn("no physical mouse or trackpad validation", facts["scope"])
            cases = {f"height{height}-{packet}" for height in (0, 64, 1200)
                     for packet in ("continuous-phased", "discrete-phaseless", "continuous-phaseless")}
            self.assertEqual(set(facts["observations"]), cases)
            for observed in facts["observations"].values():
                self.assertEqual(len(observed["events"]), 8)
                self.assertIn("maximumNativeGap", observed)
                self.assertIn("settledY", observed)
                self.assertIn("eligibleRenderSamples", observed)
        elif name == "context-menu-native-input":
            scope = facts["observations"]["contextMenuNativeScope"]
            self.assertEqual(scope["hardwareAcceptance"], "not-verified")
            self.assertIn("production WallpaperLibraryCollectionView.menu(for:)", scope["route"])
            self.assertIn("no physical trackpad validation", scope["input"])
            self.assertIn("actual trackingArea.owner", scope["hoverInput"])
            self.assertIn("no WindowServer tracking-event generation claim", scope["hoverInput"])
            for case in ("immediate-release-cancel", "held-release-cancel", "held-release-submenu-cancel", "held-release-action-detach", "live-scroll-without-end-then-held-menu"):
                observed = facts["observations"][case]
                self.assertTrue(observed["events"])
                self.assertIn("ordinarySyntheticMoveOwnerDeliveriesBeforeMenu", observed)
                self.assertIn(observed["endRelativeToReleasePacket"], ("end-before-up-enqueued", "up-enqueued-before-end"))
        elif name == "pull-count-geometry":
            positive = "-bounds-notification-shows-nonhit-count-in-native-gap"
            self.assertEqual({check for check in facts["checks"] if check.endswith(positive)},
                             {f"height{height}-inset{inset}{positive}" for height in (0, 64, 1200) for inset in (0, 56)})
        elif name == "native-refresh":
            supported = facts["observations"]["nativeRefresh"]["supported"]
            self.assertIn("no physical pull gesture", facts["scope"])
            if supported:
                self.assertIn("native-refresh-action-delivers-one-request-and-waits-for-the-real-terminal-fact", facts["checks"])
                self.assertIn("source-terminal-fact-ends-only-its-own-native-refresh", facts["checks"])
                self.assertIn("existing-input-admission-rejects-and-ends-a-blocked-native-refresh", facts["checks"])
            else:
                self.assertIn("pre27-refresh-configuration-keeps-source-callback-idle-and-does-not-add-a-custom-control", facts["checks"])
        self.assertTrue(facts["checks"], "native checks must not be empty")
        for check, passed in facts["checks"].items():
            with self.subTest(case=name, check=check):
                self.assertIs(passed, True, facts["details"].get(check, ""))

    def test_native_responsive_scrolling_survives_the_production_wheel_observer(self):
        self.check_case("responsive")

    def test_native_live_scroll_notifications_are_local_and_idempotent(self):
        self.check_case("notifications")

    def test_new_visible_cards_read_the_active_grid_and_programmatic_bounds_do_not_begin(self):
        self.check_case("new-items")

    def test_hover_restore_uses_the_clipped_visible_rect(self):
        self.check_case("clipped-hover")

    def test_hidden_window_and_inactive_App_do_not_restore_hover(self):
        self.check_case("inactive-hidden")

    def test_finger_end_hands_off_to_momentum_before_quiet_restore(self):
        self.check_case("momentum")

    def test_phase_less_wheel_extends_its_quiet_period_and_ends_once(self):
        self.check_case("wheel")

    def test_native_begin_and_window_detach_cancel_old_wheel_completion(self):
        self.check_case("cancellation")

    def test_hit_targets_clicks_and_native_selection_remain_available(self):
        self.check_case("interaction")

    def test_native_context_menu_preserves_hover_and_restores_tracking_without_scrolling(self):
        self.check_case("context-menu")

    def test_actual_collection_right_down_and_delayed_right_up_pair_native_menu_lifetime(self):
        self.check_case("context-menu-native-input")

    def test_native_refresh_uses_only_its_source_action_and_real_loading_terminal(self):
        self.check_case("native-refresh")

    def test_pull_count_uses_only_observed_native_gap_and_preserves_layout_and_admission(self):
        self.check_case("pull-count-geometry")

    def test_constructed_wheel_packets_preserve_native_contract_and_record_elasticity(self):
        self.check_case("pull-count-native-input")


if __name__ == "__main__":
    unittest.main()
