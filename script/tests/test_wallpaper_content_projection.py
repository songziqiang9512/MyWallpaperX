"""Four real source models projected through metadata-only production adapters."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration


ROOT = Path(__file__).resolve().parents[2]


class WallpaperContentProjectionTests(unittest.TestCase):
    def test_four_source_identity_publication_capabilities_and_update_independence(self):
        fixture = (ROOT / "script/tests/fixtures/WallpaperContentProjectionHarness.swift").read_text()
        sil = (ROOT / "MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift").read_text()
        fixture = fixture.replace("// PRODUCTION_STATIC_IMAGE_MODEL", declaration(sil, "struct SILWallpaper:"))
        fixture += '\n' + declaration((ROOT / 'MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopAgeRatingSupport.swift').read_text(),
                                     'nonisolated enum SteamWorkshopContentRatingSupport')
        with tempfile.TemporaryDirectory(prefix="mwx-content-projection-", dir="/private/tmp") as directory:
            work = Path(directory)
            source = work / "Checks.swift"
            source.write_text(fixture)
            binary = work / "checks"
            paths = [
                "MyWallpaperX/Models/VideoWallpaper.swift",
                "MyWallpaperX/Models/WallpaperReference.swift",
                "MyWallpaperX/Models/WallpaperContent.swift",
                "MyWallpaperX/Modules/VideoLibrary/Core/VideoLibraryContentProjection.swift",
                "MyWallpaperX/Modules/StaticImageLibrary/Core/StaticImageLibraryContentProjection.swift",
                "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopModels.swift",
                "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopDownloadProgress.swift",
                "MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebValidationModels.swift",
                "MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopLibraryContentProjection.swift",
                "MyWallpaperX/Modules/Pixabay/Core/PixabayModels.swift",
                "MyWallpaperX/Modules/Pixabay/Core/PixabayDownloadedContent.swift",
                "MyWallpaperX/Modules/Pixabay/Core/PixabayLibraryContentProjection.swift",
            ]
            build = subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor",
                 *[str(ROOT / path) for path in paths], str(source), "-module-cache-path", str(work / "modules"),
                 "-o", str(binary)], capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            run = subprocess.run([str(binary)], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                                 capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
