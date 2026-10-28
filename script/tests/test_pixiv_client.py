"""Compile the actual Pixiv source against deterministic HTTP/schema fixtures.

No external requests, real accounts, stored cookies, WebViews, or App builds.
Includes typed source filters, bounded author slices and optional identity metadata;
the held identity response proves cookie preparation never awaits the homepage.
Shared identity, rating and OnlineImage models are compiled unchanged.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "MyWallpaperX/Modules/Pixiv/Core"


@unittest.skipUnless(sys.platform == "darwin", "Foundation/WebKit require macOS")
class PixivClientTests(unittest.TestCase):
    def test_source_queries_pages_assets_and_session_boundaries(self):
        sources = [ROOT / "MyWallpaperX/Models/WallpaperReference.swift", ROOT / "MyWallpaperX/Models/WallpaperContent.swift",
                   *sorted(CORE.glob("*.swift")),
                   ROOT / "MyWallpaperX/Modules/Pixiv/UI/PixivLoginPanelController.swift",
                   ROOT / "MyWallpaperX/Shared/WallpaperNetworkSession.swift",
                   ROOT / "MyWallpaperX/Shared/UI/WallpaperLibrarySheetPresentation.swift"]
        fixture = ROOT / "script/tests/fixtures/PixivClientHarness.swift"
        account_status = declaration((ROOT / "MyWallpaperX/App/WallpaperLibraryOnlineImages.swift").read_text(),
            "    var pixivAccountStatus: String {")
        shared = ROOT / "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift"
        with tempfile.TemporaryDirectory(prefix="mwx-pixiv-", dir="/private/tmp") as directory:
            work = Path(directory)
            home = work / "home"
            home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            snapshot = work / "sources"
            snapshot.mkdir()
            frozen = []
            for source in [shared, *sources, fixture]:
                target = snapshot / source.name
                content = source.read_text()
                if source == fixture: content = content.replace("    // ACTUAL_PIXIV_ACCOUNT_STATUS", account_status)
                target.write_text(content)
                frozen.append(str(target))
            command = ["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                       "-target", "arm64-apple-macos26.0",
                       "-warnings-as-errors", "-parse-as-library", *frozen, "-module-cache-path", str(work / "modules"),
                       "-o", str(work / "checks")]
            build = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(work / "checks")], capture_output=True, text=True,
                                 env=environment, timeout=45)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("Pixiv behavior checks passed", run.stdout)
            print(run.stdout.strip())


if __name__ == "__main__":
    unittest.main()
