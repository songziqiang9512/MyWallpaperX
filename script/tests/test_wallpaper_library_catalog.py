"""Live Combine catalog + real local facts; services' UI/renderer leaves excluded."""
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


class WallpaperLibraryCatalogTests(unittest.TestCase):
    def test_live_sources_resource_revisions_update_failure_and_namespace(self):
        fixture, controller, paths, inputs = assemble_catalog_fixture()
        with tempfile.TemporaryDirectory(prefix="mwx-live-catalog-", dir="/private/tmp") as directory:
            work = Path(directory)
            (work / "Checks.swift").write_text(fixture)
            (work / "Controller.swift").write_text(controller)
            compiled_paths = write_catalog_sources(work, paths)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *compiled_paths, str(work / "Controller.swift"), str(work / "Checks.swift"),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=150)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(work / "media")], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(work / "home"), CFFIXED_USER_HOME=str(work / "home")))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
            self.assertEqual(inputs, {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in inputs})


if __name__ == "__main__":
    unittest.main()
