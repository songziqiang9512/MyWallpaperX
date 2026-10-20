"""Exercise real SIL JSON/header loading with delayed metadata completions."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration


ROOT = Path(__file__).resolve().parents[2]


class SILMetadataLoadingTests(unittest.TestCase):
    def test_initial_publication_and_safe_metadata_field_patches(self):
        product = (ROOT / "MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift").read_text()
        fixture = (ROOT / "script/tests/fixtures/SILMetadataLoadingHarness.swift").read_text()
        state = next(line for line in product.splitlines() if "private var metadataLoadGeneration:" in line)
        state += "\n" + declaration(product, "    nonisolated private struct MissingImageDimensions:")
        load = declaration(product, "    func load()")
        self.assertEqual(load.count("CGImageSourceCreateWithURL"), 1)
        load = load.replace("CGImageSourceCreateWithURL", "ProbeImageSourceCreateWithURL")
        utility = "DispatchQueue.global(qos: .utility).async { [weak self] in"
        self.assertEqual(load.count(utility), 1)
        # Only the header leaf is held. A main-queue sentinel follows the actual
        # utility batch and its product field-patch callback, including failure.
        load = load.replace(utility, utility + "\n            defer { DispatchQueue.main.async { completedBatches += 1 } }")
        save = declaration(product, "    func save()")
        opening = save.index("{")
        save = save[:opening + 1] + "\n        saves += 1; saveThreads.append(Thread.isMainThread)" + save[opening + 1:]
        methods = "\n".join([load, save, declaration(product, "    func invalidatePendingMetadataLoad()"),
                             declaration(product, "    private func applyLoadedImageDimensions(")])
        grid = (ROOT / "MyWallpaperX/Modules/StaticImageLibrary/UI/SILGridContainerView.swift").read_text()
        grid_methods = "\n".join(declaration(grid, signature) for signature in [
            "    func update(wallpapers:", "    private func applySnapshot(",
            "    private func reloadPendingDimensionItems(",
        ])
        item = (ROOT / "MyWallpaperX/Modules/StaticImageLibrary/UI/SILGridItemView.swift").read_text()
        configure = declaration(item, "    func configure(")
        metadata_text = configure[configure.index("{") + 1:configure.index("        applySelectionState(")]
        reset = (ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Persistence.swift").read_text()
        reset = declaration(reset, "    func resetToFreshInstallState()")
        self.assertLess(reset.index("sil.invalidatePendingMetadataLoad()"), reset.index("sil.wallpapers.removeAll()"))
        source = fixture.replace("// PRODUCTION_MODEL", declaration(product, "struct SILWallpaper:"))
        source = source.replace("// PRODUCTION_STATE", state).replace("// PRODUCTION_METHODS", methods)
        source = source.replace("// PRODUCTION_GRID_METHODS", grid_methods).replace("// PRODUCTION_CELL_METADATA", metadata_text)
        with tempfile.TemporaryDirectory(prefix="mwx-sil-metadata-", dir="/private/tmp") as directory:
            work = Path(directory)
            swift = work / "Checks.swift"
            swift.write_text(source)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-default-isolation", "MainActor",
                                    "-parse-as-library", str(swift), "-module-cache-path", str(work / "modules"),
                                    str(ROOT / "MyWallpaperX/Modules/StaticImageLibrary/UI/SILWaterfallLayout.swift"),
                                    "-o", str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            run = subprocess.run([str(binary), str(work / "fixtures")],
                                 env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                                 capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 12)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == "__main__":
    unittest.main()
