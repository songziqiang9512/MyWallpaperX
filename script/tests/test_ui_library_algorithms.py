"""Exercise production metadata commits and SIL layout queries against their inputs/outputs."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
VIDEO_CORE = ROOT / "MyWallpaperX/Modules/VideoLibrary/Core"


def declaration(source: str, signature: str) -> str:
    """Extract an unchanged declaration into the focused owner harness."""
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for index in range(opening, len(source)):
        depth += (source[index] == "{") - (source[index] == "}")
        if depth == 0:
            return source[start:index + 1]
    raise AssertionError(f"Unclosed production declaration: {signature}")


class UILibraryAlgorithmsTests(unittest.TestCase):
    def test_metadata_batch_and_waterfall_query_equivalence(self):
        imports = (VIDEO_CORE / "WallpaperManager+ImportProcessing.swift").read_text()
        manager = (VIDEO_CORE / "WallpaperManager.swift").read_text()
        template = (ROOT / "script/tests/fixtures/UILibraryAlgorithmsHarness.swift").read_text()
        for marker, fragment in {
            "// PRODUCTION_METADATA_TYPE": declaration(
                imports, "    nonisolated private struct ImportedAssetMetadataUpdate:"
            ),
            "// PRODUCTION_METADATA_COMMIT": declaration(
                imports, "    private func applyImportedAssetMetadataUpdates("
            ),
            "// PRODUCTION_THUMBNAIL_NOTIFICATION": declaration(
                manager, "    func notifyThumbnailReady("
            ),
        }.items():
            self.assertEqual(template.count(marker), 1)
            template = template.replace(marker, fragment)

        with tempfile.TemporaryDirectory(prefix="mwx-ui-library-algorithms-", dir="/private/tmp") as folder:
            work = Path(folder)
            source = work / "Harness.swift"
            source.write_text(template)
            binary = work / "library-algorithms"
            sources = [
                ROOT / "MyWallpaperX/Models/VideoWallpaper.swift",
                ROOT / "MyWallpaperX/Modules/StaticImageLibrary/UI/SILWaterfallLayout.swift",
                source,
            ]
            build = subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", *map(str, sources),
                 "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            runtime = work / "inputs"
            runtime.mkdir()
            run = subprocess.run(
                [str(binary), str(runtime)],
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            for line in run.stderr.splitlines():
                if line.startswith("UI algorithm observations:"):
                    print(line)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed, run.stderr)


if __name__ == "__main__":
    unittest.main()
