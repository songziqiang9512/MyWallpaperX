"""Real Shared card colors and controls, with font/symbol work observers."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS

ROOT = Path(__file__).resolve().parents[2]


class WallpaperCardControlsTests(unittest.TestCase):
    def test_native_font_metrics_symbols_and_original_commands(self):
        paths = ["MyWallpaperX/Shared/Components/WallpaperCardSupportViews.swift",
                 "MyWallpaperX/Shared/Components/WallpaperCardControlsView.swift",
                 "MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift",
                 "script/tests/fixtures/NativeAppHarness.swift",
                 "script/tests/fixtures/WallpaperCardControlsHarness.swift"]
        observed = paths + [str(Path(__file__).relative_to(ROOT)), "script/tests/native_app_harness.py",
                            "script/tests/test_video_thumbnail_prefetch.py"]
        hashes = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in observed}
        self.addCleanup(lambda: self.assertEqual(hashes,
            {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in observed}))
        with tempfile.TemporaryDirectory(prefix="mwx-card-controls-", dir="/private/tmp") as folder:
            work = Path(folder)
            sources = []
            for path in paths:
                target = work / Path(path).name
                shutil.copy2(ROOT / path, target)
                if target.name == "WallpaperCardSupportViews.swift":
                    source = target.read_text()
                    marker = "        let measured = (text as NSString).size(withAttributes: [.font: font]).width"
                    self.assertEqual(source.count(marker), 1)
                    target.write_text(source.replace(marker,
                        "        WallpaperCardControlsProbe.widthMeasurements += 1\n" + marker, 1))
                elif target.name == "WallpaperCardControlsView.swift":
                    source = target.read_text()
                    marker = "        let configuration = NSImage.SymbolConfiguration(pointSize: max(11, metrics.iconButtonSize * 0.56), weight: .medium)"
                    self.assertEqual(source.count(marker), 1)
                    target.write_text(source.replace(marker,
                        "        WallpaperCardControlsProbe.symbolConfigurations += 1\n" + marker, 1))
                sources.append(str(target))
            binary = prepare_native_app(work, "WallpaperCardControls")
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *sources, "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=30)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            print(json.dumps(checks, sort_keys=True))
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
