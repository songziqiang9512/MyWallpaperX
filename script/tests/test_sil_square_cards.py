"""Actual native square-grid geometry, shared image card controls and apply routing."""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from script.tests.native_app_harness import prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration


ROOT = Path(__file__).resolve().parents[2]


class SILSquareCardTests(unittest.TestCase):
    def test_native_flow_layout_card_actions_and_existing_apply_route(self):
        product = ROOT / "MyWallpaperX/Modules/StaticImageLibrary/UI"
        card = declaration((product / "SILGridItemView.swift").read_text(), "final class SILGridItem:")
        card = re.sub(r"\bprivate\s+", "", card)
        fixture = (ROOT / "script/tests/fixtures/SILSquareCardHarness.swift").read_text()
        model = (ROOT / "MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift").read_text()
        fixture = fixture.replace("// PRODUCTION_MODEL", declaration(model, "struct SILWallpaper:"))
        fixture = fixture.replace("// PRODUCTION_RESULT", declaration((product / "SILThumbnailProvider.swift").read_text(), "enum SILThumbnailLoadResult"))
        commands = (ROOT / "MyWallpaperX/App/WallpaperLibraryCommands.swift").read_text()
        fixture = fixture.replace("// PRODUCTION_PRIMARY_ACTIONS", "\n".join(declaration(commands, signature) for signature in (
            "    func makePrimaryAction(", "    func makeApplyAction(", "    func stop(")))
        shared = ROOT / "MyWallpaperX/Shared"
        sources = [shared / "UI" / name for name in (
            "DecodedThumbnailMemoryCache.swift", "GridThumbnailDecoder.swift", "ThumbnailCache.swift",
            "AppearanceAwareContainerView.swift", "NSViewExtensions.swift", "UIInteractionAnimation.swift",
            "WallpaperGridScrollView.swift", "BoxSelectionState.swift", "GridThumbnailPrefetchDemand.swift")]
        sources += [ROOT / "MyWallpaperX" / name for name in (
                    "Models/WallpaperReference.swift", "Models/WallpaperContent.swift", "Models/WallpaperLibraryPage.swift",
                    "Shared/Components/WallpaperLibraryGridMetrics.swift", "Shell/WallpaperLibraryGridController.swift")]
        sources += [ROOT / "MyWallpaperX/Core/PlaybackControl" / name for name in (
            "WallpaperRuntimeSwitch.swift", "PlaybackSwitchTransaction.swift", "WallpaperPlaybackSequence.swift")]
        sources += [shared / "Components/WallpaperCardInteractionView.swift",
                    shared / "Components/WallpaperCardSupportViews.swift", shared / "Components/WallpaperCardControlsView.swift",
                    ROOT / "script/tests/fixtures/NativeAppHarness.swift"]
        with tempfile.TemporaryDirectory(prefix="mwx-sil-square-", dir="/private/tmp") as folder:
            work = Path(folder)
            (work / "Card.swift").write_text("import AppKit\nimport QuartzCore\n" + card)
            (work / "Checks.swift").write_text(fixture)
            binary = prepare_native_app(work, "SILSquareCards")
            build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                "-default-isolation", "MainActor", *map(str, sources), str(work / "Card.swift"), str(work / "Checks.swift"),
                "-module-cache-path", str(work / "modules"), "-o", str(binary)], capture_output=True, text=True, timeout=150)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, timeout=45)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertGreaterEqual(len(checks), 25)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True, run.stderr)


if __name__ == "__main__":
    unittest.main()
