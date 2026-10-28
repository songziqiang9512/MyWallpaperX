"""Run the real Finder return coordinator with controlled external window I/O.

No Finder window, status item, screen capture, permissions prompt or GUI is opened.
The production notification subscriptions, timer lifetime and decisions remain intact.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FinderRevealTests(unittest.TestCase):
    def test_native_notification_timer_return_and_cancellation_boundaries(self):
        product = ROOT / "MyWallpaperX/Shared/UI/FinderRevealCoordinator.swift"
        fixture = ROOT / "script/tests/fixtures/FinderRevealHarness.swift"
        inputs = [product, fixture, Path(__file__).resolve()]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        source = product.read_text().replace("import AppKit\n", "")
        for actual, boundary in (
            ("NSWorkspace", "FinderWorkspace"), ("NSRunningApplication", "FinderApplication"),
            ("NSWindow", "FinderWindow"), ("CGWindowListCopyWindowInfo(", "FinderIO.windowList("),
            ("Date()", "FinderIO.now"),
        ):
            source = source.replace(actual, boundary)
        body = fixture.read_text().replace("// ACTUAL_FINDER_COORDINATOR", source)
        with tempfile.TemporaryDirectory(prefix="mwx-finder-reveal-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            harness = work / "Checks.swift"
            harness.write_text(body)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6",
                "-default-isolation", "MainActor", str(harness),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, run.stdout + run.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})
