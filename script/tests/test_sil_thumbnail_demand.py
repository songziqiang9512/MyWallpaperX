"""Real SIL prefetch/cache and complete AppKit-card request lifecycle.

The grid uses production demand methods with an injected visible-index source;
files, ImageIO, shared cache, cancellation and NSWindow visibility are real.
The complete card only exposes private state. This is not an FPS benchmark.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration
from script.tests.native_app_harness import prepare_native_app, run_native_app

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "MyWallpaperX/Shared/UI"
SIL = ROOT / "MyWallpaperX/Modules/StaticImageLibrary"


@unittest.skipUnless(sys.platform == "darwin", "requires native AppKit")
class SILThumbnailDemandTests(unittest.TestCase):
    def test_real_nearby_decode_and_card_loading_lifetime(self):
        grid_path = SIL / "UI/SILGridContainerView.swift"
        card_path = SIL / "UI/SILGridItemView.swift"
        model_path = SIL / "Core/SILService.swift"
        fixture_path = ROOT / "script/tests/fixtures/SILThumbnailDemandHarness.swift"
        grid = grid_path.read_text()
        fields = ["thumbnailPrefetchWork", "thumbnailPrefetchTokens", "lastPrefetchLeadingIndex", "thumbnailWindowObservation"]
        state = "\n".join(next(line for line in grid.splitlines() if "private var " + field in line)
                          for field in fields)
        methods = "\n".join(declaration(grid, name) for name in [
            "    private func cancelThumbnailPrefetch(",
            "    private func scheduleThumbnailPrefetch(",
            "    private func prefetchNearbyThumbnails(",
            "    private func updateVisibleThumbnailDemand(",
            "    private var thumbnailDemandIsVisible:",
            "    override func viewDidMoveToWindow(",
            "    override func viewDidHide(",
            "    override func viewDidUnhide(",
        ])
        leaves = "\n".join(declaration(grid, name) for name in [
            "private nonisolated func silGridThumbnailImage(",
            "private nonisolated func silGridThumbnailFailureSignature(",
            "private final class SILDecodeFailureSignature:",
        ])
        signature_start = leaves.index("private nonisolated func silGridThumbnailFailureSignature(")
        signature_opening = leaves.index("{", signature_start) + 1
        leaves = leaves[:signature_opening] + "\n    SILSignatureReads.shared.record()" + leaves[signature_opening:]
        visible_loader = declaration(grid, "            ) { [weak self] cancellation, completion in")
        visible_loader = visible_loader[visible_loader.index("{"):]
        fixture = fixture_path.read_text().replace("// PRODUCTION_GRID_STATE", state).replace(
            "// PRODUCTION_GRID_METHODS", methods).replace("// PRODUCTION_IMAGE_LEAVES", leaves).replace(
            "// PRODUCTION_VISIBLE_LOADER", visible_loader)
        fixture = fixture.replace("// PRODUCTION_MODEL", declaration(model_path.read_text(), "struct SILWallpaper:"))
        fixture = fixture.replace("// PRODUCTION_RESULT", declaration(grid, "enum SILThumbnailLoadResult"))
        # Expose observation only; all card methods, closures and NSView hierarchy remain intact.
        card = declaration(card_path.read_text(), "final class SILGridItem:")
        card = re.sub(r"\bprivate\s+", "", card)
        sources = [SHARED / name for name in [
            "DecodedThumbnailMemoryCache.swift", "GridThumbnailDecoder.swift", "ThumbnailCache.swift",
            "GridThumbnailPrefetchDemand.swift", "AppearanceAwareContainerView.swift",
            "NSViewExtensions.swift", "UIInteractionAnimation.swift", "WallpaperGridScrollView.swift",
        ]]
        sources += [ROOT / "script/tests/fixtures/GridCardInteractionChecks.swift",
                    ROOT / "script/tests/fixtures/NativeAppHarness.swift"]
        inputs = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in sources + [grid_path, card_path, model_path, fixture_path]}
        with tempfile.TemporaryDirectory(prefix="mwx-sil-demand-", dir="/private/tmp") as folder:
            work = Path(folder)
            (work / "Card.swift").write_text("import AppKit\nimport QuartzCore\n" + card)
            (work / "Checks.swift").write_text(fixture)
            binary = work / "checks"
            # Match the product's Swift language mode and default actor isolation.
            command = ["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                       "-parse-as-library", *map(str, sources), str(work / "Card.swift"),
                       str(work / "Checks.swift"), "-module-cache-path", str(work / "modules"),
                       "-o", str(binary)]
            build = subprocess.run(command, capture_output=True, text=True, timeout=150)
            proof = Path(os.environ["MWX_SIL_DEMAND_PROOF_DIR"]) if os.environ.get("MWX_SIL_DEMAND_PROOF_DIR") else None
            if proof:
                proof.mkdir(parents=True, exist_ok=True)
                (proof / "build.log").write_text(build.stdout + build.stderr)
                (proof / "inputs.json").write_text(json.dumps(inputs, indent=2))
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            run = subprocess.run([str(binary), str(work / "images")], capture_output=True, text=True,
                                 timeout=45, env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)))
            if proof:
                (proof / "runtime.log").write_text(run.stdout + run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            for name, value in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(value)
            self.assertTrue({
                "emptyFailureSetPrefetchDoesNotReadSignature", "emptyFailureSetVisibleDoesNotReadSignature",
                "visibleMissingFileKeepsFeedbackWithoutSignature", "decodeFailureRecordsCurrentSignature",
                "unchangedFailureSkipsDecode", "sameSecondSameSizeReplacementInvalidatesFailure",
                "prefetchFailureSkipsDecode", "prefetchReplacementUsesPreciseSignature",
                "cancelledVisibleMissDoesNotCompleteOrReadSignature",
            }.issubset(checks), checks)
            self.assertGreaterEqual(len(checks), 25)
            self.assertEqual(inputs, {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                                     for p in sources + [grid_path, card_path, model_path, fixture_path]})

            # Additional active-hover checks have the same LaunchServices status
            # boundary as the native Online gate, not a claimed App exit code.
            native_binary = prepare_native_app(work, "SILThumbnailDemandChecks")
            shutil.copy2(binary, native_binary)
            interaction = run_native_app(native_binary, ["--card-interactions"], timeout=45,
                                         proof_environment="MWX_SIL_DEMAND_PROOF_DIR")
            self.assertEqual(interaction.launch_returncode, 0, interaction.stdout + interaction.stderr)
            interaction_checks = json.loads(interaction.stdout)
            self.assertEqual(len(interaction_checks), 9)
            for name, passed in interaction_checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True)
            if proof:
                (proof / "card-interactions.json").write_text(interaction.stdout)
                (proof / "card-interactions-runtime.log").write_text(interaction.stderr)


if __name__ == "__main__":
    unittest.main()
