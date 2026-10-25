"""Real SIL prefetch/cache and complete AppKit-card request lifecycle.

The complete unified grid and App adapter drive the original SIL provider;
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

from script.tests.sil_unified_grid_fixture import assemble
from script.tests.native_app_harness import prepare_native_app, run_native_app

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "MyWallpaperX/Shared/UI"
SIL = ROOT / "MyWallpaperX/Modules/StaticImageLibrary"


@unittest.skipUnless(sys.platform == "darwin", "requires native AppKit")
class SILThumbnailDemandTests(unittest.TestCase):
    def test_real_nearby_decode_and_card_loading_lifetime(self):
        fixture_path = ROOT / "script/tests/fixtures/SILThumbnailDemandHarness.swift"
        fixture = fixture_path.read_text()
        with tempfile.TemporaryDirectory(prefix="mwx-sil-demand-", dir="/private/tmp") as folder:
            work = Path(folder)
            sources, originals = assemble(work, cache_name="SILLoadObservation.cache", observe_loads=True, observe_failure_signatures=True)
            sources += [ROOT / "script/tests/fixtures/GridCardInteractionChecks.swift",
                        ROOT / "script/tests/fixtures/NativeAppHarness.swift",
                        ROOT / "script/tests/fixtures/WallpaperLibraryGridCardReflowChecks.swift"]
            originals += [fixture_path, Path(__file__).resolve(), *sources[-3:]]
            inputs = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in originals}
            (work / "Checks.swift").write_text(fixture)
            binary = work / "checks"
            # Match the product's Swift language mode and default actor isolation.
            command = ["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                       "-parse-as-library", *map(str, sources),
                       str(work / "Checks.swift"), "-module-cache-path", str(work / "modules"),
                       "-o", str(binary)]
            build = subprocess.run(command, capture_output=True, text=True, timeout=150)
            proof = Path(os.environ["MWX_SIL_DEMAND_PROOF_DIR"]) if os.environ.get("MWX_SIL_DEMAND_PROOF_DIR") else None
            if proof:
                proof.mkdir(parents=True, exist_ok=True)
                (proof / "build.log").write_text(build.stdout + build.stderr)
                (proof / "inputs.json").write_text(json.dumps(inputs, indent=2))
                (proof / "compiled-inputs.json").write_text(json.dumps({
                    str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources, work / "Checks.swift"]
                }, indent=2))
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
                                     for p in originals})

            # Additional active-hover checks have the same LaunchServices status
            # boundary as the native Online gate, not a claimed App exit code.
            native_binary = prepare_native_app(work, "SILThumbnailDemandChecks")
            shutil.copy2(binary, native_binary)
            interaction = run_native_app(native_binary, ["--card-interactions"], timeout=45,
                                         proof_environment="MWX_SIL_DEMAND_PROOF_DIR")
            self.assertEqual(interaction.launch_returncode, 0, interaction.stdout + interaction.stderr)
            interaction_checks = json.loads(interaction.stdout)
            self.assertEqual(len(interaction_checks), 16)
            for name, passed in interaction_checks.items():
                with self.subTest(name=name):
                    self.assertIs(passed, True)
            if proof:
                (proof / "card-interactions.json").write_text(interaction.stdout)
                (proof / "card-interactions-runtime.log").write_text(interaction.stderr)
            reflow = run_native_app(native_binary, ["--card-reflow"], timeout=45)
            self.assertEqual(reflow.launch_returncode, 0, reflow.stdout + reflow.stderr)
            reflow_checks = json.loads(reflow.stdout)
            self.assertEqual(len(reflow_checks), 17)
            for name, passed in reflow_checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, reflow.stderr)
            if proof:
                (proof / "reflow.json").write_text(reflow.stdout)
                (proof / "reflow-runtime.log").write_text(reflow.stderr)


if __name__ == "__main__":
    unittest.main()
