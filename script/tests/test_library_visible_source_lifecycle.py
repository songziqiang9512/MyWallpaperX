"""Real local Catalog workers reject blocked, superseded resource receipts.

Replaces the retired Video/SIL private-grid probes. Current missing/recovery,
multi-consumer cadence and preview repair remain covered by their owning gates.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.library_catalog_fixture import assemble_catalog_fixture, write_catalog_sources
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class LibraryVisibleSourceLifecycleTests(unittest.TestCase):
    def test_real_blocked_video_and_image_receipts_preserve_current_sources(self):
        fixture, controller, paths, inputs = assemble_catalog_fixture(
            "script/tests/fixtures/LibraryVisibleSourceLifecycleHarness.swift")
        with tempfile.TemporaryDirectory(prefix="mwx-visible-source-lifecycle-", dir="/private/tmp") as directory:
            work = Path(directory)
            (work / "Checks.swift").write_text(fixture)
            (work / "Controller.swift").write_text(controller)
            compiled = write_catalog_sources(work, paths)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *compiled, str(work / "Controller.swift"), str(work / "Checks.swift"),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=150)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work / "media")], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home")))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertEqual(len(checks), 40)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, run.stderr)
            negative = subprocess.run([str(binary), str(work / "negative-media")], capture_output=True, text=True, timeout=40,
                env=dict(os.environ, HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home"), MWX_TEST_DROP_REPLACEMENT="1"))
            self.assertEqual(negative.returncode, 0, negative.stdout + negative.stderr)
            negative_checks = json.loads(negative.stdout)
            self.assertEqual(set(negative_checks), set(checks))
            self.assertEqual({name for name, passed in negative_checks.items() if not passed}, {
                provider + ":replacePath:lateRealFileResultCannotOverwriteAcceptedIdentityOrderOrFacts"
                for provider in ("videoLibrary", "staticImageLibrary")})
        self.assertEqual(inputs, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in inputs})


if __name__ == "__main__":
    unittest.main()
