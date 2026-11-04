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
from script.tests.native_app_harness import native_app_session, prepare_native_app, run_native_app
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "MyWallpaperX/Shared/UI"
SIL = ROOT / "MyWallpaperX/Modules/StaticImageLibrary"


@unittest.skipUnless(sys.platform == "darwin", "requires native AppKit")
class SILThumbnailDemandTests(unittest.TestCase):
    def _prepare_fixture(self, work):
        fixture_path = ROOT / "script/tests/fixtures/SILThumbnailDemandHarness.swift"
        fixture = fixture_path.read_text()
        inspector = SIL / "UI/SILInspectorView.swift"
        for marker, signature in (("PREVIEW_LOAD", "    private func loadPreviewImage("),
                                  ("MOUNT", "    override func viewDidMoveToWindow(")):
            self.assertEqual(fixture.count("// ACTUAL_INSPECTOR_" + marker), 1)
            fixture = fixture.replace("// ACTUAL_INSPECTOR_" + marker, declaration(inspector.read_text(), signature))
        sources, originals = assemble(work, cache_name='(CommandLine.arguments.contains("--resident-return") || CommandLine.arguments.contains("--adaptive-return")) ? SILThumbnailStore.sharedCache : SILLoadObservation.cache',
                                     observe_loads=True, observe_failure_signatures=True)
        sources += [ROOT / "script/tests/fixtures/GridCardInteractionChecks.swift",
                    ROOT / "script/tests/fixtures/NativeAppHarness.swift",
                    ROOT / "script/tests/fixtures/WallpaperLibraryGridCardReflowChecks.swift"]
        originals += [fixture_path, inspector, Path(__file__).resolve(), *sources[-3:]]
        # Only the decoded owner is exposed for the failure-bypass then
        # successful disk-return check. Product cache API stays unchanged.
        cache_source = SHARED / "ThumbnailCache.swift"
        cache = cache_source.read_text()
        self.assertEqual(cache.count("private let imageCache:"), 1)
        method = declaration(cache, "    func load(")
        boundary = "        guard let request = beginImageRequest("
        self.assertEqual(method.count(boundary), 1)
        observed = method.replace(boundary,
            "        SILCacheAdmissions.shared.registered(key, cachesFailure: cachesFailure)\n" + boundary, 1)
        cache = cache.replace(method, observed, 1)
        cache_copy = work / "ThumbnailCache.swift"
        self.assertEqual(cache.count("private func diskCacheURL("), 1)
        cache_copy.write_text(cache.replace("private let imageCache:", "let imageCache:", 1)
            .replace("private func diskCacheURL(", "func diskCacheURL(", 1))
        sources[sources.index(cache_source)] = cache_copy
        return sources, originals, fixture

    def test_real_nearby_decode_and_card_loading_lifetime(self):
        with tempfile.TemporaryDirectory(prefix="mwx-sil-demand-", dir="/private/tmp") as folder:
            work = Path(folder)
            sources, originals, fixture = self._prepare_fixture(work)
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
            with native_app_session():
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
                "oneFailedPathDoesNotMakeOtherColdPathsReadSignatures",
                "warmProviderRemainsSynchronousWithoutSignatureOrDecode",
                "clearAllMakesSameSizeMtimeRepairRetryableInOriginalProvider",
                "singleKeyMakesSameSizeMtimeRepairRetryableInOriginalProvider",
                "oldInFlightNilAfterClearCannotRestoreFailureAuthority",
                "sameProviderRecoversAfterClearingHeldOldFailure",
                "joinedProviderDoesNotGuessAnotherProducersFailureIdentity",
                "unknownProducerIdentityRetriesActualImageIOInsteadOfReusingNegative",
                "trueThenFalseConsumersShareOneProducerAndBothFinish",
                "falseThenTrueConsumersShareOneProducerAndBothFinish",
                "independentFalseBypassesEarlierTrueFailure",
                "independentFalseDoesNotManufactureNegativeCache",
                "inspectorFalsePolicyKeepsItsOwnFailedDemandRetryable",
                "inspectorOriginalPreviewMethodBypassesNegativeCacheAndCoversItsBackingBounds",
                "successfulFalseDemandRetiresOldFailureAcrossMemoryEviction",
            }.issubset(checks), checks)
            self.assertGreaterEqual(len(checks), 25)
            self.assertEqual(inputs, {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                                     for p in originals})

            # Additional native checks have the same LaunchServices status
            # boundary as the native Online gate, not a claimed App exit code.
            native_binary = prepare_native_app(work, "SILThumbnailDemandChecks")
            shutil.copy2(binary, native_binary)
            resident = run_native_app(native_binary, ["--resident-return", str(work / "resident-images")], timeout=45,
                                      proof_environment="MWX_SIL_DEMAND_PROOF_DIR")
            self.assertEqual(resident.launch_returncode, 0, resident.stdout + resident.stderr)
            self.assertTrue(resident.stdout.strip().startswith("{"), resident.stdout + resident.stderr)
            resident_checks = json.loads(resident.stdout)
            self.assertIs(resident_checks.get("productionResidentReturnCaseCompleted"), True, resident.stdout + resident.stderr)
            for name, passed in resident_checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, resident.stdout + resident.stderr)
            if proof:
                (proof / "resident-return.json").write_text(resident.stdout)
                (proof / "resident-return-runtime.log").write_text(resident.stderr)
            interaction = run_native_app(native_binary, ["--card-interactions"], timeout=45,
                                         proof_environment="MWX_SIL_DEMAND_PROOF_DIR")
            self.assertEqual(interaction.launch_returncode, 0, interaction.stdout + interaction.stderr)
            self.assertTrue(interaction.stdout.strip().startswith("{"), interaction.stdout + interaction.stderr)
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
            self.assertTrue(reflow.stdout.strip().startswith("{"), reflow.stdout + reflow.stderr)
            reflow_checks = json.loads(reflow.stdout)
            self.assertEqual(len(reflow_checks), 17)
            for name, passed in reflow_checks.items():
                with self.subTest(name=name): self.assertIs(passed, True, reflow.stderr)
            if proof:
                (proof / "reflow.json").write_text(reflow.stdout)
                (proof / "reflow-runtime.log").write_text(reflow.stderr)


    def test_warm_card_final_preserves_geometry_without_full_relayout(self):
        with tempfile.TemporaryDirectory(prefix="mwx-sil-warm-layout-", dir="/private/tmp") as directory:
            work = Path(directory)
            sources, originals, fixture = self._prepare_fixture(work)
            # Count the full body after its existing key guard, not entry/skip.
            card = work / "SILCard.swift"
            body = card.read_text()
            boundary = "        lastLayoutInputs = inputs"
            self.assertEqual(body.count(boundary), 1)
            card.write_text(body.replace(boundary, boundary +
                "\n        SILFullLayoutObservation.bodies[ObjectIdentifier(self), default: 0] += 1", 1))
            generated = work / "Checks.swift"; generated.write_text(fixture)
            inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in originals}
            compiled = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [*sources, generated]}
            binary = prepare_native_app(work, "SILWarmLayout")
            command = ["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                "-parse-as-library", *map(str, sources), str(generated), "-module-cache-path", str(work / "modules"), "-o", str(binary)]
            build = subprocess.run(command, capture_output=True, text=True, timeout=150)
            proof = Path(os.environ["MWX_SIL_DEMAND_PROOF_DIR"]) if os.environ.get("MWX_SIL_DEMAND_PROOF_DIR") else None
            if proof:
                proof.mkdir(parents=True, exist_ok=True)
                (proof / "warm-layout-build.log").write_text(build.stdout + build.stderr)
                (proof / "warm-layout-inputs.json").write_text(json.dumps({"source": inputs, "compiled": compiled, "command": command}, indent=2))
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, ["--warm-layout"], timeout=35, proof_environment="MWX_SIL_DEMAND_PROOF_DIR")
            if proof:
                (proof / "warm-layout-results.json").write_text(run.stdout)
                (proof / "warm-layout-runtime.log").write_text(run.stderr)
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks, run.stdout + run.stderr)
            print(json.dumps({"warmLayoutChecks": checks}, sort_keys=True))
            for name, passed in checks.items():
                with self.subTest(check=name): self.assertIs(passed, True, run.stdout + run.stderr)
            observations = [json.loads(line.removeprefix("SIL full layout work: "))
                for line in run.stderr.splitlines() if line.startswith("SIL full layout work: ")]
            self.assertEqual(len(observations), 1, run.stderr)
            counts = observations[0]
            print(json.dumps({"fullLayoutBodies": counts}, sort_keys=True))
            self.assertEqual(inputs, {str(path): hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in originals})
            self.assertEqual(compiled, {str(path): hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in compiled})
            budgets = {"warmProviderFinal": 0, "selectedWarmFinal": 0, "changedAspectFinal": 0, "changedSize": 1,
                "repeatUnavailable": 0, "staleAfterReuse": 0, "reusedFinal": 0}
            self.assertEqual(set(counts), set(budgets))
            self.assertGreaterEqual(counts["changedSize"], 1, "the observer must see the real size-change body")
            for phase, maximum in budgets.items():
                with self.subTest(layout=phase):
                    self.assertGreaterEqual(counts[phase], 0)
                    self.assertLessEqual(counts[phase], maximum, run.stderr)

    def test_retained_offscreen_target_regrant_and_uncropped_inspector_master(self):
        with tempfile.TemporaryDirectory(prefix="mwx-sil-adaptive-", dir="/private/tmp") as directory:
            work = Path(directory)
            sources, originals, fixture = self._prepare_fixture(work)
            generated = work / "Checks.swift"; generated.write_text(fixture)
            inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in originals}
            binary = prepare_native_app(work, "SILAdaptiveRegrant")
            build = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                "-parse-as-library", *map(str, sources), str(generated), "-module-cache-path", str(work / "modules"),
                "-o", str(binary)], capture_output=True, text=True, timeout=150)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = run_native_app(binary, ["--adaptive-return", str(work / "images")], timeout=45,
                proof_environment="MWX_SIL_DEMAND_PROOF_DIR")
            self.assertEqual(run.launch_returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue({
                "small-grid-final-is-one-128-square", "small-grid-keeps-uncropped-512-master-for-rectangular-inspector",
                "rectangular-inspector-return-needs-no-source-reextract", "master-floor-does-not-upscale-a-native-small-source",
                "held-offscreen-card-starts-with-old-target-pixels", "native-resize-increases-the-required-target",
                "regrant-reuses-bound-source-without-another-library-search", "regrant-does-not-clear-the-current-correct-resource",
                "retained-offscreen-card-receives-the-current-final-target", "nil-revocation-releases-the-held-card-demand",
            }.issubset(checks), checks)
            for name, value in checks.items():
                with self.subTest(name=name): self.assertIs(value, True, run.stdout + run.stderr)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in originals})
            print(run.stdout)


if __name__ == "__main__":
    unittest.main()
