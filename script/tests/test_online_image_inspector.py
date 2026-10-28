"""Real online Inspector layout/actions/cache consumers, with controlled I/O leaves.

The product view, footer, preview and page/session cancellation code run unchanged.
Only private visibility is opened in frozen copies for observing rendered state.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.test_wallpaper_library_inspector import prepare_image_primary_sources

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "real AppKit requires macOS")
class OnlineImageInspectorTests(unittest.TestCase):
    def test_footer_actions_grid_thumbnail_reuse_and_page_scope_cancellation(self):
        paths = [ROOT / name for name in (
            "MyWallpaperX/Models/WallpaperReference.swift",
            "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageContentProjection.swift",
            "MyWallpaperX/Shared/UI/WallpaperInspectorActions.swift",
            "MyWallpaperX/Shared/Components/WallpaperLibraryControlStyle.swift",
            "MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift",
            "MyWallpaperX/Shared/UI/InspectorFadingScrollView.swift",
            "MyWallpaperX/Modules/StaticImageLibrary/UI/SILInspectorSupport.swift",
            "MyWallpaperX/Shared/UI/OnlineImageInspectorView.swift",
            "script/tests/fixtures/OnlineImageLibraryAppStub.swift",
            "script/tests/fixtures/OnlineImageInspectorHarness.swift",
        )]
        identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [*paths, Path(__file__)]}
        with tempfile.TemporaryDirectory(prefix="mwx-online-image-inspector-", dir="/private/tmp") as directory:
            work = Path(directory)
            primary_sources, primary_inputs = prepare_image_primary_sources(ROOT, work)
            paths += [p for p in primary_sources if p not in paths]
            identities.update({str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in primary_inputs})
            frozen = []
            for path in paths:
                copied = work / path.name
                source = path.read_text()
                if path.name in ("OnlineImageInspectorView.swift", "SILInspectorSupport.swift"):
                    source = re.sub(r"\bprivate\s+", "", source)
                if path.name == "OnlineImageInspectorView.swift":
                    self.assertEqual(source.count("NSWorkspace.shared.open("), 1)
                    source = source.replace("NSWorkspace.shared.open(", "InspectorBrowserProbe.open(")
                copied.write_text(source)
                frozen.append(copied)
            home = work / "home"; home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *map(str, frozen), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120, env=environment)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=35, env=environment)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(check=name): self.assertIs(passed, True, result.stderr)
            print(json.dumps(checks, sort_keys=True))
        self.assertEqual(identities, {str(path): hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in identities})


if __name__ == "__main__":
    unittest.main()
