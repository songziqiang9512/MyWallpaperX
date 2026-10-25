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


ROOT = Path(__file__).resolve().parents[2]
PRODUCTION = ROOT / "MyWallpaperX/Shared/UI/WallpaperGridScrollView.swift"
FIXTURE = ROOT / "script/tests/fixtures/GridScrollInteractionChecks.swift"


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
        inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in (PRODUCTION, FIXTURE, Path(__file__))}
        original = PRODUCTION.read_text()
        marker = "    private func observeLiveScroll() {\n"
        if original.count(marker) != 1:
            raise AssertionError("the production observer installation marker must be unique")
        instrumented = original.replace(marker, marker + """        // Geometry-only fixture injection before the original observers attach.
        if GridScrollClipProbe.usesControlledGeometry {
            contentView = GridScrollGeometryClip(frame: contentView.frame)
        }
""")
        production_copy = cls.work / PRODUCTION.name
        production_copy.write_text(instrumented)
        command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                   "-default-isolation", "MainActor", str(production_copy), str(FIXTURE),
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
                "instrumentation": "Geometry mode only: native NSClipView unconstrained-bounds leaf before unchanged observer installation; native-input/old modes use the original clip",
                "scope": "standalone AppKit interaction; no frame-rate or App-wide claim",
            }, indent=2) + "\n")
        if build.returncode:
            raise AssertionError(build.stdout + build.stderr)
        if inputs != {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in (PRODUCTION, FIXTURE, Path(__file__))}:
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
        elif name == "pull-count-geometry":
            positive = "-bounds-notification-shows-nonhit-count-in-native-gap"
            self.assertEqual({check for check in facts["checks"] if check.endswith(positive)},
                             {f"height{height}-inset{inset}{positive}" for height in (0, 64, 1200) for inset in (0, 56)})
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

    def test_pull_count_uses_only_observed_native_gap_and_preserves_layout_and_admission(self):
        self.check_case("pull-count-geometry")

    def test_constructed_wheel_packets_preserve_native_contract_and_record_elasticity(self):
        self.check_case("pull-count-native-input")


if __name__ == "__main__":
    unittest.main()
