"""Full App cell adapter with native collection construction and recording media leaves.

No window, user library, scanner, decoder or network is started. The new image
card's actual applyTransfer and Commands' cancel/add blocks run with recording
card controls and fixed-reference preview callbacks; this does not prove image
drawing or full menu composition.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit")
class WallpaperLibraryCellAdapterTests(unittest.TestCase):
    def test_identity_state_callbacks_and_display_demand(self):
        sources = [ROOT / "MyWallpaperX" / path for path in (
            "Models/WallpaperReference.swift", "Models/WallpaperContent.swift", "Models/WallpaperLibraryPage.swift", "Models/VideoWallpaper.swift",
            "Core/OnlineImages/OnlineImageModels.swift", "Core/OnlineImages/OnlineImageContentProjection.swift",
            "Shared/Components/ActionMenuItem.swift", "Shared/UI/WallpaperLibrarySheetPresentation.swift",
            "App/WallpaperLibraryCellAdapter.swift", "Shared/Components/WallpaperCardInteractionView.swift",
            "Shared/UI/WallpaperGridScrollView.swift")]
        sources.append(ROOT / "script/tests/fixtures/OnlineImageLibraryAppStub.swift")
        sources.append(ROOT / "script/tests/fixtures/WallpaperLibraryCellAdapterHarness.swift")
        card = ROOT / "MyWallpaperX/Shared/UI/OnlineImageGridItem.swift"
        commands = ROOT / "MyWallpaperX/App/WallpaperLibraryCommands.swift"
        inputs = sources + [card, commands]
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        with tempfile.TemporaryDirectory(prefix="mwx-cell-adapter-", dir="/private/tmp") as directory:
            work = Path(directory)
            fixture = sources[-1].read_text().replace("// ACTUAL_IMAGE_TRANSFER", declaration(card.read_text(), "    func applyTransfer("))
            fixture = fixture.replace("// ACTUAL_IMAGE_CONTROLS", declaration(card.read_text(), "    private func updateControls("))
            fixture = fixture.replace("// ACTUAL_MENU_ADD", declaration(commands.read_text(), "        func add(_ title:"))
            fixture = fixture.replace("// ACTUAL_IMAGE_CANCEL", declaration(commands.read_text(), "            if let assetID = OnlineImageAssetID(reference: item.providerReference),"))
            frozen = []
            for index, source in enumerate(sources):
                target = work / f"Source{index}.swift"
                if source == sources[-1]:
                    target.write_text(fixture)
                else:
                    target.write_bytes(source.read_bytes())
                frozen.append(target)
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                "-default-isolation", "MainActor", *map(str, frozen), "-module-cache-path", str(work / "modules"),
                "-o", str(binary)], capture_output=True, text=True, timeout=150)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"; home.mkdir()
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30,
                env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 27)
            for name, passed in checks.items():
                with self.subTest(name=name): self.assertIs(passed, True)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})


if __name__ == "__main__":
    unittest.main()
