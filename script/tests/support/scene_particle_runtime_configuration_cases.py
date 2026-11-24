"""Build the same real Runtime fixture in both configurations and compare behavior."""
from __future__ import annotations

import math
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from uuid import UUID


def _declaration(source: str, marker: str) -> str:
    start = source.index(marker)
    body = source.index("{", start)
    depth, end = 1, body + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


# Reuse the existing no-request telemetry leaf. Its render/blit methods create
# real Metal encoders; only timing observations are outside these behavior gates.
# Particle admission, simulation, instance buffers and renderer decisions remain
# the real product sources. The separate timestamp gate tests that diagnostic.
NO_TIMESTAMP_OBSERVATION_SUPPORT = "#if DEBUG\nimport Metal\n" + _declaration(
    ((Path(__file__).resolve().parents[1] / "fixtures") / "SceneColorBlendCaptureRegionHarness.swift").read_text(),
    "enum SceneGPUStageTimestampHook {",
) + "\n#endif\n"


def compile_runtime_configurations(cls, source_root, swift_sources, harness_sources) -> None:
    swiftc = shutil.which("swiftc")
    if swiftc is None:
        raise unittest.SkipTest("swiftc is unavailable")
    cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-runtime-")
    cls.addClassCleanup(cls.temporary_directory.cleanup)
    directory = Path(cls.temporary_directory.name)
    # Reuse the two complete production methods; no renderer decision is stubbed.
    model_source = (source_root / "Rendering/Frame/SceneMetalRenderer+LayerTransforms.swift").read_text()

    model_methods = "extension SceneMetalRenderer {\n" + "\n".join(
        _declaration(model_source, marker) for marker in ["    func particleModelMatrix(", "    func parallaxOffset("]
    ) + "\n}\n"
    prepared_harnesses = []
    for source in harness_sources:
        if source.name == "SceneParticleRuntimeHarness.swift":
            copied = directory / source.name
            copied.write_text(NO_TIMESTAMP_OBSERVATION_SUPPORT
                              + source.read_text().replace("// PRODUCTION_PARTICLE_MODEL_METHODS", model_methods))
            prepared_harnesses.append(copied)
        else:
            prepared_harnesses.append(source)
    cls.binaries = {}
    for configuration, flags in (("debug", ["-D", "DEBUG"]), ("release", ["-O"])):
        binary = directory / f"scene-particle-runtime-{configuration}"
        compilation = subprocess.run([
            swiftc, *flags, *(str(path) for path in swift_sources),
            *(str(path) for path in prepared_harnesses),
            "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
            "-module-cache-path", str(directory / "module-cache"), "-o", str(binary),
        ], capture_output=True, text=True)
        if compilation.returncode:
            raise RuntimeError(f"{configuration}: {compilation.stderr}")
        cls.binaries[configuration] = binary


class SceneParticleRuntimeConfigurationCases:
    def test_child_plane_scale_cold_batches_preserve_centers_and_local_renderer_failure(self) -> None:
        for configuration in ("debug", "release"):
            result = self.run_harness("child-plane-scale-synthetic", configuration=configuration)
            self.assertEqual(len(result["variants"]), 2, result)
            baseline = None
            for variant in result["variants"]:
                self.assertEqual((variant["roots"], variant["children"]), (8, 8), variant)
                rows = variant["rows"]
                self.assertEqual(len(rows), 8, rows)
                self.assertEqual({row["name"] for row in rows}, {
                    f"{name}-child" for name in ("tall-0", "tall-45", "wide-0", "wide-45",
                                                "uniform-0", "uniform-45", "mixed", "uniform-trail")}, rows)
                if baseline is None:
                    baseline = rows
                self.assertEqual(rows, baseline, variant)
                for row in rows:
                    with self.subTest(configuration=configuration, renamed=variant["renamed"], name=row["name"]):
                        family = row["name"].split("-")[0]
                        sx, sy = {"tall": (.5, 1.5), "wide": (1.5, .5),
                                  "uniform": (2, 2), "mixed": (.5, 1.5)}[family]
                        self.assertEqual(row["renderer"], 0, row)
                        self.assertEqual(row["instances"], 1, row)
                        self.assertEqual(row["position"], [4 + 6 * sx, 5 + 4 * sy, 0], row)
                        self.assertAlmostEqual(row["halfSize"], 16 * sx, places=6)
                        self.assertAlmostEqual(row["ratio"], sy / sx, places=6)
                        rotated = "45" in row["name"] or row["name"] == "mixed-child"
                        self.assertAlmostEqual(row["rotationZ"], math.pi / 4 if rotated else 0, places=6)
                        self.assertEqual(row["spriteRight"], row["baseRight"], row)
                        for actual, base in zip(row["spriteUp"], row["baseUp"], strict=True):
                            self.assertAlmostEqual(actual, base * sy / sx, places=6)
                        self.assertTrue(row["centerModelUnchanged"], row)
                        self.assertTrue(row["viewUnchanged"], row)
                        self.assertTrue(row["directionBasisUnchanged"], row)
                        if row["name"] == "uniform-trail-child":
                            self.assertGreaterEqual(row["trail"], 0, row)
                        else:
                            self.assertEqual(row["trail"], -1, row)
                if configuration == "debug":
                    for renderer in (1, 2, 3):
                        suffix = f"mixed-child.json:renderer[{renderer}]:childPlaneScaleUnavailable"
                        self.assertTrue(any(suffix in detail for detail in variant["diagnosticDetails"]), variant)

    def test_release_keeps_real_runtime_transactions_and_output(self) -> None:
        # Exact report projections omitted by #if DEBUG. Actual admission,
        # positions, allocation budgets, frozen-state rollback, RNG, instance
        # buffers, child retirement and teardown fields are compared unchanged.
        report_keys = {
            "diagnostics", "diagnosticKinds", "diagnosticDetails", "missingSpriteRenderer",
            "staticChildScaleBounded", "staticChildUnsupportedDetails",
            "rawControlPointCopyBounded", "hiddenMentioned", "freezeDiagnostic",
            "liveIdentityFollowsCurrent", "liveIdentityFrozen", "liveRotatedFollowsCurrent",
            "liveRotatedFrozen", "resumeDiagnostic", "localFreezeDiagnosticAbsent",
            "vanishingWriteResumeDiagnostic", "singleDiagnostics", "prewarmDiagnostics",
            "staticDiagnostics", "eventspawnDiagnostics", "eventdeathDiagnostics",
            "eventfollowDiagnostics", "nestedDiagnostics", "eventValueDiagnostics", "eventValueDebugWitness",
            "childUnsupportedLayers", "budgetDetails",
            "audioChildDetails", "childScaleDetails", "unsupportedForceReported",
            "rejectedChurnObservationCount", "churnObservationsAfterRestore",
            "retryChurnObservationCount", "retryChurnObservationPaths", "laterChurnObservationCount",
            "each-real-reader-has-local-binding-rejection", "bindingRejections",
        }

        def functional(value, keys):
            if isinstance(value, dict):
                return {key: functional(item, keys) for key, item in value.items() if key not in keys}
            if isinstance(value, list):
                return [functional(item, keys) for item in value]
            return value

        for mode in (
            "playback-control", "lifecycle-synthetic", "frame-transaction-synthetic",
            "worldspace-freeze-recovery", "worldspace-gravity-frame", "child-capacity-synthetic",
            "eventfollow-synthetic", "static-scaled-rope-synthetic", "rope-trail-synthetic",
            "rope-synthetic", "subframe-lifetime-synthetic", "subframe-child-lifecycle-synthetic",
            "layer-alpha-synthetic", "synthetic", "child-pointer-control-point-synthetic",
            "batch-evidence-synthetic",
        ):
            with self.subTest(mode=mode):
                debug = self.run_harness(mode)
                release = self.run_harness(mode, configuration="release")
                if mode == "lifecycle-synthetic":
                    # Each fresh process owns a different real session UUID.
                    # Prove the returned teardown identity before normalizing it.
                    for result in (debug, release):
                        self.assertEqual(str(UUID(result["identity"])).upper(), result["identity"])
                        self.assertEqual(result["identity"], result["observationIdentity"])
                        result["identity"] = result["observationIdentity"] = "current-session"
                # Never strip Release reports: retained fields fail this equality.
                keys = report_keys | ({"initial", "discarded", "dormant", "beforeCommit",
                                       "afterDiscard", "committed"}
                                      if mode == "batch-evidence-synthetic" else set())
                self.assertEqual(release, functional(debug, keys))

    def test_release_has_no_runtime_report_storage_but_keeps_definition_diagnostics(self) -> None:
        for configuration in ("debug", "release"):
            with self.subTest(configuration=configuration):
                result = self.run_harness("configuration-storage", configuration=configuration)
                for field in ("runtimeDiagnostics", "runtimeAdoptionReport", "snapshotAdoptionReport",
                              "compilationDiagnostics"):
                    self.assertEqual(result[field], configuration == "debug", field)
                self.assertTrue(result["definitionDiagnostics"])

    def test_multiple_renderers_share_real_simulation_and_keep_local_outputs(self) -> None:
        results = [self.run_harness("multiple-renderers-synthetic", configuration=configuration)
                   for configuration in ("debug", "release")]
        self.assertEqual(results[0], results[1])
        result = results[0]
        self.assertEqual(result["rootPreparedIndices"], list(range(6)))
        for field in ("rootTextureShared", "randomizedPopulation", "replayMatches",
                      "pauseMatchesSingles", "pauseStopsBirths", "pauseKeepsExistingMotion",
                      "stopClearsEveryOutput", "stopMatchesSingles", "stopKeepsPeer"):
            self.assertTrue(result[field], field)
        rows = result["root"]
        self.assertEqual(len(rows), 6)
        for index, row in enumerate(rows):
            with self.subTest(frame=index):
                self.assertEqual(row["rootSystems"], 2)  # Target and independent peer, not six simulators.
                self.assertTrue(all(row["singleGeometry"]), row)
                self.assertTrue(all(row["singleState"]), row)
                for field in ("variantGeometry", "variantState", "peerGeometry", "peerState"):
                    self.assertTrue(row[field], (field, row))
        for row in rows[:2]:
            self.assertEqual(row["indices"], list(range(6)))
            self.assertEqual(row["population"], 3)
            self.assertTrue(all(count > 0 for count in row["counts"]))
            self.assertEqual([row["counts"][index] for index in (0, 3, 4)], [3, 3, 3])
        self.assertEqual(rows[3]["population"], 0)
        self.assertEqual([rows[3]["counts"][index] for index in (0, 2, 3, 4)], [0, 0, 0, 0])
        self.assertGreater(rows[3]["counts"][5], 0)
        self.assertEqual(rows[4]["indices"], [5])  # Short history drains before the longer policy.
        self.assertGreater(rows[4]["counts"][5], 0)
        self.assertEqual(rows[5]["indices"], [])
        self.assertEqual(rows[5]["counts"], [0] * 6)
        for trigger, expected in (("static", [0, 1, 2, 3, 6, 7]), ("eventspawn", [0, 1, 2, 3])):
            with self.subTest(trigger=trigger):
                child = result["children"][trigger]
                self.assertEqual(child["indices"], expected)
                self.assertTrue(all(count > 0 for count in child["counts"]))
                for field in ("geometryMatches", "simulationMatches", "variantMatches", "replayMatches",
                              "spriteAndTrailDiffer", "duplicateSpriteMatches", "textureViewsShared",
                              "implicitMatchesExplicit"):
                    self.assertTrue(child[field], (field, child))
                self.assertEqual(child["rootSystems"], 1)
                self.assertEqual(child["childSystems"], 1)
                self.assertEqual(child["childPopulation"], 3)
                self.assertEqual(child["templateIndices"], [0])
                self.assertEqual(child["nextSystemID"], 2)
                self.assertEqual(child["nextSeed"], 0 if trigger == "static" else 1)
                self.assertEqual(child["rootNextID"], 0 if trigger == "static" else 1)
                self.assertEqual(child["childNextID"], 3)
                self.assertEqual(child["implicitIndices"], [0])
        container = result["container"]
        self.assertEqual(container["activeLayers"], [310])
        self.assertEqual(container["rootSystems"], 0)
        self.assertEqual(container["childSystems"], 1)
        self.assertEqual(container["childPopulation"], 3)
        self.assertEqual(container["indices"], [0, 1])
        self.assertTrue(all(count > 0 for count in container["counts"]))
        for field in ("noRootSimulator", "allChildOutputs", "noExecutableTemplateRejected", "badDeclarationRejected"):
            self.assertTrue(container[field], (field, container))
        prefix = result["nonzeroPrefix"]
        self.assertEqual(prefix["liveStarts"], [3, 3])
        for field in ("rootIDs", "depthOneFollowerIDs", "depthTwoFollowerIDs"):
            self.assertEqual(prefix[field], list(range(3, 8)), (field, prefix))
        for field in ("geometryMatchesCompact", "simulationMatchesCompact", "zeroStepStable",
                      "rootRopeVisible", "childRopeVisible", "replayMatches"):
            self.assertTrue(prefix[field], (field, prefix))
