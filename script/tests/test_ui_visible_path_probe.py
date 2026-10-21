"""Exercise the production visible Video source probe across slow/stale completions."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS


ROOT = Path(__file__).resolve().parents[2]


class UIVisiblePathProbeTests(unittest.TestCase):
    def test_slow_source_probe_preserves_main_queue_and_identity(self):
        product = (ROOT / "MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridView.swift").read_text()
        template = (ROOT / "script/tests/fixtures/UIVisiblePathProbeHarness.swift").read_text()
        fields = "\n".join(next(line for line in product.splitlines() if field in line) for field in [
            "private var isMissingPathProbeInFlight", "private var visibleMissingWallpaperIDs",
            "private var needsMissingPathProbeAfterFlight",
        ])
        template = template.replace("// PRODUCTION_PROBE_STATE", fields).replace(
            "// PRODUCTION_VISIBLE_PROBE", declaration(product, "    private func probeVisibleMissingWallpapers("))
        with tempfile.TemporaryDirectory(prefix="mwx-visible-path-probe-", dir="/private/tmp") as directory:
            work = Path(directory)
            source = work / "Harness.swift"
            source.write_text(template)
            binary = work / "visible-path-probe"
            build = subprocess.run([
                "xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library", str(ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"),
                str(source), "-module-cache-path", str(work / "modules"), "-o", str(binary),
            ], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            run = subprocess.run([str(binary)],
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed, run.stderr)


if __name__ == "__main__":
    unittest.main()
